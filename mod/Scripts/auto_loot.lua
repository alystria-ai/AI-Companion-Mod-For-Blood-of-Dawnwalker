local AI=require('ai_state');local Native=require('companion_native');local M={}
local nextQuery=0;local quietSince;local pawn;local queue={};local cooldown={};local cache={};local clock
local function valid(o)return AI.valid(o)end
local function path(o)return o:GetFullName():match('^%S+ (.+)$')end
function M.reset()nextQuery=0;quietSince=nil;pawn=nil;queue={};cooldown={};cache={};clock=nil end
local function allowed(c)
 return valid(c)and c:IsInteractionEnabled()and c:GetInteractionState()==4
  and c:GetInteractionRiskType()==0 and c:GetDefaultRiskType()==0
  and c.DisplayedTimeSegmentCost==0
end
local function visiblePickup(pc,actor,component,playerLocation)
 -- Small harvestables can have their actor pivot embedded inside a rock or log.
 -- Trace to the native interaction prompt, not an arbitrary raised position.
 -- Retain the same reach limit and reject any intervening visibility blocker.
 local target=component:GetPromptLocation();local p=playerLocation
 if (p.X-target.X)^2+(p.Y-target.Y)^2+(p.Z-target.Z)^2>350*350 then return false end
 local hit={};local color={R=0,G=0,B=0,A=0}
 return not AI.find('/Script/Engine.Default__KismetSystemLibrary'):LineTraceSingle(pc,{X=p.X,Y=p.Y,Z=p.Z+40},target,0,false,{pc.Pawn,actor},0,hit,true,color,color,0)
end
local function collect(pc,actor,isCompanion)
 if not valid(actor)or actor:IsActorBeingDestroyed()or not AI.sameInstance(actor:GetWorld(),pc.Pawn:GetWorld())or isCompanion(actor)then return end
 local p=pc.Pawn:K2_GetActorLocation();local a=actor:K2_GetActorLocation()
 if (p.X-a.X)^2+(p.Y-a.Y)^2+(p.Z-a.Z)^2>350*350 then return end
 local sight=pc:LineOfSightTo(actor,{X=p.X,Y=p.Y,Z=p.Z+40},false)
 local container=actor:IsA(AI.find('/Script/DogwoodWorld.LootContainerBase'))
 local character=actor:IsA(AI.find('/Script/Dawnwalker.DawnwalkerCharacterBase'))
 if character and actor:IsAlive()then return end
 if container and (actor.bLocked or actor.bIsStealable)then return end
 local components=actor:K2_GetComponentsByClass(AI.find('/Script/DogwoodWorld.InteractableComponent'))
 for i=1,#components do
  local c=components[i]
  if allowed(c)then
   local harvestable=c:IsA(AI.find('/Script/DogwoodWorld.HarvestableComponent'))
   local lootable=c:IsA(AI.find('/Script/DogwoodWorld.LootableComponent'))
   if sight or (harvestable or lootable)and visiblePickup(pc,actor,c,p)then
    if harvestable then
     -- Herbs use their own pickup class. Native risk and state checks above
     -- still apply; StartInteraction runs the native pickup lifecycle, whereas
     -- firing InteractionTriggered alone does not collect a harvestable.
     c:StartInteraction();return
    elseif lootable then
     if not c.bIsStealable and not c.bAlwaysAtRiskOfPunishment then
      -- Native pickup preserves item rolls, capacity, persistence and regeneration.
      c:StartInteraction();return
     end
    elseif container or character then
     local inventory=container and actor.InventoryComponent or actor:GetInventoryComponent()
     if valid(inventory)and inventory:CanBeLooted()and not inventory:IsEmpty()then
      local subsystem=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary'):GetGameInstanceSubsystem(pc,AI.find('/Script/DogwoodInventory.InventorySubsystem'))
      if not valid(subsystem)then return end
      local target=subsystem:GetPlayerInventoryComponent()
      if valid(target)and AI.sameInstance(target,pc.Pawn:GetInventoryComponent())then subsystem:TransferAllItems(1,inventory,target)end
      return
     end
    end
   end
  end
 end
end
function M.tick(pc,enabled,busy,isCompanion)
 if not enabled then if pawn then M.reset()end;return end
 if not AI.playerReady(pc)then M.reset();return end
 local time=AI.find('/Script/Engine.Default__KismetSystemLibrary'):GetGameTimeInSeconds(pc)
 if not AI.sameInstance(pawn,pc.Pawn)or clock and time<clock then M.reset();pawn=pc.Pawn end
 clock=time
 local board=AI.board(AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(pawn))
 if busy or not board or board.bIsDead or board.Combat.bInCombat or pawn.bCinematicMode or AI.find('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc)then
  quietSince=nil;queue={};return
 end
 quietSince=quietSince or time;if time-quietSince<2 then return end
 if #queue==0 and time>=nextQuery then
  nextQuery=time+2
  local result,why=Native.run('protectlootquery',{path(pawn)});assert(result,why)
  local seen={};for candidate in (result.lootActors or ''):gmatch('"([^"\r\n]+)"')do
   local name=candidate:match("'([^']+)'$")or candidate
   if not seen[name]and(not cooldown[name]or time>=cooldown[name])then queue[#queue+1]=name;seen[name]=true end
   if #queue>=32 then break end
  end
  for key,t in pairs(cooldown)do if time-t>30 then cooldown[key]=nil;cache[key]=nil end end
 end
 -- At most one interaction per party tick, and never retry full bags every frame.
 local name=table.remove(queue,1);if not name then return end;cooldown[name]=time+5
 local actor=cache[name]
 if not valid(actor)or path(actor)~=name then actor=StaticFindObject(name);cache[name]=actor end
 if valid(actor)then collect(pc,actor,isCompanion)end
end
return M
