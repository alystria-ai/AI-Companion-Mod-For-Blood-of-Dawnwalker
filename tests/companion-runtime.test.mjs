import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
async function check(file,body){
 const source=await readFile(process.env.DAWNWALKER_LUA?file.replace('mod/Scripts',process.env.DAWNWALKER_LUA):file,'utf8');const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 try{const result=lauxlib.luaL_dostring(L,to_luastring(`local M=(function() ${source} end)()\n${body}`));assert.equal(result,lua.LUA_OK,result===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}
}
test('controller discovery stays out of party ticks and throttles loading retries',()=>check('mod/Scripts/targeting.lua',`
 local count=0;local live=true;local pc={IsValid=function()return live end}
 local function find()count=count+1;return pc end
 for i=1,400 do assert(M.playerController(find,i*.25)==pc)end
 assert(count==1,'Full object scan repeated on a party tick')
 live=false
 for i=401,407 do assert(M.playerController(find,i*.25)==nil)end
 assert(count==2,'Failed loading lookup was not throttled')
 live=true;assert(M.playerController(find,102)==pc)
 assert(count==2,'An already valid cached controller should be reused')
 live=false;M.playerController(find,104);assert(count==3)
`));
test('overlay input lease releases capture once and restores on close or failure',()=>check('mod/Scripts/ui_input.lua',`
 local paused=false;local modes={};local move,look=0,0
 local pc={bShowMouseCursor=false,IsValid=function()return true end}
 function pc:SetIgnoreMoveInput(value)move=move+(value and 1 or -1)end
 function pc:SetIgnoreLookInput(value)look=look+(value and 1 or -1)end
 local library={}
 function library:SetInputMode_GameAndUIEx(p,widget,lock,hide,flush)
  assert(p==pc and widget==nil and lock==0 and hide==false and flush==true);modes[#modes+1]='ui'
 end
 function library:SetInputMode_GameOnly(p,flush)assert(p==pc and flush);modes[#modes+1]='game'end
 local gameplay={IsGamePaused=function()return paused end}
 local lease=assert(M.acquire(pc,library,gameplay));assert(move==1 and look==1 and pc.bShowMouseCursor)
 assert(#modes==1);M.release(lease);M.release(lease)
 assert(move==0 and look==0 and not pc.bShowMouseCursor and #modes==2 and modes[2]=='game')
 paused=true;pc.bShowMouseCursor=true
 lease=assert(M.acquire(pc,library,gameplay));M.release(lease)
 assert(move==0 and look==0 and pc.bShowMouseCursor and #modes==3,'Pause UI was overwritten')
 paused=false;pc.bShowMouseCursor=false
 local old=pc.SetIgnoreLookInput;pc.SetIgnoreLookInput=function()error('Unavailable')end
 local failed,why=M.acquire(pc,library,gameplay)
 assert(failed==nil and why and move==0 and not pc.bShowMouseCursor and modes[#modes]=='game')
 pc.SetIgnoreLookInput=old
`));
test('combat start is handed off once; lease renewals and perception gaps do not replay it',()=>check('mod/Scripts/companion_combat.lua',`
 local starts,stops,enters,leases,following=0,0,0,0,true
 local c=M.new({enter=function()enters=enters+1;following=false end,target=function()leases=leases+1 end,start=function()starts=starts+1;return true end,stop=function()stops=stops+1 end,clear=function()end,travel=function(value)following=value end})
 local function tick(now,key,inCombat,allowed)return c:tick({now=now,key=key,nativeCombat=inCombat,allowed=allowed~=false,follow=true})end
 tick(0,'enemy',false)
 for i=1,60 do tick(i*750,'enemy',true);assert(not following)end
 assert(starts==1 and enters==1 and leases>10 and stops==0,'Combat intro restarted while renewing target')
 tick(46000,nil,true);tick(47500,'enemy',true);assert(starts==1 and stops==0 and not following)
 tick(48000,nil,false);tick(53001,nil,false);assert(following and stops==1)
 tick(53500,nil,false);assert(stops==1)
 tick(54000,'other',false);assert(starts==2 and not following)
 tick(55000,'other',true,false);assert(stops==2 and not following,'Native exit must be acknowledged')
 tick(55500,'other',true,false);assert(stops==2 and not following)
 tick(56000,nil,false,false);assert(following and stops==2)
`));

test('slow combat intro is not restarted and rejected starts have a finite retry budget',()=>check('mod/Scripts/companion_combat.lua',`
 local starts=0
 local function make(accepted)return M.new({enter=function()end,target=function()end,start=function()starts=starts+1;return accepted end,stop=function()end,clear=function()end,travel=function()end})end
 local c=make(true)
 for i=0,80 do c:tick({now=i*750,key='enemy',allowed=true,nativeCombat=false,follow=true})end
 assert(starts==1,'Slow intro was replayed')
 starts=0;c=make(false)
 for i=0,80 do c:tick({now=i*750,key='enemy',allowed=true,nativeCombat=false,follow=true})end
 assert(starts==3,'Rejected combat attempts were not bounded')
`));

test('failed combat resumes following and target churn cannot reset its retry budget',()=>check('mod/Scripts/companion_combat.lua',`
 local starts,stops,enters,clears,following=0,0,0,0,true
 local c=M.new({enter=function()enters=enters+1;following=false end,target=function()return true end,start=function()starts=starts+1;return false end,stop=function()stops=stops+1 end,clear=function()clears=clears+1 end,travel=function(v)following=v end})
 for i=0,80 do
  local phase=c:tick({now=i*750,key=i%2==0 and 'enemyA'or 'enemyB',allowed=true,nativeCombat=false,follow=true})
  if i<9 then assert(not following and c.phase=='preparing','Transient rejection released combat ownership')
  else assert(following and c.phase=='travel','Exhausted preparation left the follower disabled')end
 end
 assert(starts==3 and enters==1 and clears==1 and stops==0,'Target churn replayed combat or stopped a rejected fight')
 c:tick({now=61000,allowed=true,nativeCombat=false,follow=true})
 c:tick({now=62000,key='enemyC',allowed=true,nativeCombat=false,follow=true});assert(starts==3,'Short perception gap reset retries')
 c:tick({now=63000,allowed=true,nativeCombat=false,follow=true})
 c:tick({now=73000,allowed=true,nativeCombat=false,follow=true})
 c:tick({now=74000,key='newEncounter',allowed=true,nativeCombat=false,follow=true});assert(starts==4)
`));

test('combat retargeting never replays entry and retreat waits for an unbreakable attack',()=>check('mod/Scripts/companion_combat.lua',`
 local starts,following,locked,clears=0,true,true,0
 local c=M.new({enter=function()following=false end,target=function()return true end,start=function()starts=starts+1;return true end,stop=function()return not locked end,clear=function()clears=clears+1 end,travel=function(v)following=v end})
 c:tick({now=0,key='first',allowed=true,nativeCombat=false,follow=true})
 c:tick({now=1000,key='second',allowed=true,nativeCombat=true,follow=true});assert(starts==1)
 assert(c:tick({now=2000,allowed=false,nativeCombat=true,follow=true})=='leaving')
 assert(not following and clears==0,'Follow interrupted native root motion')
 locked=false
 assert(c:tick({now=3000,allowed=false,nativeCombat=true,follow=true})=='leaving')
 assert(not following and clears==0)
 assert(c:tick({now=3250,allowed=false,nativeCombat=false,busy=false,follow=true})=='travel')
 assert(following and clears==1)
 local busy=true;starts=0
 c=M.new({enter=function()return not busy end,target=function()return true end,start=function()starts=starts+1;return true end,stop=function()end,clear=function()end,travel=function()end})
 assert(c:tick({now=0,key='enemy',allowed=true,nativeCombat=false,follow=true})=='waiting')
 assert(c.attempts==0 and starts==0)
 busy=false;c:tick({now=750,key='enemy',allowed=true,nativeCombat=false,follow=true});assert(starts==1,'Ready companion waited ten seconds after an unbreakable action')
`));
test('finished encounters settle once and stale enemies cannot replay combat lines',()=>check('mod/Scripts/companion_combat.lua',`
 local starts,stops,clears,following,maintains=0,0,0,true,0
 local c=M.new({exitSettleMs=750,enter=function()following=false;return true end,target=function()return true end,prepare=function()return true end,
  start=function()starts=starts+1;return true end,stop=function()stops=stops+1;return true end,clear=function()clears=clears+1 end,
  travel=function(v)following=v end,maintain=function()maintains=maintains+1 end})
 local function tick(now,native,busy,active,key)return c:tick({now=now,key=key or 'enemy',allowed=true,nativeCombat=native,busy=busy,follow=true,encounterActive=active})end
 assert(tick(0,false,false,true)=='combat'and starts==1)
 assert(tick(250,true,false,true)=='combat')
 assert(tick(500,false,false,false)=='combat'and stops==0,'One idle sample interrupted combat')
 assert(tick(1000,false,true,false)=='combat'and stops==0,'Unbreakable exit was interrupted')
 assert(tick(1250,false,false,false)=='travel'and stops==1 and clears==1 and following)
 for now=1500,10000,250 do assert(tick(now,false,false,false)=='travel')end
 assert(starts==1 and stops==1,'Stale enemy replayed entry after the encounter ended')
 assert(tick(10250,false,false,true,'new enemy')=='combat'and starts==2,'Fresh encounter remained suppressed')
`));
test('native combat and perception gaps override missing whole-encounter evidence',()=>check('mod/Scripts/companion_combat.lua',`
 local enters,starts,stops,following=0,0,0,true
 local c=M.new({enter=function()enters=enters+1;following=false;return true end,target=function()return true end,start=function()starts=starts+1;return true end,
  stop=function()stops=stops+1;return true end,clear=function()end,travel=function(v)following=v end,maintain=function()end})
 for now=0,5000,250 do
  assert(c:tick({now=now,key=now%1000==0 and 'enemy'or nil,allowed=true,nativeCombat=true,busy=false,follow=true,encounterActive=false})=='combat')
 end
 assert(enters==1 and starts==0 and stops==0 and not following,'Active native fight yielded to stale encounter evidence')
`));

test('AI lifetime checks reject detached, replaced and destroying boards before native calls',()=>check('mod/Scripts/ai_state.lua',`
 EObjectFlags={RF_BeginDestroyed=0x8000,RF_FinishDestroyed=0x10000}
 local function object(name)return {IsValid=function()return true end,GetFullName=function()return name end,HasAnyFlags=function(self,mask)return ((self.flags or 0)&mask)~=0 end}end
 local board=object('board');board.Weapon={TagName={ToString=function()return 'Weapon.Sword'end}}
 local s=object('stub');s.AIBoard=board;s.IsInitializedAndHasPawn=function()return true end
 assert(M.weaponEquipped(s,board)==true)
 local calls=0;s.IsInitializedAndHasPawn=function()calls=calls+1;return true end
 s.AIBoard=nil;assert(M.board(s,board)==nil and M.weaponEquipped(s,board)==nil and calls==0)
 s.AIBoard=object('replacement');assert(M.board(s,board)==nil and calls==0)
 s.AIBoard=board;board.flags=0x8000;assert(M.board(s)==nil and calls==0)
 board.flags=0;s.flags=0x10000;assert(M.board(s)==nil and calls==0)
 s.flags=0;s.IsInitializedAndHasPawn=function()s.AIBoard=nil;return true end
 assert(M.board(s)==nil,'Board detached during native initialization check')
`));

test('native start lowers the clone gate only for entry and restores it on rejection or Lua error',()=>check('mod/Scripts/ai_state.lua',`
 EObjectFlags={RF_BeginDestroyed=0x8000,RF_FinishDestroyed=0x10000}
 local function object(name)return {IsValid=function()return true end,GetFullName=function()return name end,HasAnyFlags=function()return false end}end
 local function make(name)
  local s,b=object(name),object(name..'board');s.AIBoard=b
  s.IsInitializedAndHasPawn=function()return true end;s.IsInCombat=function()return false end;s.IsInCinematicMode=function()return false end
  b.HasAnyUnbreakableActiveAction=function()return false end;b.bCanFight=true;b.Combat={bInCombat=false}
  return s,b
 end
 local s,b=make('companion');local enemy,eb=make('enemy');local calls=0;local accept=false;local fail=false
 local lib={StartCombatBehaviors=function(_,stub)
  calls=calls+1;assert(stub==s and b.bCanFight==false and eb.bCanFight==true,'Incorrect native start precondition')
  if fail then error('Unavailable function')end
  if accept then b.bCanFight=true end;return accept
 end}
 assert(not M.startCombat(lib,s,b,enemy));assert(b.bCanFight and calls==1)
 fail=true;assert(not M.startCombat(lib,s,b,enemy));assert(b.bCanFight and calls==2)
 fail=false;accept=true;assert(M.startCombat(lib,s,b,enemy)and b.bCanFight and calls==3)
 enemy.AIBoard=nil;assert(not M.startCombat(lib,s,b,enemy)and calls==3)
 enemy.AIBoard=eb;b.HasAnyUnbreakableActiveAction=function()return true end
 assert(not M.startCombat(lib,s,b,enemy)and calls==3)
 s.AIBoard=nil;assert(not M.startCombat(lib,s,b,enemy)and calls==3)
`));

test('async class presence is insufficient until class and defaults finish loading',async()=>{
 const source=await readFile('mod/Scripts/companion_native.lua','utf8');const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const code=`package.preload.runtime_path=function()return '.'end
 local M=(function() ${source} end)()
 EObjectFlags={RF_NeedInitialization=0x200,RF_NeedLoad=0x400,RF_NeedPostLoad=0x1000,RF_NeedPostLoadSubobjects=0x2000,RF_BeginDestroyed=0x8000,RF_FinishDestroyed=0x10000}
 local flags,defaultsFlags=0,0
 local defaults={IsValid=function()return true end,HasAnyFlags=function(self,mask)return (defaultsFlags&mask)~=0 end}
 local className='Class /known'
 local class={IsValid=function()return true end,GetFullName=function()return className end,HasAnyFlags=function(self,mask)return (flags&mask)~=0 end,GetCDO=function()assert(flags==0,'CDO touched during class postload');return defaults end}
 StaticFindObject=function()return class end
 assert(M.loadedClass('/known')==class)
 for _,flag in pairs(EObjectFlags)do flags=flag;assert(M.loadedClass('/known')==nil)end
 flags=0;defaultsFlags=0x1000;assert(M.loadedClass('/known')==nil)
 defaultsFlags=0;assert(M.loadedClass('/known')==class)
 -- Reproduce an old class wrapper whose address is now a valid waypoint actor.
 className='Actor /world/waypoint';class.GetCDO=function()error('Wrong object used as class')end
 local replacement={IsValid=function()return true end,GetFullName=function()return 'Class /known'end,HasAnyFlags=function()return false end,GetCDO=function()return defaults end}
 local scans=0;StaticFindObject=function()scans=scans+1;return replacement end
 assert(M.loadedClass('/known')==replacement,'Stale valid pointer hid the loaded class')
 assert(M.loadedClass('/known')==replacement and scans==1,'Healthy cached class caused repeated scans')
 local assetName='Object /asset'
 local asset={IsValid=function()return true end,GetFullName=function()return assetName end,HasAnyFlags=function()return false end}
 StaticFindObject=function()return asset end;assert(M.loadedAsset('/asset')==asset)
 assetName='Actor /world/other';StaticFindObject=function()return nil end
 assert(M.loadedAsset('/asset')==nil,'Unrelated UObject escaped the asset cache')
 M.clearAssetCache();assert(M.loadedClass('/known')==nil,'Save reset retained a cached class')
 StaticFindObject=function()return nil end;assert(M.loadedClass('/missing')==nil)
 `;
 try{const result=lauxlib.luaL_dostring(L,to_luastring(code));assert.equal(result,lua.LUA_OK,result===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}
});

test('shared lookup cache rejects reused object addresses and clears on reset',()=>check('mod/Scripts/ai_state.lua',`
 EObjectFlags={RF_BeginDestroyed=1,RF_FinishDestroyed=2}
 local name='Class /profile';local scans=0
 local cached={IsValid=function()return true end,HasAnyFlags=function()return false end,GetFullName=function()return name end}
 local fresh={IsValid=function()return true end,HasAnyFlags=function()return false end,GetFullName=function()return 'Class /profile'end}
 StaticFindObject=function()scans=scans+1;return cached end
 assert(M.find('/profile')==cached);assert(M.find('/profile')==cached and scans==1)
 name='Actor /world/waypoint';StaticFindObject=function()scans=scans+1;return fresh end
 assert(M.find('/profile')==fresh and scans==2)
 M.clearFindCache();StaticFindObject=function()return nil end;assert(M.find('/profile')==nil)
`));

test('summon slots separate pending and live companions and face the current player',()=>check('mod/Scripts/companion_recovery.lua',`
 local function flat(p)return {X=p.X,Y=p.Y,Z=p.Z-90}end
 local function spaced(a,b)return (a.X-b.X)^2+(a.Y-b.Y)^2>=150^2 end
 local function faces(point,yaw,player)
  local dx,dy=player.X-point.X,player.Y-point.Y;local d=math.sqrt(dx*dx+dy*dy)
  assert((math.cos(math.rad(yaw))*dx+math.sin(math.rad(yaw))*dy)/d>0.999999)
 end
 local player={X=100,Y=-300,Z=100};local reserved={}
 for slot=1,3 do
  local point,yaw=M.summonPoint(player,37,slot,reserved,flat);assert(point);faces(point,yaw,player)
  for _,other in ipairs(reserved)do assert(spaced(point,other),'Summons overlap')end
  reserved[#reserved+1]=point
 end
 -- Player moves during loading; one companion has walked into the preferred
 -- new spot. Preserve the other in-flight reservation and find an alternative.
 player={X=1800,Y=500,Z=100}
 local preferred=M.summonPoint(player,-95,1,{},flat)
 local point,yaw=M.summonPoint(player,-95,1,{preferred,reserved[2]},flat)
 assert(point and spaced(point,preferred)and spaced(point,reserved[2]));faces(point,yaw,player)
 -- Reusing a dismissed slot still avoids the remaining companion's position.
 local reused,angle=M.summonPoint(player,-95,2,{preferred,point},flat)
 assert(reused and spaced(reused,preferred)and spaced(reused,point));faces(reused,angle,player)
`));
test('summoning checks projected locations and bounds attempts on cramped navigation',()=>check('mod/Scripts/companion_recovery.lua',`
 local player={X=0,Y=0,Z=100};local taken={X=300,Y=0,Z=10};local calls=0
 local point=M.summonPoint(player,0,2,{taken},function(candidate)
  calls=calls+1
  if calls<4 then return taken end
  return {X=candidate.X,Y=candidate.Y,Z=10}
 end)
 assert(point and calls>=4 and calls<=12 and (point.X-taken.X)^2+(point.Y-taken.Y)^2>=190^2)
 calls=0
 assert(M.summonPoint(player,0,1,{taken},function()calls=calls+1;return taken end)==nil)
 assert(calls==12,'Navigation search must stay bounded')
 assert(M.summonPoint(player,0,1,{},function()return player end)==nil,'Spawn overlaps player')
 assert(M.summonPoint(player,0,1,{},function()return {X=300,Y=0,Z=600}end)==nil,'Spawn on another floor')
 assert(M.summonPoint(player,0,1,{},function()return {X=2000,Y=0,Z=10}end)==nil,'Spawn too far away')
 assert(M.summonPoint(player,0,1,{},function()return nil end)==nil)
`));
test('distant catch-up excludes visible, airborne, busy, dead and fighting companions',()=>check('mod/Scripts/companion_recovery.lua',`
 local o={follow=true,dead=false,combat=false,busy=false,grounded=true,visible=false,gap=2500,now=12000}
 assert(M.catchup(o),'Distant off-camera traveller did not qualify')
 for k,v in pairs({follow=false,dead=true,combat=true,busy=true,grounded=false,visible=true,gap=1999})do
  local old=o[k];o[k]=v;assert(not M.catchup(o),'Unsafe catch-up: '..k);o[k]=old
 end
 o.last=8000;assert(not M.catchup(o),'Repeated teleport before cooldown')
 o.now=16000;assert(M.catchup(o))
 o.partyLast=15000;assert(not M.catchup(o),'Several companions teleported in one burst')
 o.now=16500;assert(M.catchup(o))
 o.minimum=4000;assert(not M.catchup(o),'A large formation was treated as lost while at its assigned distance')
`));

test('streaming retains a missing companion and reconnects only when alive and ready',()=>check('mod/Scripts/companion_recovery.lua',`
 local o={since=2000,now=2000,ready=false,dead=false}
 assert(M.missing(o)=='waiting')
 o.now=12000;assert(M.missing(o)=='unloaded')
 o.now=60000;assert(M.missing(o)=='unloaded','Missing party slot was discarded by timeout')
 o.ready=true;assert(M.missing(o)=='reattach')
 o.dead=true;assert(M.missing(o)=='defeated','Ready corpse would be reattached as a follower')
 o.ready=false;assert(M.missing(o)=='defeated')
`));

test('claw setup verifies physical equipment and selector, survives partial setup and restores each encounter',()=>check('mod/Scripts/ai_state.lua',`
 EObjectFlags={RF_BeginDestroyed=0x8000,RF_FinishDestroyed=0x10000}
 FName=function(s)return {ToString=function()return s end}end
 local function object(name)return {IsValid=function()return true end,GetFullName=function()return name end,HasAnyFlags=function()return false end}end
 local s,b,component=object('companion'),object('board'),object('component');s.AIBoard=b
 s.IsInitializedAndHasPawn=function()return true end;s.IsInCinematicMode=function()return false end
 b.HasAnyUnbreakableActiveAction=function()return false end
 b.CurrentCharacterState={TagName=FName('RebelAI.CharacterState.Neutral')}
 b.Weapon={TagName=FName('None')}
 local spawns,stances,modeWrites=0,0,0;local current='None';local accept=false;local setMode=false
 local clawClass,claws=object('claw class'),object('claws');local mainWeapon=nil;local selectorWrites=0
 claws.IsA=function(_,c)return c==clawClass end
 component.GetMainWeapon=function()return mainWeapon end
 b.Temp_BP_SetWeapon=function(_,tag)selectorWrites=selectorWrites+1;b.Weapon=tag end
 b.Temp_BP_GetCombatMode=function(_,out)out.TagName=FName(current)end
 b.Temp_BP_SetCombatMode=function(_,tag)modeWrites=modeWrites+1;if setMode then current=tag.TagName:ToString()end end
 s.BP_CharacterStateExist=function()return true end
 s.BP_SetCharacterState=function(_,tag)stances=stances+1;b.CurrentCharacterState=tag end
 component.SpawnHandToHandWeapons=function()spawns=spawns+1;if accept then mainWeapon=claws end;return accept end
 local setup={}
 local function prepare()return M.handCombat(s,b,component,setup,clawClass)end
 assert(not prepare());assert(not setup.weaponsSpawned and stances==0 and modeWrites==0 and selectorWrites==0)
 accept=true;assert(not prepare());assert(setup.weaponsSpawned and spawns==2 and stances==0)
 setMode=true;assert(prepare());assert(spawns==2 and stances==1 and selectorWrites==1)
 assert(b.Weapon.TagName:ToString()=='RebelAI.Weapon.Fists'and setup.attackSelector=='RebelAI.Weapon.Fists','Claws were present but attack-query selector stayed empty')
 b.CurrentCharacterState={TagName=FName('RebelAI.CharacterState.Neutral')}
 assert(prepare());assert(spawns==2 and stances==2 and selectorWrites==1,'Second fight replayed equipment setup or retained idle stance')
 b.HasAnyUnbreakableActiveAction=function()return true end
 assert(not prepare()and spawns==2 and stances==2)
 b.HasAnyUnbreakableActiveAction=function()return false end
 current='None';setup={};mainWeapon=nil
 component.SpawnHandToHandWeapons=function()spawns=spawns+1;s.AIBoard=nil;return true end
 local oldWrites=modeWrites
 assert(not prepare()and setup.weaponsSpawned and modeWrites==oldWrites and stances==2 and selectorWrites==1,'Detached AI received a mode/selector/state call')
 s.AIBoard=b;current='RebelAI.CombatMode.VampireHand2Hand';setup={};mainWeapon=claws;b.Weapon={TagName=FName('None')}
 assert(prepare()and modeWrites==oldWrites and stances==3 and spawns==3 and selectorWrites==2,'Existing claws were duplicated or lacked their attack selector')
 b.Weapon={TagName=FName('RebelAI.Weapon.Sword')}
 assert(not prepare()and stances==3 and selectorWrites==2,'Another native weapon selector was overwritten')
 b.Weapon={TagName=FName('None')};mainWeapon=nil
 assert(not prepare()and stances==3 and selectorWrites==2,'Attack selector was assigned without physical claws')
`));
