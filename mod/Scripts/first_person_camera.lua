-- Optional local viewpoint. The game's RebelCameraComponent has a mode stack,
-- but this build has no authored first-person mode to push into it. Borrow the
-- controller's view target only during ordinary player-controlled gameplay.
local AI=require('ai_state')
local Settings=require('companion_settings')
local M={}
local lease
local retryAt=0
local menuHeld=false
local menuResumeUntil=0
local root=require('runtime_path');local lastStatus
local function status(message)
 if message==lastStatus then return end;lastStatus=message
 local f=io.open(root..'/camera-status.txt','w');if f then f:write(message..'\n');f:close()end
end

local function same(a,b)return AI.same(a,b)end
local function valid(o)return AI.valid(o)end
local function safe(fn)
 local ok,value=pcall(fn)
 if ok then return value end
end

local function nativeScene(pc,pawn,menuTransition)
 -- A dialogue can still be preparing its camera cut while the pawn remains
 -- the view target. Give it the camera before its first sequence frame.
 if not menuTransition and safe(function()return pc:IsAnyGameInputBlockerActive()end)==true then return 'Native input blocker is active'end
 if safe(function()return pawn.IsCinematicFinisher end)==true then return 'Native finisher is active'end
 local library=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary')
 local class=AI.find('/Script/DialogueSystem.CinematicSubsystem')
 if valid(library)and valid(class)then
  local subsystem=safe(function()return library:GetWorldSubsystem(pc,class)end)
  if valid(subsystem)and valid(safe(function()return subsystem:GetActiveDialogue()end))then return 'Native dialogue is active'end
 end
 return false
end

local function viewPosition(pawn,rotation)
 -- The animated head sways and leans into the torso during walking/running.
 -- Use the capsule-relative native eye height instead, including crouch changes.
 local actor=safe(function()return pawn:K2_GetActorLocation()end)
 if not actor then return end
 local eye=safe(function()return pawn.BaseEyeHeight end)
 if type(eye)~='number'or eye<20 or eye>150 then eye=65 end
 local yaw=math.rad(rotation.Yaw or rotation.yaw or 0)
 local forward=Settings.values.FirstPersonForward or 42
 local height=Settings.values.FirstPersonHeight or 0
 return {X=actor.X+forward*math.cos(yaw),Y=actor.Y+forward*math.sin(yaw),Z=actor.Z+eye+3+height}
end

local function obstructsCamera(component,pawn)
 if same(component,safe(function()return pawn.Mesh end))then return true end
 local name=component:GetFName():ToString():lower()
 return name=='face mesh'or name=='hair mesh'or name=='beard'or name=='eyebrows'or name=='torso mesh'
  or name:find('eappearanceslot::headgear',1,true)~=nil
  or name:find('eappearanceslot::torso',1,true)~=nil
end
local function maskBody(s)
 s.visibility=s.visibility or {};s.visibilityError=nil
 -- Animation/equipment updates can restore visibility between component scans.
 -- Maintain only the small cached set each frame; discover new components at
 -- the slower interval. Setters run only when a flag actually changed.
 for key,item in pairs(s.visibility)do
  local component=item.component
  if not valid(component)or not same(component:GetOwner(),s.pawn)then s.visibility[key]=nil
  else
   local ok,err=pcall(function()
    if not component.bHiddenInGame then component:SetHiddenInGame(true,false)end
    if not component.bOwnerNoSee then component:SetOwnerNoSee(true)end
    if not component.bCastHiddenShadow then component:SetCastHiddenShadow(true)end
   end)
   if not ok then s.visibilityError=type(err)=='string'and err or 'Player visibility update failed'end
  end
 end
 local now=os.clock()
 if s.visibilityAt and now<s.visibilityAt then return end
 s.visibilityAt=now+.5;s.maskCount=0
 local class=AI.find('/Script/Engine.PrimitiveComponent')
 if not valid(class)then error('Player visibility class unavailable')end
 -- Local pawn components only. Do not propagate hiding to attached hands,
 -- weapons or other children. Restore on leaving this camera, including scenes.
 local components=s.pawn:K2_GetComponentsByClass(class)
 for i=1,math.min(#components,128)do
  local component=components[i]
  if valid(component)and same(component:GetOwner(),s.pawn)and obstructsCamera(component,s.pawn)then
   local ok,err=pcall(function()
    local key=component:GetFullName();local item=s.visibility[key]
    if not item or not same(item.component,component)then
     item={component=component,ownerNoSee=component.bOwnerNoSee,hiddenShadow=component.bCastHiddenShadow,hiddenInGame=component.bHiddenInGame}
     s.visibility[key]=item
    end
    if not component.bHiddenInGame then component:SetHiddenInGame(true,false)end
    if not component.bOwnerNoSee then component:SetOwnerNoSee(true)end
    if not component.bCastHiddenShadow then component:SetCastHiddenShadow(true)end
    if component.bHiddenInGame then s.maskCount=s.maskCount+1 end
   end)
   if not ok then s.visibilityError=type(err)=='string'and err or 'Player visibility update failed'end
  end
 end
end
local function restoreBody(s)
 for _,item in pairs(s.visibility or {})do safe(function()
  local component=item.component
  if valid(component)and same(component:GetOwner(),s.pawn)then
   if component.bOwnerNoSee then component:SetOwnerNoSee(item.ownerNoSee)end
   if component.bHiddenInGame then component:SetHiddenInGame(item.hiddenInGame,false)end
   if component.bCastHiddenShadow then component:SetCastHiddenShadow(item.hiddenShadow)end
  end
 end)end
 s.visibility=nil
end
local function releaseTurning(s)
 if valid(s.turnMovement)then
  if s.turnLookHandle then safe(function()s.turnMovement:PopLookAtMode(s.turnLookHandle)end)end
  if s.turnRotationHandle then safe(function()s.turnMovement:PopRotationMode(s.turnRotationHandle)end)end
 end
 s.turnMovement=nil;s.turnLookHandle=nil;s.turnRotationHandle=nil
end
local function syncTurning(s)
 if os.clock()<(s.turnRetryAt or 0)then return end
 local ok,err=pcall(function()
  local movement=s.pawn:GetMovementComponent()
  if not valid(movement)or movement.MovementMode~=1 or s.pc:IsMoveInputIgnored()or s.pc:IsLookInputIgnored()or s.pc:IsAnyGameInputBlockerActive()then
   releaseTurning(s);return
  end
  if same(s.turnMovement,movement)then return end
  releaseTurning(s);s.turnMovement=movement
  -- Low-priority native modes: turn with a large gaze change, allowing small
  -- head turns and higher-priority gameplay rotation rules. No capsule snaps.
  s.turnRotationHandle=movement:PushRotationMode(2,1) -- FaceDirection
  assert(type(s.turnRotationHandle)=='number'and s.turnRotationHandle>=0,'Player facing request declined')
  s.turnLookHandle=movement:PushLookAtMode(4,1) -- KeepInFOV
  assert(type(s.turnLookHandle)=='number'and s.turnLookHandle>=0,'Player turn-in-place request declined')
 end)
 if not ok then
  releaseTurning(s);s.turnRetryAt=os.clock()+5
  if s.turnError~=tostring(err)then
   s.turnError=tostring(err)
   local f=io.open(root..'/camera-turn-status.txt','w');if f then f:write(s.turnError..'\n');f:close()end
  end
 end
end
local function release()
 local s=lease
 lease=nil
 if not s then return end
 releaseTurning(s)
 restoreBody(s)
 -- A cinematic or another game system may have changed the view target.
 -- Restore only our own target, and only to the same live pawn and world.
 safe(function()
  if valid(s.pc)and valid(s.pawn)and valid(s.camera)
   and same(s.pc.Pawn,s.pawn)and same(s.pc:GetViewTarget(),s.camera)
   and same(s.pawn:GetWorld(),s.world)then
   s.pc:SetViewTargetWithBlend(s.pawn,0,0,0,false)
  end
 end)
 safe(function()if valid(s.gaze)then s.gaze:K2_DestroyActor()end end)
 safe(function()if valid(s.camera)then s.camera:K2_DestroyActor()end end)
end
M.release=release
function M.active()return lease~=nil end
local function updateGazePosition(s)
 if not valid(s.gaze)then return end
 local p=s.camera:K2_GetActorLocation();local r=s.pc:GetControlRotation()
 -- UE4SS exposes mixed-case rotator members in this build: Yaw and pitch.
 local yaw,pitch=math.rad(r.Yaw or r.yaw or 0),math.rad(r.Pitch or r.pitch or 0)
 local x,y=Settings.values.GazeHorizontal or 5,Settings.values.GazeVertical or -1
 -- Camera-local right and up, not the companion's left/right or world height.
 s.gaze:K2_SetActorLocation({X=p.X-math.sin(yaw)*x-math.sin(pitch)*math.cos(yaw)*y,
  Y=p.Y+math.cos(yaw)*x-math.sin(pitch)*math.sin(yaw)*y,Z=p.Z+math.cos(pitch)*y},false,{},true)
end
local function updateGaze(s)
 -- Attention is optional. A gaze update must never release the gameplay camera
 -- or its body mask. Keep the last valid target and report only changed errors.
 local ok,err=pcall(updateGazePosition,s)
 if not ok then
  local message=tostring(err)
  if s.gazeError~=message then
   s.gazeError=message
   local f=io.open(root..'/gaze-status.txt','w');if f then f:write('Gaze update unavailable: '..message..'\n');f:close()end
  end
 elseif s.gazeError then
  s.gazeError=nil
  local f=io.open(root..'/gaze-status.txt','w');if f then f:write('Gaze update restored\n');f:close()end
 end
end
function M.gazeTarget(player)
 if lease and same(lease.pawn,player)and valid(lease.camera)and valid(lease.pc)
  and same(lease.pc:GetViewTarget(),lease.camera)then
  if not valid(lease.gaze)then
   local gameplay=AI.find('/Script/Engine.Default__GameplayStatics')
   local class=AI.find('/Script/Engine.CameraActor');local transform=lease.camera:GetTransform()
   local anchor=gameplay:BeginDeferredActorSpawnFromClass(player,class,transform,1,player,0)
   if not valid(anchor)then return lease.camera end
   lease.gaze=anchor
   anchor=gameplay:FinishSpawningActor(anchor,transform,0)
   if not valid(anchor)then return lease.camera end
   lease.gaze=anchor;anchor:SetActorEnableCollision(false);anchor:SetActorHiddenInGame(true);anchor:SetActorTickEnabled(false)
  end
  updateGaze(lease)
  return lease.gaze
 end
end

local function eligible(pc,suspended)
 if not valid(pc)then return nil,nil,nil,nil,'Player controller is unavailable'end
 local pawn=safe(function()return pc.Pawn end)
 if not valid(pawn)then return nil,nil,nil,nil,'Player pawn is unavailable'end
 local class=AI.find('/Script/Dawnwalker.DawnwalkerPlayerCharacter')
 if not valid(class)or not pawn:IsA(class)then return nil,nil,nil,nil,'Pawn is not the player character'end
 local world=safe(function()return pawn:GetWorld()end)
 local manager=safe(function()return pc.PlayerCameraManager end)
 local follow=safe(function()return pawn.FollowCamera end)
 if not valid(world)or not valid(manager)or not valid(follow)then return nil,nil,nil,nil,'World or player camera component is unavailable'end
 local scene=nativeScene(pc,pawn,suspended);if scene then return nil,nil,nil,nil,scene end
 return pawn,world,manager,follow
end

local function update(s)
 local fov=Settings.values.FirstPersonFOV or 90
 if s.fov~=fov then
  local component=s.camera.CameraComponent
  if valid(component)then component:SetFieldOfView(fov);s.fov=fov end
 end
 local rotation=s.pc:GetControlRotation()
 if not rotation then return false end
 local position=viewPosition(s.pawn,rotation)
 if not position then return false end
 maskBody(s)
 syncTurning(s)
 local moved=s.camera:K2_SetActorLocationAndRotation(position,rotation,false,{},true)==true
 if moved then updateGaze(s)end
 return moved
end

local function acquire(pc,pawn,world,manager,follow)
 -- Only take the normal pawn view. Menus, cutscenes, dialogue and native
 -- camera actors retain their own targets.
 local target=pc:GetViewTarget()
 if not same(target,pawn)then return false,'Native view target: '..(valid(target)and target:GetFullName()or 'unavailable')end
 local gameplay=AI.find('/Script/Engine.Default__GameplayStatics')
 local cameraClass=AI.find('/Script/Engine.CameraActor')
 if not valid(gameplay)or not valid(cameraClass)then return false end
 local transform=pawn:GetTransform()
 local camera=gameplay:BeginDeferredActorSpawnFromClass(pawn,cameraClass,transform,1,pawn,0)
 if not valid(camera)then return false end
 camera=gameplay:FinishSpawningActor(camera,transform,0)
 if not valid(camera)then return false end
 local s={pc=pc,pawn=pawn,world=world,manager=manager,follow=follow,camera=camera}
 lease=s
 -- Keep camera ownership local. The temporary component mask is also needed:
 -- the game's view setup does not consistently respect owner-only visibility.
 camera:SetOwner(pawn)
 local component=camera.CameraComponent
 -- The CameraActor default is a constrained 16:9 view. Let the viewport own
 -- the aspect ratio so 16:10 and ultrawide displays do not acquire black bars.
 if valid(component)then component.bConstrainAspectRatio=false end
 if not update(s)then release();return false end
 pc:SetViewTargetWithBlend(camera,0,0,0,false)
 if not same(pc:GetViewTarget(),camera)then release();return false end
 return true
end

function M.tick(pc,enabled,suspended)
 if not enabled then release();retryAt=0;menuHeld=false;menuResumeUntil=0;status('First-person camera Off');return false end
 if suspended then menuHeld=true;menuResumeUntil=0
 elseif menuHeld then menuHeld=false;menuResumeUntil=os.clock()+.5;retryAt=0 end
 local menuTransition=suspended or os.clock()<menuResumeUntil
 local ok,result,reason=pcall(function()
  local pawn,world,manager,follow,why=eligible(pc,menuTransition)
  if not pawn then release();return false,why end
  if lease then
   if not same(lease.pc,pc)or not same(lease.pawn,pawn)or not same(lease.world,world)
    or not same(lease.manager,manager)or not same(lease.follow,follow)then
    release()
   elseif menuTransition and same(pc:GetViewTarget(),pawn)then
    -- Pause-menu resume can reassign the pawn view. Retain our mask and camera
    -- through this known transition, while real dialogue/finisher checks above
    -- still release both immediately.
    if not update(lease)then release();return false end
    pc:SetViewTargetWithBlend(lease.camera,0,0,0,false)
    return true
   elseif not same(pc:GetViewTarget(),lease.camera)then
    -- Native camera cut took ownership. Never wrestle it back this frame.
    release();retryAt=os.time()+2;return false
   else
    if not update(lease)then release();return false end
    return true
   end
  end
  if os.time()<retryAt then return false end
  local acquired,why=acquire(pc,pawn,world,manager,follow)
  if acquired then return true end
  retryAt=os.time()+2
  return false,why or 'Camera actor or view-target assignment was declined'
 end)
 if not ok then release();retryAt=os.time()+2;status('First-person camera unavailable: '..tostring(result));return false end
 if result then status(lease and lease.visibilityError and ('First-person camera active; '..lease.visibilityError)or ('First-person camera active; hidden obstructing components: '..tostring(lease and lease.maskCount or 0)))elseif reason then status(reason)end
 return result
end

return M
