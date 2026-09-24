-- Game-thread adapter for horde-owned population spawns. No party state, CDO,
-- shared faction default, or campaign pawn is changed by this module.
local Native=require('companion_native')
local AI=require('ai_state')

local M={}
local stageActor
local handles={}
local queue={}
local active
local lastActivation
local valid,same=AI.valid,AI.same
local kismet='/Script/Engine.Default__KismetSystemLibrary'
local pawnClass='/Script/Engine.Pawn'
local spawnerClass='/Script/Dawnwalker.DogwoodPopulationSimpleSpawner'

local function currentPlayer(pc)
 return valid(pc)and valid(pc.Pawn)and pc.Pawn or nil
end
local function worldOf(actor)
 local world=valid(actor)and actor:GetWorld()
 return valid(world)and world:GetFullName()or nil
end
local function now(player)
 return AI.find(kismet):GetGameTimeInSeconds(player)*1000
end
local function owned(h)
 return type(h)=='table'and handles[h]==true
end
local function removeQueued(h)
 for i=#queue,1,-1 do if queue[i]==h then table.remove(queue,i)end end
 if active==h then active=nil end
end
local function stopOwner(h)
 if not h.actionPath then return true end
 local action=h.actionPath
 -- Clear the local lease only after the bridge confirms it stopped that exact
 -- owner. A failed stop remains retryable on a later destroy/cleanup call.
 local result,why=Native.stop(action)
 if result then h.actionPath=nil;h.spawner=nil;return true end
 -- Companion world reset may already have called the bridge's global stopall.
 -- This action was obtained from our successful spawn, so absence now means
 -- the bridge has released that owner and there is nothing left to stop.
 if why=='Action is not owned by the companion bridge'then
  h.actionPath=nil;h.spawner=nil;return true
 end
 return false,why
end
local function fail(h,reason)
 h.error=tostring(reason or 'Population spawn failed')
 h.phase='failed'
 removeQueued(h)
 local ok,stopped,why=pcall(stopOwner,h)
 if not ok then h.error=h.error..'; cleanup: '..tostring(stopped)
 elseif not stopped then h.error=h.error..'; cleanup: '..tostring(why)end
 return h.phase,nil,nil,h.error
end
local function livePlayer(h)
 local player=currentPlayer(h.pc)
 return player and worldOf(player)==h.world and player or nil
end
local function loadedClass(path)
 return path and Native.loadedClass(path)or nil
end
local function advanceLoad(h,player)
 local path=h.loadPath
 if not path then
  if h.stage=='ai'then h.stage='reactions';h.loadPath=h.reactionsPath
  elseif h.stage=='reactions'then h.stage='ready';h.loadPath=nil
  else return fail(h,'Missing required class path')end
  return h.phase,nil,nil,h.stage
 end
 local class=loadedClass(path)
 if not valid(class)then
  if h.requested~=path then
   local result,why=Native.requestClass(player,path)
   if not result then return fail(h,why)end
   h.requested=path
  end
  return h.phase,nil,nil,h.stage
 end
 if h.stage=='character'then
  h.npcClass=class
  local info,why=Native.inspect(class:GetCDO())
  if not info then return fail(h,why)end
  h.pawnPath=Native.exportedPath(info.pawnClass)
  h.aiPath=Native.exportedPath(info.aiClass)
  h.reactionsPath=Native.exportedPath(info.reactionsClass)
  if not h.pawnPath then return fail(h,'Definition has no pawn class')end
  h.stage='body';h.loadPath=h.pawnPath
 elseif h.stage=='body'then
  h.stage='ai';h.loadPath=h.aiPath
 elseif h.stage=='ai'then
  h.stage='reactions';h.loadPath=h.reactionsPath
 elseif h.stage=='reactions'then
  h.stage='ready';h.loadPath=nil
 end
 h.requested=nil
 return h.phase,nil,nil,h.stage
end
local function beginPopulation(h,player,t)
 local npc=loadedClass(h.definition.path)
 if not valid(npc)then h.stage='character';h.loadPath=h.definition.path;h.requested=nil;return h.phase,nil,nil,h.stage end
 local ai=loadedClass(h.aiPath)
 if h.aiPath and not valid(ai)then h.stage='ai';h.loadPath=h.aiPath;h.requested=nil;return h.phase,nil,nil,h.stage end
 -- Lua can poll several handles per tick. Native activation constructs many
 -- objects, so allow only one activation in any one game-time frame.
 if lastActivation==t then return h.phase,nil,nil,'Waiting for population budget' end
 lastActivation=t
 local result,why=Native.spawn(player,npc,ai,h.position,h.yaw)
 if not result then return fail(h,why)end
 h.actionPath=Native.exportedPath(result.action)
 if not h.actionPath then return fail(h,'Native population action path missing')end
 h.phase='spawning';h.spawnAt=t
 return h.phase,nil,nil,'Population activated'
end
local function resolvePawn(h,result)
 if result.spawner then
  if h.spawner and h.spawner~=result.spawner then return nil,'Population owner changed' end
  local spawner=AI.find(result.spawner)
  if not valid(spawner)or not spawner:IsA(AI.find(spawnerClass))then return nil,'Population owner is invalid' end
  h.spawner=result.spawner
 end
 if not h.spawner then return nil end
 local found
 for path in (result.pawns or ''):gmatch('(/[^%s"\'(),=]+)')do
  local actor=AI.find(path)
  if valid(actor)and actor:IsA(AI.find(pawnClass))and worldOf(actor)==h.world then
   if found and not same(found,actor)then return nil,'Definition produced multiple pawns' end
   found=actor
  end
 end
 if not found then return nil end
 local lib=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary')
 if not valid(lib)then return nil,'AI stub library unavailable' end
 local stub=lib:GetAIStub(found)
 local board=AI.board(stub)
 if not board then return nil end
 if board.bIsDead then return nil,'Spawned pawn was dead on arrival' end
 return found,stub,board
end

-- definition: {hordeEnemy=true, category='combat',
--              path='/Game/_Dawnwalker/Combat/Enemies/..._C'}.
-- position is a prevalidated walkable {X,Y,Z}, in front of the player. The
-- controller owns placement; this adapter owns only the resulting population.
function M.create(pc,definition,position,requestId)
 assert(currentPlayer(pc),'Player is unavailable')
 assert(type(definition)=='table'and definition.hordeEnemy==true and definition.category=='combat',
  'Horde requires an explicitly catalogued combat enemy')
 assert(type(definition.path)=='string'and definition.path:match('^/Game/_Dawnwalker/Combat/Enemies/.+_C$'),'Horde definition must be an authored enemy')
 assert(type(position)=='table','Spawn position is missing')
 for _,key in ipairs({'X','Y','Z'})do
  local value=position[key]
  assert(type(value)=='number'and value==value and math.abs(value)<10000000,'Invalid spawn position')
 end
 local player=currentPlayer(pc)
 local p={X=position.X,Y=position.Y,Z=position.Z}
 local yaw=math.deg(math.atan(player:K2_GetActorLocation().Y-p.Y,player:K2_GetActorLocation().X-p.X))
 local h={pc=pc,player=player,world=assert(worldOf(player)),definition=definition,position=p,yaw=yaw,
  id=requestId,phase='queued',stage='character',loadPath=definition.path,createdAt=now(player)}
 handles[h]=true;queue[#queue+1]=h
 return h
end

-- Return phase, actor, stub, detail. Calling poll advances at most one async
-- load stage, then polls only the native action created for this handle.
function M.poll(h)
 assert(owned(h),'Unknown horde spawn handle')
 if h.phase=='failed'then return h.phase,nil,nil,h.error end
 if h.phase=='destroyed'then return h.phase,nil,nil,'Destroyed' end
 if h.phase=='spawned'then return M.status(h) end
 local player=livePlayer(h)
 if not player then return fail(h,'Player or spawn world changed')end
 local t=now(player)
 if h.phase=='queued'then
  if queue[1]~=h or active and active~=h then return h.phase,nil,nil,'Waiting for earlier spawn' end
  table.remove(queue,1);active=h;h.phase='loading'
 end
 if h.phase=='loading'then
  if t-h.createdAt>60000 then return fail(h,'Enemy asset loading timed out')end
  -- Pass already-resident dependencies in one bounded step; never wait on a load.
  for _=1,4 do
   if h.stage=='ready'then break end
   local stage=h.stage
   advanceLoad(h,player)
   if h.phase=='failed'then return h.phase,nil,nil,h.error end
   if h.stage==stage then return h.phase,nil,nil,h.stage end
  end
  if h.stage~='ready'then return h.phase,nil,nil,h.stage end
  return beginPopulation(h,player,t)
 end
 local result,why=Native.poll(h.actionPath)
 if result then
  local actor,stub,boardOrError=resolvePawn(h,result)
  if actor then
   h.actor,h.stub,h.board=actor,stub,boardOrError
   h.phase='spawned';active=nil
   local staged,why=pcall(stageActor,h)
   if not staged then return fail(h,why)end
   return h.phase,actor,stub,'Loaded and staged'
  end
  if type(stub)=='string'then return fail(h,stub)end
 elseif why~='Spawner not ready or world unloaded'then
  return fail(h,why)
 end
 if t-h.spawnAt>20000 then return fail(h,'Enemy population timed out')end
 return h.phase,nil,nil,why or 'Waiting for pawn'
end

-- Read-only state check. Dead and unloaded remain distinct from a pending
-- spawn; the controller decides when to call destroy and advance a wave.
function M.status(h)
 assert(owned(h),'Unknown horde spawn handle')
 if h.phase~='spawned'then
  return h.phase,nil,nil,{dead=false,combat=false,detached=false,reason=h.error or h.stage}
 end
 local actor,stub=h.actor,h.stub
 if h.corpse then return 'dead',actor,stub,{dead=true,combat=false,detached=false,reason='Confirmed defeat'}end
 if valid(actor)and worldOf(actor)==h.world then
  -- Dying actors can detach their AI before the death animation finishes.
  -- Read the retained board and combat component before requiring live AI.
  if valid(h.board)and h.board.bIsDead then
   return 'dead',actor,stub,{dead=true,combat=false,detached=false,reason='Native AI reports death'}
  end
  local ok,alive,health=pcall(function()
   local component=actor:GetComponentByClass(AI.find('/Script/DogwoodCombat.CombatComponentBase'))
   if valid(component)then return component:IsAlive(),component:GetHealthPercentage()end
  end)
  if ok and alive==true and type(health)=='number'and health>0 then h.wasAlive=true end
  if not h.staged and h.wasAlive and ok and alive==false and type(health)=='number'and health<=0 then
   return 'dead',actor,stub,{dead=true,combat=false,detached=false,reason='Native combat confirms defeat'}
  end
 end
 local board=AI.board(stub,h.board)
 if not valid(actor)or worldOf(actor)~=h.world or not board then
  return 'unloaded',nil,nil,{dead=false,combat=false,detached=true,reason='Pawn or AI board unloaded'}
 end
 if board.bIsDead then
  return 'dead',actor,stub,{dead=true,combat=false,detached=false,reason='Native AI reports death'}
 end
 local target=board:GetTarget()
 local combat=stub:IsInCombat()or board.Combat.bInCombat
 local player=currentPlayer(h.pc)
 local lib=valid(player)and AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary')or nil
 local playerStub=valid(lib)and lib:GetAIStub(player)or nil
 local targetIsPlayer=valid(target)and same(target,playerStub)or false
 return 'spawned',actor,stub,{dead=false,combat=combat,detached=false,
  target=valid(target)and target or nil,targetIsPlayer=targetIsPlayer,
  engagedPlayer=combat and targetIsPlayer}
end

local function factionsFor(player)
 local lib=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary')
 local subsystem=lib:GetWorldSubsystem(player,AI.find('/Script/RebelAI.RebelAISubsystem'))
 return valid(subsystem)and subsystem:GetFactionsController()or nil
end
local function playerAI(pc)
 local player=currentPlayer(pc)
 local stub=player and AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(player)
 return player,stub,AI.board(stub)
end
local function prepareEquipment(h)
 local stub,board=h.stub,AI.board(h.stub,h.board)
 if not board then return false,'Enemy AI detached during equipment setup'end
 local proxy=stub:BP_GetEquipmentProxy()
 local definition=stub:GetAIDefinition()
 if not valid(proxy)or not valid(definition)then return false,'Enemy equipment is not ready'end
 local setup=h.equipment
 if not setup or not same(setup.proxy,proxy)then
  setup={proxy=proxy,slots={}};h.equipment=setup
 end
 if setup.ready then return true end
 local function live()return AI.board(stub,board)and valid(proxy)end
 local inventory=false
 -- New-AI melee hits resolve weapons through this proxy. A sword spawned
 -- solely by CombatComponent can look correct but is absent from that lookup,
 -- so its hit returns before applying damage. Use only this pawn's inventory.
 for i=1,#definition.EquipmentSlotMapping do
  local mapping=definition.EquipmentSlotMapping[i]
  if mapping.InventorySlot.TagName:ToString()~='None'then
   local weapon=proxy:BP_GetInventoryWeaponClass(mapping.InventorySlot)
   if valid(weapon)then
    if not inventory then
     local selector=board.Weapon.TagName:ToString()
     local state={TagName=FName('RebelAI.CharacterState.Combat.Sword')}
     if selector=='None'and stub:BP_CharacterStateExist(state)then
      local mode={TagName=FName('None')};board:Temp_BP_GetCombatMode(mode)
      if mode.TagName:ToString()=='None'then board:Temp_BP_SetCombatMode({TagName=FName('RebelAI.CombatMode.Sword')})end
      if not live()then return false,'Enemy AI detached during weapon selection'end
      board:Temp_BP_SetWeapon({TagName=FName('RebelAI.Weapon.Sword')})
      if not live()then return false,'Enemy AI detached during weapon selection'end
      stub:BP_SetCharacterState(state)
     end
     if not live()then return false,'Enemy AI detached during weapon selection'end
    end
    inventory=true
    local slot=mapping.CharacterSlot.TagName:ToString()
    if not setup.slots[slot]then
     proxy:BP_EquipInventoryWeapon(mapping.CharacterSlot,mapping.InventorySlot)
     setup.slots[slot]=true
     if not live()then return false,'Enemy AI detached while equipping'end
    end
   end
  end
 end
 if not inventory then
  local npc=stub:GetNPCDefinition()
  if not valid(npc)then return false,'Enemy definition is not ready'end
  local config=npc.EnemyConfig
  local settings=AI.find('/Script/DogwoodAI.Default__DogwoodAISettings')
  if valid(config)and valid(settings)then
   -- Animals and unarmed enemies supply their own bite/claw weapon classes.
   -- Convert their authored body slots using the game's mapping, not a sword.
   config.HandToHandWeapons:ForEach(function(key,value)
    local weapon=value:get();local bodySlot=key:get()
    if valid(weapon)then settings.WeaponSlotToGenericCharacterSlotTag:ForEach(function(slotKey,slotValue)
     if slotKey:get()==bodySlot and live()then
      local tag=slotValue:get();local slot=tag.TagName:ToString()
      if not setup.slots[slot]then proxy:BP_EquipWeaponClass(tag,weapon);setup.slots[slot]=true end
     end
    end)end
   end)
  end
 end
 if not live()then return false,'Enemy AI detached while equipping'end
 setup.ready=true
 return true
end
local function restorePlayerPair(h)
 if h.playerPair and AI.board(h.playerPair.stub)and AI.board(h.stub)then
  local current=h.playerPair.stub:GetAttitudeTowards(h.stub)
  if current==h.playerPair.set then h.playerPair.stub:SetAttitudeTowards(h.stub,h.playerPair.old,false)end
 end
 h.playerPair=nil
end
stageActor=function(h)
 local actor,stub,board=h.actor,h.stub,AI.board(h.stub,h.board)
 assert(valid(actor)and board,'Enemy detached during preparation')
 local player,playerStub,playerBoard=playerAI(h.pc)
 assert(playerBoard,'Player AI unavailable during preparation')
 h.staged=true
 if not h.playerPair then h.playerPair={stub=playerStub,old=playerStub:GetAttitudeTowards(stub)}end
 h.playerPair.set=1
 playerStub:SetAttitudeTowards(stub,1,false);stub:SetAttitudeTowards(playerStub,1,false)
 local factions=factionsFor(player);assert(valid(factions),'Factions controller unavailable')
 factions:SetAttitudeTowardsPlayer(stub,1)
 -- These are disposable horde actors, never borrowed campaign/party members.
 actor:SetActorHiddenInGame(true);actor:SetActorEnableCollision(false);actor.bCanBeDamaged=false
 local combat=AI.find('/Script/RebelAI.Default__RebelAICombatBlueprintFunctionLibrary')
 if stub:IsInCombat()or board.Combat.bInCombat then combat:StopCombatBehaviors(stub,true,false)end
 assert(AI.board(stub,board),'Enemy detached while staging')
 board.bCanFight=false;board.bMainBehaviorSuspended=true;board:StopAllActions()
 local controller=actor:GetController();if valid(controller)then controller:StopMovement()end
end
function M.activate(h)
 assert(owned(h),'Unknown horde spawn handle')
 local state,actor,stub=M.status(h);local board=AI.board(stub,h.board)
 if state~='spawned'or not board then return false,'Enemy is no longer ready'end
 if not h.staged and not h.needsActivation then return true end
 local player,playerStub,playerBoard=playerAI(h.pc)
 if not playerBoard then return false,'Player AI unavailable'end
 local factions=factionsFor(player);if not valid(factions)then return false,'Factions controller unavailable'end
 board.bMainBehaviorSuspended=false;board.bCanFight=false
 local equipped,why=prepareEquipment(h)
 if not equipped then return false,why end
 factions:SetAttitudeTowardsPlayer(stub,3);stub:SetAttitudeTowards(playerStub,3,false)
 if not h.playerPair then h.playerPair={stub=playerStub,old=playerStub:GetAttitudeTowards(stub)}end
 playerStub:SetAttitudeTowards(stub,3,false);h.playerPair.set=3
 actor.bCanBeDamaged=true;actor:SetActorEnableCollision(true);actor:SetActorHiddenInGame(false)
 h.staged=false;h.needsActivation=nil
 return true
end

function M.displayName(h)
 assert(owned(h),'Unknown horde spawn handle')
 if AI.board(h.stub,h.board)then
  local ok,label=pcall(function()
   local d=h.stub:GetNPCDefinition()
   if valid(d)then return d.CharacterName:ToString()end
  end)
  if ok and type(label)=='string'and label:find('%S')then return label end
 end
 return h.definition.name
end

-- Equipment/AI initialization can replace the board after a pawn is staged.
-- Rebind only this handle's existing pawn, never search for a nearby enemy or
-- create a replacement population during combat. Limit retries to once a second.
function M.recover(h)
 assert(owned(h),'Unknown horde spawn handle')
 local state,actor,stub,info=M.status(h)
 if state~='unloaded'and not h.needsActivation then return state,actor,stub,info end
 local player=livePlayer(h)
 if not player or not valid(h.actor)or worldOf(h.actor)~=h.world then return state,actor,stub,info end
 local t=now(player)
 if t<(h.recoverAt or 0)then return 'unloaded',nil,nil,info end
 h.recoverAt=t+1000
 local library=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary')
 if not valid(library)then return 'unloaded',nil,nil,info end
 local fresh=library:GetAIStub(h.actor);local board=AI.board(fresh)
 if not board then return 'unloaded',nil,nil,info end
 if not same(fresh,h.stub)or not same(board,h.board)then
  restorePlayerPair(h)
  h.stub,h.board=fresh,board;h.instigator=nil;h.equipment=nil
  h.needsActivation=true
 end
 if board.bIsDead then return M.status(h)end
 if h.needsActivation then
  local ok,accepted=pcall(function()
   if h.staged then stageActor(h);h.needsActivation=nil;return true end
   return M.activate(h)
  end)
  if not ok or not accepted then return 'unloaded',nil,nil,{reason='AI reattachment pending'}end
 end
 return M.status(h)
end

-- Bootstrap perception once, then let the authored combat system pick attacks.
function M.engage(h,pc)
 assert(owned(h),'Unknown horde spawn handle')
 if h.staged then return false,'Waiting for the complete wave'end
 local state,actor,stub,info=M.status(h)
 if state~='spawned'then return false,state end
 local player,playerStub,playerBoard=playerAI(pc)
 if not playerBoard or worldOf(player)~=h.world then return false,'Player AI is unavailable'end
 local board=AI.board(stub,h.board)
 if not board or board.bIsDead or board.bMainBehaviorSuspended or stub:IsInCinematicMode()then return false,'Enemy AI is unavailable'end
 local equipped,why=prepareEquipment(h)
 if not equipped then return false,why end
 if info.combat and valid(info.target)and AI.board(info.target)then return true,'Native combat owns a live target'end
 if board:HasAnyUnbreakableActiveAction()then return false,'Enemy AI is busy'end
 local combat=AI.find('/Script/RebelAI.Default__RebelAICombatBlueprintFunctionLibrary')
 if not valid(combat)then return false,'Combat library unavailable'end
 if not h.instigator then
  combat:SetCombatInstigator(stub,playerStub);h.instigator=true
  if not AI.board(stub,h.board)or not AI.board(playerStub)then return false,'AI detached during perception setup'end
  stub:SetAttitudeTowards(playerStub,3,false)
 end
 local forced=board:GetForcedTarget()
 if not valid(forced)or same(forced,playerStub)then board:SetForcedTarget(playerStub,8.0)end
 if not AI.board(stub,h.board)then return false,'Enemy AI detached'end
 return AI.startCombat(combat,stub,board,playerStub)
end

-- Stop only the native action created by this handle. Stop owns its pawns and
-- unroots its spawner; no global stopall or broad actor search is used.
function M.destroy(h)
 if not owned(h)then return false,'Unknown horde spawn handle' end
 if h.phase=='destroyed'then return true end
 removeQueued(h)
 restorePlayerPair(h)
 if h.phase=='spawned'and AI.board(h.stub,h.board)and valid(h.actor)and worldOf(h.actor)==h.world then
  h.stub:RequestDespawn(true)
 end
 local ok,why=stopOwner(h)
 if not ok then return false,why end
 h.actor=nil;h.stub=nil;h.board=nil;h.phase='destroyed'
 return true
end

function M.retainCorpse(h)
 assert(owned(h),'Unknown horde spawn handle')
 h.corpse=true
 -- Keep the owned population alive so its ragdoll can settle naturally.
 restorePlayerPair(h)
end
function M.cleanup(preserveCorpses)
 local errors={}
 for h in pairs(handles)do
  local keep=preserveCorpses and h.corpse and valid(h.actor)and livePlayer(h)and same(currentPlayer(h.pc),h.player)and worldOf(h.actor)==h.world
  if h.phase~='destroyed'and not keep then
   local callOK,stopped,why=pcall(M.destroy,h)
   if not callOK then errors[#errors+1]=tostring(stopped)
   elseif not stopped then errors[#errors+1]=tostring(why)end
  end
  if h.phase=='destroyed'then handles[h]=nil end
 end
 return #errors==0,table.concat(errors,'; ')
end

return M
