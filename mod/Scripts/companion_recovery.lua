-- Pure arrival/travel/lifetime decisions. Detachment is not a request to destroy the
-- population owner: it may be a temporary visibility/streaming transition.
local M={}
-- Shared anchor/path/reconnection budgets must not always go to the first
-- hash-table members. Every instance gets first access once per party cycle.
function M.updateOrder(members,cursor)
 local ordered={};for _,m in pairs(members)do ordered[#ordered+1]=m end
 table.sort(ordered,function(a,b)return a.ordinal<b.ordinal end)
 local n=#ordered;if n==0 then return {},0 end
 local first=(cursor or 0)%n;local result={}
 for i=0,n-1 do result[#result+1]=ordered[(first+i)%n+1]end
 return result,(first+1)%n
end
-- Stable instance IDs never change. Labels depend on the CURRENT population.
-- Shared rear arcs instead of an ever-longer single-file tail.
function M.layout(members,settings)
 local ordered,counts={},{}
 for _,m in pairs(members)do
  ordered[#ordered+1]=m;counts[m.characterId]=(counts[m.characterId]or 0)+1
 end
 table.sort(ordered,function(a,b)return a.ordinal<b.ordinal end)
 local seen={};local largest=55
 for _,m in ipairs(ordered)do largest=math.max(largest,m.capsuleRadius or 55)end
 local compact=#ordered>=2 and #ordered<=5
 local pitch=compact and math.max(150,largest*2+40)or math.max(180,largest*2+70)
 pitch=math.max(largest*2+(compact and 35 or 60),pitch*((settings and settings.PartySpacing or 100)/100))
 local depth=100/(settings and settings.FollowerCloseness or 100)
 local narrow=settings and settings.NarrowFormation==1 or false
 local points={}
 for i,m in ipairs(ordered)do
  local back,side=M.followOffset(i,pitch,#ordered,narrow);points[i]={back=back,side=side}
  -- Closeness compresses rear depth, not lateral space. Clamp the requested
  -- depth using capsule clearance so the two controls cannot overlap seats.
  local playerClearance=(m.capsuleRadius or 55)+75
  if math.abs(back)>1 and side*side<playerClearance^2 then
   depth=math.max(depth,math.sqrt(playerClearance^2-side*side)/math.abs(back))
  end
  for j=1,i-1 do
   local x,y=back-points[j].back,side-points[j].side
   local clearance=(m.capsuleRadius or 55)+(ordered[j].capsuleRadius or 55)+35
   if math.abs(x)>1 and y*y<clearance^2 then depth=math.max(depth,math.sqrt(clearance^2-y*y)/math.abs(x))end
  end
 end
 for i,m in ipairs(ordered)do
  seen[m.characterId]=(seen[m.characterId]or 0)+1
  m.label=m.baseName..(counts[m.characterId]>1 and ' #'..seen[m.characterId]or '')
  m.formationSlot=i;m.formationPitch=pitch;m.formationCount=#ordered;m.formationDistanceScale=depth;m.formationNarrow=narrow
  local back,side=M.followOffset(i,pitch,#ordered,narrow)
  m.followSpacing=math.sqrt((back*depth)^2+side*side)+15
 end
 return ordered
end
-- Keep a settled party's frame fixed while Coen approaches somebody. A real
-- travel leg begins after three metres; stopping captures one final destination.
-- Camera turns and short sidesteps never rotate everyone's assigned slot.
function M.formationFrame(state,p,yaw,speed,now,count)
 local function capture()
  state.point={X=p.X,Y=p.Y,Z=p.Z};state.yaw=yaw
 end
 if not state.point then capture();state.epoch=0;return state end
 local gap=(p.X-state.point.X)^2+(p.Y-state.point.Y)^2
 local depart=count and count>=2 and count<=5 and 180 or 300
 if not state.moving and gap>=depart^2 then
  state.moving=true;state.epoch=state.epoch+1;state.lastMoving=now
 end
 if state.moving then
  if speed>=180 then capture();state.lastMoving=now
  elseif now-(state.lastMoving or now)>=750 then
   -- Retain the direction of actual travel when the player stops/turns.
   state.point={X=p.X,Y=p.Y,Z=p.Z};state.moving=false
  end
 end
 return state
end
function M.formationCorrection(m,frame,gap,laneDistance,speed)
 if m.formationEpoch~=frame.epoch then
  m.formationEpoch=frame.epoch;m.formationPending=true
 end
 -- An approach to speak takes priority over a last arrival adjustment.
 if not frame.moving and (gap<=170 or laneDistance<=60)then m.formationPending=nil end
 return m.formationPending==true and not frame.moving and speed<100 and laneDistance>75
end
-- Small shared budget for load/attach work; live companions still update.
-- Admit at least one step so a busy frame cannot starve the queue forever.
function M.admitLoadStep(budget,clock)
 local used=budget.used or 0
 if used>=4 or used>0 and clock-budget.started>=.004 then return false end
 if used==0 then budget.started=clock end
 budget.used=used+1;return true
end
-- Refill a bounded slice, never accumulate tokens while paused. Large moving
-- parties need more than one path per tick or their destinations lag metres.
function M.pathBudget(state,now,count,moving)
 local slice=math.floor(now/250)
 local capacity=moving and math.min(3,math.max(1,math.ceil(count/4)))or 1
 if state.slice~=slice then state.slice=slice;state.remaining=capacity end
 return state
end
function M.travelOrigin(frame,velocity,count)
 local p=frame.point
 if not frame.moving or not velocity then return p end
 -- Aim half a refresh interval ahead; the stopped frame has no prediction.
 local capacity=math.min(3,math.max(1,math.ceil(count/4)))
 local lead=math.min(0.65,math.max(0.25,count/(capacity*4)*0.5))
 local x,y=velocity.X*lead,velocity.Y*lead;local length=math.sqrt(x*x+y*y)
 if length>250 then x=x*250/length;y=y*250/length end
 return {X=p.X+x,Y=p.Y+y,Z=p.Z}
end
-- Two independent, recent sustained-run detections are evidence of a party
-- departure. A straggler's enemy may be chasing beside Coen and otherwise veto
-- that member's retreat until its pawn falls outside streaming range.
function M.partyDeparture(members,now)
 local n=0
 for _,m in pairs(members)do
  if m.returning and m.returnKind=='sustained run'and now-(m.returnSince or -math.huge)<=5000 then n=n+1;if n>=2 then return true end end
 end
 return false
end
-- Retreat needs sustained movement AWAY FROM THE FIGHT, not simply away
-- from one companion. Short dodges, circling and flanking nearby enemies do
-- not qualify. Ordinary long-distance travel never arms combat retreat.
function M.retreat(m,o)
 if not o.follow then m.returning=nil;m.rejoinedAt=nil;m.departure=nil;m.separatedAt=nil;m.sprintDeparture=nil;m.returnKind=nil;m.returnSince=nil;return false end
 local stop=o.spacing or 180
 local danger=o.fightDistance or o.threatDistance or math.huge
 local nearby=o.threatDistance or math.huge
 local outward=o.speed>180 and o.awaySpeed>o.speed*0.65
 local awayFromCompanion=o.speed>=180 and (o.companionAwaySpeed or 0)>o.speed*0.65
 if o.partyDeparture and o.encounter and o.combat and o.speed>=400 and awayFromCompanion and o.gap>math.max(1800,stop+1000)and not m.returning then
  m.returning=true;m.returnKind='party departure';m.returnSince=o.now;m.departure=nil;m.separatedAt=nil;m.rejoinedAt=nil
 end
 -- A chasing enemy may keep the same distance. Recognize a committed run
 -- using the player's own net travel, not a requirement that the enemy lag.
 -- Inside eight metres of the known enemy, ordinary fighting still wins.
 local sprint=o.encounter and o.fightKnown==true and o.speed>=400 and outward
  and danger>=800 and o.gap>math.max(900,stop+350)
 if sprint then
  m.sprintDeparture=m.sprintDeparture or {at=o.now,x=o.x or 0,y=o.y or 0}
 else m.sprintDeparture=nil end
 local d=m.sprintDeparture
 local committed=d and o.now-d.at>=1500 and ((o.x or 0)-d.x)^2+((o.y or 0)-d.y)^2>=900^2
 if committed and not m.returning then
  m.returning=true;m.returnKind='sustained run';m.returnSince=o.now;m.departure=nil;m.separatedAt=nil;m.rejoinedAt=nil
 end
 -- Player distance from this follower is not distance from its enemy.
 -- A companion flanking 25m away must not stop fighting an enemy beside Coen.
 local atOwnFight=o.fightKnown~=false and danger<=1800
 local leavingOwnFight=m.returning and m.returnKind=='sustained run'and danger>=800
  and (o.speed>=400 and outward or o.gap>stop+500)
  or m.returning and m.returnKind=='party departure'and (awayFromCompanion or o.gap>stop+500)
 if atOwnFight and not leavingOwnFight then
  if m.returning then m.noEngageUntil=nil end
  m.returning=nil;m.rejoinedAt=nil;m.departure=nil;m.separatedAt=nil;m.returnKind=nil;m.returnSince=nil
  return false
 end
 if m.returning then
  m.noEngageUntil=o.now+2500
  -- Native path acceptance/capsules can stop a follower beyond the nominal
  -- ring. A five-metre reunion allowance avoids a permanently latched return.
  if not o.combat and o.gap<=stop+500 and o.speed<170 then
   m.rejoinedAt=m.rejoinedAt or o.now
   if o.now-m.rejoinedAt>=1500 then m.returning=nil;m.rejoinedAt=nil;m.returnKind=nil;m.returnSince=nil;m.sprintDeparture=nil;m.noEngageUntil=nil end
  else m.rejoinedAt=nil end
  return m.returning==true
 end
 local nearFight=nearby<=1800 and o.gap<=math.max(3200,stop+2000)and (o.fightKnown~=true or danger<=2200)
 local departing=o.encounter and not nearFight and o.gap>math.max(900,stop+500)and danger>1800 and outward
 local stranded=o.encounter and o.gap>math.max(3500,stop+2500)and danger>3000 and o.speed<170
 -- Before followers drift into distant streaming churn, a sustained large
 -- companion gap means regroup, even if a different enemy is beside Coen.
 -- This timer survives sprint/stop transitions, but brief flanks reset it.
 local separated=o.encounter and not nearFight and danger>2200 and o.gap>math.max(2400,stop+1600)
 if separated then m.separatedAt=m.separatedAt or o.now else m.separatedAt=nil end
 if separated and o.now-m.separatedAt>=2000 then
  m.returning=true;m.returnKind='distant separation';m.rejoinedAt=nil;m.departure=nil;m.separatedAt=nil;m.noEngageUntil=o.now+2500;return true
 end
 if not departing and not stranded then m.departure=nil;return false end
 local kind=departing and 'running'or 'stranded'
 if not m.departure or m.departure.kind~=kind then
  m.departure={kind=kind,at=o.now,x=o.x or 0,y=o.y or 0,danger=danger}
 end
 local d=m.departure;local travelled=math.sqrt(((o.x or 0)-d.x)^2+((o.y or 0)-d.y)^2)
 local confirmed=departing and o.now-d.at>=2500 and travelled>=600 and danger-d.danger>=450
  or stranded and o.now-d.at>=5000
 if confirmed then m.returning=true;m.returnKind=kind;m.rejoinedAt=nil;m.departure=nil;m.noEngageUntil=o.now+2500 end
 return m.returning==true
end
-- A recovered companion may join Coen's current fight while he circles or
-- approaches an enemy. A nearby pursuer behind a fleeing player is different:
-- continuing away from that target keeps regroup active.
function M.rejoinBattle(m,o)
 local pending=m.returning or o.now<(m.noEngageUntil or 0)
 local intent=o.target and o.targetGap<=1200 and (o.speed<170 or o.targetAwaySpeed<=math.max(100,o.speed*0.35))
 if not pending or not o.allowed or not intent or o.gap>math.max(1000,(o.spacing or 250)+450)then m.battleRejoin=nil;return false end
 local s=m.battleRejoin
 if not s or s.target~=o.target then s={target=o.target,at=o.now};m.battleRejoin=s end
 if o.now-s.at<500 then return false end
 m.returning=nil;m.noEngageUntil=nil;m.rejoinedAt=nil;m.returnKind=nil;m.returnSince=nil
 m.departure=nil;m.separatedAt=nil;m.sprintDeparture=nil;m.battleRejoin=nil
 return true
end
function M.catchupLimits(speed,spacing)
 local fast=(speed or 0)>=320
 return math.max(fast and 1200 or 1600,(spacing or 250)+600),fast and 3000 or 5000
end
-- Fast travel is a discontinuity, while unusually fast continuous movement is
-- a temporary repositioning leg. Keep one epoch for the whole leg so recovery
-- can make at most one replacement-owner request if streaming never reconnects.
function M.travelTransition(state,o)
 local dx=state.point and o.point.X-state.point.X or 0
 local dy=state.point and o.point.Y-state.point.Y or 0
 local moved=math.sqrt(dx*dx+dy*dy)
 local kind,discontinuity
 if state.world and state.world~=o.world then kind='world'
 elseif state.player and state.player~=o.player then kind='player'
 elseif o.reset then kind='time reset'
 elseif state.point and moved>=3000 then kind='fast travel'
 elseif state.point and (o.speed or 0)>=1200 and moved>=200 then kind='rapid travel'end
 discontinuity=kind~=nil and kind~='rapid travel'
 local active=state.untilAt and o.now<=state.untilAt
 if kind then
  if discontinuity or not active then state.epoch=(state.epoch or 0)+1 end
  state.kind=kind;state.untilAt=o.now+5000
 end
 state.world=o.world;state.player=o.player;state.point={X=o.point.X,Y=o.point.Y,Z=o.point.Z};state.at=o.now
 if state.untilAt and o.now<=state.untilAt then return state.kind,state.epoch,discontinuity end
 state.kind=nil;state.untilAt=nil
 return nil,state.epoch or 0,false
end
-- Repositioning is not evidence that the player chose to flee a fight. Keep an
-- already-latched regroup request, but discard new departure samples.
function M.repositioning(m,active)
 if not active then return false end
 m.departure=nil;m.separatedAt=nil;m.sprintDeparture=nil
 return true
end
-- Reattachment is provisional until the same pawn survives a full observation
-- interval. Brief native respawn/unload churn must not repeatedly run attach.
function M.reconnectCandidate(m,key,now)
 if key~=m.candidateKey then m.candidateKey=key;m.candidateAt=key and now or nil;return false end
 return key~=nil and now-(m.candidateAt or now)>=1000
end
function M.followOffset(slot,pitch,count,narrow)
 if count==1 then return math.max(145,(pitch or 190)-45),0 end
 if narrow and count and count>1 then
  -- A compact depth-biased group, not a fixed two-column queue. Growing the
  -- width with sqrt(party size) keeps large parties from trailing indefinitely.
  local columns=math.max(2,math.ceil(math.sqrt(count/1.5)))
  local index=math.max(0,(slot or 1)-1);local row=math.floor(index/columns)
  local column=index%columns;local inRow=math.min(columns,count-row*columns)
  local clearance=math.max(145,(pitch or 180)-25)
  local back=math.max(145,clearance,(columns-1)*clearance*.6)+row*clearance*1.1+(column%2)*clearance*.25
  return back,(column-(inRow-1)/2)*clearance
 end
 if count and count>=2 and count<=5 and slot and slot<=count then
  -- One compact rear fan for a small group, including the fifth companion.
  -- Keep chord clearance tied to capsule size, not just a fixed radius.
  local step=(count==2 and 90 or count==3 and 150 or 170)/(count-1)
  local angles={};if count%2==1 then angles[1]=0 end
  for i=1,math.floor(count/2)do local a=(i-(count%2==0 and .5 or 0))*step;angles[#angles+1]=-a;angles[#angles+1]=a end
  local radius=math.max(130,(pitch or 150)/(2*math.sin(math.rad(step/2)))+8)
  local angle=math.rad(angles[slot]);return math.cos(angle)*radius,math.sin(angle)*radius
 end
 -- Arrival seats need less clearance than spawning a new actor. Keep the
 -- same stable 4/7/10-seat arcs, but bring them inward and spread them wider.
 -- Derive clearance from body size; large creatures still need more space.
 local clearance=math.max(155,(pitch or 180)-25)
 local index=math.max(0,(slot or 1)-1);local ring=0
 while index>=4+ring*3 do index=index-(4+ring*3);ring=ring+1 end
 local capacity=4+ring*3;local angles={};local step=170/(capacity-1)
 if capacity%2==1 then angles[1]=0 end
 for i=1,math.floor(capacity/2)do
  local a=(i-(capacity%2==0 and .5 or 0))*step
  angles[#angles+1]=-a;angles[#angles+1]=a
 end
 local inner=math.max(165,clearance/(2*math.sin(math.rad(170/6)))+8)
 local radius=math.max(inner+ring*(clearance+10),clearance/(2*math.sin(math.rad(step/2)))+8)
 local angle=math.rad(angles[index+1])
 return math.cos(angle)*radius,math.sin(angle)*radius
end
function M.followPoint(player,yaw,slot,pitch,count,distanceScale,narrow)
 local back,side=M.followOffset(slot,pitch,count,narrow);back=back*(distanceScale or 1);local angle=math.rad(yaw)
 return {X=player.X-math.cos(angle)*back-math.sin(angle)*side,Y=player.Y-math.sin(angle)*back+math.cos(angle)*side,Z=player.Z},math.sqrt(back*back+side*side)
end
-- A blocked lane yields to the native direct route, with a quiet interval.
-- Judge actual pawn progress; a stationary player does not mean a stuck NPC.
function M.formationBlocked(m,o)
 if not o.active or o.gap<=(o.spacing or 180)+150 then m.laneSample=nil;return false end
 if o.now<(m.laneRetryAt or 0)then return true end
 local s=m.laneSample
 if not s then m.laneSample={at=o.now,x=o.x,y=o.y};return false end
 if o.now-s.at<3500 then return false end
 m.laneSample={at=o.now,x=o.x,y=o.y}
 if (o.x-s.x)^2+(o.y-s.y)^2<100^2 then
  m.laneRetryAt=o.now+12000;m.laneSample=nil;return true
 end
 return false
end
function M.retryDelay(failures)
 return math.min(30000,2000*2^math.min(4,math.max(0,failures or 0)))
end
-- Also detect a stale Moving request by actual pawn displacement. Never cancel
-- waiting/paused requests: they can belong to a native task still initializing.
-- Require
-- measured stagnation outside the stopping distance; attempts have a cooldown
-- and a two-attempt budget until either pawn or player has made real progress.
function M.wakeFollow(m,o)
 if not o.allowed or (o.pathStatus~=0 and o.pathStatus~=3)or o.gap<=o.spacing+250 then
  m.wakeSample=nil;return false
 end
 local s=m.wakeSample
 if not s then m.wakeSample={at=o.now,x=o.x,y=o.y,px=o.px,py=o.py};return false end
 if (o.x-s.x)^2+(o.y-s.y)^2>100^2 then
  m.wakeAttempts=0;m.wakeSample={at=o.now,x=o.x,y=o.y,px=o.px,py=o.py};return false
 end
 if (o.px-s.px)^2+(o.py-s.py)^2>300^2 then m.wakeAttempts=0;s.px=o.px;s.py=o.py end
 if o.now-s.at<(o.pathStatus==3 and 3500 or 1500)or o.now-(m.wakeAt or -math.huge)<8000 or o.now-(o.partyLast or -math.huge)<250 or (m.wakeAttempts or 0)>=2 then return false end
 m.wakeAttempts=(m.wakeAttempts or 0)+1;m.wakeAt=o.now
 return true
end
function M.clearPoint(point,occupied,clearance)
 for _,other in ipairs(occupied)do
  if math.abs(point.Z-other.Z)<250 and (point.X-other.X)^2+(point.Y-other.Y)^2<(clearance or 210)^2 then return false end
 end
 return true
end
function M.behindCamera(point,camera,yaw)
 local angle=math.rad(yaw);local dx,dy=point.X-camera.X,point.Y-camera.Y
 return dx*math.cos(angle)+dy*math.sin(angle)<-120
end
function M.catchupPoint(player,yaw,slot,occupied,project,camera,pitch)
 local angle=math.rad(yaw)
 local cameraBack=camera and (player.X-camera.X)*math.cos(angle)+(player.Y-camera.Y)*math.sin(angle)or 0
 local extra=math.max(240,cameraBack+260)
 for i=0,5 do
  local wanted=M.followPoint(player,yaw,slot+i,pitch)
  wanted.X=wanted.X-math.cos(angle)*extra;wanted.Y=wanted.Y-math.sin(angle)*extra
  local point=project(wanted)
  if point and math.abs(point.Z-player.Z)<=250 and (point.X-player.X)^2+(point.Y-player.Y)^2>=220^2 and M.clearPoint(point,occupied,pitch or 190)and (not camera or M.behindCamera(point,camera,yaw))then return point end
 end
 return nil
end
function M.facing(from,to)
 return math.deg(math.atan(to.Y-from.Y,to.X-from.X))
end
-- Reservations include not-yet-attached summons as well as live companions.
-- Test the projected result: separate input points can collapse onto one small
-- nav island. This bounded search runs only on summon requests, not party ticks.
function M.summonArc(slot,pitch)
 pitch=pitch or 190
 local index=math.max(0,(slot or 1)-1);local ring=0
 -- Four inner seats keep spawn distance short even with wider body spacing.
 -- Outer arcs gain seats (4 + 7 + 10) instead of growing a long queue.
 while index>=4+ring*3 do index=index-(4+ring*3);ring=ring+1 end
 local capacity=4+ring*3;local angles={};local step=156/(capacity-1)
 if capacity%2==1 then angles[1]=0 end
 for i=1,math.floor(capacity/2)do
  local angle=(i-(capacity%2==0 and 0.5 or 0))*step
  angles[#angles+1]=-angle;angles[#angles+1]=angle
 end
 -- Chord distance, not arc length, sets the space between neighbors.
 -- This matters when parties grow beyond the first three arcs.
 local radius=math.max(math.max(220,pitch*1.3)+ring*(pitch+10),pitch/(2*math.sin(math.rad(step/2)))+2)
 return radius,angles,index
end
function M.summonPoint(player,yaw,slot,occupied,project,pitch)
 pitch=pitch or 190
 local radiusBase,angles,index=M.summonArc(slot,pitch)
 local forward=math.rad(yaw)
 for _,radius in ipairs({radiusBase,radiusBase+pitch,radiusBase+pitch*2})do
  for attempt=0,#angles-1 do
   local angle=math.rad(yaw+angles[(index+attempt)%#angles+1])
   local point=project({X=player.X+math.cos(angle)*radius,Y=player.Y+math.sin(angle)*radius,Z=player.Z})
   if point then
    local dx,dy=point.X-player.X,point.Y-player.Y;local gap=dx*dx+dy*dy
    local clear=gap>=math.max(200,pitch*0.5+55)^2 and gap<=(radiusBase+pitch*2+100)^2 and math.abs(point.Z-player.Z)<=250
     and dx*math.cos(forward)+dy*math.sin(forward)>=50
    for _,other in ipairs(occupied)do
     dx,dy=point.X-other.X,point.Y-other.Y
     if math.abs(point.Z-other.Z)<250 and dx*dx+dy*dy<pitch^2 then clear=false;break end
    end
    if clear then return point,M.facing(point,player)end
   end
  end
 end
 return nil
end
-- Per-tick spatial buckets compare only neighboring cells. Locked members
-- (talking, fighting, waiting) have right of way, then stable summon ordinal.
-- Only the yielding member moves; both never try to exchange the same space.
function M.separation(positions)
 local ordered,cell={},160
 for _,p in ipairs(positions)do ordered[#ordered+1]=p;cell=math.max(cell,math.max(170,(p.radius or 55)*2+60))end
 table.sort(ordered,function(a,b)
  if (a.locked==true)~=(b.locked==true)then return a.locked==true end
  return a.ordinal<b.ordinal
 end)
 local buckets,yielding={},{}
 for _,p in ipairs(ordered)do
  local x,y=math.floor(p.X/cell),math.floor(p.Y/cell)
  for dx=-1,1 do for dy=-1,1 do
   for _,q in ipairs(buckets[(x+dx)..':'..(y+dy)]or {})do
    local clearance=math.max(170,(p.radius or 55)+(q.radius or 55)+60)
    if not p.locked and math.abs(p.Z-q.Z)<200 and (p.X-q.X)^2+(p.Y-q.Y)^2<clearance^2 then yielding[p.id]=true end
   end
  end end
  local key=x..':'..y;buckets[key]=buckets[key]or {};table.insert(buckets[key],p)
 end
 return yielding
end
-- This gate is used only after native combat, action and conversation guards.
-- Settled paths use four requests/second; large moving parties use at most
-- twelve. Exhausted attempts get one spaced retry, not permanent abandonment.
function M.travelRequest(m,o)
 if not o.allowed then m.overlapSince=nil;return nil end
 if o.overlap then m.overlapSince=m.overlapSince or o.now else m.overlapSince=nil end
 if o.budget then if o.budget.remaining<=0 then return nil end
 elseif o.now-(o.partyLast or -math.huge)<250 then return nil end
 if o.now<(m.travelRetryAt or 0)or o.now-(m.travelRequestAt or -math.huge)<(o.moving and 750 or 1500)then return nil end
 if o.pathStatus~=0 and o.pathStatus~=3 then return nil end
 local progress=m.travelProgress
 if not progress or (o.x-progress.x)^2+(o.y-progress.y)^2>=100^2 or (o.px-progress.px)^2+(o.py-progress.py)^2>=300^2 then
  progress={x=o.x,y=o.y,px=o.px,py=o.py,tries=0};m.travelProgress=progress
 end
 local stuck=M.wakeFollow(m,o)
 -- Give a new crowding episode its own bounded correction budget. Ordinary
 -- arrival/path requests must not consume all chances to separate neighbors.
 if not o.overlap then progress.separationTries=0 end
 local separating=m.overlapSince and o.now-m.overlapSince>=500
 local exhausted=separating and (progress.separationTries or 0)>=3 or not separating and progress.tries>=3
 if exhausted and o.now<(progress.retryAt or (m.travelRequestAt or o.now)+8000)then return nil end
 local reason
 if separating then reason='Give companion space'
 elseif stuck then reason='Stagnant follow path'
 elseif o.correct then reason='Settle after travel'
 elseif o.moving and o.laneDistance>140 and (not m.travelGoal or (o.goal.X-m.travelGoal.X)^2+(o.goal.Y-m.travelGoal.Y)^2>=200^2)then reason='Travel beside party'
 end
 if reason then
  m.travelRequestAt=o.now
  if o.budget then o.budget.remaining=o.budget.remaining-1 end
  progress.retryAt=o.now+8000
  if separating then progress.separationTries=(progress.separationTries or 0)+1
  else progress.tries=progress.tries+1 end
 end
 return reason
end
-- Nav projection can merge different slots. Reserve the actual result, with
-- limited nearby alternatives; failed paths back off instead of teleporting.
function M.travelDestination(wanted,player,occupied,project,pitch,yaw,strict)
 pitch=pitch or 190;local angle=math.rad(yaw or 0)
 local navigable=false
 for _,offset in ipairs(strict and {{0,0}}or {{0,0},{0,-1},{0,1},{1,0},{1,-1},{1,1}})do
  local b,s=offset[1]*pitch,offset[2]*pitch
  local p=project({X=wanted.X-math.cos(angle)*b-math.sin(angle)*s,Y=wanted.Y-math.sin(angle)*b+math.cos(angle)*s,Z=wanted.Z})
  local expectedX=wanted.X-math.cos(angle)*b-math.sin(angle)*s
  local expectedY=wanted.Y-math.sin(angle)*b+math.cos(angle)*s
  if p and math.abs(p.Z-player.Z)<250 and (p.X-expectedX)^2+(p.Y-expectedY)^2<=(pitch*0.6)^2 then
   navigable=true
   if (p.X-player.X)^2+(p.Y-player.Y)^2>=math.max(130,pitch*0.5+55)^2 and M.clearPoint(p,occupied,pitch)then return p end
  end
 end
 return nil,navigable and 'occupied'or 'navigation'
end
function M.corridorPoint(player,yaw,slot,pitch)
 pitch=pitch or 190;local i=math.max(0,(slot or 1)-1);local angle=math.rad(yaw)
 local back=math.max(160,pitch)+math.floor(i/2)*pitch;local side=(i%2==0 and -0.55 or 0.55)*pitch
 return {X=player.X-math.cos(angle)*back-math.sin(angle)*side,Y=player.Y-math.sin(angle)*back+math.cos(angle)*side,Z=player.Z}
end
function M.catchup(o)
 return o.follow and not o.dead and not o.combat and not o.busy and o.grounded
  and not o.visible and o.gap>=(o.minimum or 2000) and (o.reposition or o.now-(o.last or -math.huge)>=(o.cooldown or 8000))
   and o.now-(o.partyLast or -math.huge)>=(o.partyInterval or 1500) and o.now-(o.attempted or -math.huge)>=M.retryDelay(o.failures)
end
-- A missing pawn gets time to stream back through its original rooted owner.
-- Only an explicit travel epoch can replace a vanished owner, and only once.
function M.replaceMissing(o)
 return o.travelEpoch and o.travelEpoch>0 and o.replacedEpoch~=o.travelEpoch
  and o.follow and not o.dead and (not o.owner and o.now-o.since>=12000 or o.owner and o.anchorMoved and o.now-o.since>=30000)
end
function M.missing(o)
 if o.dead then return 'defeated'end
 if o.ready then return 'reattach'end
 return o.now-o.since<10000 and 'waiting'or 'unloaded'
end
return M
