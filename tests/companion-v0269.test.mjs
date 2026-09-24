import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const scripts=process.env.DAWNWALKER_LUA||'mod/Scripts';
function execute(source){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(source));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
async function check(module,body){execute(`local M=(function() ${await readFile(`${scripts}/${module}.lua`,'utf8')} end)()\n${body}`);}
async function part(from,to,setup,body){const s=await readFile(`${scripts}/companions.lua`,'utf8');execute(setup+'\n'+s.slice(s.indexOf(from),s.indexOf(to,s.indexOf(from)))+'\n'+body);}
test('initial choices spread across active enemies and do not chase a much farther target just to spread out',()=>check('companion_combat',`
 local a={target='boar A',key='a',distance=700,assigned=2,aimed=true,attackingPlayer=true}
 local b={target='boar B',key='b',distance=900,assigned=0}
 assert(M.initialTarget({a,b})=='boar B');b.assigned=2;assert(M.initialTarget({b,a})=='boar A')
 b.distance=4000;b.assigned=0;assert(M.initialTarget({a,b})=='boar A')
 assert(M.initialTarget({})==nil)
`));
test('equally suitable initial targets have stable identity-based tie breaking',()=>check('companion_combat',`
 local a={target='a',key='a',distance=900};local b={target='b',key='b',distance=900}
 assert(M.initialTarget({a,b})=='a'and M.initialTarget({b,a})=='a')
`));
test('actual target adapter considers another active enemy and preserves its choice when Coen aims elsewhere',async()=>{
 const combat=await readFile(`${scripts}/companion_combat.lua`,'utf8');
 await part('local function targetFor','local function combatController',`
 local Combat=(function() ${combat} end)()
 local function valid(o)return o~=nil end;local function same(a,b)return a~=nil and a==b end
 local function loc(o)return o.position end
 local function distance(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2)end
 local function eligible(o,p,r)return o~=nil and o.enemy and not o.dead and distance(o.position,p)<=r*100 end
 local function ready(m)return m.board~=nil end
 local playerPoint={X=0,Y=0};local player={position=playerPoint};local playerStub={}
 local function enemy(id,x,active)
  local e={id=id,enemy=true,position={X=x,Y=0},AIBoard={GetTarget=function()return nil end},IsInCombat=function()return active end}
  e.GetActor=function()return e end;e.GetFullName=function()return id end;return e
 end
 local a,b,quiet=enemy('a',700,true),enemy('b',900,true),enemy('quiet',100,false)
 playerStub.AIBoard={GetTarget=function()return a end}
 local current=nil;local native=false
 local m={characterId='xanthe',actor={position=playerPoint},mode='follow',stub={IsInCombat=function()return native end},board={Combat={bInCombat=false},GetTarget=function()return current end}}
 local members={m,{mode='follow',combatTarget=a},{mode='follow',combatTarget=a}}
 `,`
 assert(targetFor(m,{a,b,quiet})==b,'The adapter kept piling onto the aimed opponent')
 m.combatTarget=b;assert(targetFor(m,{a,b})==b,'Aim changed an existing assignment')
 native=true;current=b;b.position={X=3500,Y=0};m.actor.position={X=3400,Y=0}
 assert(targetFor(m,{a})==b,'Coen crossing 30m replaced a native opponent')
 `);
});
test('native combat adoption releases travel leases without restoring a travel state or re-equipping',()=>part(
 'local function combatPose','local function combatMovement',`
 local releases=0;local function releaseTravelIdle()releases=releases+1 end
 local function releaseFollowPace()releases=releases+1 end
 local function ready()return true end
 `,`
 local m={travelPose=true,travelGait=true,poseOwned='RebelAI.CharacterState.Running',poseRestore='RebelAI.CharacterState.Default',weaponStowed=true}
 combatPose(m,true);assert(releases==2 and not m.travelPose and not m.poseOwned and not m.poseRestore and not m.weaponStowed)
 -- No stub/board was provided: active combat adoption cannot call their state/equipment setters.
 `));
test('preparation does not restore Default over the current travel state',()=>part(
 'local function combatPose','local function combatMovement',`
 local function releaseTravelIdle()end;local function releaseFollowPace()end;local function ready()return true end
 local function log()end;local function clean(s)return s end
 FName=function(s)return s end
 `,`
 local writes=0;local m={travelPose=true,poseOwned='RebelAI.CharacterState.Running',poseRestore='RebelAI.CharacterState.Default',stub={BP_SetCharacterState=function()writes=writes+1 end},board={HasAnyUnbreakableActiveAction=function()return false end,CurrentCharacterState={TagName={ToString=function()return 'RebelAI.CharacterState.Running'end}}}}
 combatPose(m,false);assert(writes==0 and not m.poseOwned and not m.poseRestore)
 m.travelPose=true;m.poseOwned='RebelAI.CharacterState.Running';m.poseRestore='RebelAI.CharacterState.Combat.Sword'
 combatPose(m,false);assert(writes==1,'An actual saved combat pose was not restored during preparation')
 `));
const movement=`
 EObjectFlags={RF_BeginDestroyed=1,RF_FinishDestroyed=2}
 local function obj(n)return {IsValid=function()return true end,HasAnyFlags=function()return false end,GetFullName=function()return n end}end
 local s,b=obj('stub'),obj('board');s.AIBoard=b;s.IsInitializedAndHasPawn=function()return true end
 local fighting,busy,scene=true,false,false
 s.IsInCombat=function()return fighting end;s.IsInCinematicMode=function()return scene end
 local pose='RebelAI.CharacterState.Running';b.Combat={bInCombat=false};b.CurrentCharacterState={TagName={ToString=function()return pose end}}
 b.HasAnyUnbreakableActiveAction=function()return busy end
 local walk,authored,native=obj('RebelCharacterMovementProfile /p/DA_NPC_Walker_MovementProfile.DA_NPC_Walker_MovementProfile'),obj('Xanthe authored combat'),obj('native defense')
 walk.MovementConfig={MaxSpeed=140};authored.MovementConfig={MaxSpeed=425};native.MovementConfig={MaxSpeed=100}
 local current=walk;local movement=obj('movement');local pushes,pops=0,0
 movement.GetCurrentMovementProfile=function()return current end
 movement.PushMovementProfile=function(_,p)pushes=pushes+1;current=p;return pushes end
 movement.PopMovementProfile=function()pops=pops+1;if current==authored then current=walk end end
 local state={}
`;
test('leftover walking profile gets the authored combat profile once and yields to native combat state',()=>check('ai_state',movement+`
 assert(M.combatMovement(s,b,state,movement,authored,0));assert(pushes==1 and current==authored)
 for t=250,4000,250 do assert(M.combatMovement(s,b,state,movement,authored,t))end
 assert(pushes==1)
 current=native;pose='RebelAI.CharacterState.Combat.Sword.Defense'
 assert(not M.combatMovement(s,b,state,movement,authored,4250));assert(pops==1 and current==native)
 pose='RebelAI.CharacterState.Default';assert(not M.combatMovement(s,b,state,movement,authored,8000));assert(pushes==1,'A deliberately slow native defense profile was overwritten')
`));
test('combat profile repair excludes actions, scenes, unloaded assets, travel and detached boards',()=>check('ai_state',movement+`
 assert(not M.combatMovement(s,b,state,movement,nil,0));assert(pushes==0)
 busy=true;assert(not M.combatMovement(s,b,state,movement,authored,0));busy=false
 scene=true;assert(not M.combatMovement(s,b,state,movement,authored,0));scene=false
 assert(M.combatMovement(s,b,state,movement,authored,0));fighting=false
 assert(not M.combatMovement(s,b,state,movement,authored,250));assert(current==walk and pops==1)
 fighting=true;assert(M.combatMovement(s,b,state,movement,authored,4000));s.AIBoard=nil
 assert(not M.combatMovement(s,b,state,movement,authored,4250));assert(not state.handle and pops==1,'Called native movement cleanup through a detached board')
`));
test('finishing an action can immediately repair the leftover walker profile again',()=>check('ai_state',movement+`
 assert(M.combatMovement(s,b,state,movement,authored,0));busy=true
 assert(not M.combatMovement(s,b,state,movement,authored,250));busy=false
 assert(M.combatMovement(s,b,state,movement,authored,500));assert(pushes==2 and pops==1)
`));
test('rejected movement priority does not repeatedly push a losing profile',()=>check('ai_state',movement+`
 movement.PushMovementProfile=function()pushes=pushes+1;return pushes end
 assert(M.combatMovement(s,b,state,movement,authored,0));assert(pushes==1 and pops==0)
 assert(M.combatMovement(s,b,state,movement,authored,500))
 assert(not M.combatMovement(s,b,state,movement,authored,750));assert(pops==1)
 for t=1000,3500,250 do assert(not M.combatMovement(s,b,state,movement,authored,t))end
 assert(pushes==1);assert(M.combatMovement(s,b,state,movement,authored,3750));assert(pushes==2)
`));
test('recent independent departures help a far fighter escape a pursuer beside Coen',()=>check('companion_recovery',`
 local party={{returning=true,returnKind='sustained run',returnSince=1000},{returning=true,returnKind='sustained run',returnSince=1500}}
 assert(M.partyDeparture(party,2000));assert(not M.partyDeparture(party,7000))
 party[2].returning=nil;assert(not M.partyDeparture(party,2000));party[2].returning=true
 local m={};local o={follow=true,encounter=true,combat=true,partyDeparture=M.partyDeparture(party,2000),now=2000,gap=3500,spacing=550,speed=600,awaySpeed=0,companionAwaySpeed=590,fightDistance=700,threatDistance=700,fightKnown=true,x=0,y=0}
 assert(M.retreat(m,o));assert(m.returnKind=='party departure')
 o.now=8000;o.partyDeparture=false;o.gap=1500;assert(M.retreat(m,o),'Signal expiry cancelled an already confirmed retreat')
 o.gap=600;o.speed=0;o.companionAwaySpeed=0;o.combat=false;assert(not M.retreat(m,o),'Reunion beside the fight never released suppression')
`));
test('party departure cannot recruit an idle follower or a companion during local repositioning',()=>check('companion_recovery',`
 local o={follow=true,encounter=true,combat=true,partyDeparture=true,now=2000,gap=3500,spacing=550,speed=600,awaySpeed=0,companionAwaySpeed=100,fightDistance=400,threatDistance=400,fightKnown=true,x=0,y=0}
 assert(not M.retreat({},o));o.companionAwaySpeed=590;o.speed=200;assert(not M.retreat({},o))
 o.speed=600;o.combat=false;assert(not M.retreat({},o));o.combat=true;o.gap=1200;assert(not M.retreat({},o))
`));
test('asset readiness waits for serialization and never treats a data asset as a class CDO',async()=>{
 const native=await readFile(`${scripts}/companion_native.lua`,'utf8');
 execute(`package.preload.runtime_path=function()return '.'end
 local M=(function() ${native} end)()
 EObjectFlags={RF_NeedInitialization=0x200,RF_NeedLoad=0x400,RF_NeedPostLoad=0x1000,RF_NeedPostLoadSubobjects=0x2000,RF_BeginDestroyed=0x8000,RF_FinishDestroyed=0x10000}
 local flags=0;local live=true
 local asset={GetFullName=function()return 'DataAsset /profile'end,IsValid=function()return live end,HasAnyFlags=function(_,mask)return (flags&mask)~=0 end,GetCDO=function()error('Data asset has no CDO')end}
 StaticFindObject=function()return asset end
 assert(M.loadedAsset('/profile')==asset)
 for _,flag in pairs(EObjectFlags)do flags=flag;assert(M.loadedAsset('/profile')==nil)end
 flags=0;assert(M.loadedAsset('/profile')==asset);live=false;assert(M.loadedAsset('/profile')==nil)
 `);
});
test('Xanthe waits for her asynchronous movement asset before spawning while another summon can finish',()=>part(
 'local function pollLoading','local function eligible',`
 local function valid(o)return o~=nil end
 local point={X=0,Y=0,Z=0};local player={K2_GetActorRotation=function()return {Yaw=0}end}
 local function loc()return point end;local function log()end;local function summonStage()end
 local ready=false;local requests,spawns=0,0
 local profile={IsA=function()return true end};local xantheCombatProfile='/xanthe'
 local AI={find=function()return {}end}
 local Native={loadedClass=function()return {}end,loadedAsset=function()if ready then return profile end end,
  requestAsset=function()requests=requests+1;return {requestMs=0}end,
  spawn=function()spawns=spawns+1;return {action='/action',factoryMs=0,activateMs=0}end,
  exportedPath=function(p)return p end}
 local Recovery={summonPoint=function()return point,0 end};local project=nil
 local function member(id)return {characterId=id,name=id,created=0,definition={},loading='reactions',reactionsPath='/reaction',npcClass={},loadTrace={},spawnSlot=1}end
 local m,other=member('xanthe'),member('crake');local members={m,other}
 `,`
 pollLoading(m,100);pollLoading(m,200)
 assert(requests==1 and spawns==0 and m.loading=='reactions','Spawn did not wait for its asset')
 pollLoading(other,300);assert(spawns==1 and not other.loading,'Waiting Xanthe blocked another summon')
 ready=true;pollLoading(m,400)
 assert(spawns==2 and not m.loading and m.authoredCombatProfile==profile)
 `));
