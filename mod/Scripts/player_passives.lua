-- Temporary player trait leases. Skill levels and saved quickslots are never written.
local AI=require('ai_state');local M={};local lease;local nextCheck=0
local function boundToPlayer(dev,asc)
 -- The game-instance subsystem survives a save reload, but its weak PlayerASC
 -- is cleared before the old pawn/ASC objects become invalid. The native setter
 -- dereferences that weak pointer without checking it, even when removing a grant.
 return AI.developmentBound(dev,asc)
end
local function specs(asc)
 local result={}
 local items=asc.ActivatableAbilities.Items
 for i=1,#items do local s=items[i];if AI.valid(s.Ability)then result[s.Ability:GetClass():GetFullName()]=s.Level end end
 return result
end
local function release(entry,dev,asc)
 local t=entry.trait
 if not AI.valid(t)then return end
 t.AlwaysEquippedWithoutSlotCost=entry.original
 -- Only remove the extra grant if it has not since been equipped normally.
 if boundToPlayer(dev,asc)and not dev:IsTraitEquipped(t)then dev:SetCombatFocusAbilityActive(t,false,false)end
end
function M.cleanup()
 if not lease then return end
 local pc=require('UEHelpers').GetPlayerController()
 local current=AI.playerAbilitySystem(pc)
 local old=lease;lease=nil;nextCheck=0
 local dev=AI.sameInstance(current,old.asc)and boundToPlayer(old.dev,current)and old.dev or nil
 for _,entry in pairs(old.traits)do release(entry,dev,old.asc)end
end
function M.tick(pc,enabled)
 if not enabled then M.cleanup();return end
 if os.time()<nextCheck then return end;nextCheck=os.time()+2
 if not AI.playerReady(pc)then M.cleanup();return end
 local lib=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary')
 local dev=lib:GetGameInstanceSubsystem(pc,AI.find('/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem'))
 local asc=AI.playerAbilitySystem(pc)
 if not boundToPlayer(dev,asc)then M.cleanup();nextCheck=os.time()+2;return end
 local time=AI.find('/Script/Engine.Default__KismetSystemLibrary'):GetGameTimeInSeconds(pc)
 if lease and (not AI.sameInstance(lease.asc,asc)or time<lease.time)then M.cleanup()end
 if not lease then
  lease={dev=dev,asc=asc,traits={},candidates={},time=time}
  local traits=dev:GetAllTraits();local base=AI.find('/Script/DogwoodFocus.FocusAbilityBase')
  for i=1,#traits do
   local t=traits[i]
   if AI.valid(t)and not t.AlwaysEquippedWithoutSlotCost and AI.valid(t.CombatFocusAbility)then
    local ability=t.CombatFocusAbility:GetCDO()
    if ability:IsA(base)and ability:IsAbilityPassive()then lease.candidates[#lease.candidates+1]=t end
   end
  end
 end
 lease.time=time
 local granted=specs(asc)
 for _,t in ipairs(lease.candidates)do if AI.valid(t)then
  local key=t:GetFullName();local entry=lease.traits[key]
  local level=dev:GetTraitLevel(t)
  if entry and level<=0 then release(entry,dev,asc);lease.traits[key]=nil
  elseif level>0 and AI.valid(t.CombatFocusAbility)and (entry or not t.AlwaysEquippedWithoutSlotCost)then
    if not entry then entry={trait=t,original=t.AlwaysEquippedWithoutSlotCost};lease.traits[key]=entry end
    t.AlwaysEquippedWithoutSlotCost=true
    local class=t.CombatFocusAbility:GetFullName()
    if granted[class]~=level and boundToPlayer(dev,asc)then dev:SetCombatFocusAbilityActive(t,true,false);granted[class]=level end
  end
 end end
end
return M
