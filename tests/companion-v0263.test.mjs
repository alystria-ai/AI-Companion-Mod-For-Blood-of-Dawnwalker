import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
async function check(module,setup,body){
 const source=await readFile('mod/Scripts/'+module+'.lua','utf8');
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 try{const rc=lauxlib.luaL_dostring(L,to_luastring(setup+`\nlocal M=(function() ${source} end)()\n`+body));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}
}
const damage=`
 local attrs={BaseMeleeDamage={BaseValue=0,CurrentValue=120},BaseUnarmedDamage={BaseValue=0,CurrentValue=80},DamageAIvsAI={BaseValue=10,CurrentValue=10},Health={BaseValue=1000}}
 local writes=0;local asc={GetAttributeSet=function()return attrs end}
 asc.GetAllAttributes=function(_,out)
  for _,key in ipairs({'Health','BaseMeleeDamage','BaseUnarmedDamage','DamageAIvsAI'})do
   local a={AttributeName={ToString=function()return key end}}
   out[#out+1]={get=function()return a end}
  end
 end
 local board={};local stub={GetAbilitySystemComponent=function()return asc end}
 local lib={SetAttributeValue=function(_,owner,attr,n)assert(owner==asc);local v=attrs[attr.AttributeName:ToString()];v.CurrentValue=v.CurrentValue+(n-v.BaseValue);v.BaseValue=n;writes=writes+1 end}
 local valid=true
 package.preload.ai_state=function()return {valid=function(o)return o~=nil end,same=function(a,b)return a~=nil and a==b end,board=function(s,b)return valid and s==stub and b==board and board end,find=function()return lib end}end
 local state={}
`;
test('companion base damage scales only source damage attributes and cannot stack on repeated attach',()=>check('companion_damage',damage,`
 assert(M.apply(stub,board,state,2.5));assert(attrs.BaseMeleeDamage.CurrentValue==300 and attrs.BaseUnarmedDamage.CurrentValue==200 and attrs.DamageAIvsAI.BaseValue==300)
 assert(attrs.Health.BaseValue==1000 and writes==3)
 assert(M.apply(stub,board,state,2.5));assert(writes==3)
 M.restore(stub,board,state);assert(attrs.BaseMeleeDamage.CurrentValue==120 and attrs.BaseUnarmedDamage.CurrentValue==80 and attrs.DamageAIvsAI.BaseValue==10)
 assert(M.apply(stub,board,state,2.5));assert(attrs.BaseMeleeDamage.CurrentValue==300)
`));
test('damage restoration preserves later native edits and never calls a detached ASC',()=>check('companion_damage',damage,`
 assert(M.apply(stub,board,state,2.5));attrs.BaseMeleeDamage.BaseValue=444
 M.restore(stub,board,state);assert(attrs.BaseMeleeDamage.BaseValue==444 and attrs.BaseUnarmedDamage.CurrentValue==80)
 valid=false;local before=writes;assert(not M.apply(stub,board,{},2.5));M.restore(stub,board,state);assert(writes==before)
`));
test('invalid damage multipliers fail without a stat write',()=>check('companion_damage',damage,`
 for _,n in ipairs({-1,6,11,math.huge})do assert(not M.apply(stub,board,{},n))end
 assert(writes==0)
`));

test('damage slider changes rebase instead of stacking and allow zero damage',()=>check('companion_damage',damage,`
 assert(M.apply(stub,board,state,2.5));assert(attrs.BaseMeleeDamage.CurrentValue==300)
 assert(M.apply(stub,board,state,1));assert(attrs.BaseMeleeDamage.CurrentValue==120 and attrs.DamageAIvsAI.CurrentValue==120)
 assert(M.apply(stub,board,state,0));assert(attrs.BaseMeleeDamage.CurrentValue==0 and attrs.DamageAIvsAI.CurrentValue==0)
 assert(M.apply(stub,board,state,2));assert(attrs.BaseMeleeDamage.CurrentValue==240)
`));
test('native stat refresh rebases damage without stacking or changing unrelated attributes',()=>check('companion_damage',damage,`
 assert(M.apply(stub,board,state,2.5));assert(attrs.BaseMeleeDamage.CurrentValue==300)
 -- Native level/effect updates add 40 to the unboosted source after setup.
 attrs.BaseMeleeDamage.CurrentValue=340
 assert(M.apply(stub,board,state,2.5));assert(attrs.BaseMeleeDamage.CurrentValue==400 and attrs.DamageAIvsAI.CurrentValue==400)
 assert(attrs.Health.BaseValue==1000)
 M.restore(stub,board,state);assert(attrs.BaseMeleeDamage.CurrentValue==160)
`));
test('an aggregation failure rolls back all of this attempt’s base writes',()=>check('companion_damage',damage,`
 local setter=lib.SetAttributeValue
 lib.SetAttributeValue=function(self,owner,a,n)
  if a.AttributeName:ToString()=='BaseUnarmedDamage'and n~=0 then attrs.BaseUnarmedDamage.BaseValue=n;return end
  setter(self,owner,a,n)
 end
 assert(not M.apply(stub,board,state,2.5))
 assert(attrs.BaseMeleeDamage.BaseValue==0 and attrs.BaseUnarmedDamage.BaseValue==0 and attrs.DamageAIvsAI.BaseValue==10)
 assert(not state.complete)
`));
test('AI-vs-AI uses unboosted physical strength regardless of descriptor order',()=>check('companion_damage',damage,`
 local original=asc.GetAllAttributes
 asc.GetAllAttributes=function(self,out)local temp={};original(self,temp);for i=#temp,1,-1 do out[#out+1]=temp[i]end end
 assert(M.apply(stub,board,state,5));assert(attrs.DamageAIvsAI.CurrentValue==600)
 assert(attrs.BaseMeleeDamage.CurrentValue==600 and attrs.BaseUnarmedDamage.CurrentValue==400)
 assert(M.apply(stub,board,state,2));assert(attrs.DamageAIvsAI.CurrentValue==240)
 M.restore(stub,board,state);assert(attrs.DamageAIvsAI.CurrentValue==10)
`));
const weapon=`
 EObjectFlags={RF_BeginDestroyed=1,RF_FinishDestroyed=2};FName=function(n)return n end
 local function obj(n)return {IsValid=function()return true end,HasAnyFlags=function()return false end,GetFullName=function()return n end}end
 local s,b=obj('stub'),obj('board');s.AIBoard=b;s.IsInitializedAndHasPawn=function()return true end
 local combat,busy,cinematic=false,false,false
 s.IsInCombat=function()return combat end;s.IsInCinematicMode=function()return cinematic end
 b.Combat={bInCombat=false};b.HasAnyUnbreakableActiveAction=function()return busy end
 local selected='None';b.Weapon={TagName={ToString=function()return selected end}}
 b.Temp_BP_SetWeapon=function(_,t)selected=t.TagName end
 local w,c,cls=obj('sword'),obj('combat'),obj('swordclass');local root=obj('root');local socket='socket_weapon_r'
 w.IsA=function(_,cl)return cl==cls end;w.K2_GetRootComponent=function()return root end
 root.GetAttachSocketName=function()return {ToString=function()return socket end}end
 c.EquippedWeapon=cls;c.GetMainWeapon=function()return w end
 local calls=0;local accept=true
 s.StowWeapon=function(_,anim)assert(anim and selected=='RebelAI.Weapon.Sword');calls=calls+1;if accept then w=nil;selected='None'end;return false end
 local state={}
`;
test('native stow repairs the empty selector and confirms equipment despite a false return',()=>check('ai_state',weapon,`
 assert(M.travelWeapon(s,b,c,state,0));assert(calls==1 and selected=='None' and state.done)
 assert(M.travelWeapon(s,b,c,state,5000));assert(calls==1)
`));
test('sheathing respects both combat flags, scenes, unbreakable actions and natural weapons',()=>check('ai_state',weapon,`
 combat=true;assert(not M.travelWeapon(s,b,c,state,0));combat=false
 b.Combat.bInCombat=true;assert(not M.travelWeapon(s,b,c,state,0));b.Combat.bInCombat=false
 busy=true;assert(not M.travelWeapon(s,b,c,state,0));busy=false
 cinematic=true;assert(not M.travelWeapon(s,b,c,state,0));cinematic=false
 b.bMainBehaviorSuspended=true;assert(not M.travelWeapon(s,b,c,state,0));b.bMainBehaviorSuspended=false
 c.EquippedWeapon=nil;assert(M.travelWeapon(s,b,c,state,0));assert(calls==0)
`));
test('declined stow is rate limited and bounded without leaving a fabricated selector',()=>check('ai_state',weapon,`
 accept=false;assert(not M.travelWeapon(s,b,c,state,0));assert(selected=='None')
 for t=250,1250,250 do M.travelWeapon(s,b,c,state,t)end;assert(calls==1)
 M.travelWeapon(s,b,c,state,1500);M.travelWeapon(s,b,c,state,3000);M.travelWeapon(s,b,c,state,9000);assert(calls==3 and selected=='None')
`));
test('weapons already attached elsewhere are left alone',()=>check('ai_state',weapon,`
 socket='socket_sheathed';assert(M.travelWeapon(s,b,c,state,0));assert(calls==0)
`));

test('proxy stow leftovers are released by the idle combat component without removing inventory',()=>check('ai_state',weapon,`
 accept=false;c.CurrentState=0;local removals=0;c.RemoveAllWeapons=function(_,update)assert(update);removals=removals+1;w=nil end
 assert(not M.travelWeapon(s,b,c,state,0));assert(removals==0)
 assert(M.travelWeapon(s,b,c,state,1500));assert(removals==1 and c.EquippedWeapon==cls)
 assert(M.travelWeapon(s,b,c,state,5000));assert(removals==1)
`));
