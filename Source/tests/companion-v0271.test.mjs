import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const scripts=process.env.DAWNWALKER_LUA||'mod/Scripts';
function execute(source){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(source));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
async function check(body){execute(`local M=(function() ${await readFile(`${scripts}/companion_recovery.lua`,'utf8')} end)()\n${body}`);}
test('twenty summons occupy three close front arcs, face Coen and never reuse reservations',()=>check(`
 for _,yaw in ipairs({0,37,90,-163})do
  local p={X=210,Y=-500,Z=80};local occupied={};local angle=math.rad(yaw)
  for i=1,20 do
   local q,face=M.summonPoint(p,yaw,i,occupied,function(v)return v end)
   assert(q,'No point for summon '..i)
   local x,y=q.X-p.X,q.Y-p.Y
   assert(x*math.cos(angle)+y*math.sin(angle)>50,'Spawn behind player')
   assert(x*x+y*y<=660^2,'Twenty companions spread too far away')
   assert(math.abs((M.facing(q,p)-face+180)%360-180)<0.01)
   for _,other in ipairs(occupied)do assert((q.X-other.X)^2+(q.Y-other.Y)^2>=190^2,'Overlapping reservations')end
   occupied[#occupied+1]=q
  end
 end
 assert(M.summonPoint({X=0,Y=0,Z=0},0,1,{},function()return {X=-250,Y=0,Z=0}end)==nil,'Nav snapped behind player')
`));
test('twenty followers fill rear semicircles; capsule sizes and clone labels remain correct',()=>check(`
 local members={};for i=1,20 do members[i]={id=tostring(i),ordinal=i,characterId=i==1 and 'anca'or 'brencis',baseName=i==1 and 'Anca'or 'Brencis'}end
 local ordered=M.layout(members);assert(ordered[1].label=='Anca'and ordered[2].label=='Brencis #1')
 local positions={}
 for _,m in ipairs(ordered)do
  local p,r=M.followPoint({X=0,Y=0,Z=0},0,m.formationSlot,m.formationPitch)
  assert(r<800 and r>=150,'Bad twenty-person footprint')
  for _,q in ipairs(positions)do assert((q.X-p.X)^2+(q.Y-p.Y)^2>=190^2)end
  positions[#positions+1]=p
 end
 assert(positions[1].X<0 and positions[1].Y<0 and positions[2].X<0 and positions[2].Y>0)
 assert(math.abs(positions[1].X-positions[2].X)<0.01,'First companions must share the rear arc')
 members[7].capsuleRadius=200;M.layout(members);assert(members[1].formationPitch==480)
`));
test('shared space coordinator moves only yielders and protects conversations and other native owners',()=>check(`
 local rows={};for i=1,20 do rows[i]={id=tostring(i),ordinal=i,X=(i-1)*190,Y=0,Z=0,radius=55}end
 assert(next(M.separation(rows))==nil)
 rows[2].X=rows[1].X;local y=M.separation(rows);assert(y['2']and not y['1'])
 rows[2].locked=true;y=M.separation(rows);assert(y['1']and not y['2'],'Selected character moved')
 rows[1].locked=true;assert(next(M.separation(rows))==nil,'Locked pair must keep native ownership')
 rows[1].locked=false;rows[2].Z=300;assert(next(M.separation(rows))==nil,'Different floor was treated as overlap')
 rows[2].Z=0;rows[1].X=-10;rows[2].X=10;y=M.separation(rows);assert(y['1'],'Spatial bucket boundary missed collision')
 rows={{id='a',ordinal=1,X=0,Y=0,Z=0,radius=55},{id='b',ordinal=2,X=160,Y=0,Z=0,radius=55}}
 assert(M.separation(rows).b,'Visible crowding should be corrected before capsules overlap')
`));

test('crowding retains a bounded correction budget after ordinary arrival attempts are spent',()=>check(`
 local m={travelProgress={x=0,y=0,px=500,py=0,tries=3}}
 local o={allowed=true,pathStatus=0,spacing=165,gap=165,now=0,x=0,y=0,px=500,py=0,laneDistance=200,goal={X=0,Y=190,Z=0},overlap=true}
 assert(not M.travelRequest(m,o));o.now=500;assert(M.travelRequest(m,o)=='Give companion space')
 o.now=2000;assert(M.travelRequest(m,o));o.now=3500;assert(M.travelRequest(m,o))
 o.now=6000;assert(not M.travelRequest(m,o),'Persistent blockage must not trigger an endless retry loop')
`));
test('formation path requests are budgeted, tolerate passing crowds and detect a stale moving request',()=>check(`
 local m={};local o={allowed=true,pathStatus=3,spacing=175,gap=1000,now=0,x=0,y=0,px=1000,py=0,laneDistance=900,goal={X=850,Y=160,Z=0}}
 assert(not M.travelRequest(m,o));o.now=3250;assert(not M.travelRequest(m,o));o.now=3500
 assert(M.travelRequest(m,o)=='Stagnant follow path')
 o.now=12000;assert(M.travelRequest(m,o)=='Stagnant follow path')
 o.now=30000;assert(not M.travelRequest(m,o),'Retry storm on immobile actor')
 o.x=300;o.now=31000;assert(not M.travelRequest(m,o));o.now=34500;assert(M.travelRequest(m,o),'Real movement did not renew budget')
 m={};o={allowed=true,pathStatus=0,spacing=175,gap=175,now=0,x=0,y=0,px=175,py=0,laneDistance=170,goal={X=0,Y=160,Z=0},overlap=true}
 assert(not M.travelRequest(m,o));o.now=500;o.overlap=false;assert(not M.travelRequest(m,o))
 o.now=1000;o.overlap=true;assert(not M.travelRequest(m,o));o.now=1750;o.partyLast=1700;assert(not M.travelRequest(m,o))
 o.partyLast=1500;assert(M.travelRequest(m,o)=='Give companion space')
 o.now=3500;o.allowed=false;assert(not M.travelRequest(m,o),'Conversation/combat owner interrupted')
`));
test('navigation reservations separate destinations and narrow paths remain bounded for twenty',()=>check(`
 local p={X=0,Y=0,Z=0};local wanted={X=-160,Y=0,Z=0};local reserved={{X=-160,Y=0,Z=0}}
 local q=M.travelDestination(wanted,p,reserved,function(v)return v end,160,0)
 assert(q and M.clearPoint(q,reserved,140))
 local goal,why=M.travelDestination(wanted,p,{},function()return {X=1000,Y=0,Z=0}end,160,0)
 assert(not goal and why=='navigation')
 goal,why=M.travelDestination(wanted,p,{{X=-160,Y=0,Z=0},{X=-160,Y=-160,Z=0},{X=-160,Y=160,Z=0},{X=-320,Y=0,Z=0},{X=-320,Y=-160,Z=0},{X=-320,Y=160,Z=0}},function(v)return v end,160,0)
 assert(not goal and why=='occupied','Crowding must not be confused with a cliff')
 local points={};for i=1,20 do local q=M.corridorPoint(p,0,i,160)
  assert(math.abs(q.Y)<=90 and q.X>=-1640)
  for _,other in ipairs(points)do assert((q.X-other.X)^2+(q.Y-other.Y)^2>=150^2)end
  points[#points+1]=q
 end
`));
test('twenty members share a fair four-per-second path budget and stalled overlap does not loop forever',()=>check(`
 local members={};for i=1,20 do members[i]={id=tostring(i),ordinal=i}end
 local cursor,last=0,nil;local seen={};local counts={}
 for now=0,9750,250 do
  local ordered;ordered,cursor=M.updateOrder(members,cursor)
  for _,m in ipairs(ordered)do
   local o={allowed=true,pathStatus=0,spacing=175,gap=175,now=now,x=0,y=0,px=500,py=0,laneDistance=500,goal={X=500,Y=160,Z=0},correct=true,partyLast=last}
   if M.travelRequest(m,o)then last=now;seen[m.id]=true;local second=math.floor(now/1000);counts[second]=(counts[second]or 0)+1 end
  end
 end
 local n=0;for _ in pairs(seen)do n=n+1 end;assert(n==20,'Path budget starved later summons')
 for _,n in pairs(counts)do assert(n<=4,'Whole-party burst budget exceeded')end
 local m={};local calls=0
 for now=0,30000,250 do
  if M.travelRequest(m,{allowed=true,pathStatus=3,spacing=175,gap=175,now=now,x=0,y=0,px=175,py=0,laneDistance=200,goal={X=0,Y=160,Z=0},overlap=true})then calls=calls+1 end
 end
 assert(calls==6,'Stalled separation must get only one retry per eight seconds after the initial three')
`));
test('actual follow adapter resumes native destination tracking once and defers to combat or actions',async()=>{
 const s=await readFile(`${scripts}/companions.lua`,'utf8');const part=s.slice(s.indexOf('local function followMovement'),s.indexOf('local function conversationCandidate'));
 execute(`
 local combat,busy=false,false;local resets,updates=0,0
 local actor={GetMovementComponent=function()return {}end};local other={GetMovementComponent=function()return {}end}
 local board={Follower={bFollowerModeEnabled=true,FollowerSpeed=0,KeepDistanceToPlayer=999,KeepDistanceToPlayerMoveTo=999},Combat={},HasAnyUnbreakableActiveAction=function()return busy end}
 local stub={IsInCombat=function()return combat end,IsInCinematicMode=function()return false end}
 local controller={GetMoveStatus=function()return 0 end}
 local m={id='a',actor=actor,stub=stub,board=board,controller=controller,mode='follow',resumeConversation=actor,followSpacing=175,travelPose=true,travelGait=true}
 local function ready()return true end;local function valid()return true end;local function same(a,b)return a==b end
 local function loc()return {X=0,Y=0,Z=0}end;local function distance()return 0 end
 local function releaseFollowPace()resets=resets+1 end;local function travelPose()end
 local playerPoint={X=300,Y=0,Z=0};local playerSpeed=0;local formationFrame={};local lastFollowWake
 local AI={find=function()return {}end,travelPace=function()end}
 local function ownsFormation()return false end;local function releaseFormation()end
 local Combat={followPace=function()return {stop=175,start=425,running=false,sprinting=false,enum=0}end}
 local formation={goals={a={point={X=300,Y=160,Z=0},distance=340,epoch=1}}}
 local FormationNative={update=function(member,goal,now)updates=updates+1;assert(member==m and goal==formation.goals.a);return true,'tracked'end}
 ${part}
 combat=true;followMovement(m,0);assert(updates==0 and m.resumeConversation==actor)
 combat=false;busy=true;followMovement(m,250);assert(updates==0)
 busy=false;followMovement(m,500);assert(resets==1 and updates==1 and not m.resumeConversation)
 followMovement(m,750);assert(resets==1 and updates==2,'Conversation reset replayed every tick')
 m.resumeConversation=actor;m.actor=other;followMovement(m,1000);assert(resets==1,'Stale release reset a replacement clone')
 assert(m.formationPending,'Native target acceptance must not masquerade as arrival')
 formation.goals.a.distance=50;followMovement(m,1500);assert(not m.formationPending,'Measured arrival did not settle')
 `);
});
test('group Lua handoff waits for a busy member, publishes no inactive gap, and releases final hold once',async()=>{
 const s=await readFile(`${scripts}/app.lua`,'utf8');const part=s.slice(s.indexOf("local lastGroupCommand=''"),s.indexOf('local function uiCommand()'));
 execute(`
 local text='GROUP\\t1\\troom1\\tturn1\\tmember1\\t5';local writes={};local root='test';local calls=0;local selected='old';local generation=5;local conversationMode='group';local conversationRoom='room1';local speakerTurn
 io.open=function()return {read=function()return text end,close=function()end}end
 local function write(name,value)writes[name]=value end
 local function log()end
 local releases=0;local function releaseConversation()releases=releases+1 end
 local function stop(_,quiet)assert(quiet,'Intermediate inactive selection exposed');selected=nil;generation=generation+1 end
 local function toggle(_,actor)selected=actor;generation=generation+1 end
 local Companions={actor=function()calls=calls+1;if calls==1 then return nil,true end;return 'next',false end}
 ${part}
 groupCommand();assert(selected=='old'and not writes['group-ready.tsv']);groupCommand()
 assert(selected=='next'and speakerTurn=='turn1'and writes['group-ready.tsv']=='turn1\\tready')
 groupCommand();assert(calls==2,'Replayed handoff')
 text='GROUPEND\\t1\\troom1\\tdone1\\t7';groupCommand();groupCommand();assert(releases==1)
 text='GROUPEND\\t1\\troom1\\tdone2\\t5';groupCommand();assert(releases==1,'Stale release ended a newer conversation')
 `);
});
test('companion conversation selection waits for actions and resumes only its own instance',async()=>{
 const s=await readFile(`${scripts}/companions.lua`,'utf8');const part=s.slice(s.indexOf('local function conversationCandidate'),s.indexOf('local function rememberOwner'));
 execute(`
 local M={};local a,b={},{};local members={a={actor=a,mode='follow',name='Brencis',definition={path='brencis'}},b={actor=b,mode='follow'}}
 local player={};local formationFrame={epoch=1};local busy=true;local board={Combat={},HasAnyUnbreakableActiveAction=function()return busy end}
 local stub={IsInCombat=function()return false end,IsInCinematicMode=function()return false end}
 members.a.board=board;members.a.stub=stub;members.b.board=board;members.b.stub=stub
 local function ready()return true end;local function valid()return true end;local function same(x,y)return x==y end
 local function ownsFormation(m)return m.formationOwned==true end
 local function loc()return {X=0,Y=0,Z=0}end;local function distance()return 100 end
 local function releaseFollowPace(m)if m.formationOwned then m.formationOwned=nil;board.bMainBehaviorSuspended=false end end
 local function releaseHold()end;local function travelPose(m)assert(not m.travelPose and not m.travelGait and not board.bMainBehaviorSuspended)end
 ${part}
 local actor,pending=M.actor('a');assert(not actor and pending and conversationCandidate(members.a))
 assert(M.beforeConversation(a)==false);busy=false;assert(M.actor('a')==a)
 board.bMainBehaviorSuspended=true;assert(not conversationCandidate(members.a),'External suspension must keep priority')
 members.a.formationOwned=true;assert(not conversationCandidate(members.a),'Formation no longer owns suspension; external holds keep priority')
 board.bMainBehaviorSuspended=false;assert(conversationCandidate(members.a))
 members.a.travelPose=true;members.a.travelGait=true;assert(M.beforeConversation(a))
 assert(not members.a.formationOwned and not board.bMainBehaviorSuspended,'Chat did not release formation control')
 M.afterConversation(a);assert(members.a.resumeConversation==a and members.a.talkFollowing and not members.b.resumeConversation)
 members.a.resumeConversation=nil;M.afterConversation(a);assert(not members.a.resumeConversation,'Walking away after group completion reset the path a second time')
 board.Combat.bInCombat=true;assert(M.actor('a')==nil and not conversationCandidate(members.a))
 `);
});
