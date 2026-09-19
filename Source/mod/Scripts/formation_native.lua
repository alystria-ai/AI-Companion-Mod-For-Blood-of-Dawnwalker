-- Follow distinct invisible actors through Dawnwalker's authored BT branch.
-- AIMoveToActor writes MovementTargetActor/ShouldFollowTarget/ShouldTrackTarget
-- and refreshes the behavior tree. Plain MoveToLocation bypassed this owner.
local AI=require('ai_state')
local M={version=290}
-- The inspected MovementTargetActor BT task stops 100 cm before its target
-- and does not continuously track moving goals. Compensate its stop radius
-- with a marker beyond the seat, and refresh its native intent when it moves.
function M.markerPoint(seat,actor,previous)
 local x,y=seat.X-actor.X,seat.Y-actor.Y;local d=math.sqrt(x*x+y*y)
 if d<45 and previous then return previous end
 if d<1 then return {X=seat.X,Y=seat.Y,Z=seat.Z}end
 return {X=seat.X+x*100/d,Y=seat.Y+y*100/d,Z=seat.Z}
end
local function same(a,b)return AI.same(a,b)end
local function board(s)return s and AI.board(s.stub,s.board)end
function M.owns(s,stub,expected)
 return s and s.owned and same(s.stub,stub)and same(s.board,expected)and board(s)~=nil
end
function M.release(s)
 if not s then return end
 local b=board(s)
 if s.owned and b and AI.valid(s.controller)and AI.valid(s.blackboard)and same(s.controller.Blackboard,s.blackboard)then
  local target=s.blackboard:GetValueAsObject(s.key)
  if same(target,s.marker)then
   s.controller:AIStopFollowing()
   s.blackboard:SetValueAsBool(s.followKey,s.oldFollow)
   s.blackboard:SetValueAsBool(s.trackKey,s.oldTrack)
  end
  if b.Follower.bFollowerModeEnabled==false then b.Follower.bFollowerModeEnabled=s.oldFollower end
 end
 s.owned=false
 if AI.valid(s.marker)then s.marker:K2_DestroyActor()end
 s.marker=nil;s.controller=nil;s.blackboard=nil;s.stub=nil;s.board=nil;s.sample=nil
end
local function ready(m)
 local b=AI.board(m.stub,m.board)
 return b and not b.bIsDead and not m.stub:IsInCombat()and not b.Combat.bInCombat
  and not m.stub:IsInCinematicMode()and not b.bMainBehaviorSuspended and not b:HasAnyUnbreakableActiveAction()
  and AI.valid(m.actor)and AI.valid(m.controller)and AI.valid(m.controller.Blackboard)and AI.valid(m.controller.BrainComponent)
end
function M.update(m,goal,now)
 local s=m.formationLease or {};m.formationLease=s
 if not goal or not ready(m)then M.release(s);return false,'Native action owns movement'end
 if now<(s.retryAt or 0)then return false,'Waiting before native follow retry'end
 if s.owned and (not same(s.stub,m.stub)or not same(s.board,m.board)or not same(s.controller,m.controller)
  or not same(s.blackboard,m.controller.Blackboard)or not AI.valid(s.marker))then M.release(s)end
 local c=m.controller;local bb=c.Blackboard;local key=c.MovementTargetActorBBKey
 local actorPosition=m.actor:K2_GetActorLocation()
 local desired=M.markerPoint(goal.point,actorPosition,s.point)
 local target=bb:GetValueAsObject(key)
 if AI.valid(target)and not same(target,s.marker)then M.release(s);return false,'Another native movement target has priority'end
 if not s.owned then
  local class=AI.find('/Script/Engine.TargetPoint')
  if not AI.valid(class)then s.retryAt=now+5000;return false,'Destination actor class unavailable'end
  local marker=m.actor:GetWorld():SpawnActor(class,desired,{Pitch=0,Yaw=0,Roll=0})
  if not AI.valid(marker)then s.retryAt=now+5000;return false,'Destination actor creation declined'end
  s.marker=marker;s.stub=m.stub;s.board=m.board;s.controller=c;s.blackboard=bb;s.key=key
  s.followKey=c.ShouldFollowTargetBBKey;s.trackKey=c.ShouldTrackTargetBBKey
  s.oldFollow=bb:GetValueAsBool(s.followKey);s.oldTrack=bb:GetValueAsBool(s.trackKey)
  s.oldFollower=m.board.Follower.bFollowerModeEnabled;s.owned=true
  marker:SetActorHiddenInGame(true);marker:SetActorEnableCollision(false);marker:SetLifeSpan(15)
  if not AI.valid(marker.RootComponent)then M.release(s);s.retryAt=now+5000;return false,'Destination has no scene root'end
  marker.RootComponent:SetMobility(2)
  -- Stop the old player-follow action once, then let the authored movement
  -- branch run normally. Main behavior, physics and animations stay enabled.
  m.board.Follower.bFollowerModeEnabled=false;m.board:StopAllActions();c:StopMovement()
  c:AIMoveToActor(marker,true,true,false);s.issuedAt=now;s.refreshAt=now;s.issuedPoint=desired
 end
 if not same(bb:GetValueAsObject(key),s.marker)then
  M.release(s);s.retryAt=now+3000;return false,'Native movement did not retain its target'
 end
 m.board.Follower.bFollowerModeEnabled=false
 local p=desired
 if not s.point or (p.X-s.point.X)^2+(p.Y-s.point.Y)^2>=20^2 or math.abs(p.Z-s.point.Z)>40 then
  if not s.marker:K2_SetActorLocation(p,false,{},true)then M.release(s);s.retryAt=now+3000;return false,'Destination movement declined'end
  s.point={X=p.X,Y=p.Y,Z=p.Z}
 end
 if now-(s.refreshAt or 0)>=1000 then s.marker:SetLifeSpan(15);s.refreshAt=now end
 if goal.moving and s.issuedPoint and now-(s.issuedAt or 0)>=1000
  and (p.X-s.issuedPoint.X)^2+(p.Y-s.issuedPoint.Y)^2>=150^2 then
  c:AIMoveToActor(s.marker,true,true,false);s.issuedAt=now;s.issuedPoint={X=p.X,Y=p.Y,Z=p.Z}
 end
 -- Measure the pawn, not request acceptance. One native rebind after a real
 -- stall is bounded; it never turns into continuous MoveTo replacement.
 local a=actorPosition;local sample=s.sample
 if not sample or (a.X-sample.X)^2+(a.Y-sample.Y)^2>=75^2 or goal.distance<=100 then
  s.sample={X=a.X,Y=a.Y,at=now};s.failures=0
 elseif now-sample.at>=4500 and now-(s.issuedAt or 0)>=6000 then
  s.failures=(s.failures or 0)+1
  if s.failures>=3 then M.release(s);s.retryAt=now+6000;return false,'Native route blocked; follow fallback'end
  c:AIMoveToActor(s.marker,true,true,false);s.issuedAt=now;s.sample={X=a.X,Y=a.Y,at=now}
 end
 return true,goal.mode..'; native destination tracking'
end
return M
