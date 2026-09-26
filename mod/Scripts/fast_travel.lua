-- Lease the live map's departure gate and preload custom destinations.
-- The game's loading screen and fast-travel system own presentation and arrival.
local AI=require('ai_state');local M={};local leases={};local tips={};local nextCheck=0
local maps={};local discoveryElapsed=0
local journey;local arrival;local releaseMapUI
local function failure(err)
 local f=io.open(require('runtime_path')..'/fast-travel-status.txt','w');if f then f:write(tostring(err));f:close()end
end
local function caption(v,text)
 if not v or v.retired or not AI.playerReady(v.pc)or not AI.sameInstance(v.pc.Pawn,v.pawn)or not AI.sameInstance(v.pc.Pawn:GetWorld(),v.world)or not AI.valid(v.button)or v.caption==text then return end;v.caption=text
 v.button:SetButtonText(AI.find('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(text))
end
local function disposeJourney(message)
 local s=journey;journey=nil;if not s then return end
 arrival={samples=0}
 failure(message or 'Travel cancelled during cleanup')
 if AI.valid(s.loading)then s.loading:Cancel()end
 if AI.valid(s.world)and AI.valid(s.world.PersistentLevel)and AI.valid(s.anchor)and not s.anchor:IsActorBeingDestroyed()then
  if AI.valid(s.source)then s.source:DisableStreamingSource()end
  s.anchor:K2_DestroyActor()
 end
 if message and s.tip and not s.tip.retired then caption(s.tip,message);s.tip.messageUntil=os.time()+5 end
end
local function location(v)
 return {X=v.X,Y=v.Y,Z=v.Z}
end
local function closeMap(pc)
 local hubs={};AI.find('/Script/UMG.Default__WidgetBlueprintLibrary'):GetAllWidgetsOfClass(pc,hubs,AI.find('/Script/DogwoodUI.DWHUBWidgetBase'),false)
 for _,hub in ipairs(hubs)do if AI.valid(hub)and hub:IsVisible()then hub:RequestCloseHub()end end
end
local function beginJourney(pc,v)
 if journey or not v.point then return end
 local s={pawn=pc.Pawn,world=pc.Pawn:GetWorld(),point=location(v.point),tip=v,started=os.time()};journey=s
 local gameplay=AI.find('/Script/Engine.Default__GameplayStatics')
 s.loading=AI.find('/Script/RebelLoading.Default__AsynAction_RequestLoadingScreen'):RequestLoadingScreen(pc)
 assert(AI.valid(s.loading),'Loading screen could not be requested')
 s.loading:Activate()
 local transform=pc.Pawn:GetTransform();transform.Translation=s.point
 s.anchor=gameplay:BeginDeferredActorSpawnFromClass(pc,AI.find('/Script/Engine.CameraActor'),transform,1,pc.Pawn,0)
 assert(AI.valid(s.anchor),'Destination loader could not be created')
 s.anchor=gameplay:FinishSpawningActor(s.anchor,transform,0)
 s.anchor:SetActorHiddenInGame(true);s.anchor:SetActorEnableCollision(false)
 local identity={Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1}}
 s.source=s.anchor:AddComponentByClass(AI.find('/Script/Engine.WorldPartitionStreamingSourceComponent'),false,identity,false)
 assert(AI.valid(s.source),'Destination streaming is unavailable')
 s.source.TargetState=2;s.source:EnableStreamingSource();caption(v,'Loading destination...')
 failure('Loading destination')
 -- Finish all borrowed map work while its widget tree is still alive. Arrival
 -- must never write captions into the closed map or retain its old buttons.
 s.tip=nil;releaseMapUI()
 -- World Partition cannot finish activation while the native map pauses the
 -- world. Let the hub release its own pause/input lease before waiting.
 closeMap(pc)
end
local function safeLanding(pc,s)
 local pawn=pc.Pawn;local capsule=pawn.CapsuleComponent
 if not AI.valid(capsule)then return end
 local half=capsule:GetScaledCapsuleHalfHeight();local radius=capsule:GetScaledCapsuleRadius()
 local system=AI.find('/Script/Engine.Default__KismetSystemLibrary')
 local color={R=0,G=0,B=0,A=0};local p=s.point
 for _,offset in ipairs({{0,0},{150,0},{-150,0},{0,150},{0,-150},{300,0},{-300,0},{0,300},{0,-300}})do
  local x,y=p.X+offset[1],p.Y+offset[2];local hit={}
  -- UE4SS reports both packed HitResult flags as true for an ordinary blocking
  -- hit. Verify travel along the ray and penetration depth instead; keep the
  -- independent full-capsule clearance sweep below.
  if system:LineTraceSingle(pc,{X=x,Y=y,Z=p.Z+3000},{X=x,Y=y,Z=p.Z-10000},0,false,{pawn,s.anchor},0,hit,true,color,color,0)and hit.Time>0 and hit.Distance>1 and hit.PenetrationDepth<=0 and hit.ImpactNormal.Z>=.7 then
   local dest={X=hit.ImpactPoint.X,Y=hit.ImpactPoint.Y,Z=hit.ImpactPoint.Z+half+8};local clear={}
   if not system:CapsuleTraceSingle(pc,dest,{X=dest.X,Y=dest.Y,Z=dest.Z+1},radius,half,0,false,{pawn,s.anchor},0,clear,true,color,color,0)then return dest end
  end
 end
end
local function advanceJourney(pc)
 local s=journey;if not s then return end
 if not AI.sameInstance(pc.Pawn,s.pawn)or not AI.sameInstance(pc.Pawn:GetWorld(),s.world)then disposeJourney('Player or world changed');return end
 if s.sent then
  local p=pc.Pawn:K2_GetActorLocation();local d=s.destination
  if (p.X-d.X)^2+(p.Y-d.Y)^2<250000 then disposeJourney('Arrived')
  elseif os.time()-s.sent>45 then disposeJourney('Travel did not complete')end
  return
 end
 if os.time()-s.started>45 then disposeJourney('Destination unavailable');return end
 if os.time()-s.started<2 or not s.source:IsStreamingCompleted()then return end
 local dest=safeLanding(pc,s)
 if not dest then disposeJourney('No safe ground nearby');return end
 local subsystem=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary'):GetWorldSubsystem(pc,AI.find('/Script/DogwoodMap.FastTravelSystem'))
 if not AI.valid(subsystem)then disposeJourney('Travel system unavailable');return end
 -- Native travel owns loading, the safety platform and arrival. Never move the pawn directly.
 local result=subsystem:FastTravelToLocation(dest,pc.Pawn:K2_GetActorRotation())
 if result~=2 then disposeJourney('Travel unavailable');return end
 s.destination=dest;s.sent=os.time();caption(s.tip,'Travelling...')
 failure('Native travel accepted')
 closeMap(pc)
end
local function extraButton(pc,v)
 if AI.valid(v.button)then return end
 local lib=AI.find('/Script/UMG.Default__WidgetBlueprintLibrary')
 local class=AI.retainUIClass(AI.find('/Game/_Dawnwalker/UI/_Unified/BaseWidgets/DWW_Button.DWW_Button_C'))
 local b=lib:Create(pc,class,pc);assert(AI.valid(b),'Map travel button unavailable');v.button=b
 -- Reuse the map's own F/controller travel action and key glyph. CommonUI
 -- routes this only while the destination button is visible and enabled.
 b:SetTriggeringInputAction(v.widget.FastTravelButton.TriggeringInputAction)
 b.bHideInputActionWithKeyboard=false;b:SetHideInputAction(false);b:SetShouldSelectUponReceivingFocus(false)
 b:SetIsSelectable(true);b:SetIsToggleable(false);b:SetIsInteractableWhenSelected(true);b:ClearSelection()
 v.widget.InputBox:AddChild(b);caption(v,'Travel here')
end
local function updateDestination(pc,v)
 local lib=AI.find('/Script/DogwoodMap.Default__MappinSystemBlueprintLibrary')
 local system=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary'):GetGameInstanceSubsystem(pc,AI.find('/Script/DogwoodMap.MappinSystemImpl'))
 if not AI.valid(system)then return end
 local id=v.widget['Pin Instance Id'];local key=tostring(id.Value)
 local kind=lib:GetMappinInstanceType(system,id)
 local allowed=id.Value~=0 and kind~=0 and kind~=22 and kind~=24
 if allowed then
  extraButton(pc,v)
  if v.key~=key then
   v.messageUntil=nil;v.button:ClearSelection();v.key=key
  end
  -- Moving a custom marker can retain its ID. Always use its current position.
  v.point=location(lib:GetMappinInstanceLocation(system,id))
  if v.button:GetVisibility()~=0 then v.button:SetVisibility(0)end
  local enabled=not journey
  if v.interactable~=enabled then v.interactable=enabled;v.button:SetIsInteractionEnabled(enabled)end
  -- Custom waypoints normally have no native action, so their action box is collapsed.
  v.inputOverride=true
  if v.widget.InputBox:GetVisibility()~=0 then v.widget.InputBox:SetVisibility(0)end
  if not journey and os.time()>=(v.messageUntil or 0)then
   caption(v,'Travel here')
  end
 elseif AI.valid(v.button)then
  if v.point or v.interactable then v.button:SetVisibility(1);v.button:SetIsInteractionEnabled(false);v.button:ClearSelection()end
  v.point=nil;v.key=nil;v.interactable=false
  if v.inputOverride then v.widget.InputBox:SetVisibility(v.widget['Has Any Input']and 0 or 1);v.inputOverride=nil end
 end
end
local function restore(v)
 if not AI.playerReady(v.pc)or not AI.sameInstance(v.pc.Pawn,v.pawn)or not AI.sameInstance(v.pc.Pawn:GetWorld(),v.world)then return end
 if AI.valid(v.widget)and v.widget:GetFullName()==v.name and v.widget.FastTravelEnabled==true then
  v.widget.FastTravelEnabled=v.original
 end
end
local function restoreTip(v)
 v.retired=true
 if not AI.playerReady(v.pc)or not AI.sameInstance(v.pc.Pawn,v.pawn)or not AI.sameInstance(v.pc.Pawn:GetWorld(),v.world)then return end
 if AI.valid(v.button)then v.button:ClearSelection();v.button:SetIsInteractionEnabled(false);v.button:RemoveFromParent()end
 if AI.valid(v.widget)and v.inputOverride and AI.valid(v.widget.InputBox)then v.widget.InputBox:SetVisibility(v.widget['Has Any Input']and 0 or 1)end
 if AI.valid(v.widget)and v.widget:GetFullName()==v.name and v.widget.IsFastTravelEnabled==true then
  v.widget.IsFastTravelEnabled=v.original
  if v.widget:IsVisible()then v.widget['Setup Fast Travel Button'](v.widget)end
 end
end
releaseMapUI=function()
 for _,v in pairs(tips)do restoreTip(v)end
 for _,v in pairs(leases)do restore(v)end
 leases={};tips={};maps={};nextCheck=0;discoveryElapsed=0
end
function M.cleanup()
 disposeJourney();releaseMapUI()
end
-- Only an open, already discovered map needs the UI cadence. Discovery remains
-- on the normal utility cadence; a new pin uses its existing tooltip immediately.
function M.active()return next(leases)~=nil end
-- Visible scenery is not proof that arrival cleanup has completed. An early
-- menu request stays queued until the same possessed player is stable across
-- normal utility ticks. No global scan or repeated widget construction.
function M.uiReady(pc)
 if journey or arrival then return false end
 return AI.playerReady(pc)~=nil
end
function M.tick(pc,enabled,elapsed)
 if arrival then
  arrival.elapsed=(arrival.elapsed or 0)+(elapsed or 250)
  if arrival.elapsed>=250 then
   arrival.elapsed=0
   local pawn,world=AI.playerReady(pc)
   if not pawn then arrival={samples=0}
   elseif AI.sameInstance(pawn,arrival.pawn)and AI.sameInstance(world,arrival.world)then
    arrival.samples=arrival.samples+1;if arrival.samples>=3 then arrival=nil end
   else arrival={pawn=pawn,world=world,samples=0}end
  end
 end
 if not enabled then if next(leases)or journey then M.cleanup()end;return end
 if not AI.playerReady(pc)then M.cleanup();return end
 local pawn=pc.Pawn
 local board=AI.board(AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(pawn))
 if not board or board.bIsDead or board.Combat.bInCombat or pawn.bCinematicMode then M.cleanup();return end
 if journey and os.time()>=nextCheck then
  nextCheck=os.time()+1
  local ok,err=pcall(advanceJourney,pc);if not ok then disposeJourney('Travel unavailable');failure(err)end
 end
 if not AI.find('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc)then
  if journey then return end
  if next(leases)or journey then M.cleanup()end;return
 end
 local system=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary'):GetWorldSubsystem(pc,AI.find('/Script/DialogueSystem.CinematicSubsystem'))
 if AI.valid(system)and AI.valid(system:GetActiveDialogue())then M.cleanup();return end
 -- Cache map discovery. Pin creation, hovering and F presses then update on the
 -- UI cadence without a widget or actor scan for every frame.
 discoveryElapsed=discoveryElapsed+(elapsed or 250)
 if #maps==0 or discoveryElapsed>=1000 then
  discoveryElapsed=0;maps={}
  AI.find('/Script/UMG.Default__WidgetBlueprintLibrary'):GetAllWidgetsOfClass(pc,maps,AI.find('/Script/DogwoodUI.MapWidget'),false)
 end
 local found={};local foundTips={}
 for _,widget in ipairs(maps)do
  if AI.valid(widget)and AI.sameInstance(widget:GetWorld(),pc.Pawn:GetWorld())and widget:IsVisible()then
   local name=widget:GetFullName();found[name]=true
   local entry=leases[name]
   if entry and(not AI.sameInstance(entry.widget,widget)or not AI.sameInstance(entry.pawn,pc.Pawn)or not AI.sameInstance(entry.world,pc.Pawn:GetWorld()))then restore(entry);entry=nil end
   if not entry then
    AI.retainUIClass(widget:GetClass())
    entry={widget=widget,name=name,pc=pc,pawn=pc.Pawn,world=pc.Pawn:GetWorld(),original=widget.FastTravelEnabled};leases[name]=entry
   end
   if not widget.FastTravelEnabled then
    widget.FastTravelEnabled=true
   end
   -- The normal map independently disables travel on its tooltip. Updating
   -- MapWidget alone never exposes the native button. Its own setup still
   -- checks pin type and unlock state; do not force button visibility.
   local tip=widget.ToolTip
   if AI.valid(tip)and tip:IsVisible()then
    local tipName=tip:GetFullName();foundTips[tipName]=true
    local prior=tips[tipName]
    if prior and(not AI.sameInstance(prior.widget,tip)or not AI.sameInstance(prior.pawn,pc.Pawn)or not AI.sameInstance(prior.world,pc.Pawn:GetWorld()))then restoreTip(prior);prior=nil end
    if not prior then
     AI.retainUIClass(tip:GetClass())
     prior={widget=tip,name=tipName,pc=pc,pawn=pc.Pawn,world=pc.Pawn:GetWorld(),original=tip.IsFastTravelEnabled};tips[tipName]=prior
    end
    if not tip.IsFastTravelEnabled then
     tip.IsFastTravelEnabled=true;tip['Setup Fast Travel Button'](tip)
    end
    updateDestination(pc,prior)
    if AI.valid(prior.button)and prior.button:GetSelected()then
     prior.button:ClearSelection()
     if not journey and prior.point then
      local ok,err=pcall(beginJourney,pc,prior);if not ok then disposeJourney('Destination unavailable');failure(err)end
     end
    end
   end
  end
 end
 for name,v in pairs(leases)do if not found[name]then restore(v);leases[name]=nil end end
 for name,v in pairs(tips)do if not foundTips[name]then restoreTip(v);tips[name]=nil end end
end
return M
