-- Lease only the native details panel's roadshrine gate. Native purchase costs,
-- prerequisites, quest locks and confirmations still decide whether buying works.
local AI=require('ai_state');local M={};local leases={};local nextCheck=0
local classPath='/Game/_Dawnwalker/UI/_Unified/GameHub/CharacterDevelopment/Details/WBP_Hub_CharacterDevelopment_Details.WBP_Hub_CharacterDevelopment_Details_C'
local function ready(pc)
 local asc=AI.playerAbilitySystem(pc);if not asc then return false end
 local dev=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary'):GetGameInstanceSubsystem(pc,AI.find('/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem'))
 return AI.developmentBound(dev,asc)
end
function M.cleanup()
 local pc=require('UEHelpers').GetPlayerController()
 local live=ready(pc)
 for _,v in pairs(leases)do if live and AI.sameInstance(v.pawn,pc.Pawn)and AI.sameInstance(v.world,pc.Pawn:GetWorld())and AI.valid(v.widget)and v.widget:GetFullName()==v.name and v.widget['Skills Purchasable']==true then v.widget['Set Skills Purchasable'](v.widget,v.original)end end
 leases={};nextCheck=0
end
function M.tick(pc,enabled)
 if not enabled then if next(leases)then M.cleanup()end;return end
 if os.time()<nextCheck then return end;nextCheck=os.time()+1
 if not ready(pc)then leases={};return end
 -- No widget discovery while exploring. The native Skills page pauses the game.
 if not AI.find('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc)then if next(leases)then M.cleanup()end;return end
 local class=AI.find(classPath);if not AI.valid(class)then return end
 local widgets={};AI.find('/Script/UMG.Default__WidgetBlueprintLibrary'):GetAllWidgetsOfClass(pc,widgets,class,false)
 for _,widget in ipairs(widgets)do
  if AI.valid(widget)and AI.sameInstance(widget:GetOwningPlayerPawn(),pc.Pawn)and widget:IsVisible()and not widget.bIsFromNotification then
   local name=widget:GetFullName();local entry=leases[name]
   if entry and(not AI.sameInstance(entry.pawn,pc.Pawn)or not AI.sameInstance(entry.world,pc.Pawn:GetWorld()))then entry=nil end
   if not entry then entry={widget=widget,name=name,pawn=pc.Pawn,world=pc.Pawn:GetWorld(),original=widget['Skills Purchasable']};leases[name]=entry end
   if widget['Skills Purchasable']~=true then widget['Set Skills Purchasable'](widget,true)end
  end
 end
end
return M
