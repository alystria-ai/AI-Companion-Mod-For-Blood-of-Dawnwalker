local M = {}
local AI=require('ai_state')
local valid=AI.valid
-- Native controller targets live for three seconds and may be emitted every
-- frame. 256 is a normal count at high frame rates, not evidence of corruption.
local maxHeadTargets=4096
local function stubFor(actor)
    local lib=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary')
    if valid(lib)then return lib:GetAIStub(actor)end
end
-- Capture only known reflected primitive properties. Reacquire embedded structs on
-- restoration: never retain a raw struct wrapper across actor destruction/reload.
local function change(state,get,key,value)
    local object=get();local previous=object[key]
    assert(type(previous)==type(value),'Unexpected type for '..key)
    if previous==value then return end
    state.changes[#state.changes+1]=function()
        if valid(state.actor)and (not state.stub or AI.board(state.stub,state.board))then local current=get();if current[key]==value then current[key]=previous end end
    end
    object[key]=value
end
local function restore(state)
    for i=#state.changes,1,-1 do
        local ok,e=pcall(state.changes[i]);if not ok then state.log('Restore failed: '..tostring(e))end
    end
    state.changes={}
end
-- Reflected RebelLocomotion APIs: KeepInFOV lets head/torso aim before a native
-- turn, and FaceDirection feeds the animation-driven rotation path. Never rotate
-- the capsule directly. Each push is paired with its own pop handle.
local function ownsAttentionFocus(state)
    local actor=state.controller:GetFocusActor()
    if not state.focusPoint then return AI.same(actor,state.player)end
    if valid(actor)then return false end
    local p=state.controller:GetFocalPoint();local q=state.focusPoint
    return (p.X-q.X)^2+(p.Y-q.Y)^2+(p.Z-q.Z)^2<1
end
local function sideFocus(a,p,degrees)
    local angle=math.rad(degrees);local x,y=p.X-a.X,p.Y-a.Y
    return {X=a.X+x*math.cos(angle)-y*math.sin(angle),Y=a.Y+x*math.sin(angle)+y*math.cos(angle),Z=p.Z+65}
end
-- Controller focus drives locomotion aim, but does not register a native head
-- tracking target. Ask RebelAI to build its own actor/socket tracking data;
-- capture only handles added by this call so other AI look targets stay intact.
local function headTargets(actor)
    local targets=actor.LookAtTargets
    assert(#targets<=maxHeadTargets,'Unexpected native look target count')
    local handles={}
    for i=1,#targets do
        local handle=targets[i].LookAtTargetHandle
        assert(type(handle)=='number','Invalid native look target handle')
        handles[handle]=true
    end
    return handles,#targets
end
local function releaseHeadTracking(state)
    if valid(state.actor)then
        for handle in pairs(state.headHandles or {})do
            local ok,err=pcall(function()state.actor:RemoveLookAtTarget(handle)end)
            if not ok then state.log('Head tracking restore: '..tostring(err))end
        end
    end
    state.headHandles=nil
    state.headCamera=nil
end
local function trackHead(state,held)
    -- Distant idle followers keep their more relaxed side glance. The speaking
    -- character and nearby direct-attention followers track the player's eyes.
    if not held and state.sideAngle~=0 then return end
    local now=os.clock()
    if now<(state.nextHeadCheck or 0)then return end
    state.nextHeadCheck=now+1
    local ok,err=pcall(function()
        if not AI.board(state.stub,state.board)then return end
        local camera=require('first_person_camera').gazeTarget(state.player)
        if (camera or state.headCamera)and not AI.same(camera,state.headCamera)then
            releaseHeadTracking(state);state.headReported=nil
        end
        local current,count=headTargets(state.actor)
        for handle in pairs(state.headHandles or {})do
            if current[handle]then return end
            state.headHandles[handle]=nil
        end
        if count>=maxHeadTargets then return end
        if camera then
            local result,why=require('companion_native').cameraGaze(state.actor,camera)
            local handle=result and tonumber(result.handle)
            assert(handle and handle>=0,why or 'Camera look target rejected')
            state.headHandles={[handle]=true};state.headCamera=camera
            if not state.headReported then
                state.headReported=true;state.log('Native head tracking acquired; first-person camera target, owned handle only')
            end
            return
        end
        local targetStub=stubFor(state.player)
        if not AI.board(targetStub)then return end
        state.board:AddLookAtTarget(targetStub)
        local after=headTargets(state.actor)
        state.headHandles=state.headHandles or {}
        local added=0
        for handle in pairs(after)do if not current[handle]then state.headHandles[handle]=true;added=added+1 end end
        if added>0 and not state.headReported then
            state.headReported=true;state.log('Native head tracking acquired; player face/socket target, owned handles only')
        end
        if added==0 then state.nextHeadCheck=now+5 end
    end)
    if not ok then
        state.nextHeadCheck=now+5
        if state.headError~=tostring(err)then state.headError=tostring(err);state.log('Native head tracking unavailable: '..state.headError)end
    end
end
local function releaseIdleSmile(state)
    local face=state.idleFace;state.idleFace=nil
    if face and valid(state.actor)then
        local ok,err=pcall(function()require('face_graph').restoreLayer(face)end)
        if not ok then state.log('Idle expression restore: '..tostring(err))end
    end
end
function M.takeIdleFace(state)
    -- Transfer the whole lease, including its original layer and blink clock.
    -- The conversation becomes its only writer and restores it when finished.
    if not state then return nil end
    local face=state.idleFace
    if not face or face.restored or not valid(state.actor)or not valid(face.main)or not valid(face.instance)then return nil end
    state.idleFace=nil
    return face
end
function M.canTransferAttention(state,actor)
    if not state or not state.focusOwned or not state.lookHandle or not state.rotationHandle
        or not AI.same(state.actor,actor)or state.sideAngle~=0 then return false end
    local ok,ready=pcall(function()
        local v=actor:GetVelocity()
        return valid(state.controller)and valid(state.movement)and AI.board(state.stub,state.board)~=nil and ownsAttentionFocus(state)
            and v.X*v.X+v.Y*v.Y+v.Z*v.Z<1 and state.controller:GetMoveStatus()==0
    end)
    return ok and ready
end
local function trackIdleSmile(state,held)
    if held or not state.idleSmile or state.sideAngle~=0 then return end
    local ok,err=pcall(function()
        local Face=require('face_graph')
        if not state.idleFace then
            if state.smileAttempted then return end
            state.smileAttempted=true
            local graph=Face.capture(state.actor,state.log,true)
            if not graph then return end
            state.idleFace=Face.linkSpeechLayer(graph,state.log)
            Face.beginJaw(state.idleFace,state.actor,os.time())
            state.smileStarted=os.clock()
        end
        local strength=1-math.exp(-math.max(0,os.clock()-state.smileStarted)/.5)
        local weights={CTRL_expressions_jawOpen=0}
        for _,side in ipairs({'L','R'})do
            weights['CTRL_expressions_mouthCornerPull'..side]=.21*strength
            weights['CTRL_expressions_mouthCornerUp'..side]=.075*strength
            weights['CTRL_expressions_mouthDimple'..side]=.04*strength
            weights['CTRL_expressions_eyeCheekRaise'..side]=.10*strength
        end
        Face.applyWeights(state.idleFace,weights)
    end)
    if not ok then
        releaseIdleSmile(state)
        if state.smileError~=tostring(err)then state.smileError=tostring(err);state.log('Idle expression unavailable: '..state.smileError)end
    end
end
function M.releaseAttention(state)
    if not state then return end
    releaseIdleSmile(state)
    releaseHeadTracking(state)
    local function attempt(fn)local ok,e=pcall(fn);if not ok then state.log('Attention restore: '..tostring(e))end end
    if valid(state.actor)and valid(state.movement)then
        if state.lookHandle then attempt(function()state.movement:PopLookAtMode(state.lookHandle)end)end
        if state.rotationHandle then attempt(function()state.movement:PopRotationMode(state.rotationHandle)end)end
    end
    state.lookHandle=nil;state.rotationHandle=nil
    if valid(state.actor)and valid(state.controller)and state.focusOwned then attempt(function()
        if not ownsAttentionFocus(state)then return end
        if valid(state.oldFocus)then state.controller:K2_SetFocus(state.oldFocus)
        elseif state.oldPoint then state.controller:K2_SetFocalPoint(state.oldPoint)
        else state.controller:K2_ClearFocus()end
    end)end
    state.focusOwned=false
    if state.changes then restore(state)end
end
local attentionRetry={}
function M.attend(state,actor,player,log,held,options)
    local sideAngle=options and options.sideAngle or 0
    local idleSmile=options and options.idleSmile==true or false
    local range=options and options.range or 450
    if state and (not AI.same(state.actor,actor)or not AI.same(state.player,player))then
        M.releaseAttention(state);state=nil
    end
    local key=valid(actor)and actor:GetFullName()or ''
    if not state and os.time()<(attentionRetry[key]or 0)then return nil end
    local ok,result=pcall(function()
        if not valid(actor)or not valid(player)then return false end
        local stub=state and state.stub or stubFor(actor);local board=AI.board(stub,state and state.board)
        if not board or board.bIsDead or stub:IsInCombat()or board.Combat.bInCombat or stub:IsInCinematicMode()or board:HasAnyUnbreakableActiveAction()or (board.bMainBehaviorSuspended and not held)then return false end
        local p,a=player:K2_GetActorLocation(),actor:K2_GetActorLocation()
        local velocity=actor:GetVelocity()
        if not held and ((p.X-a.X)^2+(p.Y-a.Y)^2+(p.Z-a.Z)^2>range^2 or velocity.X^2+velocity.Y^2>(state and 40 or 25)^2)then return false end
        if state then
            if not valid(state.controller)or not valid(state.movement)then return false end
            if not ownsAttentionFocus(state)then attentionRetry[key]=os.time()+2;return false end
            if state.idleSmile~=idleSmile then
                if not idleSmile then releaseIdleSmile(state)end
                state.idleSmile=idleSmile;state.smileAttempted=nil
            end
            if state.sideAngle~=sideAngle then
                state.sideAngle=sideAngle
                if sideAngle~=0 then releaseIdleSmile(state)end
                state.smileAttempted=nil
                if sideAngle==0 then state.focusPoint=nil;state.controller:K2_SetFocus(player)
                else
                    state.focusPoint=sideFocus(a,p,sideAngle);state.controller:K2_SetFocalPoint(state.focusPoint)
                    if not held then releaseHeadTracking(state)end
                end
            end
            if sideAngle~=0 then
                local q=sideFocus(a,p,sideAngle);local old=state.focusPoint
                if (q.X-old.X)^2+(q.Y-old.Y)^2+(q.Z-old.Z)^2>=50^2 then
                    state.controller:K2_SetFocalPoint(q);state.focusPoint=q
                end
            end
            trackHead(state,held)
            trackIdleSmile(state,held)
            return true
        end
        state={actor=actor,player=player,stub=stub,board=board,sideAngle=sideAngle,idleSmile=idleSmile,changes={},controller=actor:GetController(),movement=actor:GetMovementComponent(),log=log}
        assert(valid(state.controller)and valid(state.movement),'Native attention controls unavailable')
        change(state,function()return actor end,'bUseControllerRotationYaw',false)
        change(state,function()return state.movement end,'bOrientRotationToMovement',false)
        change(state,function()return state.movement end,'bUseControllerDesiredRotation',false)
        state.oldFocus=state.controller:GetFocusActor()
        if not valid(state.oldFocus)then
            local p=state.controller:GetFocalPoint()
            if type(p.X)=='number'and type(p.Y)=='number'and type(p.Z)=='number'and math.abs(p.X)<1e12 and math.abs(p.Y)<1e12 and math.abs(p.Z)<1e12 then state.oldPoint={X=p.X,Y=p.Y,Z=p.Z}end
        end
        state.focusOwned=true
        if sideAngle~=0 then
            state.focusPoint=sideFocus(a,p,sideAngle);state.controller:K2_SetFocalPoint(state.focusPoint)
        else state.controller:K2_SetFocus(player)end
        state.rotationHandle=state.movement:PushRotationMode(2,50)
        assert(type(state.rotationHandle)=='number'and state.rotationHandle>=0,'Native rotation lease rejected')
        state.lookHandle=state.movement:PushLookAtMode(4,50)
        assert(type(state.lookHandle)=='number'and state.lookHandle>=0,'Native look lease rejected')
        trackHead(state,held)
        trackIdleSmile(state,held)
        log('Native attention: KeepInFOV / FaceDirection; animation owns body turning')
        return true
    end)
    if not ok or not result then
        M.releaseAttention(state)
        if not ok then attentionRetry[key]=os.time()+5;log('Native attention unavailable: '..tostring(result))end
        return nil
    end
    return state
end
function M.canReuseHold(state)
    if not state or state.blocked or state.following or not valid(state.actor)then return false end
    local ok,ready=pcall(function()
        return AI.board(state.stub,state.board)~=nil and state.board.bMainBehaviorSuspended
            and not state.board.bIsDead and not state.stub:IsInCombat()and not state.board.Combat.bInCombat
            and not state.stub:IsInCinematicMode()and not state.board:HasAnyUnbreakableActiveAction()
            and valid(state.movement)and valid(state.controller)
    end)
    return ok and ready
end
function M.begin(actor,log,inheritedAttention)
    local state={actor=actor,changes={},log=log,attention=inheritedAttention}
    local ok,err=pcall(function()
        state.controller=actor:GetController();state.movement=actor:GetMovementComponent()
        local found,stub=pcall(stubFor,actor)
        if found and valid(stub)then
            state.stub=stub;state.board=AI.board(stub)
            if not state.board then state.blocked=true;state.reason='NPC AI is initializing or unloading';return end
        end
        if valid(state.board)then
            if state.stub:IsInCinematicMode()or state.stub:IsInCombat()or state.board.Combat.bInCombat or state.board.bIsDead or state.board.bMainBehaviorSuspended or state.board:HasAnyUnbreakableActiveAction()then
                state.blocked=true;state.reason='NPC is busy with combat, a cinematic, or another behavior hold';return
            end
            change(state,function()return state.board end,'bMainBehaviorSuspended',true)
            -- A settled actor with no live action has nothing to cancel. This
            -- preserves idle/turn animation; moving or busy actors still stop.
            local inspected,idle=pcall(function()
                local v=actor:GetVelocity()
                return #state.board.ActiveActions==0 and v.X*v.X+v.Y*v.Y+v.Z*v.Z<1
                    and valid(state.controller)and state.controller:GetMoveStatus()==0
            end)
            state.alreadyIdle=inspected and idle
            if not state.alreadyIdle then
                state.board:StopPlayingMontagesByActions()
                state.board:StopAllActions()
            end
        end
        if valid(state.controller)and not state.alreadyIdle then state.controller:StopMovement()end
        change(state,function()return actor end,'bUseControllerRotationYaw',false)
        local movement=state.movement
        if valid(movement)and (movement.MovementMode==1 or movement.MovementMode==2)then
            state.mode=movement.MovementMode;state.custom=movement.CustomMovementMode
            -- These two flags prevent movement acceleration from rotating the body
            -- against our conversation turn. Actor, controller and mesh keep ticking.
            pcall(function()change(state,function()return movement end,'bOrientRotationToMovement',false)end)
            pcall(function()change(state,function()return movement end,'bUseControllerDesiredRotation',false)end)
            -- Zero native locomotion input while holding the goal. Keep walking
            -- physics enabled so root-motion turn/stop animations can move feet.
            local previousInput=movement:GetOverrideInputSize()
            assert(type(previousInput)=='number','Native movement input unavailable')
            if previousInput~=0 then state.changes[#state.changes+1]=function()
                if valid(state.actor)and (not state.stub or AI.board(state.stub,state.board))and valid(movement)and movement:GetOverrideInputSize()==0 then
                    -- Reset writes the native -1 sentinel. The ordinary setter
                    -- clamps negative values to zero, so Set(-1) freezes travel.
                    if previousInput<0 then movement:ResetOverrideInputSize()
                    else movement:SetOverrideInputSize(previousInput)end
                end
            end;movement:SetOverrideInputSize(0)end
            if not state.alreadyIdle then movement:StopMovementImmediately()end
        end
        log('Conversation hold: native behavior suspended; body idle animation remains running')
    end)
    if not ok then restore(state);state.blocked=true;state.reason=tostring(err);log('Conversation hold unavailable: '..state.reason)end
    return state
end
function M.face(state,playerLocation,player)
    if not state or state.blocked or state.following or not valid(state.actor)then return end
    if state.stub and not AI.board(state.stub,state.board)then M.finish(state);state.blocked=true;return end
    if valid(state.stub)and (state.stub:IsInCinematicMode()or state.stub:IsInCombat()or state.board.Combat.bInCombat or state.board.bIsDead)then
        M.finish(state);state.blocked=true;return
    end
    if valid(player)then state.attention=M.attend(state.attention,state.actor,player,state.log,true)end
end
function M.finish(state)
    if not state then return end
    M.releaseAttention(state.attention);state.attention=nil
    local followed=state.following;state.following=false
    restore(state)
    if followed and AI.board(state.stub,state.board)and not state.stub:IsInCombat()and not state.board.Combat.bInCombat and not state.stub:IsInCinematicMode()and not state.board.bIsDead and not state.board.bMainBehaviorSuspended and not state.board:HasAnyUnbreakableActiveAction()then
        -- Invalidate our follower goal once, allowing the normal community tree to resume.
        pcall(function()state.board:StopAllActions();if valid(state.controller)then state.controller:StopMovement()end end)
    end
end
function M.follow(state,player)
    if not state or state.blocked or not AI.board(state.stub,state.board)or not valid(player)or not state.mode then
        return false,'Native companion behavior unavailable for this NPC'
    end
    if state.following then return true,'Companion mode is already enabled'end
    if state.stub:IsInCinematicMode()or state.board.bIsDead or state.stub:IsHostileTowardsPlayer()or state.stub:IsInCombat()or state.board.Combat.bInCombat or state.board:HasAnyUnbreakableActiveAction()then
        return false,'NPC is busy, hostile, or unavailable for following'
    end
    M.releaseAttention(state.attention);state.attention=nil
    restore(state) -- restore walking and yaw BEFORE enabling the native follower tree
    local ok,err=pcall(function()
        local board=state.board
        assert(not board.bMainBehaviorSuspended,'Game has suspended this NPC')
        change(state,function()return board.Leader end,'bLeaderModeEnabled',false)
        change(state,function()return board.Follower end,'bFollowerModeEnabled',true)
        change(state,function()return board.Follower end,'bIsTemporaryFollower',true)
        change(state,function()return board.Follower end,'bIsPlayerInFollowArea',true)
        change(state,function()return board.Follower end,'bReturnToAP',false)
        local lib=AI.find('/Script/RebelAI.Default__RebelAIBoardBlueprintFunctionLibrary')
        assert(valid(lib)and lib:GetIsInFollowerMode(state.stub),'Native follower mode rejected')
        board:StopAllActions()
        state.following=true;state.playerStub=stubFor(player)
    end)
    if not ok then restore(state);return false,'Companion setup failed: '..tostring(err)end
    return true,state.board.bCanFight and 'Native companion mode enabled; combat assistance available' or 'Native companion mode enabled; this NPC currently has combat disabled by the game'
end
function M.followTick(state,player)
    if not state or not state.following or not AI.board(state.stub,state.board)or not valid(player)then return false,'Companion unloaded'end
    local board=state.board
    if state.stub:IsInCinematicMode()or board.bIsDead or board.bMainBehaviorSuspended or state.stub:IsHostileTowardsPlayer()then return false,'Game took control of companion'end
    if not board.Follower.bFollowerModeEnabled then return false,'Game ended follower mode'end
    -- Maintain the temporary player's follow area without resubmitting MoveToActor.
    board.Follower.bIsPlayerInFollowArea=true;board.Follower.bReturnToAP=false
    if not board.bCanFight then return true end
    if state.stub:IsInCombat()or board.Combat.bInCombat or board:HasAnyUnbreakableActiveAction()then return true end
    local playerStub=state.playerStub
    if not AI.board(playerStub)or not playerStub:IsInCombat()then return true end
    local enemy=playerStub.AIBoard:GetTarget()
    if not AI.board(enemy)or enemy:IsPlayer()or enemy:IsInCinematicMode()or enemy.AIBoard.bIsDead or not enemy:IsHostileTowardsPlayer()then return true end
    local actor=enemy:GetActor();if not valid(actor)then return true end
    local a,b=actor:K2_GetActorLocation(),player:K2_GetActorLocation()
    if (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2>2000^2 then return true end
    if state.lastAssist and os.time()-state.lastAssist<3 then return true end
    state.lastAssist=os.time()
    -- Never overwrite another system's forced target. Ours expires after 2 seconds.
    local forced=board:GetForcedTarget();if valid(forced)then return true end
    local combat=AI.find('/Script/RebelAI.Default__RebelAICombatBlueprintFunctionLibrary')
    if valid(combat)then
        board:SetForcedTarget(enemy,2.0)
        local accepted=combat:StartCombatBehaviors(state.stub)
        state.log('Companion combat request: '..tostring(accepted))
    end
    return true
end
function M.inspect(actor)
    local rows={os.date(),actor:GetFullName()}
    local function read(label,fn)local ok,v=pcall(fn);rows[#rows+1]=label..'='..(ok and tostring(v)or ('unavailable: '..tostring(v)))end
    local lib=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary')
    local stub=lib:GetAIStub(actor);if not valid(stub)then return 'No RebelAI stub'end
    local board=AI.board(stub)
    if not board then return table.concat(rows,'\n')..'\nAI board detached or uninitialized'end
    read('position',function()local p=actor:K2_GetActorLocation();return string.format('%.0f,%.0f,%.0f',p.X,p.Y,p.Z)end)
    read('moving',function()return stub:IsMoving()end)
    read('controller',function()return actor:GetController():GetFullName()end)
    read('cinematic',function()return stub:IsInCinematicMode()end)
    read('combat',function()return stub:IsInCombat()end)
    read('weaponEquipped',function()return AI.weaponEquipped(stub,board)end)
    read('weaponSelector',function()return board.Weapon.TagName:ToString()end)
    read('attackTicket',function()return board.TicketUser.bHasTicket end)
    read('selectedAttack',function()return board.Combat.SelectedAttack.ActionTag.TagName:ToString()end)
    read('inAttackRange',function()return board.Combat.bInAttackRange end)
    read('characterState',function()return board.CurrentCharacterState.TagName:ToString()end)
    read('combatMode',function()local tag={TagName=FName('None')};board:Temp_BP_GetCombatMode(tag);return tag.TagName:ToString()end)
    read('availableCharacterStates',function()
        local states=stub:GetAIDefinition().CharacterStates;assert(#states<=64,'Unexpected state count')
        local names={};for i=1,#states do names[#names+1]=states[i].Tag.TagName:ToString()end
        return table.concat(names,',')
    end)
    read('friendly',function()return stub:IsFriendlyTowardsPlayer()end)
    read('hostile',function()return stub:IsHostileTowardsPlayer()end)
    read('suspended',function()return board.bMainBehaviorSuspended end)
    read('canFight',function()return board.bCanFight end)
    read('movementMode',function()return actor:GetMovementComponent().MovementMode end)
    read('movementInputOverride',function()return actor:GetMovementComponent():GetOverrideInputSize()end)
    read('lookAtMode',function()return actor:GetMovementComponent().CurrentLookAtMode end)
    read('headLookTargets',function()return #actor.LookAtTargets end)
    read('rotationMode',function()return actor:GetMovementComponent().CurrentRotationMode end)
    read('turnInPlace',function()return actor.Mesh:GetAnimInstance().bCanTurnInPlace end)
    read('velocity',function()local v=actor:GetVelocity();return math.sqrt(v.X*v.X+v.Y*v.Y)end)
    read('movementProfile',function()return actor:GetMovementComponent():GetCurrentMovementProfile():GetFullName()end)
    read('profileMaxSpeed',function()return actor:GetMovementComponent():GetCurrentMovementProfile().MovementConfig.MaxSpeed end)
    read('distanceToTarget',function()return board.Combat.DistanceToTarget end)
    read('targetGap',function()
        local t=board:GetTarget();if not AI.board(t)or not valid(t:GetActor())then return 'None'end
        local a,b=actor:K2_GetActorLocation(),t:GetActor():K2_GetActorLocation()
        return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2)
    end)
    read('targetIsPlayer',function()local t=board:GetTarget();return AI.board(t)and t:IsPlayer()or false end)
    read('unbreakableAction',function()return board:HasAnyUnbreakableActiveAction()end)
    read('target',function()local t=board:GetTarget();return valid(t)and t:GetFullName()or 'None'end)
    read('forcedTarget',function()local t=board:GetForcedTarget();return valid(t)and t:GetFullName()or 'None'end)
    read('targetAttitude',function()local t=board:GetTarget();return valid(t)and stub:GetAttitudeTowards(t)or 'None'end)
    read('targetHealth',function()
        local t=board:GetTarget();if not AI.board(t)then return 'None'end
        local asc=t:GetAbilitySystemComponent();local attrs=asc:GetAttributeSet(AI.find('/Script/DogwoodStats.CharacterBaseAttributeSet'))
        return tostring(attrs.Health.CurrentValue)..'/'..tostring(attrs.MaxHealth.CurrentValue)
    end)
    read('abilitySystem',function()local a=stub:GetAbilitySystemComponent();return valid(a)and a:GetFullName()or 'None'end)
    read('abilityCount',function()local a=stub:GetAbilitySystemComponent();return valid(a)and #a.ActivatableAbilities.Items or 0 end)
    read('followerDamageTag',function()return stub:HasTag({TagName=FName('RebelAI.Flag.DealFollowerDamage')})end)
    local combatComponent=actor:GetComponentByClass(AI.find('/Script/DogwoodCombat.CombatComponentBase'))
    if valid(combatComponent)then
        read('physicalWeapon',function()local weapon=combatComponent:GetMainWeapon();return valid(weapon)and weapon:GetFullName()or 'None'end)
        read('equippedWeaponClass',function()local c=combatComponent.EquippedWeapon;return valid(c)and c:GetFullName()or 'None'end)
        read('combatComponentState',function()return combatComponent.CurrentState end)
        read('attackTargetFilterClass',function()local c=combatComponent.AttackTargetFilterClass;return valid(c)and c:GetFullName()or 'None'end)
    end
    read('nativeAiDamageFallback',function()
        local asc=stub:GetAbilitySystemComponent();local attrs=asc:GetAttributeSet(AI.find('/Script/DogwoodStats.CharacterBaseAttributeSet'))
        return attrs.DamageAIvsAI.CurrentValue
    end)
    read('aiDefinition',function()return stub.CachedAIDefinition:GetFullName()end)
    read('aggressive',function()return board.Aggression.bIsAggressive end)
    read('preferredLocation',function()return board.Positioning.bPreferredLocationIsSet end)
    read('dead',function()return board.bIsDead end)
    read('behavior',function()return board.CurrentBehaviorName:ToString()end)
    read('phase',function()return board.CurrentPhaseName:ToString()end)
    for _,key in ipairs({'bFollowerModeEnabled','KeepDistanceToPlayer','KeepDistanceToPlayerMoveTo','TeleportDistance','ReturnToAPDistance','bIsPlayerInFollowArea','bReturnToAP','bIsTemporaryFollower','FollowerSpeed','PathToPlayerNotExist'})do
        read(key,function()return board.Follower[key]end)
    end
    read('leader',function()return board.Leader.bLeaderModeEnabled end)
    return table.concat(rows,'\n')
end
function M.catalog()
    -- RC5 returns STRUCT array elements as parameter wrappers: :get() unwraps
    -- the owned struct. Plain UObject array elements do not need that call.
    -- Read only these three reflected FNames; never load assets or soft refs.
    local helpers=AI.find('/Script/AssetRegistry.Default__AssetRegistryHelpers')
    assert(valid(helpers),'Asset registry helpers unavailable')
    local registry=helpers:GetAssetRegistry()
    assert(valid(registry),'Asset registry unavailable')
    local rows={'package\tasset\tpath'}
    for _,path in ipairs({'/Game/_Dawnwalker/NPC','/Game/_Dawnwalker/Combat/Enemies','/Game/_Dawnwalker/Quest'})do
        local assets={}
        registry:GetAssetsByPath(FName(path),assets,true,true)
        assert(#assets<=30000,'Unexpected asset count')
        for i=1,#assets do
            local asset=assets[i]:get()
            local name=asset.AssetName:ToString()
            if name:match('^NPCDef_')or name:match('^AIDef_')or name:match('^AIConfig_')or name:match('^GA_AI_')then
                rows[#rows+1]=asset.PackageName:ToString()..'\t'..name..'\t'..asset.PackagePath:ToString()
            end
        end
    end
    return table.concat(rows,'\n')
end
-- Small one-second trace for the two caster bosses. Read only reflected
-- scalar ability counts and native ticket queries; never activate/cancel an
-- ability or clear a cooldown. The party caller bounds and batches the log.
function M.combatActivity(stub,board)
    if not AI.board(stub,board)then return 'AI detached'end
    local rows={}
    local function read(key,fn)local ok,value=pcall(fn);rows[#rows+1]=key..'='..tostring(value):gsub('[\r\n]',' '):sub(1,1800)end
    read('behavior',function()return board.CurrentBehaviorName:ToString()end)
    read('standardTicket',function()return board:HasTicketOfType({TagName=FName('RebelAI.Ticket.Standard')})end)
    read('helperTicket',function()return board:HasTicketOfType({TagName=FName('RebelAI.Ticket.Helper')})end)
    read('busy',function()return board:HasAnyUnbreakableActiveAction()end)
    read('activeAbilities',function()
        local asc=stub:GetAbilitySystemComponent();if not valid(asc)then return 'Unavailable'end
        local items=asc.ActivatableAbilities.Items;assert(#items<=256,'Unexpected ability count')
        local active={}
        for i=1,#items do local item=items[i]
            if item.ActiveCount>0 and valid(item.Ability)then active[#active+1]=item.Ability:GetFullName()..':'..item.ActiveCount end
        end
        return #active>0 and table.concat(active,'; ')or 'None'
    end)
    return table.concat(rows,'\n')..'\n'
end
return M
