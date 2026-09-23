-- Optional local viewpoint. The game's RebelCameraComponent has a mode stack,
-- but this build has no authored first-person mode to push into it. Borrow the
-- controller's view target only during ordinary player-controlled gameplay.
local AI=require('ai_state')
local M={}
local lease
local retryAt=0
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

local function nativeScene(pc,pawn)
 -- A dialogue can still be preparing its camera cut while the pawn remains
 -- the view target. Give it the camera before its first sequence frame.
 if safe(function()return pc:IsAnyGameInputBlockerActive()end)==true then return 'Native input blocker is active'end
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
 local mesh=safe(function()return pawn.Mesh end)
 local socket=safe(function()return pawn.HeadSocketName end)
 local head
 if valid(mesh)and socket and safe(function()return socket:ToString()end)~='None'
  and safe(function()return mesh:DoesSocketExist(socket)end)then
  head=safe(function()return mesh:GetSocketLocation(socket)end)
 end
 if not head or type(head.X)~='number' or type(head.Y)~='number' or type(head.Z)~='number'then
  local actor=safe(function()return pawn:K2_GetActorLocation()end)
  if not actor then return end
  local eye=safe(function()return pawn.BaseEyeHeight end)
  head={X=actor.X,Y=actor.Y,Z=actor.Z+(type(eye)=='number'and eye or 65)}
 end
 -- A small forward shift keeps the face out of the lens without hiding or
 -- changing the player's mesh, collision, weapons, or animation.
 local yaw=math.rad(rotation.Yaw or rotation.yaw or 0)
 return {X=head.X+24*math.cos(yaw),Y=head.Y+24*math.sin(yaw),Z=head.Z+3}
end

local function release()
 local s=lease
 lease=nil
 if not s then return end
 -- A cinematic or another game system may have changed the view target.
 -- Restore only our own target, and only to the same live pawn and world.
 safe(function()
  if valid(s.pc)and valid(s.pawn)and valid(s.camera)
   and same(s.pc.Pawn,s.pawn)and same(s.pc:GetViewTarget(),s.camera)
   and same(s.pawn:GetWorld(),s.world)then
   s.pc:SetViewTargetWithBlend(s.pawn,0,0,0,false)
  end
 end)
 safe(function()if valid(s.camera)then s.camera:K2_DestroyActor()end end)
end
M.release=release
function M.active()return lease~=nil end

local function eligible(pc,suspended)
 if suspended then return nil,nil,nil,nil,'Mod menu, chat input or scene is active'end
 if not valid(pc)then return nil,nil,nil,nil,'Player controller is unavailable'end
 local pawn=safe(function()return pc.Pawn end)
 if not valid(pawn)then return nil,nil,nil,nil,'Player pawn is unavailable'end
 local class=AI.find('/Script/Dawnwalker.DawnwalkerPlayerCharacter')
 if not valid(class)or not pawn:IsA(class)then return nil,nil,nil,nil,'Pawn is not the player character'end
 local world=safe(function()return pawn:GetWorld()end)
 local manager=safe(function()return pc.PlayerCameraManager end)
 local follow=safe(function()return pawn.FollowCamera end)
 if not valid(world)or not valid(manager)or not valid(follow)then return nil,nil,nil,nil,'World or player camera component is unavailable'end
 local scene=nativeScene(pc,pawn);if scene then return nil,nil,nil,nil,scene end
 return pawn,world,manager,follow
end

local function update(s)
 local rotation=s.pc:GetControlRotation()
 if not rotation then return false end
 local position=viewPosition(s.pawn,rotation)
 if not position then return false end
 return s.camera:K2_SetActorLocationAndRotation(position,rotation,false,{},true)==true
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
 local camera=gameplay:BeginDeferredActorSpawnFromClass(pawn,cameraClass,transform,1,nil,0)
 if not valid(camera)then return false end
 camera=gameplay:FinishSpawningActor(camera,transform,0)
 if not valid(camera)then return false end
 local s={pc=pc,pawn=pawn,world=world,manager=manager,follow=follow,camera=camera}
 lease=s
 local component=camera.CameraComponent
 local fov=manager:GetFOVAngle()
 if valid(component)and type(fov)=='number'and fov>=40 and fov<=130 then component:SetFieldOfView(fov)end
 if not update(s)then release();return false end
 pc:SetViewTargetWithBlend(camera,0,0,0,false)
 if not same(pc:GetViewTarget(),camera)then release();return false end
 return true
end

function M.tick(pc,enabled,suspended)
 if not enabled then release();retryAt=0;status('First-person camera Off');return false end
 local ok,result,reason=pcall(function()
  local pawn,world,manager,follow,why=eligible(pc,suspended)
  if not pawn then release();return false,why end
  if lease then
   if not same(lease.pc,pc)or not same(lease.pawn,pawn)or not same(lease.world,world)
    or not same(lease.manager,manager)or not same(lease.follow,follow)then
    release()
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
 if result then status('First-person camera active')elseif reason then status(reason)end
 return result
end

return M
