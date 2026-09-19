-- Per-owned-pawn source attributes. Do not modify player stats or shared effects.
local AI=require('ai_state')
local M={}
local keys={BaseMeleeDamage=true,BaseUnarmedDamage=true,DamageAIvsAI=true}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<100000000 end
local function equal(a,b)return finite(a)and finite(b)and math.abs(a-b)<math.max(.001,math.abs(b)*.00001)end
local function descriptors(asc,fn)
 local all={};asc:GetAllAttributes(all)
 assert(#all<=512,'Unexpected attribute count')
 for i=1,#all do
  local a=all[i]:get();local name=a.AttributeName:ToString()
  if keys[name]then fn(name,a)end
 end
end
function M.apply(stub,board,state,multiplier)
 if not AI.board(stub,board)or board.bIsDead then return false,'AI unavailable'end
 multiplier=tonumber(multiplier)or 1
 if not finite(multiplier)or multiplier<0 or multiplier>5 then return false,'Invalid companion damage multiplier'end
 local asc=stub:GetAbilitySystemComponent()
 if not AI.valid(asc)then return false,'Attributes unavailable'end
 if AI.same(asc,state.asc)and state.complete then
  local currentAttrs=asc:GetAttributeSet(AI.find('/Script/DogwoodStats.CharacterBaseAttributeSet'))
  local retained=AI.valid(currentAttrs)
  if retained then for name,e in pairs(state.entries or {})do
   if not equal(currentAttrs[name].BaseValue,e.owned)or not equal(currentAttrs[name].CurrentValue,e.target)then retained=false;break end
  end end
  if state.multiplier==multiplier and retained then return true,state.note end
  M.restore(stub,board,state)
 end
 -- A replacement ASC owns a fresh baseline; reattaching the same one never stacks.
 if not AI.same(asc,state.asc)then state.asc=asc;state.entries={}end
 local attrs=asc:GetAttributeSet(AI.find('/Script/DogwoodStats.CharacterBaseAttributeSet'))
 if not AI.valid(attrs)then return false,'Character attributes unavailable'end
 local lib=AI.find('/Script/DogwoodCombat.Default__CombatBlueprintFunctionLibrary')
 -- Capture the unboosted physical baseline BEFORE any writes. Native AI-vs-AI
 -- defaults to tiny helper damage (10 on inspected story characters); multiplying
 -- that by five still gives only 50. Give owned clones normal physical strength.
 local melee,unarmed=attrs.BaseMeleeDamage.CurrentValue,attrs.BaseUnarmedDamage.CurrentValue
 if not finite(melee)or not finite(unarmed)then return false,'Physical baseline unavailable'end
 local physical=math.max(0,melee,unarmed)
 local count,notes=0,{}
 local ok,err=pcall(function()
 descriptors(asc,function(name,attribute)
  if not AI.board(stub,board)or not AI.same(stub:GetAbilitySystemComponent(),asc)then error('AI changed during damage setup')end
  local current=attrs[name].BaseValue;local effective=attrs[name].CurrentValue
  assert(finite(current)and finite(effective),'Invalid damage attribute')
  local entry=state.entries[name]
  if not entry then
   local baseline=name=='DamageAIvsAI'and math.max(effective,physical)or effective
   local target=baseline*multiplier
   entry={original=current,effective=effective,baseline=baseline,target=target,owned=current+target-effective};state.entries[name]=entry
  end
  if equal(current,entry.original)then lib:SetAttributeValue(asc,attribute,entry.owned)
  elseif not equal(current,entry.owned)then error('Native base damage changed during setup')end
  local readback=attrs[name].BaseValue;assert(equal(readback,entry.owned),'Native damage setter did not retain value')
  local actual=attrs[name].CurrentValue
  assert(equal(actual,entry.target),'Native effect aggregation changed; damage boost not confirmed')
  count=count+1;notes[#notes+1]=name..'='..tostring(entry.effective)..' -> '..tostring(actual)
 end)
 assert(count==3,'Required companion damage attributes missing')
 end)
 if not ok then
  -- Roll back only writes we still own, including partial failures. A failed
  -- readback must not leave half the damage attributes boosted indefinitely.
  local restored,why=pcall(M.restore,stub,board,state)
  return false,tostring(err)..(restored and ''or ('; restore failed: '..tostring(why)))
 end
 state.complete=true;state.multiplier=multiplier;state.note=tostring(multiplier)..'x owned physical damage; AI-vs-AI uses normal physical baseline; '..table.concat(notes,', ')
 return true,state.note
end
function M.restore(stub,board,state)
 if not state or not AI.board(stub,board)or not AI.same(stub:GetAbilitySystemComponent(),state.asc)then return end
 local asc=state.asc;local attrs=asc:GetAttributeSet(AI.find('/Script/DogwoodStats.CharacterBaseAttributeSet'))
 if not AI.valid(attrs)then return end
 local lib=AI.find('/Script/DogwoodCombat.Default__CombatBlueprintFunctionLibrary')
 descriptors(asc,function(name,attribute)
  local e=state.entries and state.entries[name]
  if e and AI.board(stub,board)and equal(attrs[name].BaseValue,e.owned)then lib:SetAttributeValue(asc,attribute,e.original)end
 end)
 state.complete=nil;state.asc=nil;state.entries=nil
end
return M
