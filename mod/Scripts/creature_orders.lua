-- Explicit creature orders reuse the native movement-target and combat paths.
-- Only manager-owned creatures reach this module; no world NPC is recruited.
local AI=require('ai_state');local Formation=require('formation_native');local M={}
local function point(actor)local p=actor:K2_GetActorLocation();return {X=p.X,Y=p.Y,Z=p.Z}end
local function distance(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2)end
local function live(m)
 local b=AI.board(m.stub,m.board)
 return b and not b.bIsDead and AI.valid(m.actor)and AI.valid(m.controller)and not m.addonControl and not m.stub:IsInCinematicMode()
end
function M.cancel(m,ctx)
 local s=m.addonOrder;if not s then return end;m.addonOrder=nil
 if not live(m)or not AI.same(m.board,s.board)then return end
 if s.motion then Formation.release(s.motion.formationLease)end
 if s.sensing then AI.retreatSensing(m.stub,m.board,s.sensing,false)end
 if s.oldCanFight~=nil and m.board.bCanFight==false then m.board.bCanFight=s.oldCanFight end
 if s.look then
  if AI.valid(m.actor.CharacterMovement)and s.look>=0 then m.actor.CharacterMovement:PopLookAtMode(s.look)end
  if AI.valid(s.oldFocus)then m.controller:K2_SetFocus(s.oldFocus)else m.controller:K2_ClearFocus()end
 end
end
local function departure(m,ctx)
 local a,p=point(m.actor),point(ctx.player);local dx,dy=a.X-p.X,a.Y-p.Y;local len=math.sqrt(dx*dx+dy*dy)
 if len<30 then local yaw=math.rad(ctx.player:K2_GetActorRotation().Yaw);dx,dy,len=math.cos(yaw),math.sin(yaw),1 end
 dx,dy=dx/len,dy/len
 for _,angle in ipairs({0,math.pi/4,-math.pi/4,math.pi/2,-math.pi/2})do
  local x,y=dx*math.cos(angle)-dy*math.sin(angle),dx*math.sin(angle)+dy*math.cos(angle)
  local projected=ctx.project({X=a.X+x*1500,Y=a.Y+y*1500,Z=a.Z})
  if projected and distance(projected,p)>math.max(600,distance(a,p)+400)then return projected end
 end
end
function M.action(m,op,ctx)
 if not live(m)then return false,'Creature is unavailable or being ridden'end
 if op=='follow'or op=='stop'then M.cancel(m,ctx);return ctx.apply(m,op)end
 if op=='attack'then
  if not m.combatDefinition then return false,'This creature has no native combat abilities'end
  local target,score;local p=point(ctx.player);local a=point(m.actor)
  for _,enemy in ipairs(ctx.enemies or{})do
   if ctx.eligible(enemy,p,30)then
    local d=distance(point(enemy:GetActor()),a);if not score or d<score then target,score=enemy,d end
   end
  end
  if not target then return false,'There is no hostile enemy nearby'end
  M.cancel(m,ctx);ctx.prepare(m);ctx.apply(m,'follow')
  m.returning=nil;m.noEngageUntil=nil;m.combatTarget=target;m.board.bCanFight=true
  m.board:SetForcedTarget(target,4.0);m.issuedTarget=target;m.status='Attacking nearby enemy';return true,m.status
 end
 if op~='come'and op~='leave'and op~='look'then return false,'Unsupported creature order'end
 local goal=op=='leave'and departure(m,ctx)or nil
 if op=='leave'and not goal then return false,'No clear path away was found; the creature remains with you'end
 M.cancel(m,ctx);ctx.prepare(m)
 local s={op=op,started=ctx.now,board=m.board,oldCanFight=m.board.bCanFight,sensing={},goal=goal,previousMode=m.mode}
 s.motion={actor=m.actor,stub=m.stub,board=m.board,controller=m.controller,addonOwner=m.addonOwner,formationLease={}}
 m.addonOrder=s;m.mode='follow';m.lastTick=nil;m.lastFollowTick=nil
 m.status=op=='leave'and'Walking away'or op=='come'and'Coming to you'or'Looking at you';return true,m.status
end
function M.tick(m,now,ctx)
 local s=m.addonOrder;if not s then return false end
 if not live(m)or not AI.same(s.board,m.board)then M.cancel(m,ctx);return false end
 if m.board:HasAnyUnbreakableActiveAction()then m.status='Waiting for the current action to finish';return true end
 m.board.bCanFight=false;AI.retreatSensing(m.stub,m.board,s.sensing,true)
 if not AI.board(m.stub,m.board)then M.cancel(m,ctx);return true end
 local nativeCombat=m.stub:IsInCombat()or m.board.Combat.bInCombat
 local manager=ctx.combatController(m)
 local phase=manager:tick({now=now,allowed=false,nativeCombat=nativeCombat,busy=false,follow=false,encounterActive=false})
 if nativeCombat or phase=='leaving'then m.status='Leaving combat to obey your order';return true end
 if s.op=='look'then
  if not s.look then
   s.oldFocus=m.controller:GetFocusActor();m.controller:K2_SetFocus(ctx.player)
   s.look=m.actor.CharacterMovement:PushLookAtMode(4,50);s.lookAt=now
  end
  if now-(s.lookAt or now)>=6000 then M.cancel(m,ctx);ctx.apply(m,s.previousMode=='stop'and'stop'or'follow');return false end
  return true
 end
 local a,p=point(m.actor),point(ctx.player);local goal=s.goal
 if s.op=='come'then
  local dx,dy=a.X-p.X,a.Y-p.Y;local d=math.max(1,math.sqrt(dx*dx+dy*dy))
  local gap=math.max(180,(m.formationRadius or m.actor.CapsuleComponent:GetScaledCapsuleRadius()*1.6)+100)
  goal=ctx.project({X=p.X+dx/d*gap,Y=p.Y+dy/d*gap,Z=p.Z})
  if not goal then m.status='Waiting for a walkable place beside you';return true end
 end
 local gap=distance(a,goal)
 if gap<=110 then
  local leave=s.op=='leave';M.cancel(m,ctx)
  if leave then m.status='Leaving';ctx.dismiss(m.id)
  else ctx.apply(m,'stop');m.status='Waiting beside you'end
  return true
 end
 if now-s.started>45000 then M.cancel(m,ctx);ctx.apply(m,'stop');m.status='The route was blocked. Ask me to follow or try again.';return true end
 local accepted,reason=Formation.update(s.motion,{point=goal,distance=gap,moving=s.op=='come',smallParty=true,epoch=s.started,mode=m.status},now)
 if not accepted then m.status=reason or'Waiting for a clear path'end
 return true
end
return M
