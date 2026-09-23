local AI=require('ai_state');local Settings=require('companion_settings')
local M={}
local function attributes(stub)
 local asc=stub:GetAbilitySystemComponent();assert(AI.valid(asc),'Missing ability system')
 local attrs=asc:GetAttributeSet(AI.find('/Script/DogwoodStats.CharacterBaseAttributeSet'))
 assert(AI.valid(attrs),'Missing base attributes');return asc,attrs
end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<10000 end
local function equal(a,b)return finite(a)and finite(b)and math.abs(a-b)<.001 end
function M.apply(m,playerStub)
 if not AI.board(m.stub,m.board)or m.board.bIsDead then return end
 if m.civilian then m.actor.bCanBeDamaged=false;return end
 local asc,attrs=attributes(m.stub)
 local playerAsc=playerStub:GetAbilitySystemComponent()
 assert(AI.valid(playerAsc)and not AI.same(asc,playerAsc),'Refusing to tune player attributes')
 if not AI.same(m.tuningAsc,asc)then m.tuningBase={};m.tuningOwned={};m.tuningAsc=asc;m.tuningRevision=nil end
 local name='AttackSpeedMultiplierAdditive'
 local current=attrs[name].BaseValue;local effective=attrs[name].CurrentValue
 assert(finite(current)and finite(effective),'Invalid tuning attribute')
 local base=m.tuningBase[name]
 -- Native stat refreshes replace the baseline; never compound our own write.
 if base==nil or m.tuningOwned[name]and not equal(current,m.tuningOwned[name])then base=current;m.tuningBase[name]=base end
 local wanted=base+(Settings.values.AttackFrequency/100-1)
 if m.tuningRevision==Settings.revision and equal(current,wanted)then return end
 local list={};asc:GetAllAttributes(list);assert(#list<=512,'Attribute count changed')
 local lib=AI.find('/Script/DogwoodCombat.Default__CombatBlueprintFunctionLibrary')
 local found=false;local changed=false
 for _,raw in ipairs(list)do
  local a=raw:get()
  if a.AttributeName:ToString()==name then
   assert(AI.board(m.stub,m.board)and AI.same(m.stub:GetAbilitySystemComponent(),asc),'Companion changed during tuning')
   if not equal(current,wanted)then lib:SetAttributeValue(asc,a,wanted);changed=true end
   assert(equal(attrs[name].BaseValue,wanted),'Native tuning setter did not retain frequency')
   m.tuningOwned[name]=wanted;found=true;break
  end
 end
 assert(found,'Companion attack frequency attribute missing')
 m.actor.bCanBeDamaged=not m.civilian
 m.tuningNote=name..'='..tostring(attrs[name].CurrentValue);m.tuningRevision=Settings.revision
 return changed
end

function M.friendly(m,playerStub)
 if not AI.board(m.stub,m.board)or not AI.board(playerStub)then return end
 local subsystem=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary'):GetWorldSubsystem(m.actor,AI.find('/Script/RebelAI.RebelAISubsystem'))
 assert(AI.valid(subsystem),'Missing AI subsystem')
 local factions=subsystem:GetFactionsController();assert(AI.valid(factions),'Missing factions controller')
 factions:SetAttitudeTowardsPlayer(m.stub,1)
 factions:BP_SetAttitude(m.stub,playerStub,1,true)
 factions:BP_SetAttitude(playerStub,m.stub,1,true)
end
-- Only the party manager calls this, for its own spawned actors. Attitude and
-- an already acquired combat target are separate pieces of native AI state.
function M.guardAllegiance(m,playerStub,ownedStubs,now)
 if not AI.board(m.stub,m.board)or not AI.board(playerStub)then return false end
 local function protected(s)
  if not AI.board(s)then return false end
  if AI.same(s,playerStub)then return true end
  local other=ownedStubs[s:GetFullName()]
  return other~=nil and AI.same(other.stub,s)and AI.board(other.stub,other.board)~=nil
 end
 local target,forced=m.board:GetTarget(),m.board:GetForcedTarget()
 local fighting=m.stub:IsInCombat()or m.board.Combat.bInCombat
 local badTarget=fighting and protected(target)
 local badForced=protected(forced)
 local hostile=m.stub:IsHostileTowardsPlayer()or m.stub:GetAttitudeTowards(playerStub)~=1
 if hostile then M.friendly(m,playerStub)end
 -- Repair only the protected pair selected by native AI. Enemy relations and
 -- the original campaign actors never enter this path.
 for _,s in pairs({target,forced})do
  if protected(s)and not AI.same(s,m.stub)then
   if m.stub:GetAttitudeTowards(s)~=1 then m.stub:SetAttitudeTowards(s,1,false)end
   if s:GetAttitudeTowards(m.stub)~=1 then s:SetAttitudeTowards(m.stub,1,false)end
  end
 end
 if badForced then m.board:SetForcedTarget(nil,0.0);m.issuedTarget=nil end
 if badTarget or badForced then
  m.allegianceRepairs=(m.allegianceRepairs or 0)+1
  m.allegianceBlockedUntil=now+1000
  m.combatTarget=nil;m.instigator=nil
 end
 return badTarget or badForced or now<(m.allegianceBlockedUntil or 0)
end
function M.canRespawn(m,now,inCombat,enabled,delay)
 if not enabled or inCombat then m.peaceSince=nil;return false end
 m.peaceSince=m.peaceSince or now
 return now-m.peaceSince>=delay*1000
end
return M
