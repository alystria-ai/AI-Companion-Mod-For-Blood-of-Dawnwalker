import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const path=process.env.DAWNWALKER_LUA||'mod/Scripts';
const [recovery,planner,native]=await Promise.all(['companion_recovery','party_formation','formation_native'].map(n=>readFile(`${path}/${n}.lua`,'utf8')));
function run(s){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(s));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
const planning=`local R=(function()${recovery}end)();local function require()return R end;local P=(function()${planner}end)()`;
test('whole-party arrival seats stay compact and separated, remain fixed during approaches and release dismissed members',()=>run(`${planning}
 for _,count in ipairs({10,40})do
  local p=P.new();local rows={}
  for i=1,count do rows[i]={id=tostring(i),ordinal=i,slot=i,pitch=190,radius=55,position={X=i*12,Y=0,Z=0}}end
  p:update(rows,{X=0,Y=0,Z=0},0,0,0)
  assert(p.goals['1'].point.X==12,'New summons should keep their front placement until departure')
  p:update(rows,{X=1000,Y=0,Z=0},0,600,1000)
  local g=p:update(rows,{X=1100,Y=0,Z=0},90,0,2000)
  for i=1,count do
   local q=g[tostring(i)].point;local radius=R.summonArc(i,190)
   local dx,dy=q.X-1100,q.Y
   assert(dx<0 and dx*dx+dy*dy<radius*radius,'Arrival seat was not brought closer behind Coen')
   for j=1,i-1 do local v=g[tostring(j)].point;assert((q.X-v.X)^2+(q.Y-v.Y)^2>=160^2,'Assigned seats overlap')end
  end
  local before=g['1'].point
  for _,row in ipairs(rows)do row.pitch=300;row.distanceScale=2 end
  p:update(rows,{X=1150,Y=50,Z=0},180,0,3000)
  assert(p.goals['1'].point.X==before.X and p.goals['1'].point.Y==before.Y,'Camera/approach shuffled the party')
  table.remove(rows);p:update(rows,{X=1150,Y=50,Z=0},180,0,3250);assert(not p.seats[tostring(count)],'Dismissed member retained its seat')
 end
 for _,count in ipairs({1,2,3,4,6,20,40})do
  local members={};for i=1,count do members[i]={ordinal=i,characterId='a',baseName='A',capsuleRadius=55}end
  for _,narrow in ipairs({0,1})do for _,closeness in ipairs({50,100,150})do for _,spacing in ipairs({75,100,175})do
   local ordered=R.layout(members,{FollowerCloseness=closeness,PartySpacing=spacing,NarrowFormation=narrow});local points={}
   for i,m in ipairs(ordered)do
    local q=R.followPoint({X=0,Y=0,Z=0},0,i,m.formationPitch,count,m.formationDistanceScale,m.formationNarrow)
    assert(q.X<=0 and q.X*q.X+q.Y*q.Y>=130^2-0.01,'Closeness overlapped Coen')
    for _,v in ipairs(points)do assert((q.X-v.X)^2+(q.Y-v.Y)^2>=145^2-0.01,'Following controls overlapped seats')end
    points[#points+1]=q
   end
  end end end
 end
 for count=1,4 do
  local frame={};R.formationFrame(frame,{X=0,Y=0,Z=0},0,0,0,count)
  R.formationFrame(frame,{X=100,Y=0,Z=0},0,140,1000,count,false)
  assert(frame.moving,'Small group waited too long to follow')
  frame={};R.formationFrame(frame,{X=0,Y=0,Z=0},0,0,0,count)
  R.formationFrame(frame,{X=100,Y=0,Z=0},0,140,1000,count,true)
  assert(not frame.moving,'Approaching a friend moved the small party')
 end
 local group=P.new()
 local friend={{id='a',ordinal=1,slot=1,count=1,pitch=150,radius=55,position={X=0,Y=-135,Z=0}}}
 group:update(friend,{X=0,Y=0,Z=0},0,0,0)
 group:update(friend,{X=200,Y=0,Z=0},0,140,1000,nil,{X=140,Y=0})
 assert(group.goals.a.point.X>200 and group.goals.a.point.Y==-135,'Moving side destination did not compensate for path lag')
 group:update(friend,{X=200,Y=0,Z=0},0,0,2000,nil,{X=0,Y=0})
 assert(group.goals.a.point.X==200,'Stopping retained the forward lead or placed the friend behind')
`));
test('combat and conversations retain their space while a blocked rear seat yields on its own arc',()=>run(`${planning}
 local p=P.new();local rows={}
 for i=1,9 do rows[i]={id=tostring(i),ordinal=i,slot=i,pitch=190,radius=55,position={X=0,Y=0,Z=0}}end
 p:update(rows,{X=0,Y=0,Z=0},0,0,0);p:update(rows,{X=1000,Y=0,Z=0},0,600,1000)
 local point=p.goals['1'].point;rows[9].locked=true;rows[9].position=point
 p:update(rows,{X=1000,Y=0,Z=0},0,0,2000)
 assert(not p.goals['9'],'Locked combat/conversation member was assigned a move')
 local q=p.goals['1'].point
 assert((q.X-point.X)^2+(q.Y-point.Y)^2>=155^2,'Yielding member moved into a locked actor')
 rows[9].locked=false;p:update(rows,{X=1500,Y=0,Z=0},0,600,3000);assert(p.goals['9'],'Released member never rejoined')
 -- Approaching a parked companion must reserve its spot even when a later
 -- arrival's planned destination is exactly there.
 p=P.new();rows={}
 for i=1,6 do rows[i]={id=tostring(i),ordinal=i,slot=i,pitch=190,radius=55,position={X=-1000,Y=i*200,Z=0}}end
 p:update(rows,{X=0,Y=0,Z=0},0,0,0)
 p:update(rows,{X=1000,Y=0,Z=0},0,600,1000)
 p:update(rows,{X=1000,Y=0,Z=0},0,0,2000)
 local occupied=p.goals['2'].point
 rows[1].position={X=occupied.X,Y=occupied.Y,Z=occupied.Z}
 p.seats['1'].parked=rows[1].position
 p:update(rows,{X=1000,Y=0,Z=0},0,0,2250)
 assert(p.goals['1'].distance==0,'Arriving seat displaced a parked speaker')
 local arrival=p.goals['2'].point
 assert((arrival.X-occupied.X)^2+(arrival.Y-occupied.Y)^2>=145^2,'Arrival did not respect the parked speaker')
`));
const boundary=`
 local alive=function(o)return o and not o.dead end
 local AI={valid=alive,same=function(a,b)return alive(a)and alive(b)and a==b end,board=function(s,b)return alive(s)and s.AIBoard==b and alive(b)and b or nil end,find=function()return {}end}
 local require=function()return AI end
 local N=(function()${native}end)()
 local b={Follower={bFollowerModeEnabled=true},Combat={},StopAllActions=function()end,HasAnyUnbreakableActiveAction=function()return false end}
 local stub={AIBoard=b,IsInCombat=function()return b.Combat.bInCombat end,IsInCinematicMode=function()return false end}
 local bb={values={track=false,follow=false},GetValueAsObject=function(self,k)return self.values[k]end,GetValueAsBool=function(self,k)return self.values[k]or false end,SetValueAsBool=function(self,k,v)self.values[k]=v end}
 local calls,stops,destroyed=0,0,0;local marker
 local c={Blackboard=bb,BrainComponent={},MovementTargetActorBBKey='target',ShouldFollowTargetBBKey='follow',ShouldTrackTargetBBKey='track',StopMovement=function()end,GetMoveStatus=function(self)return self.pathStatus or 3 end}
 c.AIMoveToActor=function(self,target,follow,track,fast)assert(not b.bMainBehaviorSuspended and not b.Follower.bFollowerModeEnabled);calls=calls+1;bb.values.target=target;bb.values.follow=follow;bb.values.track=track end
 c.AIStopFollowing=function()stops=stops+1;bb.values.target=nil end
 local world={SpawnActor=function(self,class,p,r)
  marker={point=p,RootComponent={SetMobility=function()end},SetActorHiddenInGame=function()end,SetActorEnableCollision=function()end,SetLifeSpan=function()end,K2_DestroyActor=function(self)self.dead=true;destroyed=destroyed+1 end,K2_SetActorLocation=function(self,p)self.point=p;return true end};return marker
 end}
 local actor={GetWorld=function()return world end,K2_GetActorLocation=function()return {X=0,Y=0,Z=0}end}
 local m={actor=actor,stub=stub,board=b,controller=c};local goal={point={X=500,Y=0,Z=0},distance=500,mode='Rear arc'}
`;
test('changed native destinations refresh at most once per second; combat releases actor and flags',()=>run(`${boundary}
 assert(N.update(m,goal,0));local owned=marker
 for now=250,4000,250 do goal.point={X=500+now*.1,Y=0,Z=0};assert(N.update(m,goal,now))end
 assert(marker==owned and calls==5,'Changed seats must reuse their actor and refresh at most once per second')
 assert(N.owns(m.formationLease,stub,b)and not b.bMainBehaviorSuspended)
 b.Combat.bInCombat=true;assert(not N.update(m,goal,4250))
 assert(stops==1 and destroyed==1 and b.Follower.bFollowerModeEnabled and not bb.values.target)
 assert(bb.values.follow==false and bb.values.track==false,'Native tracking flags were not restored')
 N.release(m.formationLease);assert(destroyed==1 and stops==1,'Cleanup ran twice')
`));
test('native ownership preserves a foreign movement target and cleans up detached actor markers',()=>run(`${boundary}
 local foreign={};bb.values.target=foreign;assert(not N.update(m,goal,0));assert(calls==0)
 bb.values.target=nil;assert(N.update(m,goal,1000));bb.values.target=foreign;N.release(m.formationLease)
 assert(bb.values.target==foreign and stops==0 and destroyed==1,'Another native action was cancelled')
 bb.values.target=nil;assert(N.update(m,goal,2000));stub.AIBoard={};N.release(m.formationLease)
 assert(destroyed==2,'Detached pawn leaked its private marker')
`));
test('arrival stops the path once and small idle motion does not restart it',()=>run(`${boundary}
 goal.epoch=1;assert(N.update(m,goal,0))
 actor.K2_GetActorLocation=function()return {X=414,Y=0,Z=0}end
 goal.distance=86;assert(N.update(m,goal,250));assert(stops==1 and m.formationLease.settled,'Native arrival must not stay in the old 80 to 100 cm dead zone')
 for now=500,4000,250 do goal.distance=110;assert(N.update(m,goal,now))end
 assert(calls==1 and stops==1 and not b.Follower.bFollowerModeEnabled,'Idle correction restarted following')
 goal.moving=true;goal.epoch=2;goal.point={X=1000,Y=0,Z=0};goal.distance=550
 assert(N.update(m,goal,4250));assert(calls==2 and not m.formationLease.settled,'Real departure did not resume')
 assert(marker.point.X==1100,'Resumed navigation used the old arrival point')
 goal.moving=false;goal.distance=40;N.update(m,goal,4500);N.release(m.formationLease)
 assert(b.Follower.bFollowerModeEnabled and bb.values.follow==false and bb.values.track==false,'Idle lease failed to restore flags')
 goal.distance=125;c.pathStatus=0;assert(N.update(m,goal,5000));assert(m.formationLease.settled,'Native idle just inside settled tolerance kept chasing')
`));
test('native route stalls have bounded rebinds and yield after measured failure',()=>run(`${boundary}
 for now=0,6000,250 do N.update(m,goal,now)end
 assert(calls==3 and not m.formationLease.owned,'Stalled native route became an endless restart loop')
 assert(m.formationLease.retryAt==12000 and b.Follower.bFollowerModeEnabled)
 for now=6250,11750,250 do N.update(m,goal,now)end
 assert(calls==3,'Fallback delay ignored')
`));
test('native stop-radius compensation reaches the seat and moving intents refresh at a bounded cadence',()=>run(`${boundary}
 local seat={X=500,Y=200,Z=0};local a={X=0,Y=0,Z=0};local previous
 for i=1,100 do
  local target=N.markerPoint(seat,a,previous);previous=target
  local dx,dy=target.X-a.X,target.Y-a.Y;local d=math.sqrt(dx*dx+dy*dy)
  if d>100 then local step=math.min(25,d-100);a.X=a.X+dx*step/d;a.Y=a.Y+dy*step/d end
 end
 assert((a.X-seat.X)^2+(a.Y-seat.Y)^2<45^2,'Native 100 cm acceptance left the pawn short of its seat')
 goal.moving=true;assert(N.update(m,goal,0));local owned=marker
 for now=250,4000,250 do goal.point={X=500+now*.5,Y=0,Z=0};assert(N.update(m,goal,now))end
 assert(marker==owned and calls==5,'Moving intent refresh must reuse its actor and remain at most once per second')
`));
