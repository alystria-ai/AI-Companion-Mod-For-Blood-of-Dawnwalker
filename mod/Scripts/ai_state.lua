-- A stub can remain a valid UObject after its pawn/board is detached. pcall
-- cannot catch an access violation inside a native UFunction. Check the live
-- board, not just a cached UObject, before calling board-dependent functions.
local M={}
local objects={}
-- This UE4SS build has no object hash table: repeated StaticFindObject calls
-- scan the complete object array. Cache classes/default libraries, validate
-- before reuse, and never cache a failed lookup as if it were a live object.
function M.find(path)
 local value=objects[path]
 -- Unloaded asset addresses may be reused for another valid UObject. Check
 -- the exact path before returning a cached class/profile/library reference.
 if not M.valid(value)or value:GetFullName():match('^%S+ (.+)$')~=path then
  objects[path]=nil;value=StaticFindObject(path)
  if not M.valid(value)or value:GetFullName():match('^%S+ (.+)$')~=path then return nil end
  objects[path]=value
 end
 return value
end
function M.clearFindCache()objects={}end
-- UE4SS can cache reflected fields of Blueprint classes after their widgets
-- close. Keep only the static UI classes alive across travel/GC, never widgets,
-- players or worlds. The engine referencer also survives Lua hot reloads.
local uiReferencer
local retainedUI={}
function M.retainUIClass(class)
 assert(M.valid(class)and class:IsA('/Script/CoreUObject.Class'),'Expected a static UI class')
 local name=class:GetFullName()
 if retainedUI[name]==class and M.valid(uiReferencer)then return class end
 if not M.valid(uiReferencer)then
  uiReferencer=StaticFindObject('/Engine/Transient.DawnwalkerCompanions_UIClasses')
  if not M.valid(uiReferencer)then
   local outer=FindObject('Package','/Engine/Transient')
   assert(M.valid(outer),'UI asset package unavailable')
   uiReferencer=StaticConstructObject(M.find('/Script/Engine.ObjectReferencer'),outer,FName('DawnwalkerCompanions_UIClasses'),EObjectFlags.RF_Transient,EInternalObjectFlags.RootSet)
  end
  assert(M.valid(uiReferencer)and uiReferencer:IsA('/Script/Engine.ObjectReferencer')and uiReferencer:HasAnyInternalFlags(EInternalObjectFlags.RootSet),'UI class retention unavailable')
  retainedUI={}
  for i=1,#uiReferencer.ReferencedObjects do
   local existing=uiReferencer.ReferencedObjects[i]
   if M.valid(existing)and existing:IsA('/Script/CoreUObject.Class')then retainedUI[existing:GetFullName()]=existing end
  end
 end
 retainedUI[name]=class
 local list={};for _,value in pairs(retainedUI)do if M.valid(value)then list[#list+1]=value end end
 assert(#list<=32,'UI class retention limit exceeded')
 uiReferencer.ReferencedObjects=nil;uiReferencer.ReferencedObjects=list
 return class
end
function M.valid(o)
 if not o or not o:IsValid()then return false end
 return not o:HasAnyFlags(EObjectFlags.RF_BeginDestroyed|EObjectFlags.RF_FinishDestroyed)
end
function M.same(a,b)
 return M.valid(a)and M.valid(b)and a:GetFullName()==b:GetFullName()
end
function M.sameInstance(a,b)
 return M.same(a,b)and a:GetAddress()==b:GetAddress()
end
-- A valid UObject can outlive possession and its world during save loading.
-- These checks are for infrequent player utilities, not per-frame face work.
function M.playerReady(pc)
 if not M.valid(pc)or pc:IsActorBeingDestroyed()then return end
 local pawn=pc.Pawn
 if not M.valid(pawn)or pawn:IsActorBeingDestroyed()or not M.sameInstance(pawn.Controller,pc)or not M.valid(pawn.RootComponent)then return end
 local world=pawn:GetWorld()
 if not M.valid(world)or not M.valid(world.PersistentLevel)or not M.sameInstance(pc:GetWorld(),world)then return end
 return pawn,world
end
function M.playerAbilitySystem(pc)
 local pawn=M.playerReady(pc);if not pawn then return end
 local asc=M.find('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary'):GetAbilitySystemComponent(pawn)
 if M.valid(asc)and M.sameInstance(asc.AvatarActor,pawn)then return asc end
end
function M.developmentBound(dev,asc)
 if not M.valid(dev)or not M.valid(asc)then return false end
 local ok,current=pcall(function()return dev.PlayerASC:Get()end)
 return ok and M.sameInstance(current,asc)
end
-- These leases belong only to the caller's owned DynamicSpawnPoint. Static
-- SceneRoots reject movement; TeleportTo also does not suit a plain marker.
function M.moveSpawnAnchor(marker,position,lease)
 if not M.valid(marker)or not M.valid(marker.RootComponent)then return false end
 local root=marker.RootComponent
 if lease.root and not M.same(lease.root,root)then return false end
 if not lease.root then
  lease.root=root;lease.mobility=root.Mobility
  root:SetMobility(2) -- Movable, confirmed against the live owned marker.
 end
 if root.Mobility~=2 then return false end
 marker:K2_SetActorLocation(position,false,{},true)
 local p=marker:K2_GetActorLocation()
 return (p.X-position.X)^2+(p.Y-position.Y)^2+(p.Z-position.Z)^2<=4
end
function M.releaseSpawnAnchor(lease)
 if lease and M.valid(lease.root)and lease.root.Mobility==2 then lease.root:SetMobility(lease.mobility)end
 if lease then lease.root=nil;lease.mobility=nil end
end
function M.board(stub,expected)
 if not M.valid(stub)then return nil end
 local board=stub.AIBoard
 if not M.valid(board)or expected and not M.same(board,expected)then return nil end
 if not stub:IsInitializedAndHasPawn()then return nil end
 -- The initialization check is native too; reacquire after it returns.
 if not M.same(stub.AIBoard,board)then return nil end
 return board
end
function M.weaponEquipped(stub,expected)
 local board=M.board(stub,expected)
 if not board then return nil end
 return board.Weapon.TagName:ToString()~='None'
end
-- StowWeapon's bool is always false in this build, even after successful
-- native equipment cleanup. Confirm the physical weapon instead of that bool.
function M.travelWeapon(stub,expected,component,state,now)
 local board=M.board(stub,expected)
 if not board or not M.valid(component)or board.bIsDead or board.Combat.bInCombat or stub:IsInCombat()or stub:IsInCinematicMode()or board.bMainBehaviorSuspended or board:HasAnyUnbreakableActiveAction()then return false,'Native action owns equipment'end
 if state.done then return true,state.note end
 if now<(state.retryAt or 0)or (state.attempts or 0)>=3 then return false,state.note end
 local main=component:GetMainWeapon()
 if not M.valid(main)then state.done=true;state.note='Weapon already stowed';return true,state.note end
 -- Inventory swords only. Claws and other natural weapons keep native handling.
 if not M.valid(component.EquippedWeapon)or not main:IsA(component.EquippedWeapon)then state.done=true;state.note='Native non-inventory weapon';return true,state.note end
 local mesh=main:K2_GetRootComponent();if not M.valid(mesh)then return false,'Weapon root unavailable'end
 local socket=mesh:GetAttachSocketName():ToString()
 if socket~='socket_weapon_r'and socket~='socket_weapon_l'then state.done=true;state.note='Weapon outside hand: '..socket;return true,state.note end
 local old=board.Weapon.TagName:ToString()
 if old~='None'and old~='RebelAI.Weapon.Sword'then return false,'Native AI selected a different weapon'end
 state.attempts=(state.attempts or 0)+1;state.retryAt=now+1500
 -- StopCombatBehaviors clears this before the proxy receives its stow request.
 -- Restore the existing sword's selector; never create a replacement here.
 if old=='None'then board:Temp_BP_SetWeapon({TagName=FName('RebelAI.Weapon.Sword')})end
 if not M.board(stub,expected)then return false,'AI detached'end
 stub:StowWeapon(true)
 if not M.board(stub,expected)then return false,'AI detached'end
 local after=component:GetMainWeapon()
 -- CombatComponent-spawned swords can outlive the equipment proxy's stow.
 -- After allowing the normal request to complete, release those native combat
 -- weapon instances through their owner. The inventory class remains equipped.
 if state.attempts>=2 and not state.cleaned and M.same(after,main)and component.CurrentState==0 and not board.Combat.bInCombat and not stub:IsInCombat()and not stub:IsInCinematicMode()and not board.bMainBehaviorSuspended and not board:HasAnyUnbreakableActiveAction()then
  state.cleaned=true;component:RemoveAllWeapons(true)
  if not M.board(stub,expected)then return false,'AI detached'end
  after=component:GetMainWeapon()
 end
 local sheathed=not M.valid(after)
 if M.valid(after)then
  local r=after:K2_GetRootComponent()
  if M.valid(r)then local attachment=r:GetAttachSocketName():ToString();sheathed=attachment~='socket_weapon_r'and attachment~='socket_weapon_l'end
 end
 -- Don't leave a fabricated selector if a native stow was declined.
 if old=='None'and board.Weapon.TagName:ToString()=='RebelAI.Weapon.Sword'then board:Temp_BP_SetWeapon({TagName=FName('None')})end
 state.done=sheathed;state.note=sheathed and 'Native sword stow confirmed'or 'Waiting for native sword stow'
 return sheathed,state.note
end
-- Only called for manager-owned clones. During combat follower locomotion and
-- temporary-follower identity are released too, selecting native AI-vs-AI damage.
-- Campaign helper damage has a separate balancing calculation that can suppress
-- attacks even when physical attributes are boosted. Do not edit its shared CDO.
function M.ownedDamageBranch(stub,expected)
 if not M.board(stub,expected)then return false end
 local tag={TagName=FName('RebelAI.Flag.DealFollowerDamage')}
 if stub:HasTag(tag)then stub:RemoveTag(tag)end
 return M.board(stub,expected)and stub:HasTag(tag)==false
end
function M.swordCombat(stub,expected,component,setup)
 local function live()return M.board(stub,expected)and M.valid(component)end
 local board=M.board(stub,expected)
 if not board or not M.valid(component)then return false,'AI or combat component detached'end
 if board.bIsDead or stub:IsInCinematicMode()or board.bMainBehaviorSuspended or board:HasAnyUnbreakableActiveAction()then return false,'Native action owns AI'end
 -- Use equipment populated from the NPC definition's inventory. No new item
 -- or shared config is invented. This callback synchronizes an unready clone.
 if not M.valid(component.EquippedWeapon)and not setup.inventorySynced then
  setup.inventorySynced=true;component:OnInventoryContentsChanged()
 end
 if not live()then return false,'AI detached'end
 if not M.valid(component.EquippedWeapon)then return false,'Definition inventory weapon is not equipped'end
 local main=component:GetMainWeapon()
 if not live()then return false,'AI detached'end
 if not M.valid(main)then
  if not component:SpawnEquippedWeapon(true)then return false,'Native equipped weapon spawn declined'end
 end
 if not live()or not M.valid(component:GetMainWeapon())then return false,'Native equipped weapon unavailable'end
 local state={TagName=FName('RebelAI.CharacterState.Combat.Sword')}
 if not stub:BP_CharacterStateExist(state)then return false,'Sword combat state unavailable'end
 if not live()then return false,'AI detached'end
 local selector=board.Weapon.TagName:ToString()
 if selector~='None'and selector~='RebelAI.Weapon.Sword'then return true,'Native AI selected another weapon'end
 local mode={TagName=FName('None')};board:Temp_BP_GetCombatMode(mode)
 if mode.TagName:ToString()=='None'then board:Temp_BP_SetCombatMode({TagName=FName('RebelAI.CombatMode.Sword')})end
 if not live()then return false,'AI detached'end
 if selector=='None'then board:Temp_BP_SetWeapon({TagName=FName('RebelAI.Weapon.Sword')})end
 if not live()then return false,'AI detached'end
 stub:BP_SetCharacterState(state)
 setup.attackSelector='RebelAI.Weapon.Sword'
 return live()and board.Weapon.TagName:ToString()==setup.attackSelector,'Native inventory weapon and sword selector configured'
end
-- Only for an owned Lacra clone whose inspected definition supplies claws but
-- no inventory weapon. Keep weapon creation separate from per-encounter stance.
function M.handCombat(stub,expected,component,setup,clawClass)
 local function live()return M.board(stub,expected)and M.valid(component)end
 local board=M.board(stub,expected)
 if not board or not M.valid(component)then return false,'AI or combat component detached'end
 if board.bIsDead or stub:IsInCinematicMode()or board.bMainBehaviorSuspended or board:HasAnyUnbreakableActiveAction()then return false,'Native action owns AI'end
 local function mode()
  local tag={TagName=FName('None')};board:Temp_BP_GetCombatMode(tag);return tag.TagName:ToString()
 end
 local current=mode()
 if not live()then return false,'AI detached'end
 if not setup.weaponsSpawned and current~='None'and current~='RebelAI.CombatMode.Hand2Hand'and current~='RebelAI.CombatMode.VampireHand2Hand'then return true,'Native equipment already configured'end
 if not M.valid(clawClass)then return false,'Native claw class unavailable'end
 local stateName='RebelAI.CharacterState.Combat.Hand2Hand'
 local state={TagName=FName(stateName)}
 if not stub:BP_CharacterStateExist(state)then return false,'Hand-to-hand state unavailable'end
 if not live()then return false,'AI detached'end
 local weapon=component:GetMainWeapon()
 if not live()then return false,'AI detached'end
 if not M.valid(weapon)and not setup.weaponsSpawned then
  if not component:SpawnHandToHandWeapons()then return false,'Native claw setup declined'end
  setup.weaponsSpawned=true -- A later state failure must not spawn them again.
 end
 if not live()then return false,'AI detached'end
 weapon=component:GetMainWeapon()
 if not live()then return false,'AI detached'end
 if not M.valid(weapon)or not weapon:IsA(clawClass)then return false,'Expected native claws are not active'end
 setup.weaponsSpawned=true
 -- Weapon setup may select a native mode itself. Preserve that selection.
 if mode()=='None'then
  if not live()then return false,'AI detached'end
  board:Temp_BP_SetCombatMode({TagName=FName('RebelAI.CombatMode.Hand2Hand')})
 end
 if not live()then return false,'AI detached'end
 current=mode()
 if current=='None'then return false,'Native combat mode unavailable'end
 if not live()then return false,'AI detached'end
 -- The exported AssetTree_Lacra hooks its attacks beneath the inherited
 -- RebelAI.Action.Attack > RebelAI.Weapon.Fists branch (GUID DD70D012...).
 -- Physical claws and CombatMode alone do not set this action-query selector.
 local selector='RebelAI.Weapon.Fists'
 local previous=board.Weapon.TagName:ToString()
 if previous~='None'and previous~=selector then return false,'Native AI owns another weapon selector'end
 if previous~=selector then board:Temp_BP_SetWeapon({TagName=FName(selector)})end
 if not live()then return false,'AI detached'end
 if board.Weapon.TagName:ToString()~=selector then return false,'Native claw attack selector unavailable'end
 setup.attackSelector=selector
 stub:BP_SetCharacterState(state)
 if not live()then return false,'AI detached'end
 if board.CurrentCharacterState.TagName:ToString()~=stateName then return false,'Native combat state pending'end
 return true,'Native claws configured; selector='..selector..'; mode='..current
end
-- Native movement profiles are shared assets: lease the existing follower
-- profile on this movement component, never edit the asset's speed/priority.
-- Instance-only references. Never edit shared selector assets/CDOs or construct
-- reflected arrays. The donor is the inspected human locomotion parent CDO.
local idleKeys={'IdleAnimSet','FixedDirectionIdleAnimSet','TurnInPlaceBlendSpaceSet'}
function M.releaseIdleSelectors(state)
 if M.valid(state.layer)then
  for _,v in ipairs(state.values or {})do
   if M.same(state.layer[v.key],v.owned)and M.valid(v.old)then state.layer[v.key]=v.old end
  end
 end
 state.layer=nil;state.values=nil
end
function M.leaseIdleSelectors(layer,donor,state)
 if state.layer and not M.same(state.layer,layer)then M.releaseIdleSelectors(state)end
 if not M.valid(layer)or not M.valid(donor)or M.same(layer,donor)then return false end
 if state.layer then return true end -- A later native edit is never overwritten.
 local values={}
 for _,key in ipairs(idleKeys)do
  local old,replacement=layer[key],donor[key]
  if not M.valid(old)or not M.valid(replacement)then return false end
  if not M.same(old,replacement)then values[#values+1]={key=key,old=old,owned=replacement}end
 end
 state.layer=layer;state.values=values
 for _,v in ipairs(values)do layer[v.key]=v.owned end
 return true
end
function M.releaseTravelProfile(state)
 if state.handle~=nil and M.board(state.stub,state.board)and M.valid(state.movement)then state.movement:PopMovementProfile(state.handle)end
 state.handle=nil;state.movement=nil;state.profile=nil;state.stub=nil;state.board=nil
end
function M.combatMovement(stub,expected,state,movement,profile,now)
 local function release(why)M.releaseTravelProfile(state);return false,why end
 local b=M.board(stub,expected)
 if not b or not M.valid(movement)or b.bIsDead or not(stub:IsInCombat()or b.Combat.bInCombat)
  or stub:IsInCinematicMode()or b.bMainBehaviorSuspended or b:HasAnyUnbreakableActiveAction()then return release('Native action / travel owns movement')end
 local pose=b.CurrentCharacterState.TagName:ToString()
 if pose~='None'and pose~='RebelAI.CharacterState.Default'and pose~='RebelAI.CharacterState.Running'then return release('Native combat character state owns movement')end
 local current=movement:GetCurrentMovementProfile()
 if state.handle~=nil then
  if M.same(state.movement,movement)and M.same(current,state.profile)then return true,'Authored Xanthe combat profile in use'end
  -- Push updates the stack; GetCurrentMovementProfile reads a cached pointer
  -- applied by a later locomotion tick. Allow that tick before rejecting it.
  local currentName=M.valid(current)and current:GetFullName()or ''
  local walker=currentName:find('DA_NPC_Walker_MovementProfile.',1,true)or currentName:find('DA_Follower_Walker_MovementProfile.',1,true)
  if M.same(state.movement,movement)and walker and now<(state.pendingUntil or 0)then return true,'Waiting for native movement tick'end
  if walker then state.retryAt=now+3000 end
  return release('Native movement profile changed')
 end
 if not M.valid(current)then return false,'Movement profile unavailable'end
 local name=current:GetFullName()
 if not name:find('DA_NPC_Walker_MovementProfile.',1,true)and not name:find('DA_Follower_Walker_MovementProfile.',1,true)then return false,'Native movement profile preserved'end
 if not M.valid(profile)then return false,'Authored combat profile not loaded'end
 if now<(state.retryAt or 0)then return false,'Waiting before movement repair retry'end
 if profile.MovementConfig.MaxSpeed<=current.MovementConfig.MaxSpeed then return false,'Authored combat profile is not faster'end
 local handle=movement:PushMovementProfile(profile)
 if type(handle)~='number'or handle<0 then state.retryAt=now+3000;return false,'Combat profile request declined'end
 state.handle=handle;state.movement=movement;state.profile=profile;state.stub=stub;state.board=b
 state.pendingUntil=now+750
 state.retryAt=nil
 return true,'Authored combat movement queued'
end
-- Campaign followers are forced Defensive beyond nine metres from Coen by
-- the shared Offensive tree. During combat our party manager owns reunion;
-- release only that temporary-follower identity so native boss combat can run.
function M.releaseCombatFollower(state)
 if not state then return end
 local b=M.board(state.stub,state.board)
 if state.owned and b and b.Follower.bIsTemporaryFollower==false then b.Follower.bIsTemporaryFollower=state.original end
 state.owned=nil;state.original=nil;state.stub=nil;state.board=nil
end
function M.combatFollower(stub,expected,state)
 local b=M.board(stub,expected)
 if not b or b.bIsDead or stub:IsInCinematicMode()or b.bMainBehaviorSuspended then M.releaseCombatFollower(state);return false end
 if state.owned and not M.same(state.board,b)then M.releaseCombatFollower(state)end
 if not state.owned then state.stub=stub;state.board=b;state.original=b.Follower.bIsTemporaryFollower;state.owned=true end
 if b.Follower.bIsTemporaryFollower then b.Follower.bIsTemporaryFollower=false end
 return true
end
function M.ignoreCombatGuardAreas(library,stub,expected)
 if not M.valid(library)or not M.board(stub,expected)then return false end
 library:SetIgnoreGuardAreas(stub,true)
 return M.board(stub,expected)~=nil
end
-- A formation path and the native Follower task cannot own navigation together.
-- Suspend only the main task while our path is active; keep movement physics,
-- animation, sensing and combat arbitration alive. Never adopt an external hold.
function M.ownsFormation(state,stub,expected)
 return state and state.owned and M.same(state.stub,stub)and M.same(state.board,expected)and M.board(stub,expected)~=nil and expected.bMainBehaviorSuspended==true
end
function M.releaseFormation(state)
 if not state or not state.owned then return end
 local b=M.board(state.stub,state.board)
 if b and b.bMainBehaviorSuspended==true then b.bMainBehaviorSuspended=state.previous end
 state.owned=false;state.untilTime=nil
end
function M.acquireFormation(stub,expected,state,controller)
 local b=M.board(stub,expected)
 if not b or b.bIsDead or stub:IsInCombat()or b.Combat.bInCombat or stub:IsInCinematicMode()or b:HasAnyUnbreakableActiveAction()then M.releaseFormation(state);return false end
 if M.ownsFormation(state,stub,expected)then return true end
 M.releaseFormation(state)
 if b.bMainBehaviorSuspended then return false end
 state.stub=stub;state.board=b;state.previous=false;state.owned=true
 local ok=pcall(function()
  b.bMainBehaviorSuspended=true;b:StopAllActions()
  if M.valid(controller)then controller:StopMovement()end
 end)
 if not ok then M.releaseFormation(state);return false end
 return M.ownsFormation(state,stub,expected)==true
end
function M.travelPace(stub,expected,state,movement,profile,speed,formation,targetSpeed,now)
 local b=M.board(stub,expected)
 if not b or b.bIsDead or stub:IsInCombat()or b.Combat.bInCombat or stub:IsInCinematicMode()or b.bMainBehaviorSuspended and not M.ownsFormation(formation,stub,expected)or b:HasAnyUnbreakableActiveAction()then
  M.releaseTravelProfile(state);return false
 end
 -- Check the live value; a cached request is not proof the native task kept it.
 if b.Follower.FollowerSpeed~=speed then b.Follower.FollowerSpeed=speed end
 if not M.valid(movement)or not M.valid(profile)then M.releaseTravelProfile(state);return true end
 -- Match walking as well as fast travel with a private authored profile.
 -- Slower requested gaits must replace our sprint lease too. Shared NPC
 -- assets and combat/attack animation speed are untouched.
 local baseSpeed=profile.MovementConfig.MaxSpeed
 local step=speed==2 and 100 or 25
 if targetSpeed and baseSpeed>0 and math.abs(targetSpeed-baseSpeed)>=step*.5 then
  local desired=math.max(step,math.floor(targetSpeed/step+.5)*step)
  if not M.valid(state.boostProfile)or not M.same(state.boostSource,profile)or not M.same(state.boostOwner,movement)then
   local copy=StaticConstructObject(profile:GetClass(),movement,0,0,0,false,false,profile)
   if M.valid(copy)and not M.same(copy,profile)then
    state.boostProfile=copy;state.boostSource=profile;state.boostOwner=movement
    state.boostSpeed=nil;state.boostAt=nil
   end
  end
  if M.valid(state.boostProfile)and M.same(state.boostSource,profile)and M.same(state.boostOwner,movement)then
   if not state.boostSpeed or math.abs(desired-state.boostSpeed)>=step and (now or 0)-(state.boostAt or 0)>=500 then
    M.releaseTravelProfile(state)
    state.boostProfile.MovementConfig.MaxSpeed=desired
    state.boostProfile.MovementConfig.RootSpeedScale=profile.MovementConfig.RootSpeedScale*desired/baseSpeed
    state.boostSpeed=desired;state.boostAt=now or 0
   end
   profile=state.boostProfile
  end
 end
 if state.handle~=nil and (not M.same(state.movement,movement)or not M.same(state.profile,profile))then M.releaseTravelProfile(state)end
 if state.handle==nil then
  local current=movement:GetCurrentMovementProfile()
  if M.same(current,profile)then return true end
  local h=movement:PushMovementProfile(profile)
  if type(h)=='number'and h>=0 then state.handle=h;state.movement=movement;state.profile=profile;state.stub=stub;state.board=expected end
 end
 return M.board(stub,expected)~=nil
end
-- Only owned spawned companions use this travel suppression. Keep sensing
-- off while intentionally leaving, so HostileDetected does not immediately
-- enqueue another combat reaction after StopCombatBehaviors.
function M.stopDetectionReaction(stub,expected)
 local board=M.board(stub,expected)
 if not board or board:HasAnyUnbreakableActiveAction()or not board:HasReaction()then return end
 local tag=board:GetReactionSituationTag().TagName:ToString()
 if M.board(stub,expected)and (tag=='RebelAI.Situation.HostileDetected'or tag=='RebelAI.Situation.FightIsNearby'or tag=='RebelAI.Situation.Target.Escaped')then board:StopReaction()end
end
function M.retreatSensing(stub,expected,state,enabled)
 if not M.board(stub,expected)then return false end
 if enabled and not state.sensingSuppressed then
  stub:SetPerceptionEnabled(false);state.sensingSuppressed=true
  if not M.board(stub,expected)then return false end
  stub:ResetPerception(true)
 elseif not enabled and state.sensingSuppressed then
  stub:SetPerceptionEnabled(true);state.sensingSuppressed=nil
 end
 if enabled then M.stopDetectionReaction(stub,expected)end
 return M.board(stub,expected)~=nil
end
function M.stopCombatForTravel(lib,stub,expected,follow)
 local board=M.board(stub,expected)
 if not board then return true end
 if board:HasAnyUnbreakableActiveAction()then return false end
 -- The native Idle entry reads the follower flag. Set it BEFORE requesting
 -- that entry; enabling it afterwards can leave the pawn in ordinary Idle.
 board.Follower.bFollowerModeEnabled=follow==true
 M.stopDetectionReaction(stub,expected)
 if not M.board(stub,expected)then return true end
 lib:StopCombatBehaviors(stub,true,false)
 return true -- Request delivered; the manager still checks native exit.
end
function M.startCombat(lib,stub,expected,target)
 local board=M.board(stub,expected)
 if not board or not M.board(target)then return false,'AI detached'end
 if board.bIsDead or stub:IsInCinematicMode()or board.bMainBehaviorSuspended then return false,'Native action owns AI'end
 if stub:IsInCombat()or board.Combat.bInCombat then return true,'Native combat already entering / active'end
 if board:HasAnyUnbreakableActiveAction()then return false,'Native action owns AI'end
 -- StartCombatBehaviors returns false for an already-enabled bCanFight gate
 -- in Dawnwalker patch 2. Lower only this owned clone's gate for the call.
 local previous=board.bCanFight;board.bCanFight=false
 local ok,accepted=pcall(function()return lib:StartCombatBehaviors(stub)end)
 local live=M.board(stub,board)
 if live and (not ok or not accepted)then board.bCanFight=previous end
 if live and (stub:IsInCombat()or board.Combat.bInCombat)then return true,'Native combat acknowledged'end
 if not live then return false,'AI detached during combat entry'end
 if not ok then return false,tostring(accepted)end
 return accepted==true,accepted and 'Accepted'or 'Native target/start gate declined; waiting for eligibility'
end
return M
