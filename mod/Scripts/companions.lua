-- Owns only pawns returned by our rooted population spawners. Story actors are
-- never recruited, destroyed, or reconfigured by this module.
local Native=require('companion_native')
local Config=require('companion_config')
local Combat=require('companion_combat')
local Engagement=require('engagement')
local AI=require('ai_state')
local Recovery=require('companion_recovery')
local Formation=require('party_formation')
local FormationNative=require('formation_native')
local Damage=require('companion_damage')
local Settings=require('companion_settings')
local Tuning=require('companion_tuning')
local Protection=require('companion_protection')
local nativeCommands={};local nativeSequence=0
local root=require('runtime_path')
local M={};local members={};local byId={};local lastCommand='';local ack={'','',''}
local worldName,playerName=nil,nil;local lastGameTime=nil;local note='F5: select a companion. Unpause to summon.'
local player,playerStub,subsystem,combatLib;local epoch=tostring(os.time()*1000)
local enemyCache,lastEnemyQuery,lastFault={},nil,nil
local threatDistance,threatPoint,threatTarget,playerBattle
local partyEncounterActive=false
local summons={};local spawnOrdinal=0;local updateCursor=0
local populationStartedAt
local ownedStubs={}
local project
local lastPartyCatchup,lastReconnectPoll,lastDiagnosticTick,lastAnchorUpdate,lastFollowWake
local travelState={epoch=0};local travelKind,travelEpoch,travelDiscontinuity=nil,0,false;local pendingWorldParty;local playerEpoch=0
local slowWork={};local slowestTick=0
local function measured(label,fn,...)
 local start=os.clock();local result=table.pack(fn(...));local elapsed=(os.clock()-start)*1000
 if elapsed>=8 then
  slowWork[#slowWork+1]=os.date()..' '..label..' '..string.format('%.1f ms',elapsed)
  if #slowWork>20 then table.remove(slowWork,1)end
 end
 return table.unpack(result,1,result.n)
end
local playerPoint,playerSpeed,playerVelocity,travelHeading,cameraPoint,cameraYaw
local formation=Formation.new();local formationFrame=formation.frame
local partyPositions={}
local partyDeparture=false
local xantheCombatProfile='/Game/_Dawnwalker/Player/MovementProfiles/DA_Xanthe_Combat_MovementProfile.DA_Xanthe_Combat_MovementProfile'
local valid,same=AI.valid,AI.same
local function ready(m)return valid(m.actor)and AI.board(m.stub,m.board)end
local function clean(s)return tostring(s or ''):gsub('[\r\n\t]',' '):sub(1,500)end
local function read(name,max)local f=io.open(root..'/'..name,'rb');if not f then return ''end;local s=f:read(max or 65536)or '';f:close();return s end
local function write(name,s)local f=assert(io.open(root..'/'..name,'wb'));f:write(s);f:close()end
local function log(s)print('[Dawnwalker Companions] '..clean(s)..'\n')end
local function summonStage(m,phase,message)
 if not m.request then return end
 m.loadTrace=m.loadTrace or {}
 m.loadTrace[#m.loadTrace+1]=phase..'\t'..os.time()..'\t'..clean(message)
 pcall(write,'companion-loading-'..m.id..'.txt',m.name..'\n'..table.concat(m.loadTrace,'\n')..'\n')
 for _,s in ipairs(summons)do if s.id==m.request then s.phase=phase;s.message=message or '';return end end
end
local function split(s,separator)local a={};for p in (s..separator):gmatch('(.-)'..separator)do a[#a+1]=p end;return a end
local previous=read('companions-state.tsv'):match('^PARTY\t1\t(%d+)')
if previous then epoch=tostring(math.max(tonumber(epoch),tonumber(previous)+1))end
for _,c in ipairs(Config.characters)do byId[c.id]=c end
local function loc(actor)local p=actor:K2_GetActorLocation();return {X=p.X,Y=p.Y,Z=p.Z}end
local function distance(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)end
local function stub(actor)return AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(actor)end
local function component(actor,path)return actor:GetComponentByClass(AI.find(path))end
local function fraction(value)if type(value)=='number'and value==value and value>=0 and value<=1 then return value end end
local function stats(m)
 if valid(m.healthComponent)then
  m.health=fraction(m.healthComponent:GetHealthPercentage());m.stamina=fraction(m.healthComponent:GetStaminaPercentage())
 end
end
local function ownsFormation(m)return FormationNative.owns(m.formationLease,m.stub,m.board)==true end
local function releaseFormation(m)FormationNative.release(m.formationLease)end
local function releaseFollowPace(m)
 releaseFormation(m)
 if m.paceLease then AI.releaseTravelProfile(m.paceLease)end
 m.followSprinting=nil
 if m.followSpeedOwned~=nil and ready(m)and m.board.Follower.FollowerSpeed==m.followSpeedOwned then
  m.board.Follower.FollowerSpeed=m.followSpeedRestore
 end
 m.followSpeedOwned=nil;m.followSpeedRestore=nil;m.followRunning=nil;m.followPaceSpeed=nil
end
local function releaseTravelIdle(m)
 if m.idleLease then AI.releaseIdleSelectors(m.idleLease)end
 m.idleChecked=nil
end
local function releaseCombatMovement(m)
 if m.combatMovement then AI.releaseTravelProfile(m.combatMovement)end
 AI.releaseCombatFollower(m.combatFollowerLease)
end
local function travelIdle(m)
 if (m.archetype or m.characterId)~='ambrus'then return end
 local now=m.now or 0
 if m.idleChecked and now-m.idleChecked<1000 then return end
 m.idleChecked=now
 local ok,why=pcall(function()
  local mesh=m.actor.Mesh;if not valid(mesh)then return false end
  local anim=mesh:GetAnimInstance();if not valid(anim)then return false end
  local cls=AI.find('/Game/_Dawnwalker/Animation_MH/Humans/Ambrus/Animation/LinkedLayers/ABP_AmbrusLocomotionLayers.ABP_AmbrusLocomotionLayers_C')
  local parent=AI.find('/Game/_Dawnwalker/Animation_MH/Humans/LinkedLayers/ABP_NPC_HumanLocomotionDefaultLayers.ABP_NPC_HumanLocomotionDefaultLayers_C')
  if not valid(cls)or not valid(parent)then return false end
  local layer=anim:GetLinkedAnimLayerInstanceByClass(cls,true)
  if not valid(layer)or same(layer,cls:GetCDO())then return false end
  m.idleLease=m.idleLease or {}
  return AI.leaseIdleSelectors(layer,parent:GetCDO(),m.idleLease)
 end)
 m.idleNote=ok and (why and 'Human travel idle selectors leased'or 'Waiting for linked locomotion instance')or clean(why)
end
local function releaseHold(m)if m.hold then Engagement.finish(m.hold);m.hold=nil end end
local restoreEnemies
local function restoreRetreat(m)
 if m.retreatState then
  if AI.board(m.retreatStub,m.retreatBoard)then AI.retreatSensing(m.retreatStub,m.retreatBoard,m.retreatState,false)end
  for _,a in ipairs(m.retreatAttitudes or {})do
   if AI.board(a.source)and AI.board(a.target)and a.source:GetAttitudeTowards(a.target)==1 then a.source:SetAttitudeTowards(a.target,a.old,false)end
  end
 end
 m.retreatState=nil;m.retreatStub=nil;m.retreatBoard=nil;m.retreatAttitudes=nil;m.retreatPairs=nil
end
local function retreatSensing(m,enabled,enemies)
 if not enabled then
  if m.retreatState then restoreRetreat(m);restoreEnemies(m)end
  return true
 end
 if not ready(m)then return end
 m.retreatState=m.retreatState or {};m.retreatStub=m.stub;m.retreatBoard=m.board
 if not AI.retreatSensing(m.stub,m.board,m.retreatState,true)then return false end
 m.retreatAttitudes=m.retreatAttitudes or {};m.retreatPairs=m.retreatPairs or {}
 -- Damage/instigator handling can make a previously neutralized pair hostile
 -- again without perception. Maintain our one-way lease during the entire
 -- retreat, including enemies left outside Coen's discovery radius.
 local seen={}
 local function neutral(t)
  if not AI.board(t)or same(t,playerStub)or same(t,m.stub)then return end
  local key=t:GetFullName();if ownedStubs[key]or seen[key]then return end;seen[key]=true
  local old=m.stub:GetAttitudeTowards(t)
  if old~=3 then return end
  if not m.retreatPairs[key]then
   if #m.retreatAttitudes>=64 then return end
   m.retreatPairs[key]=true;m.retreatAttitudes[#m.retreatAttitudes+1]={source=m.stub,target=t,old=old}
  else m.retreatRepairs=(m.retreatRepairs or 0)+1 end
  m.stub:SetAttitudeTowards(t,1,false)
 end
 for _,a in ipairs(m.retreatAttitudes)do neutral(a.target)end
 neutral(m.board:GetTarget())
 neutral(m.combatTarget)
 neutral(m.instigator)
 for _,a in ipairs(m.enemyAttitudes or {})do if same(a.source,m.stub)then neutral(a.target)end end
 for i=1,math.min(#enemies,64)do neutral(enemies[i])end
end
local function restoreAttitudes(m)
 for _,a in ipairs(m.attitudes or {})do pcall(function()if AI.board(a.source)and AI.board(a.target)and a.source:GetAttitudeTowards(a.target)==(a.set or 1) then a.source:SetAttitudeTowards(a.target,a.old,false)end end)end
 m.attitudes={}
end
local function friendly(m,a,b)
 if same(a,b)then return end
 local old=a:GetAttitudeTowards(b)
 a:SetAttitudeTowards(b,1,false) -- ERebelAIAttitude::Friendly in the captured dump.
 m.attitudes[#m.attitudes+1]={source=a,target=b,old=old}
end
restoreEnemies=function(m)
 for _,a in ipairs(m.enemyAttitudes or {})do pcall(function()
  if AI.board(a.source)and AI.board(a.target)and a.source:GetAttitudeTowards(a.target)==3 then a.source:SetAttitudeTowards(a.target,a.old,false)end
 end)end
 m.enemyAttitudes={};m.enemyPairs={}
end
local function enemyPair(m,a,b)
 m.enemyAttitudes=m.enemyAttitudes or {};m.enemyPairs=m.enemyPairs or {}
 local key=a:GetFullName()..'>'..b:GetFullName()
 if m.enemyPairs[key]then return true end
 local old=a:GetAttitudeTowards(b)
 if old==3 then return true end -- Native hostility requires no override/restore.
 if #m.enemyAttitudes>=128 then return false end -- Defer a new hint; never dismiss a busy party member.
 a:SetAttitudeTowards(b,3,false) -- Hostile=3 in this game's ERebelAIAttitude.
 m.enemyAttitudes[#m.enemyAttitudes+1]={source=a,target=b,old=old};m.enemyPairs[key]=true
 return true
end
local function dismiss(m,reason)
 summonStage(m,'failed',reason)
 local unmarked,unmarkError=pcall(Protection.unmark,m)
 if not unmarked then log('Source marker cleanup: '..tostring(unmarkError))end
 AI.releaseSpawnAnchor(m.anchorLease)
 pcall(Damage.restore,m.stub,m.board,m.damageTuning)
 releaseCombatMovement(m);releaseTravelIdle(m);releaseFollowPace(m);releaseHold(m);restoreRetreat(m);restoreEnemies(m);restoreAttitudes(m)
 if ready(m)then m.stub:RequestDespawn(true)end
 if m.actionPath then local result,why=Native.stop(m.actionPath);assert(result,why)end
 if m.stubKey then ownedStubs[m.stubKey]=nil;m.stubKey=nil end
 members[m.id]=nil;log(m.name..': '..reason)
 Recovery.layout(members)
end
local beforeReset=nil
function M.beforeReset(fn)beforeReset=fn end
local function resetParty(reason,preserve)
 local saved,seen={},{}
 if preserve then
  for _,entry in ipairs(pendingWorldParty and pendingWorldParty.entries or {})do saved[#saved+1]=entry;seen[entry.id]=true end
  for _,m in pairs(members)do if not seen[m.id]then
   saved[#saved+1]={id=m.id,characterId=m.characterId,ordinal=m.ordinal,mode=m.mode,spawnSlot=m.spawnSlot,replacedEpoch=m.replacedEpoch,
    defeated=m.defeated==true or m.health==0 or ready(m)and m.board.bIsDead,peaceSince=m.peaceSince}
  end end
  table.sort(saved,function(a,b)return a.ordinal<b.ordinal end)
 end
 if beforeReset then beforeReset()end -- Drop selected-actor references before native destruction.
 if not preserve then nativeCommands={}end
 formation=Formation.new();formationFrame=formation.frame;partyDeparture=false;partyPositions={}
 updateCursor=0;lastFollowWake=nil;lastPartyCatchup=nil;lastReconnectPoll=nil;lastDiagnosticTick=nil;lastAnchorUpdate=nil;travelHeading=nil;playerStub=nil
 local old={};for _,m in pairs(members)do old[#old+1]=m end
 for _,m in ipairs(old)do dismiss(m,reason or 'Dismissed for reload / world change')end
 -- Root ownership lives in the native DLL across Lua reloads. Never abandon it.
 local result,why=Native.stopAll();assert(result,why)
 Protection.cleanup()
 return {entries=saved,retryAt=0}
end
function M.cleanup()
 resetParty('Dismissed for reload / world change')
 pendingWorldParty=nil;travelState={epoch=0};travelKind=nil;travelEpoch=0;travelDiscontinuity=false
end
local function readAbilities(m)
 -- RebelAI exposes its own ASC through the stub. A Pawn component lookup may
 -- return no ASC or a different component from the one executing AI actions.
 m.asc=m.stub:GetAbilitySystemComponent()
 if not valid(m.asc)then m.grantCount=0;return end
 -- A live property TArray exposes GameplayAbilitySpec directly. Only returned
 -- out-param arrays (such as AssetRegistry results) use RemoteUnrealParam:get().
 local items=m.asc.ActivatableAbilities.Items
 assert(#items<=256,'Unexpected ability count')
 local rows={};m.grantCount=#items
 for i=1,#items do local ability=items[i].Ability;if valid(ability)then
  rows[#rows+1]=ability:GetClass():GetFullName()
 end end
 -- Diagnostics only: standalone action-tree fragments can supply abilities on
 -- demand. A persistent GAS list is not the character's complete repertoire.
 table.sort(rows);local signature=table.concat(rows,'\n')
 if signature~=m.grantSignature then
  m.grantSignature=signature
  write('companion-powers-'..m.id..'.txt',m.name..'\nPawn: '..m.actor:GetFullName()..'\nAI: '..m.stub:GetAIDefinition():GetFullName()..'\nASC: '..m.asc:GetFullName()..'\nGranted: '..#rows..'\n'..signature..'\n')
 end
end
local function refreshAbilities(m)
 local ok,err=pcall(readAbilities,m)
 if not ok then
  local fault=tostring(err)
  if m.abilityFault~=fault then log(m.name..' ability inspection: '..fault)end
  m.abilityFault=fault
 else m.abilityFault=nil end
end
-- Transition the owned clone's real character state, not anim-instance flags.
-- Some bosses start with no character state despite Follower / Idle behavior.
-- Never force this every tick or over a scene, unbreakable action or combat.
local function travelPose(m,running)
 running=running==true
 if not ready(m)then return end
 if m.stub:IsInCombat()or m.board.Combat.bInCombat or m.stub:IsInCinematicMode()or m.board.bMainBehaviorSuspended or m.board:HasAnyUnbreakableActiveAction()then return end
 releaseCombatMovement(m)
 travelIdle(m)
 if (m.archetype or m.characterId)~='lacra'and not(m.handSetup and m.handSetup.attackSelector)then
  m.stowState=m.stowState or {}
  local ok,why=pcall(AI.travelWeapon,m.stub,m.board,m.healthComponent,m.stowState,m.now or 0)
  m.stowNote=ok and m.stowState.note or clean(why)
 end
 if m.travelPose and m.travelGait==running then return end
 m.travelPose=true;m.travelGait=running
 local ok,why=pcall(function()
  local current=m.board.CurrentCharacterState.TagName:ToString()
  if not m.poseStates then
   local states=m.stub:GetAIDefinition().CharacterStates;assert(#states<=64,'Unexpected character states')
   m.poseStates={};for i=1,#states do
    local tag=states[i].Tag.TagName:ToString();m.poseStates[tag]=true
    if tag=='RebelAI.CharacterState.Neutral'then
     local tags=states[i].AnimTags.GameplayTags
     for j=1,#tags do if tags[j].TagName:ToString()=='Character.IsInCombat'then m.neutralIsCombat=true end end
    end
   end
  end
  local known=m.poseStates
  local desired=running and 'RebelAI.CharacterState.Running'or (m.neutralIsCombat and 'RebelAI.CharacterState.Default'or 'RebelAI.CharacterState.Neutral')
  if known[desired]and current~=desired and (current==m.poseOwned or current=='None'or current:find('RebelAI.CharacterState.Combat',1,true)==1 or current=='RebelAI.CharacterState.Default'or current=='RebelAI.CharacterState.Running'or current=='RebelAI.CharacterState.Neutral')then
   local tag={TagName=FName(desired)}
   if m.stub:BP_CharacterStateExist(tag)then
    m.poseRestore=m.poseRestore or (current~='None'and current or known['RebelAI.CharacterState.Default']and 'RebelAI.CharacterState.Default'or nil)
    -- No restore destination means no safe state override.
    if m.poseRestore then m.stub:BP_SetCharacterState(tag);m.poseOwned=desired end
   end
  end
  -- Lacra's Fists selector chooses claw attacks; it is not an inventory sword
  -- to sheath. Neutral/Running still restores her ordinary travel animation.
  -- Equipment cleanup runs separately, including after a native phase exit.
  if not ready(m)then return end
  m.poseNote='Travel state: '..m.board.CurrentCharacterState.TagName:ToString()
 end)
 if not ok then m.poseNote='Travel stance unavailable: '..clean(why);log(m.name..' '..m.poseNote)end
end
local function combatPose(m,nativeCombat)
 releaseTravelIdle(m)
 releaseFollowPace(m)
 -- Once combat is active, the pre-travel pose is stale. Restoring Default
 -- here was putting Xanthe back into her 140 cm/s walking profile mid-entry.
 if nativeCombat then
  m.travelPose=nil;m.travelGait=nil;m.stowState=nil;m.poseOwned=nil;m.poseRestore=nil;m.weaponStowed=nil
  return
 end
 if not ready(m)or not m.travelPose or m.board:HasAnyUnbreakableActiveAction()then return end
 m.travelPose=nil;m.travelGait=nil;m.stowState=nil
 local ok,why=pcall(function()
  -- If native AI already changed it, that state belongs to native AI.
  if m.poseOwned and m.poseRestore and m.poseRestore:find('RebelAI.CharacterState.Combat.',1,true)==1 and m.board.CurrentCharacterState.TagName:ToString()==m.poseOwned then
   m.stub:BP_SetCharacterState({TagName=FName(m.poseRestore)})
  end
  m.poseOwned=nil;m.poseRestore=nil
  -- Restore our stow without starting an equip montage that would immediately
  -- block the native combat-entry gate. Native combat owns its introduction.
  if m.weaponStowed and AI.weaponEquipped(m.stub,m.board)==false then m.stub:EquipWeapon(false)end
  m.weaponStowed=nil
 end)
 if not ok then log(m.name..' combat stance: '..clean(why))end
end
local function combatMovement(m)
 -- Xanthe's inspected Default/Running states both use NPC_Walker, whereas
 -- every authored Combat state uses this same character-specific profile.
 -- Only repair that exact leftover profile; native defense/attack profiles win.
 if (m.archetype or m.characterId)~='xanthe'or not ready(m)then return end
 m.combatMovement=m.combatMovement or {}
 if not valid(m.authoredCombatProfile)and m.now>=(m.combatProfilePoll or 0)then
  m.combatProfilePoll=m.now+500
  m.authoredCombatProfile=Native.loadedAsset(xantheCombatProfile)
  -- Soft assets may be collected between summon and combat. Re-request
  -- asynchronously, polling completion without a blocking load or rooted pawn.
  if not valid(m.authoredCombatProfile)and m.now>=(m.combatProfileRetry or 0)then
   m.combatProfileRetry=m.now+10000
   local ok,result=pcall(Native.requestAsset,player,xantheCombatProfile)
   if not ok or not result then m.combatMovementNote='Combat profile reload unavailable';return end
  end
 end
 local ok,why=AI.combatMovement(m.stub,m.board,m.combatMovement,m.actor:GetMovementComponent(),m.authoredCombatProfile,m.now)
 m.combatMovementNote=why
end
local function combatEquipment(m)
 if not ready(m)then return false end
 if not AI.ownedDamageBranch(m.stub,m.board)then return false end
 -- Ambrus and other sword users may lose their physical weapon/selector when
 -- an initial stow completed before a combat mode ever existed.
 if (m.archetype or m.characterId)~='lacra'and valid(m.healthComponent)then
  local equipped=m.healthComponent.EquippedWeapon
  if valid(equipped)or (m.archetype or m.characterId)=='ambrus'then
   m.swordSetup=m.swordSetup or {}
   local accepted,why=AI.swordCombat(m.stub,m.board,m.healthComponent,m.swordSetup)
   m.equipmentNote=why;return accepted
  end
 end
 if (m.archetype or m.characterId)~='lacra'then return true end
 local defClass=Native.loadedClass(m.definition.path)
 local def=valid(defClass)and defClass:GetCDO()or nil
 if not valid(def)or not valid(def.EnemyConfig)or #def.EnemyConfig.HandToHandWeapons==0 then return false end
 -- Lacra's inspected definition specifies vampire claws and no inventory
 -- weapon. Initialize the native setup instead of granting guessed attacks.
 m.handSetup=m.handSetup or {}
 local claws=Native.loadedClass('/Game/_Dawnwalker/Blueprints/Items/HandToHand/BP_Weapon_VampireClaws.BP_Weapon_VampireClaws_C')
 local accepted,why=AI.handCombat(m.stub,m.board,m.healthComponent,m.handSetup,claws)
 if ready(m)then refreshAbilities(m)end
 if m.equipmentNote~=why then log(m.name..' equipment: '..why..'; granted abilities='..tostring(m.grantCount))end
 m.equipmentNote=why
 return accepted
end
local function followMovement(m,now)
 if not ready(m)or m.combat and m.combat.phase~='travel'then releaseFormation(m);return end
 if m.lastFollowTick and now-m.lastFollowTick<250 then return end
 if m.hold or m.conversationAt or m.mode~='follow'or m.stub:IsInCombat()or m.board.Combat.bInCombat
  or m.stub:IsInCinematicMode()or m.board.bMainBehaviorSuspended or m.board:HasAnyUnbreakableActiveAction()then releaseFormation(m);return end
 m.lastFollowTick=now
 if m.resumeConversation then
  if same(m.actor,m.resumeConversation)then
   releaseFollowPace(m);m.travelPose=nil;m.travelGait=nil
  end
  m.resumeConversation=nil
 end
 local goal=formation.goals[m.id]
 if not goal then releaseFormation(m);return end
 local a,p=loc(m.actor),playerPoint or loc(player)
 local gap=math.sqrt((a.X-p.X)^2+(a.Y-p.Y)^2)
 m.followPosition=a;m.formationPoint=goal.point;m.slotDistance=goal.distance
 m.formationPending=goal.distance>100;m.formationEpoch=goal.epoch
 local paceGap=math.max(gap,(m.followSpacing or 250)+goal.distance)
 local pace=Combat.followPace(paceGap,playerSpeed or 0,m.followRunning,m.followSpacing,m.followSprinting)
 local old=m.board.Follower.FollowerSpeed
 if m.followSpeedRestore==nil then m.followSpeedRestore=old end
 m.followSpeedOwned=pace.enum;m.followPaceSpeed=pace.enum;m.followRunning=pace.running;m.followSprinting=pace.sprinting;m.followGap=gap
 -- Native Coen following is a fallback only. Its stop radius does not control
 -- the private actor destination used by the authored movement branch.
 m.board.Follower.KeepDistanceToPlayer=m.followSpacing or 250
 m.board.Follower.KeepDistanceToPlayerMoveTo=(m.followSpacing or 250)+150
 travelPose(m,pace.running)
 if not ready(m)then releaseFormation(m);return end
 m.paceLease=m.paceLease or {}
 local suffix=pace.sprinting and 'Sprinter'or 'Runner'
 local path='/Game/_Dawnwalker/NPC/BasicNPC/MovementProfiles/DA_Follower_'..suffix..'_MovementProfile.DA_Follower_'..suffix..'_MovementProfile'
 AI.travelPace(m.stub,m.board,m.paceLease,m.actor:GetMovementComponent(),pace.running and AI.find(path)or nil,pace.enum)
 local active,why=FormationNative.update(m,goal,now)
 m.wakeNote=why;m.formationPathStatus=valid(m.controller)and m.controller:GetMoveStatus()or nil
 m.travelRequestAt=m.formationLease and m.formationLease.issuedAt
 if not active and ready(m)then m.board.Follower.bFollowerModeEnabled=true end
end
local function conversationCandidate(m)
 return m.definition.chat~=false and ready(m)and not m.board.bIsDead and not m.stub:IsInCombat()and not m.board.Combat.bInCombat
  and not m.stub:IsInCinematicMode()and (not m.board.bMainBehaviorSuspended or m.hold)
  and (not m.combat or m.combat.phase=='travel')
end
local function conversationReady(m)
 return conversationCandidate(m)and not m.board:HasAnyUnbreakableActiveAction()
end
function M.actor(id)
 local m=members[id]
 if not m or not conversationCandidate(m)or not valid(player)or distance(loc(m.actor),loc(player))>1200 then return nil,false end
 if m.board:HasAnyUnbreakableActiveAction()then return nil,true end
 return m.actor,false
end
function M.identity(actor)
 for _,m in pairs(members)do if same(m.actor,actor)then return {name=m.name,definition=m.definition.path,characterId=m.characterId,chat=m.definition.chat~=false}end end
end
function M.beforeConversation(actor)
 for _,m in pairs(members)do if same(m.actor,actor)then
  if not conversationReady(m)then return false,'Companion is busy with combat or an action'end
  m.talkFollowing=nil;m.resumeConversation=nil;m.formationPending=nil;m.formationEpoch=formationFrame.epoch
  m.conversationOwned=actor
  releaseFollowPace(m);releaseHold(m)
  -- A cached running gait is not evidence that the native animation state
  -- still matches it. Re-evaluate once before acquiring the movement hold.
  m.travelPose=nil;m.travelGait=nil;travelPose(m,false);return true
 end end
 return true
end
function M.afterConversation(actor)
 for _,m in pairs(members)do if same(m.actor,actor)then
  if not same(m.conversationOwned,actor)then return end
  m.conversationOwned=nil
  m.conversationAt=nil;m.talkFollowing=true -- The party manager owns follow/wait again.
  -- Resume only this instance after the hold restored its locomotion flags.
  -- Follow ticks defer the one-shot reset if combat or another owner intervenes.
  m.resumeConversation=actor;m.lastFollowTick=nil
  return
 end end
end
local function rememberOwner(m,result)
 if not result or not result.spawner or valid(m.spawner)then return end
 local owner=AI.find(result.spawner)
 if valid(owner)and owner:IsA(AI.find('/Script/Dawnwalker.DogwoodPopulationSimpleSpawner'))then
  m.spawner=owner
  local points=owner.DynamicSpawnPoints
  if #points==1 and valid(points[1])and points[1]:IsA(AI.find('/Script/Population.DynamicSpawnPoint'))then m.spawnAnchor=points[1]end
 end
end
local function syncSpawnAnchor(m,now)
 if m.mode~='follow'or m.defeated or m.health==0 or not valid(m.spawnAnchor)or not valid(m.spawner)then return end
 local urgent=travelKind and m.anchorEpoch~=travelEpoch
 if not urgent and now-(m.anchorAttempt or -math.huge)<((m.anchorFailures or 0)>0 and Recovery.retryDelay(m.anchorFailures)or 1000) or now-(lastAnchorUpdate or -math.huge)<250 then return end
 if m.spawnAnchor:GetWorld():GetFullName()~=worldName then return end
 local p=playerPoint or loc(player)
 if distance(loc(m.spawnAnchor),p)<math.max(600,(m.followSpacing or 400)+250) then return end
 local pm=player:GetMovementComponent();if not valid(pm)or pm.MovementMode~=1 then return end
 if urgent then m.anchorEpoch=travelEpoch;m.anchorFailures=nil end
 m.anchorAttempt=now;lastAnchorUpdate=now
 local occupied={}
 for _,other in pairs(members)do if other~=m then
  local point=valid(other.actor)and loc(other.actor)or other.position
  if point then occupied[#occupied+1]=point end
 end end
 local yaw=travelHeading or 0
 local destination=Recovery.catchupPoint(p,yaw,m.formationSlot or m.spawnSlot,occupied,project,nil,m.formationPitch)
 if not destination then m.anchorFailures=math.min(4,(m.anchorFailures or 0)+1);m.anchorNote='No nearby navigation';return end
 -- Move only the marker belonging to this clone's registered population owner.
 -- It supplies the next streamed pawn's arrival, not combat movement commands.
 m.anchorLease=m.anchorLease or {}
 if AI.moveSpawnAnchor(m.spawnAnchor,destination,m.anchorLease)then
  m.anchorFailures=nil;m.position=destination;m.anchorAt=now;m.anchorNote='Owned spawn marker follows Coen'
 else m.anchorFailures=math.min(4,(m.anchorFailures or 0)+1);m.anchorNote='Native spawn marker move declined; retries backed off'end
end
local function attach(m,actor)
 local s=stub(actor);local board=AI.board(s);if not board then return false end
 assert(actor:GetWorld():GetFullName()==worldName,'Spawned pawn belongs to another world')
 if m.stubKey then ownedStubs[m.stubKey]=nil end
 m.actor,m.stub,m.board=actor,s,board;m.attitudes={}
 -- These are mod-owned population clones. Their original boss arena must not
 -- force Defensive/GuardArea behavior as the party travels across the world.
 -- The native setter changes only this initialized board, never its AI CDO.
 local guardLib=AI.find('/Script/RebelAI.Default__RebelAIBoardBlueprintFunctionLibrary')
 assert(AI.ignoreCombatGuardAreas(guardLib,s,board),'Companion guard-area setup unavailable');m.guardAreasIgnored=true
 m.stubKey=s:GetFullName();ownedStubs[m.stubKey]=m
 m.controller=actor:GetController()
 m.laneSample=nil;m.laneRetryAt=nil;m.formationPoint=nil;m.wakeSample=nil;m.wakeAttempts=nil;m.wakeAt=nil
 m.travelGoal=nil;m.travelRequestAt=nil;m.travelProgress=nil;m.resumeConversation=nil;m.conversationOwned=nil;m.overlapSince=nil;m.narrowUntil=nil
 m.formationEpoch=formationFrame.epoch;m.formationPending=nil
 local capsule=actor.CapsuleComponent
 if valid(capsule)then m.capsuleRadius=capsule:GetScaledCapsuleRadius()end
 Recovery.layout(members)
 friendly(m,s,playerStub);friendly(m,playerStub,s)
 m.playerEpoch=playerEpoch
 for _,other in pairs(members)do if other~=m and ready(other)then friendly(m,s,other.stub);friendly(m,other.stub,s)end end
 assert(not s:IsHostileTowardsPlayer(),'Companion friendship was rejected')
 board.Leader.bLeaderModeEnabled=false
 board.Follower.bFollowerModeEnabled=true;board.Follower.bIsTemporaryFollower=true
 board.Follower.bIsPlayerInFollowArea=true;board.Follower.bReturnToAP=false
 board:StopAllActions() -- One goal reset after the clone becomes friendly.
 m.originalCanFight=board.bCanFight
 -- Changing the clone's gate does not grant attacks; native AI still needs a
 -- combat definition and weapons. No shared NPC/config CDO is modified.
 m.combatDefinition=valid(s:GetAIDefinition()) and s:GetAIDefinition():IsA(AI.find('/Script/RebelAI.RebelAIDef'))
 m.healthComponent=component(actor,'/Script/DogwoodCombat.CombatComponentBase')
 m.asc=s:GetAbilitySystemComponent()
 measured('protect player',Protection.ensure,player,playerStub)
 measured('mark source '..m.name,Protection.mark,m,playerStub)
 local tuningOK,tuningError=pcall(Tuning.apply,m,playerStub);if not tuningOK then log('Companion tuning: '..tostring(tuningError))end
 local factionOK,factionError=pcall(Tuning.friendly,m,playerStub);if not factionOK then log('Companion allegiance: '..tostring(factionError))end
 m.damageBranch=AI.ownedDamageBranch(s,board)and 'Owned source damage; campaign helper cap bypassed'or 'Owned source damage tag unavailable'
 m.damageTuning=m.damageTuning or {}
 local damageOk,accepted,damageNote=pcall(Damage.apply,s,board,m.damageTuning,Settings.values.DamagePercent/100)
 m.damageNote=damageOk and damageNote or clean(accepted)
 if not damageOk or not accepted then
  pcall(Damage.restore,s,board,m.damageTuning)
  log(m.name..' damage tuning unavailable: '..tostring(m.damageNote))
 end
 refreshAbilities(m)
 travelPose(m)
 followMovement(m,m.now or 0)
 -- Initial appearance faces the player's current position, including movement
 -- during streaming. Do this once; normal following/combat owns later turns.
 if not m.arrivalFaced then
  m.arrivalFaced=true
  if not board.bIsDead and not board.bMainBehaviorSuspended and not s:IsInCombat()and not s:IsInCinematicMode()and not board:HasAnyUnbreakableActiveAction()then
   local ok,why=pcall(function()
    local rot=actor:K2_GetActorRotation();local yaw=Recovery.facing(loc(actor),loc(player))
    actor:K2_SetActorRotation({Pitch=rot.Pitch,Yaw=yaw,Roll=rot.Roll},false)
   end)
   if not ok then log(m.name..' arrival facing: '..tostring(why))end
  end
 end
 summonStage(m,'ready',m.name..' has joined your party')
 m.status='Following';m.created=nil;log(m.name..' spawned: '..actor:GetFullName());return true
end
local function reconnect(m,now)
 if not m.missingAt then log(m.name..' AI detached; retaining its population owner and party slot')end
 m.missingAt=m.missingAt or now
 local backoff=math.min(8000,1000*2^(m.reconnectAttempts or 0))
 if m.lastReconnect and now-m.lastReconnect<backoff or lastReconnectPoll and now-lastReconnectPoll<1500 then return end
 m.lastReconnect=now
 lastReconnectPoll=now;m.reconnectAttempts=math.min(3,(m.reconnectAttempts or 0)+1)
 -- Only this member's population owner can supply its replacement pawn.
 local result,why=Native.poll(m.actionPath);local found,foundBoard
 if result then
  rememberOwner(m,result)
  for path in (result.pawns or ''):gmatch('(/[^%s"\'(),=]+)')do
   local actor=AI.find(path)
   local board=valid(actor)and actor:IsA(AI.find('/Script/Engine.Pawn'))and AI.board(stub(actor))
   if board then
    if found and not same(found,actor)then error('Multiple pawns in companion owner')end
    found,foundBoard=actor,board
   end
  end
 end
 local state=Recovery.missing({now=now,since=m.missingAt,ready=found~=nil,dead=m.defeated==true or m.health==0 or foundBoard and foundBoard.bIsDead})
 if state=='reattach'and not Recovery.reconnectCandidate(m,found:GetFullName(),now)then
  m.status='Waiting for stable companion AI';return
 end
 if state~='reattach'then Recovery.reconnectCandidate(m,nil,now)end
 if state=='reattach'then
  releaseCombatMovement(m);releaseTravelIdle(m);releaseFollowPace(m);restoreRetreat(m);restoreEnemies(m);restoreAttitudes(m);releaseHold(m)
  m.combat=nil;m.combatTarget=nil;m.issuedTarget=nil;m.instigator=nil
  m.followPaceSpeed=nil;m.followSpeedOwned=nil;m.followSpeedRestore=nil;m.followRunning=nil;m.followDistance=nil
  m.travelPose=nil;m.travelGait=nil;m.poseOwned=nil;m.poseRestore=nil;m.weaponStowed=nil;m.handSetup=nil;m.stowState=nil
  m.poseStates=nil;m.lastTick=nil;m.swordSetup=nil;m.stableSince=now
  if measured('reattach '..m.name,attach,m,found)then m.missingAt=nil;m.recoveryState=nil;m.detail='Rejoined after AI streaming';log(m.name..' reattached to its population pawn')end
 else
  if state=='defeated'then m.defeated=true end
  m.status=state=='defeated'and 'Defeated'or state=='waiting'and 'Waiting for companion AI'or 'Companion unloaded / return closer'
  m.detail='Party slot retained; '..tostring(why or 'waiting for its population pawn to become ready')
  if m.recoveryState~=state then
   m.recoveryState=state
   write('companion-recovery-'..m.id..'.txt',os.date()..'\n'..m.status..'\n'..m.detail..'\nowner='..tostring(m.actionPath)..'\nlastPlayerGap='..tostring(m.playerGap)..'\n')
   log(m.name..': '..m.status)
  end
  if state=='unloaded'and Recovery.replaceMissing({now=now,since=m.missingAt,owner=valid(m.spawner),anchorMoved=m.anchorAt~=nil and m.anchorEpoch==m.travelEpoch,
   follow=m.mode=='follow',dead=m.defeated==true or m.health==0,travelEpoch=m.travelEpoch,replacedEpoch=m.replacedEpoch})then return 'replace' end
 end
end
local function pollSpawn(m,now)
 local result,why=Native.poll(m.actionPath)
 if result then
  rememberOwner(m,result)
  m.lastSpawnText=result.pawns or ''
  -- Engine ExportText gives object paths for the spawner's own weak pawn map.
  -- Resolve ONLY paths in that export, then require Pawn/world validity.
  local found=nil
  for path in m.lastSpawnText:gmatch('(/[^%s"\'(),=]+)')do
   local actor=AI.find(path)
   if valid(actor)and actor:IsA(AI.find('/Script/Engine.Pawn'))then
    if found and not same(found,actor)then error('Definition produced more than one pawn; unsupported')end
    found=actor
   end
  end
  if found and measured('attach '..m.name,attach,m,found)then return end
 end
 if now-m.created>20000 then
  write('companion-spawn-diagnostic.txt',m.name..'\n'..tostring(why or '')..'\n'..(m.lastSpawnText or ''))
  dismiss(m,'Spawn timed out');error('Spawn did not resolve within 20 game seconds; diagnostic saved')
 end
end
project=function(point)
 local output={X=0,Y=0,Z=0}
 local nav=AI.find('/Script/NavigationSystem.Default__NavigationSystemV1')
 if not valid(nav)or not nav:K2_ProjectPointToNavigation(player,point,output,nil,nil,{X=150,Y=150,Z=250})then return nil end
 if type(output.X)~='number'or distance(output,point)>500 then return nil end
 return {X=output.X,Y=output.Y,Z=output.Z}
end
local function catchup(m,now)
 if not ready(m)or m.hold or m.mode~='follow'or m.stub:IsInCinematicMode()or m.board.bMainBehaviorSuspended then return end
 if travelKind and m.catchupEpoch~=travelEpoch then m.catchupEpoch=travelEpoch;m.lastCatchupAttempt=nil;m.catchupFailures=nil end
 if m.lastCatchupCheck and now-m.lastCatchupCheck<500 then return end;m.lastCatchupCheck=now
 local p,a=loc(player),loc(m.actor);local gap=distance(a,p);m.playerGap=gap
 local minimum,cooldown=Recovery.catchupLimits(playerSpeed,m.followSpacing)
 if gap<minimum then return end
 local movement=m.actor:GetMovementComponent();local pm=player:GetMovementComponent()
 local ground=valid(movement)and valid(pm)and movement.MovementMode==1 and pm.MovementMode==1
 -- WasRecentlyRendered also reports shadows. Use a conservative rear-camera
 -- half-plane; never relocate a pawn or its destination in front of the view.
 local hidden=cameraPoint and Recovery.behindCamera(a,cameraPoint,cameraYaw)
 if not Recovery.catchup({follow=true,dead=m.board.bIsDead,combat=m.stub:IsInCombat()or m.board.Combat.bInCombat,busy=m.board:HasAnyUnbreakableActiveAction(),grounded=ground,visible=not hidden,gap=gap,minimum=minimum,now=now,cooldown=cooldown,last=m.lastCatchup,attempted=m.lastCatchupAttempt,failures=m.catchupFailures,partyInterval=250,partyLast=lastPartyCatchup,reposition=travelKind~=nil})then return end
 m.lastCatchupAttempt=now
 m.catchupFailures=math.min(4,(m.catchupFailures or 0)+1)
 lastPartyCatchup=now
 local occupied={};for _,other in pairs(members)do if other~=m and valid(other.actor)then occupied[#occupied+1]=loc(other.actor)end end
 local yaw=cameraYaw or travelHeading or 0
 local destination=Recovery.catchupPoint(p,yaw,m.formationSlot or m.spawnSlot,occupied,project,cameraPoint,m.formationPitch)
 local capsule=m.actor.CapsuleComponent
 if not destination or not valid(capsule)then m.catchupNote='No unseen walkable arrival point';return end
 destination.Z=destination.Z+capsule:GetScaledCapsuleHalfHeight()+4
 -- Collision-checked fallback for a distant off-camera traveller. No teleport
 -- during combat, scenes, hold, an unbreakable action, or while either is airborne.
 if m.actor:K2_TeleportTo(destination,{Pitch=0,Yaw=yaw,Roll=0})and ready(m)then
  m.catchupFailures=nil;m.laneSample=nil;m.lastCatchup=now;m.catchupNote='Arrived behind camera'
  m.followRunning=nil;m.followPaceSpeed=nil
  log(m.name..' caught up from '..math.floor(gap/100)..' metres')
 else m.catchupNote='Native collision check declined arrival'end
end
local function spawn(id,now,request)
 assert(not members[request],'Spawn request already exists')
 local c=assert(byId[id],'Unknown companion')
 local used={};for _,other in pairs(members)do if other.spawnSlot then used[other.spawnSlot]=true end end
 local slot=1;while used[slot]do slot=slot+1 end
 local occupied={};for _,other in pairs(members)do
  local point=valid(other.actor)and loc(other.actor)or other.position
  if point then occupied[#occupied+1]=point end
 end
 local pitch=190;for _,other in pairs(members)do pitch=math.max(pitch,other.formationPitch or 190)end
 local position,yaw=Recovery.summonPoint(loc(player),player:K2_GetActorRotation().Yaw,slot,occupied,project,pitch)
 assert(position,'No clear walkable summon point nearby; move onto open ground')
 spawnOrdinal=spawnOrdinal+1
 local label=id=='matriarch'and 'Bakr-Erga'or id=='marat'and 'Crake'or c.name
 local m={id=request,characterId=id,archetype=c.archetype~=''and c.archetype or id,label=label,baseName=label,ordinal=spawnOrdinal,name=c.name,definition=c,loading='character',spawnSlot=slot,position=position,yaw=yaw,created=now,mode='follow',status='Loading character',detail='',attitudes={}}
 members[request]=m -- A distinct game actor; the Convai identity stays c.id.
 Recovery.layout(members)
 m.request=request
 for i=#summons,1,-1 do if summons[i].id==request then table.remove(summons,i)end end
 summons[#summons+1]={id=request,member=request,phase='character',message='Preparing character'}
 if #summons>64 then
  for i,s in ipairs(summons)do if s.phase=='ready'or s.phase=='failed'then table.remove(summons,i);break end end
 end
 summonStage(m,'character','Preparing character')
end
local function pollLoading(m,now)
 if now-m.created>60000 then error('Character loading timed out after 60 unpaused seconds')end
 local paths={character=m.definition.path,body=m.pawnPath,ai=m.aiPath,reactions=m.reactionsPath}
 local path=paths[m.loading]
 local class=path and Native.loadedClass(path)or nil
 if path and not valid(class)then
  if m.loadRequested~=path then
   local result,why=Native.requestClass(player,path);assert(result,why);m.loadRequested=path
   log(m.name..' async '..m.loading..' load submitted in '..tostring(result.requestMs)..' ms')
   m.loadTrace[#m.loadTrace+1]=m.loading..' requestMs='..tostring(result.requestMs)
  end
  return
 end
 if m.loading=='character'then
  m.npcClass=class
  local info,why=Native.inspect(class:GetCDO());assert(info,why)
  m.aiPath=Native.exportedPath(info.aiClass);m.pawnPath=assert(Native.exportedPath(info.pawnClass),'Pawn class is missing')
  m.reactionsPath=Native.exportedPath(info.reactionsClass)
  m.loading='body';m.status='Loading character model';summonStage(m,'body','Loading appearance and animations');return
 end
 if m.loading=='body'then
  m.loading='ai';m.status='Loading AI';summonStage(m,'ai','Preparing movement and combat');return
 end
 if m.loading=='ai'then
  m.loading='reactions';m.status='Loading reactions';summonStage(m,'reactions','Preparing reactions');return
 end
 if (m.archetype or m.characterId)=='xanthe'then
  local profile=Native.loadedAsset(xantheCombatProfile)
  if not valid(profile)then
   if not m.profileRequested then
    local result,why=Native.requestAsset(player,xantheCombatProfile);assert(result,why);m.profileRequested=true
    summonStage(m,'reactions','Loading combat movement')
    log(m.name..' async combat profile requested in '..tostring(result.requestMs)..' ms')
   end
   return
  end
  assert(profile:IsA(AI.find('/Script/RebelLocomotion.RebelCharacterMovementProfile')),'Invalid authored combat profile type')
  m.authoredCombatProfile=profile
 end
 -- Refresh relative to the player after streaming, retaining this member's
 -- slot and avoiding both live companions and in-flight summon reservations.
 local occupied={};for _,other in pairs(members)do if other~=m then
  local point=valid(other.actor)and loc(other.actor)or other.position
  if point then occupied[#occupied+1]=point end
 end end
 local position,yaw=Recovery.summonPoint(loc(player),player:K2_GetActorRotation().Yaw,m.formationSlot or m.spawnSlot,occupied,project,m.formationPitch)
 assert(position,'No clear walkable summon point; move onto open ground and summon again')
 m.position,m.yaw=position,yaw
 -- Other async loads can collect an earlier soft class. Reacquire at use and
 -- return to its loading stage instead of handing a stale pointer to the bridge.
 m.npcClass=Native.loadedClass(m.definition.path)
 if not valid(m.npcClass)then m.loading='character';m.loadRequested=nil;return end
 local aiClass=m.aiPath and Native.loadedClass(m.aiPath)or nil
 if m.aiPath and not valid(aiClass)then m.loading='ai';m.loadRequested=nil;return end
 -- Async streams may complete together. Start only one population activation
 -- per tick so deferred engine construction does not form a single-frame burst.
 if populationStartedAt==now then return end
 populationStartedAt=now
 local result,why=Native.spawn(player,m.npcClass,aiClass,position,yaw);assert(result,why)
 m.actionPath=assert(Native.exportedPath(result.action),'Spawn action path missing')
 m.loading=nil;m.npcClass=nil;m.created=now;m.status='Spawning'
 m.loadTrace[#m.loadTrace+1]='factoryMs='..tostring(result.factoryMs)..' activateMs='..tostring(result.activateMs)..' lookupMs='..tostring(result.lookupMs)..' nativeMs='..tostring(result.nativeMs)
 m.loadTrace[#m.loadTrace+1]=string.format('arrival slot=%d X=%.1f Y=%.1f Z=%.1f yaw=%.1f',m.spawnSlot,position.X,position.Y,position.Z,yaw)
 summonStage(m,'spawning','Bringing companion into the world')
end
local function replaceMissingMember(m,now)
 local id,character,ordinal,mode,epoch=m.id,m.characterId,m.ordinal,m.mode,m.travelEpoch
 dismiss(m,'Recreating an unavailable travel owner')
 spawn(character,now,id)
 local replacement=members[id];replacement.ordinal=ordinal;replacement.mode=mode;replacement.replacedEpoch=epoch
 Recovery.layout(members)
 log(replacement.name..' owner recreated after travel streaming did not recover')
end
local function cancelPendingWorldDismissals()
 if not pendingWorldParty then return end
 local entries=pendingWorldParty.entries;local queued={}
 for _,command in ipairs(nativeCommands)do
  local consumed=false
  if command.op=='dismiss_all'then entries={};pendingWorldParty.entries=entries
  elseif command.op=='dismiss'then
   for i=#entries,1,-1 do if entries[i].id==command.id then table.remove(entries,i);consumed=true;break end end
  end
  if not consumed then queued[#queued+1]=command end
 end
 nativeCommands=queued
end
local function restoreWorldParty(now)
 if not pendingWorldParty or now<(pendingWorldParty.retryAt or 0)then return end
 local queue=pendingWorldParty.entries
 local saved=queue[1]
 if not saved then pendingWorldParty=nil;log('Party restored after world travel');return end
 local ok,why=true
 if members[saved.id]then table.remove(queue,1)
 elseif saved.defeated then
  local c=assert(byId[saved.characterId],'Unknown companion')
  local label=saved.characterId=='matriarch'and 'Bakr-Erga'or saved.characterId=='marat'and 'Crake'or c.name
  members[saved.id]={id=saved.id,characterId=saved.characterId,archetype=c.archetype~=''and c.archetype or saved.characterId,label=label,baseName=label,
   ordinal=saved.ordinal,name=c.name,definition=c,spawnSlot=saved.spawnSlot,mode=saved.mode,status='Fallen · recovering',detail='',attitudes={},defeated=true,health=0,peaceSince=nil,replacedEpoch=saved.replacedEpoch,travelEpoch=travelEpoch}
  table.remove(queue,1)
 else
  ok,why=pcall(spawn,saved.characterId,now,saved.id)
  if ok then
   local m=members[saved.id];m.ordinal=saved.ordinal;m.mode=saved.mode;m.spawnSlot=saved.spawnSlot or m.spawnSlot;m.replacedEpoch=saved.replacedEpoch;m.travelEpoch=travelEpoch
   table.remove(queue,1)
  end
 end
 Recovery.layout(members)
 if not ok then pendingWorldParty.retryAt=now+2000;note='Waiting to restore travelling party: '..clean(why)
 elseif #queue==0 then pendingWorldParty=nil;log('Party restored after world travel')
 else note='Restoring travelling party · '..#queue..' remaining'end
end
local function eligible(enemy,anchor,leash)
 -- Friendship may be temporarily changed by a native reaction. Party identity
 -- is stronger than attitude: an owned companion can never be an enemy hint.
 if valid(enemy)and ownedStubs[enemy:GetFullName()]then return false end
 local board=AI.board(enemy)
 if not board or enemy:IsPlayer()or enemy:IsInCinematicMode()or not enemy:IsHostileTowardsPlayer()or not enemy:IsTargetable()then return false end
 local actor=enemy:GetActor()
 return valid(board)and not board.bIsDead and valid(actor)and actor:GetWorld():GetFullName()==worldName and distance(loc(actor),anchor)<=leash*100
end
local function targetFor(m,enemies)
 local anchor=playerPoint or loc(player)
 -- The departure detector owns retreat. Coen crossing a second distance
 -- boundary must not replace an opponent still engaged with this companion.
 local current=m.board:GetTarget()
 if eligible(current,anchor,30)or (m.stub:IsInCombat()or m.board.Combat.bInCombat)and eligible(current,loc(m.actor),40)then return current end
 if eligible(m.combatTarget,anchor,30)then return m.combatTarget end
 local aimed=playerStub.AIBoard:GetTarget()
 local assigned={}
 for _,other in pairs(members)do if other~=m and other.mode=='follow'and not other.returning then
  local target=other.combatTarget
  if ready(other)then local active=other.board:GetTarget();if eligible(active,anchor,30)then target=active end end
  if valid(target)then local key=target:GetFullName();assigned[key]=(assigned[key]or 0)+1 end
 end end
 local candidates,seen={},{};local origin=loc(m.actor)
 local function consider(enemy)
  if eligible(enemy,anchor,25)then
   local key=enemy:GetFullName();if seen[key]then return end;seen[key]=true
   local target=enemy.AIBoard:GetTarget()
   if same(enemy,aimed)or enemy:IsInCombat()or same(target,playerStub)or same(target,m.stub)then
    candidates[#candidates+1]={target=enemy,key=key,distance=distance(loc(enemy:GetActor()),origin),assigned=assigned[key],attackingPlayer=same(target,playerStub),aimed=same(enemy,aimed)}
   end
  end
 end
 consider(aimed)
 for i=1,math.min(#enemies,64)do consider(enemies[i])end
 return Combat.initialTarget(candidates)
end
local function combatController(m)
 if m.combat then return m.combat end
 m.combat=Combat.new({
  settleMs=500,retryMs=3000,prepareTimeoutMs=12000,
  enter=function(nativeCombat)
   releaseFormation(m)
   if not ready(m)or not nativeCombat and m.board:HasAnyUnbreakableActiveAction()then return false end
   releaseHold(m)
   if not ready(m)then return false end
   local following=m.board.Follower.bFollowerModeEnabled
   m.board.Follower.bFollowerModeEnabled=false
   m.combatFollowerLease=m.combatFollowerLease or {}
   if not AI.combatFollower(m.stub,m.board,m.combatFollowerLease)then return false end
   if following and not nativeCombat and not m.board:HasAnyUnbreakableActiveAction()then m.board:StopAllActions()end
   m.stowState=nil
   combatPose(m,nativeCombat)
   -- An already-running native fight owns equipment too. Only the explicit
   -- preparation path below repairs missing inventory/claw setup.
   return ready(m)and true or false
  end,
  travel=function(enabled)
   releaseCombatMovement(m)
   if not ready(m)then return end
   local nativeFollow=enabled and not ownsFormation(m)
   if m.board.Follower.bFollowerModeEnabled~=nativeFollow then m.board.Follower.bFollowerModeEnabled=nativeFollow end
   if enabled then m.board.Follower.bIsPlayerInFollowArea=true;m.board.Follower.bReturnToAP=false end
  end,
  maintain=function()
   if ready(m)then
    -- Native transitions can re-enable follower mode during a fight. Maintain
    -- this ownership flag without stopping actions or replaying the intro.
    if m.board.Follower.bFollowerModeEnabled then m.board.Follower.bFollowerModeEnabled=false end
     m.combatFollowerLease=m.combatFollowerLease or {}
     AI.combatFollower(m.stub,m.board,m.combatFollowerLease)
     AI.ownedDamageBranch(m.stub,m.board)
     releaseFollowPace(m)
   end
  end,
  target=function()
   local target=m.combatTarget
   if not ready(m)then return false end
   local nativeOwns=(m.stub:IsInCombat()or m.board.Combat.bInCombat)and same(m.board:GetTarget(),target)
   if not eligible(target,nativeOwns and loc(m.actor)or loc(player),nativeOwns and 40 or 30)then return false end
   -- Former villains can share a faction with Coen's enemies. Friendship with
   -- Coen alone does not make them willing to attack that faction.
   local forced=m.board:GetForcedTarget()
   if valid(forced)and not same(forced,m.issuedTarget)then return false end
   -- The hint bootstraps entry. Once native AI has an eligible opponent,
   -- release our lease instead of forcing a target every three seconds.
   if nativeOwns then
    if valid(forced)and same(forced,m.issuedTarget)then m.board:SetForcedTarget(nil,0.0)end
    m.issuedTarget=nil
    return true
   end
   if not enemyPair(m,m.stub,target)or not enemyPair(m,target,m.stub)then return false end
   if not valid(forced)or same(forced,m.issuedTarget)then
    m.board:SetForcedTarget(target,8.0);m.issuedTarget=target
   end
   -- This also registers the enemy in native perception/combat bookkeeping.
   -- Its native implementation requires BOTH stubs and boards to be live.
   if not same(target,m.instigator)then
    if not ready(m)or not AI.board(target)then return false end
    combatLib:SetCombatInstigator(m.stub,target);m.instigator=target
    -- SetCombatInstigator uses bKeep=true for NPC targets. Reapply our owned
    -- temporary pair relation; restoreEnemies returns its old value on exit.
    if not ready(m)or not AI.board(target)then return false end
    m.stub:SetAttitudeTowards(target,3,false)
   end
   return true
  end,
  prepare=function()
   if not ready(m)or m.board:HasAnyUnbreakableActiveAction()then return false end
   local ok=combatEquipment(m);m.combatEntryNote=m.equipmentNote
   return ok and ready(m)and not m.board:HasAnyUnbreakableActiveAction()
  end,
  start=function()
   local accepted,reason=AI.startCombat(combatLib,m.stub,m.board,m.combatTarget)
   m.combatEntryNote=reason
   log(m.name..' combat entry: '..tostring(accepted)..'; '..reason..'; enemy='..(valid(m.combatTarget)and m.combatTarget:GetFullName()or 'unloaded'))
   return accepted
  end,
  inhibit=function(first)
   releaseCombatMovement(m)
   if not ready(m)then return end
   m.board.bCanFight=false;if first then m.board.Follower.bFollowerModeEnabled=false end
   if same(m.board:GetForcedTarget(),m.issuedTarget)then m.board:SetForcedTarget(nil,0.0)end
   m.issuedTarget=nil
  end,
  stop=function(follow)
   return AI.stopCombatForTravel(combatLib,m.stub,m.board,follow)
  end,
  clear=function()
   if not m.retreatState then restoreEnemies(m)end
   if ready(m)and same(m.board:GetForcedTarget(),m.issuedTarget)then m.board:SetForcedTarget(nil,0.0)end
   m.issuedTarget=nil;m.instigator=nil
  end,
 })
 return m.combat
end
local function apply(m,op)
 if op=='follow'then
  releaseHold(m);m.mode='follow';m.lastTick=nil;m.lastFollowTick=nil
  return true,'Following Coen; native combat assistance enabled'
 end
 if op=='stop'then
  releaseFollowPace(m);m.mode='stop';m.lastTick=nil
  return true,'Waiting here until you ask me to follow'
 end
 return false,'Unsupported companion action'
end
function M.conversationAction(actor,name)
 for _,m in pairs(members)do if same(m.actor,actor)then
  if not ready(m)or m.board.bIsDead or m.stub:IsInCinematicMode()then return false,'Companion is unavailable' end
  local op=name=='Follow'and 'follow'or name=='Stop Walking'and 'stop'
  if not op then return nil end
  m.talkFollowing=op=='follow'
  return apply(m,op)
 end end
 return nil -- World NPC actions use the ordinary conversation adapter.
end
function M.view()
 local rows={};for _,m in pairs(members)do rows[#rows+1]={id=m.id,name=m.name,status=m.status,ordinal=m.ordinal or 0,characterId=m.characterId,loading=m.loading~=nil or m.created~=nil,defeated=m.defeated==true}end
 table.sort(rows,function(a,b)return a.ordinal<b.ordinal end)
 local pending={};for _,c in ipairs(nativeCommands)do if c.op=='spawn' then pending[#pending+1]={id=c.request,characterId=c.id}end end
 local history={};for _,s in ipairs(summons)do history[#history+1]={id=s.id,member=s.member,phase=s.phase,message=s.message}end
 return {members=rows,characters=Config.characters,note=note,error=lastFault,queued=#pending,pending=pending,summons=history,epoch=epoch}
end
function M.enqueue(op,id)
 assert(op=='spawn'or op=='dismiss'or op=='dismiss_all','Unknown party operation');assert(#nativeCommands<64,'Please wait for queued commands')
 local request
 if op=='spawn' then
  assert(byId[id],'Unknown companion');nativeSequence=nativeSequence+1
  request='p'..string.format('%x',os.time())..string.format('%x',nativeSequence)
  summons[#summons+1]={id=request,member=request,phase='queued',message='Waiting to begin loading'}
 end
 nativeCommands[#nativeCommands+1]={op=op,id=id,request=request};lastFault=nil;return request
end
local function nativeCommand(now,selected)
 local c=table.remove(nativeCommands,1);if not c then return end
 if c.op=='spawn' then
  local ok,why=pcall(spawn,c.id,now,c.request)
  if not ok then
   for _,s in ipairs(summons)do if s.id==c.request then s.phase='failed';s.message=clean(why);break end end
   lastFault=clean(why);log('Summon failed: '..lastFault)
  end
 elseif c.op=='dismiss_all'then for _,m in pairs(members)do assert(not same(m.actor,selected),'Close conversation first');dismiss(m,'Dismissed')end
 else local m=assert(members[c.id],'Companion no longer present');assert(not same(m.actor,selected),'Close conversation first');dismiss(m,'Dismissed')end
end
local function command(now,selected)
 local text=read('companions-command.tsv',16385);if #text>16384 then return end
 local header,wire=text:match('^([^\n]*)\n(.*)$');if not header then return end
 local p=split(header,'\t')
 if #p~=7 or p[1]~='CMD'or p[2]~=epoch or not p[4]:match('^p%x+$')or p[4]==lastCommand then return end
 if not tonumber(p[3])or math.abs(os.time()-tonumber(p[3]))>60 then return end
 lastCommand=p[4]
 lastFault=nil
 local ok,why=pcall(function()
  local op,id,value=p[5],p[6],p[7]
  if pendingWorldParty then
   if op=='spawn'then
    assert(byId[id],'Unknown companion');nativeCommands[#nativeCommands+1]={op='spawn',id=id,request=p[4]}
    summons[#summons+1]={id=p[4],member=p[4],phase='queued',message='Waiting for world travel to finish'};return 'Spawn queued'
   elseif op=='dismiss_all'then
    pendingWorldParty.entries={}
    for _,m in pairs(members)do assert(not same(m.actor,selected),'Close the conversation before dismissing its companion')end
    local old={};for _,m in pairs(members)do old[#old+1]=m end;for _,m in ipairs(old)do dismiss(m,'Dismissed')end
    return 'Party dismissed'
   end
   for i,saved in ipairs(pendingWorldParty.entries)do if saved.id==id then
    if op=='dismiss'then table.remove(pendingWorldParty.entries,i);return 'Dismissed'end
    if op=='follow'or op=='stop'then saved.mode=op;return op=='follow'and 'Following player'or 'Waiting here'end
   end end
  end
  if op=='spawn'then spawn(id,now,p[4]);return 'Spawn requested'end
  if op=='dismiss_all'then
   for _,m in pairs(members)do assert(not same(m.actor,selected),'Close the conversation before dismissing its companion')end
   for _,m in pairs(members)do dismiss(m,'Dismissed')end;return 'Party dismissed'
  end
  local m=assert(members[id],'Companion is not spawned')
  assert(not same(m.actor,selected),'Close the conversation before changing this companion')
  if op=='dismiss'then dismiss(m,'Dismissed');return 'Dismissed'end
  assert(ready(m),'Companion is spawning or its AI has unloaded')
  assert(not m.stub:IsInCinematicMode()and not m.board.bIsDead,'Companion is unavailable')
  if op=='follow'or op=='stop'then
   local accepted,message=apply(m,op);assert(accepted,message);return message
  end
  error('Unsupported command')
 end)
 ack={p[4],ok and 'ok'or 'failed',clean(why)};log(ack[3])
end
local function update(m,now,enemies,selected)
 m.now=now
 if travelKind then m.travelEpoch=travelEpoch end
 if m.formationLease and m.formationLease.owned and (not ready(m)or m.board.bIsDead or m.stub:IsInCombat()or m.board.Combat.bInCombat or m.stub:IsInCinematicMode()or m.board:HasAnyUnbreakableActiveAction())then releaseFormation(m)end
 if m.fault then return end
 if m.defeated or ready(m)and m.board.bIsDead then
  if not m.defeated then releaseCombatMovement(m);releaseTravelIdle(m);releaseFollowPace(m);m.defeated=true end
  local battle=partyEncounterActive
  for _,other in pairs(members)do if other~=m and ready(other)and not other.board.bIsDead and other.stub:IsInCombat()then battle=true;break end end
  m.status=battle and 'Fallen · waiting for combat to end'or 'Fallen · recovering'
  if Tuning.canRespawn(m,now,battle,true,Settings.respawnDelay)then
   if same(m.actor,selected)and beforeReset then beforeReset()end
   local id,character,ordinal=m.id,m.characterId,m.ordinal
   dismiss(m,'Returning after combat');spawn(character,now,id);members[id].ordinal=ordinal;Recovery.layout(members)
  end
  return
 end
 if not same(m.actor,selected)and (not ready(m)or not m.board.bIsDead and not m.stub:IsInCinematicMode()and not m.board.bMainBehaviorSuspended)then measured('spawn anchor '..m.name,syncSpawnAnchor,m,now)end
 if m.loading then pollLoading(m,now);return end
 if not m.actor then pollSpawn(m,now);return end
 if not ready(m)then if measured('reconnect '..m.name,reconnect,m,now)=='replace'then replaceMissingMember(m,now)end;return end
 if m.missingAt then if measured('reconnect '..m.name,reconnect,m,now)=='replace'then replaceMissingMember(m,now)end;return end
 if m.stableSince and now-m.stableSince>=10000 then m.reconnectAttempts=nil;m.stableSince=nil;m.candidateKey=nil;m.candidateAt=nil end
 if m.board.bIsDead then releaseCombatMovement(m);releaseTravelIdle(m);m.defeated=true;m.status='Defeated';return end
 if m.playerEpoch~=playerEpoch then friendly(m,m.stub,playerStub);friendly(m,playerStub,m.stub);m.playerEpoch=playerEpoch end
 local allegianceBlocked=Tuning.guardAllegiance(m,playerStub,ownedStubs,now)
 if allegianceBlocked then
  -- Stop an acquired friendly target even if a conversation normally owns
  -- this tick. The native exit adapter still waits for unbreakable actions.
  m.board.bCanFight=false
  if not m.stub:IsInCinematicMode()and not m.board.bMainBehaviorSuspended then
   combatController(m):tick({now=now,allowed=false,nativeCombat=m.stub:IsInCombat()or m.board.Combat.bInCombat,
    busy=m.board:HasAnyUnbreakableActiveAction(),follow=m.mode=='follow'})
  end
  m.status='Restoring allegiance';return
 end
 if same(m.actor,selected)and not m.talkFollowing then releaseCombatMovement(m);releaseFollowPace(m);m.status='In conversation';m.conversationAt=m.conversationAt or now;return end
 if m.stub:IsInCinematicMode()or m.board.bMainBehaviorSuspended and not m.hold then
  releaseCombatMovement(m);releaseTravelIdle(m);releaseFollowPace(m);releaseHold(m);restoreRetreat(m);restoreEnemies(m);m.status='Native scene owns AI';m.conversationAt=m.conversationAt or now;return
 end
 -- Following, retreat distance and native exit acknowledgement are cheap and
 -- run at 250 ms; enemy discovery remains shared and throttled to 750 ms.
 m.lastTick=now;m.conversationAt=nil
 if not m.lastStats or now-m.lastStats>=1500 then
  m.lastStats=now;stats(m)
  local ok,why=pcall(function()
   Protection.mark(m,playerStub)
   if Tuning.apply(m,playerStub)then Damage.restore(m.stub,m.board,m.damageTuning)end
   local accepted,message=Damage.apply(m.stub,m.board,m.damageTuning,Settings.values.DamagePercent/100)
   m.damageNote=message;if not accepted then error(message)end
  end)
  if not ok then m.detail='Tuning unavailable: '..tostring(why)end
 end
 if now-(m.lastAbilityScan or 0)>10000 then m.lastAbilityScan=now;refreshAbilities(m)end
 local a,p=loc(m.actor),playerPoint or loc(player)
 local dx,dy=p.X-a.X,p.Y-a.Y;local gap=math.sqrt(dx*dx+dy*dy);m.followGap=gap;m.playerGap=gap
 local nativeCombat=m.stub:IsInCombat()or m.board.Combat.bInCombat
 local manager=combatController(m)
 local nativeTarget=m.board:GetTarget()
 if eligible(nativeTarget,p,2000)then
  m.fightPoint=loc(nativeTarget:GetActor());m.fightPointAt=now
 end
 if nativeCombat or manager.accepted then m.encounterAt=now end
 local fightKnown=m.fightPointAt and now-m.fightPointAt<15000
 local velocity=playerVelocity or {X=0,Y=0}
 local origin=(fightKnown and m.fightPoint)or a
 local ex,ey=p.X-origin.X,p.Y-origin.Y;local enemyGap=math.sqrt(ex*ex+ey*ey)
 local danger=math.min(threatDistance or math.huge,enemyGap)
 local awaySpeed=enemyGap>1 and (velocity.X*ex+velocity.Y*ey)/enemyGap or 0
 local companionAwaySpeed=gap>1 and (velocity.X*dx+velocity.Y*dy)/gap or 0
 local wasReturning=m.returning
 if travelDiscontinuity and m.repositionEpoch~=travelEpoch then Recovery.repositioning(m,true);m.repositionEpoch=travelEpoch end
 Recovery.retreat(m,{follow=m.mode=='follow',encounter=m.encounterAt and now-m.encounterAt<15000,now=now,gap=gap,spacing=m.followSpacing,speed=playerSpeed or 0,awaySpeed=awaySpeed,combat=nativeCombat,threatDistance=danger,fightDistance=enemyGap,fightKnown=fightKnown==true,x=p.X,y=p.Y,partyDeparture=partyDeparture,companionAwaySpeed=companionAwaySpeed})
 if Recovery.rejoinBattle(m,{allowed=m.mode=='follow'and manager.phase=='travel'and not nativeCombat,now=now,gap=gap,spacing=m.followSpacing,
  target=playerBattle and playerBattle.key,targetGap=playerBattle and playerBattle.gap or math.huge,speed=playerSpeed or 0,targetAwaySpeed=playerBattle and playerBattle.awaySpeed or math.huge})then
  m.combatTarget=nil;m.fightPoint=playerBattle.point;m.fightPointAt=now
  log(m.name..' rejoined the player battle')
 end
 if (wasReturning==true)~=(m.returning==true)then log(m.name..(m.returning and ' regroup requested'or ' regroup released')..'; player-to-enemy='..math.floor(enemyGap/100)..'m; player-to-companion='..math.floor(gap/100)..'m')end
 local suppressed=m.returning or now<(m.noEngageUntil or 0)or m.mode=='stop'
 retreatSensing(m,suppressed,enemies)
 if not ready(m)then return end
 -- Reach the party before accepting a NEW fight. Existing native combat keeps
 -- its own movement until the retreat detector requests a clean exit.
 local joiningParty=manager.phase=='travel'and not nativeCombat and gap>math.max(1400,(m.followSpacing or 250)+800)
 local canFight=m.combatDefinition and m.mode=='follow'and not suppressed and not joiningParty
 if canFight and manager.phase~='leaving'and not m.board.bCanFight then m.board.bCanFight=true end
 if not canFight and m.board.bCanFight then m.board.bCanFight=false end
 local target=canFight and targetFor(m,enemies)or nil
 local forced=m.board:GetForcedTarget()
 if canFight and valid(forced)and not same(forced,m.issuedTarget)and eligible(forced,p,30)then target=forced end
 m.combatTarget=target
 local phase=manager:tick({now=now,allowed=canFight==true,key=target and target:GetFullName()or nil,nativeCombat=nativeCombat,busy=m.board:HasAnyUnbreakableActiveAction(),follow=m.mode=='follow',encounterActive=partyEncounterActive})
 if not ready(m)then return end
 if ((m.archetype or m.characterId)=='brencis'or (m.archetype or m.characterId)=='xanthe')and now>=(m.nextActivitySample or 0)then
  m.nextActivitySample=now+1000
  m.activityHistory=m.activityHistory or {}
  m.activityHistory[#m.activityHistory+1]=tostring(now)..' '..phase..'\n'..Engagement.combatActivity(m.stub,m.board)
  if #m.activityHistory>180 then table.remove(m.activityHistory,1)end
  if now>=(m.nextActivityWrite or 0)then
   m.nextActivityWrite=now+4000
   write('companion-activity-'..m.id..'.txt',m.name..'\n'..table.concat(m.activityHistory,'\n---\n'))
  end
 end
 if phase=='preparing'then m.status='Joining combat'
 elseif phase=='combat'then m.status=nativeCombat and 'Fighting' or 'Joining combat';combatMovement(m)
 elseif phase=='leaving'then m.status=m.returning and 'Breaking away to follow you'or 'Finishing combat'
 else
  if m.mode=='stop'then
   releaseFollowPace(m);travelPose(m,false)
   if not m.hold then m.hold=Engagement.begin(m.actor,log)end
   m.status='Waiting for you'
  else
   releaseHold(m)
   m.status=m.returning and 'Catching up to you'or 'Following'
   if target then m.status=phase=='declined'and 'Following / combat unavailable'or 'Following / joining fight'end
   followMovement(m,now);measured('catchup '..m.name,catchup,m,now)
  end
 end
 if (not lastDiagnosticTick or now-lastDiagnosticTick>=1000)and (m.diagnosticPhase~=phase or now-(m.lastDiagnostic or 0)>=15000)then
  lastDiagnosticTick=now;m.diagnosticPhase=phase
  m.lastDiagnostic=now
  local ok,report=pcall(measured,'diagnostic '..m.name,Engagement.inspect,m.actor)
  if ok then
   local reaction='unavailable';pcall(function()reaction=m.board:GetReactionSituationTag().TagName:ToString()end)
   report=report..'\nmanager='..phase..'\ncombatStarts='..m.combat.attempts..'\nentry='..tostring(m.combatEntryNote)..'\nequipment='..tostring(m.equipmentNote)..'\ngrants='..tostring(m.grantCount)..'\nstance='..tostring(m.poseNote)..'\ncatchup='..tostring(m.followRunning)..'\nplayerGap='..tostring(m.followGap)..'\nlastCatchup='..tostring(m.lastCatchup)..'\ncatchupNote='..tostring(m.catchupNote)..'\nstow='..tostring(m.stowNote)..'\ndamageTuning='..tostring(m.damageNote)..'\ndamageBranch='..tostring(m.damageBranch)..'\nfollowSpacing='..tostring(m.followSpacing)..'\nformationMoves='..tostring(m.formationMoves)..'\nlaneRetryAt='..tostring(m.laneRetryAt)..'\nreturning='..tostring(m.returning)..'\nnoEngageUntil='..tostring(m.noEngageUntil)..'\nstopRetryAt='..tostring(m.combat.nextStop)..'\ncombatFlag='..tostring(m.board.Combat.bInCombat)..'\nreaction='..reaction..'\nthreatDistance='..tostring(danger)..'\nfightDistance='..tostring(enemyGap)..'\nplayerSpeed='..tostring(playerSpeed)..'\nwake='..tostring(m.wakeNote)..'\nanchor='..tostring(m.anchorNote)..'\npaceProfileLeased='..tostring(m.paceLease and m.paceLease.handle)..'\ndeparture='..tostring(m.departure and m.departure.kind)..'\nsensingSuppressed='..tostring(m.retreatState and m.retreatState.sensingSuppressed)..'\n'
   report=report..'travelIdle='..tostring(m.idleNote)..'\nformationPending='..tostring(m.formationPending)..'\nformationEpoch='..tostring(m.formationEpoch)..'\nreturnKind='..tostring(m.returnKind)..'\nretreatHostilityRepairs='..tostring(m.retreatRepairs)..'\n'
   report=report..'combatMovement='..tostring(m.combatMovementNote)..'\ncombatMovementLeased='..tostring(m.combatMovement and m.combatMovement.handle~=nil)..'\npartyDeparture='..tostring(partyDeparture)..'\n'
   report=report..'combatFollowerIdentityReleased='..tostring(m.combatFollowerLease and m.combatFollowerLease.owned==true)..'\nguardAreasIgnored='..tostring(m.guardAreasIgnored)..'\n'
   write('companion-combat-'..m.id..'.txt',report)
   m.combatHistory=m.combatHistory or {};m.combatHistory[#m.combatHistory+1]=report
   if #m.combatHistory>12 then table.remove(m.combatHistory,1)end
   write('companion-history-'..m.id..'.txt',table.concat(m.combatHistory,'\n---\n'))
  end
 end
end
local function publish()
 local formation={'id\tname\tx\ty\tslotX\tslotY\tgapToSlot\tpathOwned\tpending\tlastRequest\tpathStatus\trequestAt\tretryAt\tseat'}
 local rows={'PARTY\t1\t'..epoch..'\t'..os.time()..'\t'..Config.limit,'ACK\t'..table.concat(ack,'\t'),'NOTE\t'..clean(lastFault or note)}
 local ordered={};for _,m in pairs(members)do ordered[#ordered+1]=m end
 table.sort(ordered,function(a,b)return a.ordinal<b.ordinal end)
 for _,m in ipairs(ordered)do
  -- Preserve the old column positions across helper/Lua hot reloads. Fields
  -- 12 and 17 are reserved; they no longer advertise or control powers.
  rows[#rows+1]=table.concat({'MEMBER',m.id,m.name,clean(m.status),m.mode,'native','native','native','0','0','0','',m.health and tostring(m.health)or '',m.stamina and tostring(m.stamina)or '','',m.board and valid(m.board)and m.board.bCanFight and '1'or '0','0',clean(m.detail)},'\t')
  local actor=valid(m.actor)and m.actor:GetFullName()or ''
  local gap=valid(m.actor)and valid(player)and distance(loc(m.actor),loc(player))or 999999
  local available=conversationCandidate(m)
  local a,q=m.followPosition or {},m.formationPoint or {}
  formation[#formation+1]=table.concat({m.id,clean(m.label),tostring(a.X or ''),tostring(a.Y or ''),tostring(q.X or ''),tostring(q.Y or ''),tostring(m.slotDistance or ''),tostring(ownsFormation(m)),tostring(m.formationPending),clean(m.wakeNote),tostring(m.formationPathStatus or ''),tostring(m.travelRequestAt or ''),tostring(m.formationLease and m.formationLease.retryAt or ''),tostring(m.formationSlot or '')},'\t')
  rows[#rows+1]=table.concat({'IDENTITY',m.id,m.characterId,clean(m.label),clean(actor),tostring(gap),available and m.definition.chat~=false and '1'or '0'},'\t')
 end
 for _,s in ipairs(summons)do rows[#rows+1]=table.concat({'SUMMON',s.id,s.member,s.phase,clean(s.message)},'\t')end
 rows[#rows+1]='END\t'..epoch
 write('companions-state.tsv',table.concat(rows,'\n')..'\n')
 write('companion-formation.tsv',table.concat(formation,'\n')..'\n')
end
function M.tick(pc,selected)
 local tickStarted=os.clock();Settings.poll()
 local ok,why=pcall(function()
  if not valid(pc)or not valid(pc.Pawn)then
   if next(members)then M.cleanup();worldName=nil;playerName=nil;lastGameTime=nil end
   note='Load a save to manage companions';publish();return
  end
  player=pc.Pawn
  local currentWorld=player:GetWorld():GetFullName()
  local currentPlayer=player:GetFullName()
  local now=AI.find('/Script/Engine.Default__KismetSystemLibrary'):GetGameTimeInSeconds(player)*1000
  local clockReset=lastGameTime and now<lastGameTime
  if worldName and worldName~=currentWorld then
   pendingWorldParty=resetParty('Recreating after world travel',true);epoch=tostring(tonumber(epoch)+1);lastGameTime=nil;subsystem=nil;enemyCache={};lastEnemyQuery=nil
  elseif playerName and playerName~=currentPlayer then playerEpoch=playerEpoch+1;playerStub=nil;subsystem=nil;enemyCache={};lastEnemyQuery=nil end
  worldName=currentWorld;playerName=currentPlayer
  if lastGameTime and clockReset then pendingWorldParty=resetParty('Recreating after world time reset',true);epoch=tostring(tonumber(epoch)+1);lastGameTime=nil;subsystem=nil;enemyCache={};lastEnemyQuery=nil end
  if lastGameTime and now==lastGameTime then note='Paused. Queued commands execute after unpausing.';publish();return end
  lastGameTime=now;note='Companions follow and fight automatically; native AI chooses abilities.'
  playerPoint=loc(player)
  local velocity=player:GetVelocity();playerVelocity={X=velocity.X,Y=velocity.Y};playerSpeed=math.sqrt(velocity.X^2+velocity.Y^2)
  travelKind,travelEpoch,travelDiscontinuity=Recovery.travelTransition(travelState,{now=now,world=currentWorld,player=currentPlayer,point=playerPoint,speed=playerSpeed,reset=clockReset})
  local heading=playerSpeed>100 and math.deg(math.atan(velocity.Y,velocity.X))or travelHeading or player:K2_GetActorRotation().Yaw

  local camera=pc.PlayerCameraManager
  if valid(camera)then cameraPoint=camera:GetCameraLocation();cameraYaw=camera:GetCameraRotation().Yaw else cameraPoint=nil;cameraYaw=nil end
  if not AI.board(playerStub)or not same(playerStub:GetActor(),player)then playerStub=stub(player)end
  if not AI.board(playerStub)then note='Waiting for player AI';publish();return end
  command(now,selected)
  cancelPendingWorldDismissals()
  restoreWorldParty(now)
  if not valid(combatLib)then combatLib=AI.find('/Script/RebelAI.Default__RebelAICombatBlueprintFunctionLibrary')end
  if not pendingWorldParty then nativeCommand(now,selected)end
  if next(members)then Protection.ensure(player,playerStub)end
  local enemies={};local needsEnemies=false
  for _,m in pairs(members)do if valid(m.actor)and m.mode=='follow'then needsEnemies=true end end
  if needsEnemies then
   if not valid(subsystem)then subsystem=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary'):GetWorldSubsystem(player,AI.find('/Script/RebelAI.RebelAISubsystem'))end
   if not lastEnemyQuery or now<lastEnemyQuery or now-lastEnemyQuery>=750 then
    enemyCache={};if valid(subsystem)then subsystem:GetEnemyStubsInRange(playerStub,3000,enemyCache)end;lastEnemyQuery=now
   end
   enemies=enemyCache
  end
  threatDistance=math.huge;threatPoint=nil;threatTarget=nil
  for i=1,math.min(#enemies,64)do
   local enemy=enemies[i]
   if eligible(enemy,playerPoint,30)and (enemy:IsInCombat()or same(enemy.AIBoard:GetTarget(),playerStub))then
    local p=loc(enemy:GetActor());local gap=distance(p,playerPoint)
    if gap<threatDistance then threatDistance=gap;threatPoint=p;threatTarget=enemy end
   end
  end
  playerBattle=nil
  local aimed=playerStub.AIBoard:GetTarget()
  if not eligible(aimed,playerPoint,12)then aimed=threatTarget end
  if eligible(aimed,playerPoint,12)and (playerStub:IsInCombat()or aimed:IsInCombat())then
   local q=loc(aimed:GetActor());local dx,dy=playerPoint.X-q.X,playerPoint.Y-q.Y
   local gap=math.sqrt(dx*dx+dy*dy)
   playerBattle={key=aimed:GetFullName(),point=q,gap=gap,awaySpeed=gap>1 and (playerVelocity.X*dx+playerVelocity.Y*dy)/gap or 0}
  end
  partyDeparture=Recovery.partyDeparture(members,now)
  -- A leftover enemy combat flag is not evidence that our encounter is still
  -- running. Snapshot the whole party before updating any individual member.
  partyEncounterActive=playerStub:IsInCombat()
  for _,m in pairs(members)do
   if ready(m)and not m.board.bIsDead and (m.stub:IsInCombat()or m.board.Combat.bInCombat)then partyEncounterActive=true;break end
  end
  if not partyEncounterActive then
   for i=1,math.min(#enemies,64)do
    local enemy=enemies[i]
    if eligible(enemy,playerPoint,30)then
     local target=enemy.AIBoard:GetTarget()
     local other=valid(target)and ownedStubs[target:GetFullName()]
     if same(target,playerStub)or other and ready(other)and not other.board.bIsDead and same(other.stub,target)then partyEncounterActive=true;break end
    end
   end
  end
  -- Read each live position once for the shared space coordinator. A stationary
  -- conversation/scene/combat participant never gets an avoidance MoveTo.
  partyPositions={}
  for _,m in pairs(members)do if ready(m)then
   local p=loc(m.actor);p.id=m.id;p.ordinal=m.ordinal;p.radius=m.capsuleRadius or 55
   p.position={X=p.X,Y=p.Y,Z=p.Z};p.slot=m.formationSlot;p.pitch=m.formationPitch
   p.locked=m.mode~='follow'or same(m.actor,selected)and not m.talkFollowing or m.hold~=nil
    or m.stub:IsInCombat()or m.board.Combat.bInCombat or m.stub:IsInCinematicMode()
    or m.board.bMainBehaviorSuspended or m.board.bIsDead or m.board:HasAnyUnbreakableActiveAction()
    or m.combat and m.combat.phase~='travel'
   partyPositions[#partyPositions+1]=p
  end end
  formation:update(partyPositions,playerPoint,heading,playerSpeed,now,members)
  travelHeading=formationFrame.yaw
  local ordered;ordered,updateCursor=Recovery.updateOrder(members,updateCursor)
  local loadBudget={}
  for _,m in ipairs(ordered)do
   local pending=m.loading~=nil or not m.actor and m.actionPath~=nil
   if not pending or Recovery.admitLoadStep(loadBudget,os.clock())then
   local good,err=pcall(update,m,now,enemies,selected)
   if not good then
    pcall(releaseFormation,m)
    m.status='Adapter error';m.detail=clean(err);m.fault=true
    lastFault=m.name..': '..m.detail;log(lastFault);pcall(write,'companion-error.txt',os.date()..'\n'..lastFault..'\n'..(m.lastSpawnText or ''))
    local stopped,stopError=pcall(dismiss,m,'Adapter error: '..m.detail)
    if not stopped then m.detail=m.detail..'; cleanup: '..clean(stopError)end
   end
   end
  end
  publish()
 end)
 if not ok then note='Companion adapter: '..clean(why);log(note);pcall(publish)end
 local elapsed=(os.clock()-tickStarted)*1000
 slowestTick=math.max(slowestTick,elapsed)
 M.tickMax=math.max(M.tickMax or 0,elapsed);M.tickCount=(M.tickCount or 0)+1;M.tickTotal=(M.tickTotal or 0)+elapsed
 if os.time()~=(M.lastPerf or 0)and os.time()%5==0 then
  M.lastPerf=os.time();pcall(write,'companion-performance.txt',os.date()..'\nticks='..M.tickCount..'\naverageMs='..M.tickTotal/M.tickCount..'\nmaxMs='..M.tickMax..'\nlastMs='..elapsed..'\nsessionMaxMs='..slowestTick..'\nslowWork='..table.concat(slowWork,'\n')..'\n')
  M.tickCount=0;M.tickTotal=0;M.tickMax=0
 end
end
return M
