-- Host-side rollback for a vanished mount add-on. The add-on normally restores
-- its own state before withdrawing its lease. This guard acts only while the
-- original player is still attached to the exact leased creature.
local M={}
local function valid(o)return o and o:IsValid()and not o:HasAnyFlags(EObjectFlags.RF_BeginDestroyed|EObjectFlags.RF_FinishDestroyed)end
local function identity(o)return o:GetFullName()..'#'..tostring(o:GetAddress())end
local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
local function v(x,y,z)return {X=x,Y=y,Z=z}end
function M.capture(pc,creature)
 if not valid(pc)or not valid(pc.Pawn)or not valid(creature)then return nil end
 local p=pc.Pawn;local mesh=p.Mesh;local move=p.CharacterMovement
 if not valid(mesh)or not valid(move)or not valid(mesh:GetAnimInstance())then return nil end
 local pos=p:K2_GetActorLocation()
 return {pc=pc,player=p,creature=creature,playerId=identity(p),worldId=identity(p:GetWorld()),creatureId=identity(creature),
  collision=p:GetActorEnableCollision(),movement=move.MovementMode,custom=move.CustomMovementMode,
  ignoreBaseRotation=move.bIgnoreBaseRotation,controllerYaw=p.bUseControllerRotationYaw,
  animMode=mesh:GetAnimationMode(),animClass=mesh:GetAnimInstance():GetClass(),view=pc:GetViewTarget(),
  moveIgnored=pc:IsMoveInputIgnored(),position=v(pos.X,pos.Y,pos.Z)}
end
local function current(s)
 return s and valid(s.pc)and valid(s.pc.Pawn)and valid(s.player)and same(s.pc.Pawn,s.player)
  and identity(s.player)==s.playerId and valid(s.player:GetWorld())and identity(s.player:GetWorld())==s.worldId
  and valid(s.creature)and identity(s.creature)==s.creatureId and valid(s.creature:GetWorld())and identity(s.creature:GetWorld())==s.worldId
end
local function exitPoint(s)
 local actor=s.creature;local a=actor:K2_GetActorLocation();local cap=s.player.CapsuleComponent
 local half,radius=cap:GetScaledCapsuleHalfHeight(),cap:GetScaledCapsuleRadius()
 local creatureCap=actor.CapsuleComponent;local spread=valid(creatureCap)and creatureCap:GetScaledCapsuleRadius()+radius+65 or 200
 local depth=valid(creatureCap)and creatureCap:GetScaledCapsuleHalfHeight()or 200
 local lib=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary');local color={R=0,G=0,B=0,A=0}
 for _,ring in ipairs({1,1.6,2.2})do
 for _,angle in ipairs({0,math.pi/2,math.pi,math.pi*1.5,math.pi/4,-math.pi/4,3*math.pi/4,-3*math.pi/4})do
  local x,y=a.X+math.cos(angle)*spread*ring,a.Y+math.sin(angle)*spread*ring;local hit={}
  if lib:LineTraceSingle(s.pc,v(x,y,a.Z+depth+100),v(x,y,a.Z-depth-400),0,false,{actor,s.player},0,hit,true,color,color,0)and hit.ImpactNormal.Z>=0.72 then
   local p=v(hit.ImpactPoint.X,hit.ImpactPoint.Y,hit.ImpactPoint.Z+half+5);local blocked={}
   if not lib:CapsuleTraceSingle(s.pc,p,v(p.X,p.Y,p.Z+1),radius,half,0,false,{actor,s.player},0,blocked,true,color,color,0)then return p end
  end
 end
 end
 -- Ground mounts start at a verified ordinary walking position in this world.
 -- This is an emergency fallback only if every nearby exit is obstructed.
 return s.position
end
function M.restore(s)
 if not current(s)then return true,'Retired mount session','retired'end
 local now=os.time()
 if s.retryAfter and now<s.retryAfter then return false,s.lastError or 'Rider recovery pending','retry'end
 local parent=s.player:GetAttachParentActor()
 if not s.cleanup and not same(parent,s.creature)then return true,'Add-on already restored the rider','already_restored'end
 if s.cleanup and valid(parent)and not same(parent,s.creature)then return true,'Another attachment now owns the rider','retired'end
 s.cleanup=s.cleanup or{}
 s.retryAfter=now+1
 local failures={};local function attempt(name,fn)
  if s.cleanup[name]then return end
  local ok,err=pcall(fn);if ok then s.cleanup[name]=true else failures[#failures+1]=name..': '..tostring(err)end
 end
 attempt('safe exit',function()s.exitPosition=exitPoint(s)end)
 local dest=s.exitPosition or s.position
 attempt('creature stop',function()s.creature.CharacterMovement:StopMovementImmediately()end)
 attempt('detach',function()s.player:K2_DetachFromActor(1,1,1)end)
 if not s.cleanup.detach then s.lastError=table.concat(failures,'; ');return false,s.lastError,'retry'end
 attempt('position',function()s.player:K2_SetActorLocation(dest,false,{},true)end)
 attempt('collision',function()s.player:SetActorEnableCollision(s.collision)end)
 attempt('movement',function()s.player.CharacterMovement:SetMovementMode(s.movement,s.custom)end)
 attempt('rotation',function()
  if type(s.ignoreBaseRotation)=='boolean'then s.player.CharacterMovement.bIgnoreBaseRotation=s.ignoreBaseRotation end
  if type(s.controllerYaw)=='boolean'then s.player.bUseControllerRotationYaw=s.controllerYaw end
 end)
 attempt('animation class',function()s.player.Mesh:SetAnimInstanceClass(s.animClass)end)
 if s.cleanup['animation class']then
  -- Dawnwalker's UE5.5 reflection requires the force-init boolean explicitly.
  -- The class step already recreated the original instance, so do not force
  -- another initialization, or repeat that class step on a later retry.
  attempt('animation mode',function()s.player.Mesh:SetAnimationMode(s.animMode,false)end)
 end
 -- The rider adds exactly one ignore count only when capture saw no prior
 -- ignore. Ordinary dismount detaches first, so this branch cannot double-pop.
 if not s.moveIgnored then attempt('input',function()s.pc:SetIgnoreMoveInput(false)end)end
 attempt('camera',function()
  local view=s.pc:GetViewTarget()
  if valid(view)and view:IsA('/Script/Engine.CameraActor')and same(view:GetOwner(),s.creature)then
   s.pc:SetViewTargetWithBlend(s.player,0,0,0,false);view:K2_DestroyActor()
  end
 end)
 s.lastError=#failures>0 and table.concat(failures,'; ')or nil
 if not s.lastError then s.retryAfter=nil end
 return #failures==0,s.lastError or 'Abandoned rider restored',#failures==0 and 'restored'or 'retry'
end
return M
