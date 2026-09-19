import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const scripts=process.env.DAWNWALKER_LUA||'mod/Scripts';
function execute(source){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(source));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
async function check(module,body){execute(`local M=(function() ${await readFile(`${scripts}/${module}.lua`,'utf8')} end)()\n${body}`);}
test('turning and short approaches leave the party frame and settled slots alone',()=>check('companion_recovery',`
 local f={};M.formationFrame(f,{X=0,Y=0,Z=0},0,0,0)
 local m={formationEpoch=0}
 for t=250,10000,250 do
  M.formationFrame(f,{X=0,Y=math.sin(t)*250,Z=0},180,600,t)
  assert(f.epoch==0 and f.yaw==0 and f.point.X==0 and f.point.Y==0)
  assert(not M.formationCorrection(m,f,600,900,0),'Settled party chased a new slot')
 end
`));
test('real travel permits one arrival adjustment, while an approach cancels it',()=>check('companion_recovery',`
 local f={};local m={formationEpoch=0};M.formationFrame(f,{X=0,Y=0,Z=0},0,0,0)
 M.formationFrame(f,{X=500,Y=0,Z=0},0,600,1000)
 assert(f.moving and f.epoch==1);assert(not M.formationCorrection(m,f,800,700,600))
 M.formationFrame(f,{X=600,Y=0,Z=0},90,0,1500);assert(f.moving)
 M.formationFrame(f,{X=600,Y=0,Z=0},90,0,1750);assert(not f.moving and f.yaw==0)
 assert(M.formationCorrection(m,f,800,700,0))
 assert(M.formationCorrection(m,f,447,320,0),'An accepted path must remain pending while still distant')
 assert(not M.formationCorrection(m,f,220,55,0),'Arrival should clear the correction')
 M.formationFrame(f,{X=600,Y=200,Z=0},90,0,3000)
 assert(not M.formationCorrection(m,f,800,700,0));assert(f.point.Y==0)
 m.formationPending=true;assert(not M.formationCorrection(m,f,150,700,0))
 assert(not M.formationCorrection(m,f,800,700,0),'Approach only suspended, rather than cancelled, the adjustment')
`));
test('short local movement does not wake a follower, but a real gap keeps fast pace',()=>check('companion_recovery',`
 local m={};local o={allowed=true,pathStatus=0,spacing=400,gap=630,now=0,x=0,y=0,px=0,py=0}
 for t=0,20000,250 do o.now=t;assert(not M.wakeFollow(m,o))end
 o.gap=1200;o.now=21000;assert(not M.wakeFollow(m,o));o.now=22500;assert(M.wakeFollow(m,o))
`));
const retreat=`local m={};local o={follow=true,encounter=true,fightKnown=true,now=0,gap=2400,spacing=400,speed=600,awaySpeed=600,combat=true,threatDistance=1200,fightDistance=1200,x=0,y=0}
 local function step(t,x) o.now=t;o.x=x;return M.retreat(m,o)end
`;
test('committed departure retreats even when a chasing enemy keeps its distance',()=>check('companion_recovery',retreat+`
 assert(not step(0,0));assert(not step(1250,750));assert(step(1500,900))
 assert(m.returnKind=='sustained run');assert(step(1750,1050));assert(step(6000,3600))
 assert(m.noEngageUntil==8500,'Nearby pursuer cleared regroup while still running')
 o.gap=600;assert(step(6100,3660),'Catching up beside the running player reopened combat')
 o.gap=2000;o.speed=0;o.awaySpeed=0;assert(step(6200,3660),'Stopping before reunion let the pursuer cancel retreat')
 o.speed=0;o.awaySpeed=0;o.fightDistance=4000;o.threatDistance=4000;o.gap=600
 assert(step(6250,3600),'Combat has not exited yet');o.combat=false
 assert(step(6500,3600));assert(not step(8000,3600))
`));
test('short sprints, tangential movement and returning to the actual fight do not latch regroup',()=>check('companion_recovery',retreat+`
 assert(not step(0,0));assert(not step(1250,750));o.speed=0;assert(not step(1500,750));assert(not m.sprintDeparture)
 o.speed=600;o.awaySpeed=100;for t=1750,6000,250 do assert(not step(t,t))end
 o.awaySpeed=600;o.fightDistance=300;o.threatDistance=300
 for t=6250,10000,250 do assert(not step(t,t))end
 m.returning=true;m.returnKind='sustained run';m.noEngageUntil=99999
 assert(not step(10250,10000)and not m.noEngageUntil)
`));
const objects=`
 EObjectFlags={RF_BeginDestroyed=1,RF_FinishDestroyed=2}
 local function obj(n)return {IsValid=function()return true end,HasAnyFlags=function()return false end,GetFullName=function()return n end}end
 local keys={'IdleAnimSet','FixedDirectionIdleAnimSet','TurnInPlaceBlendSpaceSet'}
 local layer,donor=obj('linked instance'),obj('parent CDO');local original={}
 for _,k in ipairs(keys)do layer[k]=obj('boss '..k);original[k]=layer[k];donor[k]=obj('human '..k)end
 local state={}
`;
test('Ambrus travel lease changes only instance idle references and restores exact combat selectors',()=>check('ai_state',objects+`
 assert(M.leaseIdleSelectors(layer,donor,state));for _,k in ipairs(keys)do assert(layer[k]==donor[k])end
 assert(M.leaseIdleSelectors(layer,donor,state));assert(#state.values==3)
 M.releaseIdleSelectors(state);M.releaseIdleSelectors(state)
 for _,k in ipairs(keys)do assert(layer[k]==original[k]);assert(donor[k]:GetFullName()=='human '..k)end
 assert(not M.leaseIdleSelectors(donor,donor,{}),'A CDO was treated as its own live instance')
`));
test('idle lease respects native overrides, invalid assets and a replacement linked instance',()=>check('ai_state',objects+`
 local missing=donor.TurnInPlaceBlendSpaceSet;donor.TurnInPlaceBlendSpaceSet=nil
 assert(not M.leaseIdleSelectors(layer,donor,state));for _,k in ipairs(keys)do assert(layer[k]==original[k])end
 donor.TurnInPlaceBlendSpaceSet=missing;assert(M.leaseIdleSelectors(layer,donor,state))
 local external=obj('native scene selector');layer.IdleAnimSet=external
 assert(M.leaseIdleSelectors(layer,donor,state));assert(layer.IdleAnimSet==external)
 local replacement=obj('new linked instance');for _,k in ipairs(keys)do replacement[k]=original[k]end
 assert(M.leaseIdleSelectors(replacement,donor,state));assert(layer.IdleAnimSet==external)
 assert(layer.FixedDirectionIdleAnimSet==original.FixedDirectionIdleAnimSet)
 replacement.IsValid=function()return false end;M.releaseIdleSelectors(state);assert(state.layer==nil)
`));
test('retreat renews hostile pairs after hits and remembers opponents beyond the discovery radius',async()=>{
 const src=await readFile(`${scripts}/companions.lua`,'utf8');
 const part=src.slice(src.indexOf('local restoreEnemies'),src.indexOf('local function restoreAttitudes'));
 execute(`
 local function obj(n)return {GetFullName=function()return n end}end
 local function same(a,b)return a~=nil and a==b end
 local AI={board=function(o)return o~=nil end,retreatSensing=function()return true end}
 local playerStub=obj('player');local ally=obj('ally');local ownedStubs={ally=true}
 local function ready()return true end
 ${part}
 local restored=0;restoreEnemies=function()restored=restored+1 end
 local source,enemy,far=obj('source'),obj('enemy'),obj('far')
 local attitudes={[enemy]=3,[far]=3,[ally]=3,[playerStub]=3};local writes=0
 source.GetAttitudeTowards=function(_,t)return attitudes[t]end
 source.SetAttitudeTowards=function(_,t,v)attitudes[t]=v;writes=writes+1 end
 local target=enemy;local m={stub=source,board={GetTarget=function()return target end},enemyAttitudes={{source=source,target=far}}}
 retreatSensing(m,true,{ally,playerStub});assert(attitudes[enemy]==1 and attitudes[far]==1 and writes==2)
 assert(attitudes[ally]==3 and attitudes[playerStub]==3,'Retreat edited a party relationship')
 target=nil;m.enemyAttitudes={};retreatSensing(m,true,{});assert(writes==2)
 attitudes[enemy]=3;attitudes[far]=3 -- A native damage/instigator path changes these back.
 retreatSensing(m,true,{});assert(writes==4 and m.retreatRepairs==2)
 attitudes[far]=2 -- An external neutral change belongs to that owner.
 retreatSensing(m,false,{});assert(attitudes[enemy]==3 and attitudes[far]==2 and restored==1)
 `);
});
