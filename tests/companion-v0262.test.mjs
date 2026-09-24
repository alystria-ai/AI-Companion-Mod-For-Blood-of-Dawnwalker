import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
async function check(module,body){
 const source=await readFile((process.env.DAWNWALKER_LUA||'mod/Scripts')+'/'+module+'.lua','utf8');
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 try{const rc=lauxlib.luaL_dostring(L,to_luastring(`local M=(function() ${source} end)()\n${body}`));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}
}
test('sprint begins as Coen sprints, closes larger gaps and has a distinct exit threshold',()=>check('companion_combat',`
 local p=M.followPace(230,425,false,180,false);assert(p.running and p.sprinting and p.enum==2)
 assert(M.followPace(610,0,false,180,false).enum==2)
 assert(M.followPace(400,0,true,180,true).enum==2)
 assert(M.followPace(280,0,true,180,true).enum==1)
 assert(M.followPace(180,0,true,180,true).enum==0)
 local far=M.followPace(2500,0,false,180,false)
 assert(far.targetSpeed and far.targetSpeed>590,'Stationary player disabled distant catch-up boost')
 local closing=M.followPace(800,0,true,180,true)
 assert(closing.targetSpeed<far.targetSpeed,'Boost did not ease as the gap closed')
 assert(M.followPace(280,0,true,180,true).targetSpeed==nil,'Boost remained active beside player')
 assert(M.followPace(6000,5000,false,180,false).targetSpeed==4000,'Travel speed was not bounded')
`));
test('a distant old encounter regroups even when a different enemy is now beside the player',()=>check('companion_recovery',`
 local m={};local o={follow=true,encounter=true,now=0,gap=4200,spacing=180,speed=600,awaySpeed=0,combat=true,threatDistance=500,fightDistance=5000,x=0,y=0}
 assert(not M.retreat(m,o));o.now=1750;o.speed=0;assert(not M.retreat(m,o))
 o.now=2000;assert(M.retreat(m,o),'Close enemy blocked distant companion recovery')
`));
test('brief distant dodge resets regroup evidence and ordinary nearby combat remains native',()=>check('companion_recovery',`
 local m={};local o={follow=true,encounter=true,now=0,gap=2500,spacing=180,speed=400,awaySpeed=0,combat=true,threatDistance=500,fightDistance=500}
 assert(not M.retreat(m,o));o.now=1750;o.gap=1800;assert(not M.retreat(m,o))
 o.now=3000;o.gap=2500;assert(not M.retreat(m,o));o.now=4500;assert(not M.retreat(m,o))
 o.follow=false;assert(not M.retreat(m,o)and not m.separatedAt)
 o.follow=true;o.encounter=false;for n=5000,15000,250 do o.now=n;assert(not M.retreat(m,o))end
`));
test('reattachment requires a surviving identical pawn, not a rapid series of replacements',()=>check('companion_recovery',`
 local m={};assert(not M.reconnectCandidate(m,'pawn1',0));assert(not M.reconnectCandidate(m,'pawn1',750))
 assert(not M.reconnectCandidate(m,'pawn2',800));assert(not M.reconnectCandidate(m,'pawn3',1600))
 assert(M.reconnectCandidate(m,'pawn3',2600));assert(not M.reconnectCandidate(m,nil,2700))
 assert(not M.reconnectCandidate(m,'pawn3',3000))
`));
test('catch-up moves behind the actual third-person camera instead of repeatedly rejecting the first slot',()=>check('companion_recovery',`
 local p={X=0,Y=0,Z=100};local camera={X=-600,Y=0,Z=200}
 local point=M.catchupPoint(p,0,1,{},function(v)return v end,camera)
 assert(point and point.X<-720 and M.behindCamera(point,camera,0))
 local calls=0
 point=M.catchupPoint(p,0,1,{},function(v)calls=calls+1;if calls==1 then return {X=-400,Y=0,Z=100}end;return v end,camera)
 assert(point and calls==2 and M.behindCamera(point,camera,0),'Projected point in view stopped the whole search')
 camera={X=0,Y=-900,Z=200};point=M.catchupPoint(p,90,2,{},function(v)return v end,camera)
 assert(point and M.behindCamera(point,camera,90))
`));
test('failed catch-up attempts use a short retry while successful relocation keeps the longer cooldown',()=>check('companion_recovery',`
 local o={follow=true,dead=false,combat=false,busy=false,grounded=true,visible=false,gap=4000,now=1000,attempted=0}
 assert(not M.catchup(o));o.now=2000;assert(M.catchup(o))
 o.last=2000;o.now=9999;assert(not M.catchup(o));o.now=10000;assert(M.catchup(o))
 o.now=5000;o.cooldown=3000;assert(M.catchup(o),'Fast travel kept the ordinary eight-second cooldown')
 o.combat=true;assert(not M.catchup(o))
`));
const ai=`
 EObjectFlags={RF_BeginDestroyed=1,RF_FinishDestroyed=2}
 local function obj(name)return {IsValid=function()return true end,HasAnyFlags=function()return false end,GetFullName=function()return name end}end
 local s,b=obj('stub'),obj('board');s.AIBoard=b;s.IsInitializedAndHasPawn=function()return true end
 local combat,busy=false,false;s.IsInCombat=function()return combat end;s.IsInCinematicMode=function()return false end
 b.Follower={FollowerSpeed=0};b.Combat={bInCombat=false};b.HasAnyUnbreakableActiveAction=function()return busy end
 local movement,profile,current=obj('movement'),obj('sprint'),obj('walker')
 profile.MovementConfig={MaxSpeed=590};current.MovementConfig={MaxSpeed=140}
 local pushes,pops=0,0;movement.GetCurrentMovementProfile=function()return current end
 movement.PushMovementProfile=function(_,p)assert(p==profile);pushes=pushes+1;return 42 end
 movement.PopMovementProfile=function(_,h)assert(h==42);pops=pops+1;return true end
 local lease={}
`;
test('travel leases a native faster profile once, repairs native enum drift and releases before combat',()=>check('ai_state',ai+`
 assert(M.travelPace(s,b,lease,movement,profile,2));assert(pushes==1 and b.Follower.FollowerSpeed==2)
 for i=1,20 do b.Follower.FollowerSpeed=0;M.travelPace(s,b,lease,movement,profile,2);assert(b.Follower.FollowerSpeed==2)end
 assert(pushes==1 and profile.MovementConfig.MaxSpeed==590)
 combat=true;assert(not M.travelPace(s,b,lease,movement,profile,2));assert(pops==1)
 M.releaseTravelProfile(lease);assert(pops==1,'Profile popped twice')
`));
test('native faster profiles are preserved and detached or busy pawns cannot acquire a travel override',()=>check('ai_state',ai+`
 current.MovementConfig.MaxSpeed=900;assert(M.travelPace(s,b,lease,movement,profile,2));assert(pushes==0)
 current.MovementConfig.MaxSpeed=140;busy=true;assert(not M.travelPace(s,b,lease,movement,profile,2));assert(pushes==0)
 busy=false;s.AIBoard=nil;assert(not M.travelPace(s,b,lease,movement,profile,2));assert(pushes==0)
 s.AIBoard=b;M.travelPace(s,b,lease,movement,profile,2);assert(pushes==1)
 assert(M.travelPace(s,b,lease,movement,profile,0));assert(pops==1 and b.Follower.FollowerSpeed==0)
`));
