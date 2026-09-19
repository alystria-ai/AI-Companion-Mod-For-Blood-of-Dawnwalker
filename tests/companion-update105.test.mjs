import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
async function run(setup,body){const source=await readFile('mod/Scripts/companion_tuning.lua','utf8');const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(setup+'\nlocal M=(function()\n'+source+'\nend)()\n'+body));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
test('recovery requires continuous peace; disable, renewed combat and dismissal do not cause immediate respawn',()=>run(`
 package.preload.ai_state=function()return {}end;package.preload.companion_settings=function()return {}end
`, `
 local m={};assert(not M.canRespawn(m,1000,true,true,8));assert(m.peaceSince==nil)
 assert(not M.canRespawn(m,2000,false,true,8));assert(not M.canRespawn(m,9000,false,true,8))
 assert(not M.canRespawn(m,9500,true,true,8));assert(not M.canRespawn(m,10000,false,true,8))
 assert(M.canRespawn(m,18000,false,true,8));assert(not M.canRespawn(m,19000,false,false,8));assert(m.peaceSince==nil)
 local replacement={};assert(not M.canRespawn(replacement,20000,false,true,8))
`));
test('combat-only roster is distinct and backed by the captured asset catalogue',async()=>{
 const roster=JSON.parse(await readFile('characters/companion-config.json','utf8'));const assets=await readFile('runtime/companion-asset-catalog.tsv','utf8');
 const ids=new Set();for(const c of roster.characters){assert(!ids.has(c.id));ids.add(c.id);assert(assets.includes(c.path.split('.')[0]+'\t'));if(c.category==='combat')assert.equal(c.chat,false);}
 assert(roster.characters.filter(c=>c.category==='combat').length>=50);assert.equal(roster.characters.filter(c=>c.category==='story').length,15);
});

const aggregatedTuningSetup=`
 local settings={revision=0,values={AttackFrequency=150}}
 package.preload.companion_settings=function()return settings end
 local attrs={Level={BaseValue=4,CurrentValue=4},AttackSpeedMultiplierAdditive={BaseValue=.1,CurrentValue=.1}}
 local playerAttrs={Level={CurrentValue=12}};local writes=0
 local asc={GetAttributeSet=function()return attrs end,GetAllAttributes=function(_,out)for _,name in ipairs({'Level','AttackSpeedMultiplierAdditive'})do out[#out+1]={get=function()return {AttributeName={ToString=function()return name end}}end}end end}
 local playerAsc={GetAttributeSet=function()return playerAttrs end}
 local stub={GetAbilitySystemComponent=function()return asc end};local player={GetAbilitySystemComponent=function()return playerAsc end}
 local lib={SetAttributeValue=function(_,owner,a,value)assert(owner==asc);writes=writes+1;local v=attrs[a.AttributeName:ToString()];v.CurrentValue=v.CurrentValue+value-v.BaseValue;v.BaseValue=value end}
 package.preload.ai_state=function()return {board=function()return true end,valid=function(o)return o~=nil end,same=function(a,b)return a~=nil and a==b end,find=function()return lib end}end
 local member={stub=stub,board={},actor={}}
`.replace('BaseValue=4,CurrentValue=4','BaseValue=4,CurrentValue=8');
test('tuning rejects an accidentally supplied player ASC before writes',()=>run(aggregatedTuningSetup,`
 member.stub=player
 local ok=pcall(M.apply,member,player);assert(not ok and writes==0)
`));
test('frequency changes only the owned ASC, never levels or unrelated actors, and does not stack',()=>run(aggregatedTuningSetup,`
 assert(M.apply(member,player));assert(attrs.Level.BaseValue==4 and attrs.Level.CurrentValue==8)
 assert(math.abs(attrs.AttackSpeedMultiplierAdditive.BaseValue-.6)<.001 and writes==1)
 M.apply(member,player);assert(writes==1)
 playerAttrs.Level.CurrentValue=90;M.apply(member,player);assert(writes==1 and attrs.Level.CurrentValue==8)
 settings.values.AttackFrequency=100;settings.revision=1;M.apply(member,player)
 assert(math.abs(attrs.AttackSpeedMultiplierAdditive.BaseValue-.1)<.001 and writes==2)
 attrs.AttackSpeedMultiplierAdditive.BaseValue=.2;attrs.AttackSpeedMultiplierAdditive.CurrentValue=.2
 settings.values.AttackFrequency=180;settings.revision=2;M.apply(member,player)
 assert(math.abs(attrs.AttackSpeedMultiplierAdditive.BaseValue-1)<.001)
 assert(playerAttrs.Level.CurrentValue==90 and member.actor.bCanBeDamaged)
`));
test('removed level and recovery toggles are not exposed or executed',async()=>{
 for(const p of ['mod/config.ini','mod/mod_settings.ini','mod/Scripts/companion_settings.lua','mod/Scripts/companion_tuning.lua']){
  assert(!/ScaleToPlayer|Match player level|RespawnAfterCombat/.test(await readFile(p,'utf8')),p);
 }
});

const allegianceSetup=`
 local repairs,writes,clears=0,0,0
 local function stub(name)
  local s={name=name,attitudes={},board={Combat={bInCombat=false}}}
  function s:GetFullName()return self.name end
  function s:GetAttitudeTowards(other)return self.attitudes[other]or 1 end
  function s:SetAttitudeTowards(other,value)self.attitudes[other]=value;writes=writes+1 end
  function s:IsHostileTowardsPlayer()return self.hostile==true end
  function s:IsInCombat()return self.fighting==true end
  function s.board:GetTarget()return self.target end
  function s.board:GetForcedTarget()return self.forced end
  function s.board:SetForcedTarget(value)self.forced=value;clears=clears+1 end
  return s
 end
 local player,ally,other,enemy=stub('player'),stub('ally'),stub('other'),stub('enemy')
 local member={stub=ally,board=ally.board};local party={other={stub=other,board=other.board}}
 package.preload.ai_state=function()return {board=function(s,b)return s and (not b or s.board==b)and s.board or nil end,
  same=function(a,b)return a~=nil and a==b end}end
 package.preload.companion_settings=function()return {}end
`;
test('owned allegiance guard rejects friendly attack targets but preserves gaze and enemy combat',()=>run(allegianceSetup,`
 M.friendly=function(m,p)assert(m==member and p==player);repairs=repairs+1;ally.hostile=false;ally.attitudes[player]=1 end
 ally.board.target=player
 assert(not M.guardAllegiance(member,player,party,0),'A peaceful follow/gaze target was treated as an attack')
 ally.fighting=true;ally.hostile=true;ally.attitudes[player]=3
 assert(M.guardAllegiance(member,player,party,250));assert(repairs==1 and member.allegianceRepairs==1)
 ally.board.target=enemy;ally.attitudes[enemy]=3
 assert(M.guardAllegiance(member,player,party,500),'Exit grace was lost')
 assert(not M.guardAllegiance(member,player,party,1500))
 assert(ally.attitudes[enemy]==3 and repairs==1 and clears==0,'Legitimate enemy combat changed')
 ally.board.forced=other;ally.attitudes[other]=3;other.attitudes[ally]=3
 assert(M.guardAllegiance(member,player,party,2000))
 assert(ally.board.forced==nil and clears==1 and ally.attitudes[other]==1 and other.attitudes[ally]==1)
 ally.board.target=other;other.board={Combat={}} -- stale registry must not claim this actor
 assert(not M.guardAllegiance(member,player,party,3500))
 assert(enemy.attitudes[ally]==nil and player.attitudes[enemy]==nil,'Unrelated relations were touched')
`));
