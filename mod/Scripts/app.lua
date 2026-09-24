local UE = require('UEHelpers')
local config = require('config')
local root = require('runtime_path')
local Targeting = require('targeting')
local Engagement = require('engagement')
local FaceInspector = require('face_inspector')
local FaceGraph = require('face_graph')
local Companions=require('companions')
local NativeMenu=require('companion_menu')
local Romance=require('companion_romance')
local Settings=require('companion_settings')
local Horde=require('horde_mode')
local FirstPerson=require('first_person_camera')
local lastRelationshipRead=0
local combatTrace=nil
local UiInput=require('ui_input')
local speechLayer=nil
local conversationMode='single';local conversationRoom='';local speakerTurn=''
local requestId=0
local identity={}
local generation = os.time() * 1000
local selected, bindings = nil, {}
local selectedName,selectedClass='',''
local status = 'Ready: F7 to talk, F8 to inspect the aimed actor'
local pending, lastHeartbeat, lastKey = false, 0, 0
local previewEnd, previewTick = 0, 0
local engagement, selectedAt = nil, 0
local attention=nil
local activeController, cachedController = nil, nil
local idleSecond, devSecond, updateCount = -1, -1, 0
local lookingAwaySince=nil
local groupOrigin=nil
local inspectionCache=nil
local composeController,inputLease=nil,nil
local function log(s)
    local kind=type(s)
    local value=(kind=='string'or kind=='number')and s or 'Non-text Lua error'
    pcall(print,'[DawnwalkerConvai] '..value..'\n')
end
local function valid(o) return o and o:IsValid() end
local function safe(f) local ok,r=pcall(f); if not ok then log(r) end; return ok,r end
local function playerController()
    cachedController=Targeting.playerController(UE.GetPlayerController,os.time())
    return cachedController
end
local function write(name,s)
    local f,err=io.open(root..'/'..name,'w');if not f then error(err) end
    f:write(s);f:close()
end
local function clean(s) return (tostring(s):gsub('[\r\n\t]',' ')) end
local lastSpatialStatus=''
local function spatialSnapshot(pc,point)
    local camera=pc.PlayerCameraManager
    assert(valid(camera),'Spatial camera unavailable')
    return Targeting.spatial(camera:GetCameraLocation(),camera:GetCameraRotation(),point,generation,os.time())
end
local function restoreFocusPause()
    local err=UiInput.release(inputLease);if err then log('UI input restore: '..err)end
    composeController,inputLease=nil,nil
end
local function acquireUiInput(pc)
    local library=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
    local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics')
    if not valid(library)or not valid(gameplay)then return nil,'UI input library unavailable'end
    local lease,err=UiInput.acquire(pc,library,gameplay)
    if not lease then log('UI input setup: '..tostring(err));return nil,'Could not release game mouse capture'end
    composeController,inputLease=pc,lease
    return true
end

local function each(array,callback)
    for i=1,#array do callback(array[i])end
end
local function publish()
    write('target.txt', table.concat({tostring(generation),(selected and previewEnd==0) and '1' or '0',selected and selectedName or '',selected and selectedClass or '',clean(status),conversationMode,tostring(requestId),clean(identity.name or ''),clean(identity.definition or ''),clean(identity.bodyType or ''),clean(identity.voiceTag or ''),conversationRoom,speakerTurn},'\n')..'\n')
end
local function cacheSelection(actor)
    selectedName=clean(actor:GetFullName());selectedClass=clean(actor:GetClass():GetFullName())
end
local function forgetConversation(message)
    -- Unloading/destroyed objects cannot safely restore face layers, focus or
    -- input leases. Only discard Lua state here; publish uses cached strings.
    selected=nil;bindings={};speechLayer=nil;attention=nil;engagement=nil
    activeController=nil;composeController=nil;inputLease=nil;groupOrigin=nil;lookingAwaySince=nil
    previewEnd=0;conversationRoom='';speakerTurn='';identity={};selectedName='';selectedClass=''
    generation=generation+1;status=message or 'Conversation unloaded';publish()
end
Companions.beforeReset(function(reason)
    if reason=='party-reset'then FirstPerson.release();Horde.stop('Horde ended for world or party reset',true)end
    forgetConversation('Conversation ended for world or party reset')
end)
local function neutral()
    if speechLayer then pcall(function()FaceGraph.applyWeights(speechLayer,{})end)end
    for _,b in ipairs(bindings) do if valid(b.mesh) then pcall(function() b.mesh:SetMorphTarget(FName(b.name),b.original or 0.0,true) end) end end
end
local function releaseConversation()
    Engagement.releaseAttention(attention);attention=nil
    Engagement.finish(engagement);engagement=nil
    if selected then Companions.afterConversation(selected)end
end
local lastReplyRelease=''
local function releaseCompletedReply(data)
    -- Called only after frame generation and freshness validation. Never release
    -- a newer composer, a group speaker, or an explicit world-NPC Follow action.
    if conversationMode~='single'or not selected or composeController then return end
    local token=data:match('\nREPLY%-END\t([%w%-]+)\n')
    if not token then return end
    local key=tostring(generation)..':'..token
    if key==lastReplyRelease then return end
    lastReplyRelease=key
    if engagement and engagement.following then return end
    releaseConversation();log('Single reply complete; conversation movement released')
end
-- Group membership is chosen within twelve metres of the player. Preserve
-- this shared origin across speaker handoffs: facing the original addressee
-- must not count as walking away from a later speaker behind the camera.
local function conversationWalkedAway(a,forward,b,following)
    if conversationMode=='group' then
        if not groupOrigin then groupOrigin={X=a.X,Y=a.Y,Z=a.Z} end
        local x,y,z=a.X-groupOrigin.X,a.Y-groupOrigin.Y,a.Z-groupOrigin.Z
        return x*x+y*y+z*z>1200*1200
    end
    return Targeting.walkedAway(a,forward,b,config.MaxDistance,following)
end
local function stop(message,quiet)
    lookingAwaySince=nil
    if not quiet then groupOrigin=nil end
    restoreFocusPause()
    releaseConversation();activeController=nil
    neutral();bindings={};selected=nil;previewEnd=0;generation=generation+1;status=message or 'Conversation ended';if not quiet then publish()end;log(status)
    local layer=speechLayer;speechLayer=nil
    if layer then FaceGraph.restoreLayer(layer)end
end
if RegisterModCleanup then RegisterModCleanup(function()FirstPerson.release();Horde.stop('Horde ended for live reload',true);if combatTrace then combatTrace.stop()end;NativeMenu.close();stop('Released for live reload');Companions.cleanup()end)end
local function trace(nearest)
    local pc=playerController();if not valid(pc) or not valid(pc.Pawn) then return nil,'Player not ready' end
    cachedController=pc
    local camera=pc.PlayerCameraManager;if not valid(camera) then return nil,'Camera not ready' end
    local start=camera:GetCameraLocation();local forward=UE.GetKismetMathLibrary():GetForwardVector(camera:GetCameraRotation())
    local player=pc.Pawn;local location=player:K2_GetActorLocation()
    local best,bestScore=nil,math.huge;local fallback,fallbackDistance=nil,math.huge
    local companion,companionDistance=nil,math.huge
    -- Chat keys prefer a visible, camera-facing actor, then the nearest owned
    -- companion even behind the camera or cover. Debug targeting remains aimed.
    local fallbackRadius=nearest and 1200 or config.MaxDistance
    local candidates=FindAllOf('Pawn') or {}
    local report={'Selection: nearby NPC, preferring camera-facing direction','Pawn instances: '..#candidates}
    for _,actor in ipairs(candidates) do
        local ok,err=pcall(function()
            if not valid(actor) or actor:GetFullName()==player:GetFullName() then return end
            if actor:GetWorld():GetFullName()~=player:GetWorld():GetFullName() then return end
            if actor:IsPlayerControlled() then return end
            local score,distance,reason=Targeting.score(location,forward,actor:K2_GetActorLocation(),config.MaxDistance,config.FacingHalfAngle or 80)
            local identity=Companions.identity(actor)
            if identity and identity.chat==false then return end
            local owned=nearest~=nil and identity or nil
            if owned then
                if distance<companionDistance then companion,companionDistance=actor,distance end
                -- Keep the angular score finite when removing the companion range cap.
                score,distance,reason=Targeting.score(location,forward,actor:K2_GetActorLocation(),math.max(config.MaxDistance,distance),config.FacingHalfAngle or 80)
            end
            if distance<config.MaxDistance*3 then table.insert(report,string.format('%s | %.0f units | %s',actor:GetFullName(),distance,reason)) end
            if nearest~=nil and distance<=fallbackRadius then
                local meta=owned or Targeting.identify(actor)
                if meta.definition and meta.definition:find('NPCDef_',1,true)and not meta.definition:find('/Animals/',1,true)and pc:LineOfSightTo(actor,start,false)then
                    if distance<fallbackDistance then fallback,fallbackDistance=actor,distance end
                end
            end
            if not score then return end
            local visible=pc:LineOfSightTo(actor,start,false)
            if not visible then table.insert(report,'  Blocked by line-of-sight check');return end
            if score<bestScore then best,bestScore=actor,score end
        end)
        if not ok then table.insert(report,'Candidate inspection: '..tostring(err)) end
    end
    local chosen=best or companion or fallback
    table.insert(report,chosen and ('Selected: '..chosen:GetFullName()..(best and ' | camera-facing' or companion and ' | nearest companion' or ' | nearest visible character'))or 'No conversation target available')
    write('targeting-diagnostics.txt',table.concat(report,'\n'));log(chosen and ('Selected '..chosen:GetFullName())or 'No nearby visible target; see targeting-diagnostics.txt')
    if chosen then return chosen,nil end
    return nil,nearest~=nil and 'No companion available. Summon one with F5 or approach a visible NPC.'or 'No visible NPC in front of you within 4.5 metres.'
end
local channels={'JawForward','JawRight','JawLeft','JawOpen','MouthClose','MouthFunnel','MouthPucker','MouthRight','MouthLeft','MouthSmileLeft','MouthSmileRight','MouthFrownLeft','MouthFrownRight','MouthDimpleLeft','MouthDimpleRight','MouthStretchLeft','MouthStretchRight','MouthRollLower','MouthRollUpper','MouthShrugLower','MouthShrugUpper','MouthPressLeft','MouthPressRight','MouthLowerDownLeft','MouthLowerDownRight','MouthUpperUpLeft','MouthUpperUpRight'}
-- JALI test mode returns before the morph adapter and Convai conversation loop.
if config.FacialProbeOnly then
    local Probe=require('jali_probe')

    local FaceGraph=require('face_graph')
    local graphState,graphOverride=nil,nil
    local previewState,previewPending=nil,false
    local previewEngagement,previewController=nil,nil
    local function releasePreview(reason)
        local layerOK,layerError=pcall(function()FaceGraph.restoreLayer(graphOverride)end)
        Engagement.finish(previewEngagement)
        graphOverride=nil
        if not layerOK then log('Layer restore error: '..tostring(layerError))end
        previewState=nil;previewEngagement=nil;previewController=nil
        log('Direct jaw test released: '..reason)
    end
    if RegisterModCleanup then RegisterModCleanup(function()releasePreview('live reload')end)end
    local busy,done=false,false
    local function append(line)
        local f,err=io.open(root..'/jali-probe.txt','a')
        if not f then error(err)end
        f:write(line..'\n');f:close()
    end
    RegisterKeyBind(Key.F8,function()
        if busy or done then return end
        busy=true
        ExecuteInGameThread(function()
            local ok,err=pcall(function()
                write('jali-probe.txt','BEGIN v0.7\n')
                append('NEXT select nearby NPC')
                local actor,reason=trace()
                if not actor then append(tostring(reason))end
                Probe.run(actor,append)
            end)
            done=true;busy=false
            status=ok and 'JALI probe complete. Pause with Esc and tell Codex.' or ('JALI probe error: '..tostring(err))
            if not ok then pcall(append,'LUA ERROR '..tostring(err))end
            safe(publish);log(status)
        end)
    end)
    local function previewLog(line)
        local f,err=io.open(root..'/jali-preview.txt','a');if not f then error(err)end
        f:write(line..'\n');f:close();log(line)
    end
    RegisterKeyBind(Key.F6,function()
        if previewPending or previewState then return end
        previewPending=true
        ExecuteInGameThread(function()
            local ok=safe(function()
                write('jali-preview.txt','BEGIN v0.13 direct Lua JawOpenAlpha test\n')
                local actor,reason=trace()
                if actor then
                    write('face-graph.txt','BEGIN v0.13\n')
                    graphState=nil
                    local graphOK,graphError=pcall(function()
                        graphState=FaceGraph.capture(actor,function(line)
                            local f,err=io.open(root..'/face-graph.txt','a');if not f then error(err)end
                            f:write(line..'\n');f:close()
                        end)
                    end)
                    if not graphOK then previewLog('Graph capture failed: '..tostring(graphError))end
                end
                if actor then
                    graphOverride=FaceGraph.linkSpeechLayer(graphState,previewLog)
                    previewState,reason=FaceGraph.beginJaw(graphOverride,actor,os.time())
                end
                if previewState and config.FaceAndHold then
                    previewController=cachedController
                    previewEngagement=Engagement.begin(actor,previewLog)
                    if valid(previewController) and valid(previewController.Pawn)then
                        Engagement.face(previewEngagement,previewController.Pawn:K2_GetActorLocation(),previewController.Pawn)
                    end
                end
                status=reason;publish();previewLog(reason)
            end)
            if not ok then safe(function()releasePreview('setup error')end)end
            previewPending=false
        end)
    end)
    RegisterKeyBind(Key.F7,function()ExecuteInGameThread(function()
        safe(function()releasePreview('cancelled with F7')end)
    end)end)
    LoopAsync(50,function()
        -- No controller scans or game-thread callbacks while idle.
        if not previewState or previewPending then return false end
        previewPending=true
        ExecuteInGameThread(function()
            local ok= safe(function()
                if previewEngagement then
                    if not valid(previewController) or not valid(previewController.Pawn)then releasePreview('player unloaded');return end
                    local location=previewController.Pawn:K2_GetActorLocation()
                    if previewState.frame%2==0 then Engagement.face(previewEngagement,location,previewController.Pawn)end
                end
                if previewState.frame%10==0 then
                    local sampleOK,sampleError=pcall(function()FaceGraph.sample(graphState)end)
                    if not sampleOK then previewLog('Curve sample unavailable: '..tostring(sampleError));graphState=nil end
                end
                if FaceGraph.tickJaw(previewState,os.time())then releasePreview('complete');status='Direct jaw test ended; NPC released. Pause with Esc and report mouth movement.';publish()end
            end)
            if not ok then safe(function()releasePreview('Lua error')end)end
            previewPending=false
        end)
        return false
    end)
    status='v0.13: F6 direct jaw control test; F7 release'
    safe(publish);log(status)
    return
end
local function inspectMetadata(actor)
    -- F8 never enters morph discovery or generic instance-value reflection.
    local report={'Metadata only: no property values, pose buffers or soft references are read.'}
    write('face-api-checkpoints.txt','BEGIN metadata inspection\n')
    local emitted=0
    local function checkpoint(operation)
        local f,err=io.open(root..'/face-api-checkpoints.txt','a')
        if not f then error(err) end
        for i=emitted+1,#report do f:write(report[i]..'\n') end
        emitted=#report
        f:write('NEXT '..operation..'\n');f:close()
    end
    checkpoint('Find skeletal component class')
    local cls=StaticFindObject('/Script/Engine.SkeletalMeshComponent')
    if not valid(cls) then error('SkeletalMeshComponent class unavailable') end
    checkpoint('Selected actor K2_GetComponentsByClass')
    local meshes=actor:K2_GetComponentsByClass(cls)
    checkpoint('Enumerate selected actor components')
    each(meshes,function(mesh)
        checkpoint('Validate owned mesh')
        if not valid(mesh) then return end
        checkpoint('Owned mesh GetFName')
        local name=mesh:GetFName():ToString()
        table.insert(report,'Mesh: '..name)
        if name:lower():find('face',1,true) then FaceInspector.layers(mesh,report,checkpoint) end
    end)
    checkpoint('COMPLETE')
    write('face-api-diagnostics.txt',table.concat(report,'\n'))
    log('Face metadata inspection complete; no runtime property values read')
end
local function inspect(actor,detailed)
    if detailed then inspectMetadata(actor);return end
    if config.UseFaceLayer then
        local graph=FaceGraph.capture(actor,log,true)
        speechLayer=FaceGraph.linkSpeechLayer(graph,log)
        FaceGraph.beginJaw(speechLayer,actor,os.time()) -- Capture original input for restoration.
        bindings={};return
    end
    if not detailed and inspectionCache and valid(inspectionCache.actor) and inspectionCache.actor:GetFullName()==actor:GetFullName() then
        bindings=inspectionCache.bindings;return
    end
    bindings={};local report={'Actor: '..actor:GetFullName(),'Class: '..actor:GetClass():GetFullName()}
    write('npc-diagnostics.txt',table.concat(report,'\n')..'\nInspecting components...')
    local cls=StaticFindObject('/Script/Engine.SkeletalMeshComponent')
    local found,meshes=pcall(function() return actor:K2_GetComponentsByClass(cls) end)
    if not found then
        error('K2_GetComponentsByClass unavailable: '..tostring(meshes))
    end
    each(meshes,function(mesh)
        local meshOk,meshError=pcall(function()
        if not valid(mesh) then return end
        table.insert(report,'Mesh component: '..mesh:GetFullName())
        local face=mesh:GetFName():ToString():lower():find('face',1,true)~=nil
        local ok,asset=pcall(function() return mesh:GetSkeletalMeshAsset() end)
        if not ok or not valid(asset) then ok,asset=pcall(function() return mesh.SkeletalMesh end) end
        if not ok or not valid(asset) then table.insert(report,'  No accessible skeletal mesh asset: '..tostring(asset));return end
        table.insert(report,'Asset: '..asset:GetFullName())
        local morphNames={}
        local function normalize(name) return name:lower():gsub('[^%w]','') end
        local function readMorphs(array) each(array,function(v)
            if valid(v) then local name=v:GetFName():ToString();morphNames[normalize(name)]=name;table.insert(report,'  Morph: '..name) end
        end) end
        local morphOk,morphError=pcall(function() readMorphs(asset.MorphTargets) end)
        if not morphOk then
            morphOk,morphError=pcall(function() readMorphs(asset:GetMorphTargets()) end)
        end
        if not morphOk then table.insert(report,'  Morph enumeration unavailable: '..tostring(morphError)) end
        pcall(function()
            local anim=mesh:GetAnimInstance();if valid(anim) then table.insert(report,'Animation class: '..anim:GetClass():GetFullName()) end
        end)
        for _,channel in ipairs(channels) do
            local candidates=config.MorphMap[channel] and {config.MorphMap[channel]} or {channel}
            for _,name in ipairs(candidates) do
                local actual=morphNames[normalize(name)]
                if actual then
                    local originalOk,original=pcall(function() return mesh:GetMorphTarget(FName(actual)) end)
                    table.insert(bindings,{mesh=mesh,name=actual,channel=channel,original=(originalOk and original) or 0});table.insert(report,'  Bound '..channel..' -> '..actual);break
                end
            end
        end
        end)
        if not meshOk then table.insert(report,'Mesh inspection error: '..tostring(meshError)) end
    end)
    table.insert(report,'Matched mouth morphs: '..#bindings)
    write('npc-diagnostics.txt',table.concat(report,'\n'))
    inspectionCache={actor=actor,bindings=bindings}
    log('Inspection complete: '..#bindings..' matching morphs; details saved to file')
end
local function toggle(mode,actorOverride)
    if selected and not actorOverride then if mode~='compose'then requestId=requestId+1 end;publish();return end
    requestId=mode=='compose'and 0 or 1
    local actor,reason=actorOverride,nil
    if not actor then actor,reason=trace(conversationMode=='group')end
    if not actor then status=reason;publish();log(reason);return end
    local pawnClass=StaticFindObject('/Script/Engine.Pawn')
    if not actor:IsA(pawnClass) then status='Hit is not a Pawn: '..actor:GetFullName()..'. F8 records it for adaptation.';publish();log(status);return end
    local canTalk,why=Companions.beforeConversation(actor)
    if canTalk==false then status=why;publish();return end
    inspect(actor);cacheSelection(actor);selected=actor;generation=generation+1;identity=Companions.identity(actor)or Targeting.identify(actor)
    activeController=cachedController
    selectedAt=os.time()
    if config.FaceAndHold then engagement=Engagement.begin(actor,log) end
    if engagement and engagement.blocked then stop(engagement.reason or 'Character is busy');return end
    status='Selected '..actor:GetFName():ToString()..(speechLayer and '; Convai JawOpen -> Lua JawOpenAlpha' or ('; mouth morphs matched: '..#bindings))
    publish();log(status)
end
local lastAction=''
local function applyAction()
    local f=io.open(root..'/actions.txt','r');if not f then return end
    local data=f:read(1024);f:close()
    -- An empty action mailbox is normal between requests; read(n) returns nil at EOF.
    if not data or data=='' then return end
    local gen,stamp,id,name=data:match('^(%d+)\t(%d+)\t([%w_-]+)\t([^\r\n]+)')
    if not selected or tonumber(gen)~=generation or not stamp or math.abs(os.time()-tonumber(stamp))>3 or id==lastAction then return end
    lastAction=id
    local result,message=false,'Unsupported action'
    local ok,err=pcall(function()
        if name=='Follow'or name=='Stop Walking'or name=='Look At Player'then Engagement.releaseAttention(attention);attention=nil end
        if name=='Follow' then
            local owned=Companions.identity(selected)
            if owned then
                releaseConversation()
                result,message=Companions.conversationAction(selected,name)
            else result,message=Engagement.follow(engagement,activeController.Pawn)end
            if not result then Engagement.finish(engagement);engagement=Engagement.begin(selected,log)end
        elseif name=='Stop Walking' or name=='Look At Player' then
            if name=='Stop Walking'then Companions.conversationAction(selected,name)end
            Engagement.finish(engagement);engagement=nil
            local allowed,why=Companions.beforeConversation(selected)
            if allowed==false then error(why)end
            engagement=Engagement.begin(selected,log)
            Engagement.face(engagement,activeController.Pawn:K2_GetActorLocation(),activeController.Pawn)
            result=not engagement.blocked
            message=result and (name=='Stop Walking'and Companions.identity(selected)and 'Waiting here until you ask me to follow'or 'Stopped and facing Coen')or engagement.reason
        elseif name=='Leave' then stop('Released by conversation action');result,message=true,'Released; resumed normal game behavior' end
    end)
    if not ok then result=false;message=tostring(err);if selected then stop('Action failed; restored NPC')end end
    write('action-result.txt',gen..'\t'..id..'\t'..(result and '1' or '0')..'\t'..clean(message)..'\n')
    status=message;publish()
    log('Action '..name..': '..message)
    if selected then pcall(function()write('ai-inspection.txt',Engagement.inspect(selected))end)end
end
RegisterKeyBind(Key.F7,function()
    ExecuteInGameThread(function()safe(function()stop('Released with F7')end)end)
end)
local function preview(actorOverride)
    if selected then stop('Stopped');return end
    local actor,reason=actorOverride,nil
    if not actor then actor,reason=trace() end
    if not actor then status=reason;publish();log(status);return end
    inspect(actor)
    if #bindings==0 and not speechLayer then
        status='No compatible mouth morphs. F8 inspects the facial animation interface; F6 will not run an empty animation test.'
        publish();log(status);return
    end
    cacheSelection(actor);selected=actor;generation=generation+1;previewEnd=os.time()+6;previewTick=0
    activeController=cachedController
    if speechLayer and config.FaceAndHold then engagement=Engagement.begin(actor,log)end
    -- Facial preview is independent of movement/AI controls to isolate animation.
    status=(speechLayer or #bindings>0) and 'Lua-only facial test: six seconds, then restore' or 'No compatible facial controls'
    publish();log(status)
end
RegisterKeyBind(Key.F6,function() ExecuteInGameThread(function()
    local action=config.UseFaceLayer and function()toggle('text')end or preview
    if not safe(action)then safe(function()stop('Text test setup failed; released NPC')end)end
end) end)
RegisterKeyBind(Key.F8,function() ExecuteInGameThread(function() safe(function()
    if config.UseFaceLayer then
        toggle('compose');write('ui-open.txt',tostring(os.time())..':'..tostring(generation));return
    end
    if selected then stop('Stopped for diagnostics') end
    local actor,reason=trace();if actor then inspect(actor,true);bindings={};status='Facial API diagnostics saved for '..actor:GetFName():ToString() else status=reason end
    publish();log(status)
end) end) end)
-- The helper owns all four chat hotkeys. Stable UE callbacks intentionally do nothing.
if config.UseFaceLayer then for _,key in ipairs({Key.F6,Key.F7,Key.F8})do RegisterKeyBind(key,function()end)end end
-- Development-only mailbox. It accepts fixed actions, never executable text.
-- This lets local tests run when the game's raw input misses injected keys.
local lastDevCommand=''
local function developmentCommand()
    if combatTrace then combatTrace.tick()end
    local f=io.open(root..'/dev-command.txt','r');if not f then return end
    local content=f:read(2048);f:close()
    if not content or content==''then return end
    local id,action,hint=content:match('^([%w_-]+)\n([%a]+)\n([^\r\n]*)')
    if not config.DevelopmentCommands and action~='dump' and action~='identities' and action~='aiinfo' and action~='catalog' and action~='nativeinfo' and action~='spatialinfo' then return end
    if not id or id==lastDevCommand then return end
    lastDevCommand=id
    local ok,err=pcall(function()
        if action=='spatialinfo' then
            -- Fixed read-only check against the player; no selection, scan or AI writes.
            local pc=playerController();assert(valid(pc)and valid(pc.Pawn),'Spatial probe player unavailable')
            local ok,row=pcall(spatialSnapshot,pc,pc.Pawn:K2_GetActorLocation())
            local rows={ok and ('OK\n'..row)or ('ERROR\n'..tostring(row))}
            local r=pc.PlayerCameraManager:GetCameraRotation()
            rows[#rows+1]='rotation type='..type(r)
            for _,key in ipairs({'Yaw','Pitch','Roll','yaw','pitch','roll'})do
                local pass,value=pcall(function()return r[key]end)
                rows[#rows+1]=key..'='..(pass and (type(value)=='number'and tostring(value)or type(value))or 'read failed')
            end
            local mathLib=UE.GetKismetMathLibrary()
            for _,name in ipairs({'GetForwardVector','GetRightVector','GetUpVector'})do
                local pass,value=pcall(function()local v=mathLib[name](mathLib,r);return table.concat({tostring(v.X),tostring(v.Y),tostring(v.Z)},',')end)
                rows[#rows+1]=name..'='..tostring(value)
            end
            if ok then
                local position=pc.Pawn:K2_GetActorLocation();local camera=pc.PlayerCameraManager:GetCameraLocation()
                local x,y,z=position.X-camera.X,position.Y-camera.Y,position.Z+60-camera.Z
                local function dot(v)return (x*v.X+y*v.Y+z*v.Z)/100 end
                local expected={dot(mathLib:GetRightVector(r)),dot(mathLib:GetUpVector(r)),-dot(mathLib:GetForwardVector(r))}
                local fields={};for value in row:gmatch('[^\t\n]+')do fields[#fields+1]=tonumber(value)end
                local agrees=true;for i=1,3 do if math.abs(fields[i+2]-expected[i])>.005 then agrees=false end end
                rows[#rows+1]='Native camera basis agreement='..tostring(agrees)
            end
            write('spatial-probe.txt',table.concat(rows,'\n'));return
        end
        if action=='stop' then stop('Development test stopped');return end
        if action=='nativeinfo' then
            local marker=io.open(root..'/companion-native-'..id..'.txt','r')
            if marker then marker:close();return end
            write('companion-native-'..id..'.txt','Started '..os.date())
            local partyProbes={partyaudit='inspect_party_combat',partystats='inspect_party_stats',partydamage='inspect_party_damage',appearance='inspect_companion_appearance',appearancecheck='test_companion_appearance',romance='inspect_romance'}
            if hint=='protectioncheck'then
                local pc=playerController();assert(valid(pc)and valid(pc.Pawn),'Player unavailable')
                local report=assert(loadfile(root..'/../mod/Development/inspect_companion_protection.lua'))()(root,pc.Pawn,require('companion_native'),require('ai_state'))
                local loader=require('live_reload');local watched=false
                for _,name in ipairs(loader.modules)do if name=='companion_protection'then watched=true end end
                if not watched then loader.modules[#loader.modules+1]='companion_protection'end
                write('companion-native-'..id..'.txt',report);return
            end
            if hint=='damagetrace'then
                local pc=playerController();assert(valid(pc)and valid(pc.Pawn),'Player unavailable')
                if combatTrace then combatTrace.stop()end
                combatTrace=assert(loadfile(root..'/../mod/Development/trace_companion_damage.lua'))()(root,pc.Pawn,Companions,require('ai_state'))
                write('companion-native-'..id..'.txt','Damage observation armed for five minutes or 200 rows; stops on reload.');return
            end
            if hint=='damagepath'then
                local pc=playerController();assert(valid(pc)and valid(pc.Pawn),'Player unavailable')
                local report=assert(loadfile(root..'/../mod/Development/inspect_damage_path.lua'))()(root,pc.Pawn)
                write('companion-native-'..id..'.txt',report);return
            end
            if partyProbes[hint]then
                local pc=playerController();assert(valid(pc),'Player unavailable')
                assert(StaticFindObject('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc),'Pause before requesting a party audit')
                local report=assert(loadfile(root..'/../mod/Development/'..partyProbes[hint]..'.lua'))()(root)
                write('companion-native-'..id..'.txt',report);return
            end
            if hint=='compat105'then
                local pc=playerController();assert(valid(pc)and valid(pc.Pawn),'Player unavailable')
                local paths={'/Script/DogwoodStats.CharacterBaseAttributeSet','/Script/DogwoodStats.CharacterBaseAttributeSet:AttackSpeedMultiplierAdditive','/Script/DogwoodStats.CharacterBaseAttributeSet:Level','/Script/RebelAI.RebelAIFactionsController:BP_SetAttitude','/Script/RebelAI.RebelAIFactionsController:SetAttitudeTowardsPlayer','/Script/UMG.UserWidget','/Script/UMG.Default__WidgetBlueprintLibrary'}
                local rows={};for _,path in ipairs(paths)do local obj=StaticFindObject(path);rows[#rows+1]=path..'='..tostring(valid(obj))end
                local stub=StaticFindObject('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(pc.Pawn)
                if valid(stub)then
                 local asc=stub:GetAbilitySystemComponent();local attrs=asc:GetAttributeSet(StaticFindObject('/Script/DogwoodStats.CharacterBaseAttributeSet'))
                 for _,key in ipairs({'Level','AttackSpeedMultiplierAdditive','Health','MaxHealth'})do local ok,value=pcall(function()return attrs[key].CurrentValue end);rows[#rows+1]='Player '..key..'='..tostring(value)end
                end
                local native,why=require('companion_native').probe();rows[#rows+1]=native and native.raw or tostring(why)
                write('companion-native-'..id..'.txt',table.concat(rows,'\n'));return
            end
            if hint=='menuprobe'then
                local pc=playerController();assert(valid(pc)and valid(pc.Pawn),'Player unavailable')
                local report=NativeMenu.probe(pc)
                write('companion-native-'..id..'.txt','Native UMG construction and cleanup:\n'..report);return
            end
            if hint=='menupreview'then
                NativeMenu.preview(playerController());return
            end
            if hint=='attackconfig'then
                local report=assert(loadfile(root..'/../mod/Development/inspect_companion_attacks.lua'))()(root)
                write('companion-native-'..id..'.txt',report);return
            end
            if hint=='attacktree'then
                local report=assert(loadfile(root..'/../mod/Development/inspect_companion_tree.lua'))()(root)
                write('companion-native-'..id..'.txt',report);return
            end
            if hint=='companiondefs'then
                local native=require('companion_native');local pc=playerController()
                assert(valid(pc)and valid(pc.Pawn),'Player unavailable')
                local rows={}
                for _,path in ipairs({
                    '/Game/_Dawnwalker/Combat/Enemies/Bosses/Lacra/NPCDef_Lacra_Base.NPCDef_Lacra_Base_C',
                    '/Game/_Dawnwalker/Quest/q103_lacra/Characters/Humanoid/NPCDef_Lacra.NPCDef_Lacra_C',
                    '/Game/_Dawnwalker/Quest/q103_lacra/Characters/Humanoid/NPCDef_Lacra_Boss.NPCDef_Lacra_Boss_C',
                    '/Game/_Dawnwalker/Combat/Enemies/Bosses/Ambrus/NPCDef_Ambrus_Base.NPCDef_Ambrus_Base_C',
                })do
                    rows[#rows+1]='DEFINITION '..path
                    local class=native.loadedClass(path)
                    if not valid(class)then
                        local requested,why=native.requestClass(pc.Pawn,path)
                        rows[#rows+1]=requested and 'ASYNC LOAD REQUESTED'or tostring(why)
                    else
                        local def=class:GetCDO();local result,why=native.inspect(def)
                        rows[#rows+1]=result and result.raw or tostring(why)
                        local function read(key,fn)local ok,v=pcall(fn);rows[#rows+1]=key..'='..(ok and tostring(v)or tostring(v))end
                        local function name(o)return valid(o)and o:GetFullName()or 'None'end
                        for _,key in ipairs({'CharacterAbilityConfig','EnemyConfig','DefaultMovementProfile','DefaultAnimLayer','OffenseBehaviorTree','NeutralBehaviorTree'})do read(key,function()return name(def[key])end)end
                        read('boss',function()return def.bIsBoss end)
                        read('deathFact',function()return def.FactTagToAddAfterDying.TagName:ToString()end)
                        read('abilities',function()
                            local a=def.CharacterAbilityConfig;if not valid(a)then return 'None'end
                            local out={};assert(#a.DefaultAbilities<256)
                            for i=1,#a.DefaultAbilities do out[#out+1]=name(a.DefaultAbilities[i])end
                            return table.concat(out,';')
                        end)
                        local function mapText(map,objects)
                            assert(#map<256);local out={}
                            map:ForEach(function(k,v)out[#out+1]=tostring(k:get())..'='..(objects and name(v:get())or tostring(v:get()))end)
                            return table.concat(out,';')
                        end
                        read('abilityLevels',function()
                            local out={};local map=def.CharacterAbilityConfig.DefaultAbilitiesWithLevels;assert(#map<256)
                            map:ForEach(function(k,v)out[#out+1]=name(k:get())..'='..tostring(v:get())end)
                            return table.concat(out,';')
                        end)
                        read('equipment',function()return mapText(def.EquipmentSlots,true)end)
                        read('combatAnimations',function()return mapText(def.CombatAnimationConfigs,true)end)
                        read('handWeapons',function()return mapText(def.EnemyConfig.HandToHandWeapons,true)end)
                        read('fistWeapons',function()return mapText(def.EnemyConfig.FistfightWeapons,true)end)
                    end
                end
                write('companion-native-'..id..'.txt',table.concat(rows,'\n'));return
            end
            if hint=='followprofiles'then
                local rows={}
                for _,path in ipairs({'/Game/_Dawnwalker/NPC/BasicNPC/MovementProfiles/DA_Follower_Runner_MovementProfile.DA_Follower_Runner_MovementProfile','/Game/_Dawnwalker/NPC/BasicNPC/MovementProfiles/DA_Follower_Walker_MovementProfile.DA_Follower_Walker_MovementProfile','/Game/_Dawnwalker/Player/MovementProfiles/DA_Combat_Defense_MovementProfile.DA_Combat_Defense_MovementProfile'})do
                    local profile=StaticFindObject(path)
                    rows[#rows+1]=path..'\t'..(valid(profile)and ('priority='..tostring(profile.Priority)..' maxSpeed='..tostring(profile.MovementConfig.MaxSpeed))or 'not loaded')
                end
                write('companion-native-'..id..'.txt',table.concat(rows,'\n'));return
            end
            if hint=='readiness'then
                local native=require('companion_native');local rows={}
                for _,path in ipairs({'/Script/Engine.KismetSystemLibrary','/Game/_Dawnwalker/NPC/MainNPC/NPCDef_Anca.NPCDef_Anca_C','/Game/_Dawnwalker/NPC/BasicNPC/BP_NonPlayerCharacter.BP_NonPlayerCharacter_C'})do
                    local class=native.loadedClass(path);rows[#rows+1]=path..'\t'..(valid(class)and 'ready'or 'not loaded')
                end
                write('companion-native-'..id..'.txt',table.concat(rows,'\n'));return
            end
            if hint=='async'then
                local pc=playerController();assert(valid(pc)and valid(pc.Pawn),'Player unavailable')
                local native=require('companion_native');local c=require('companion_config').characters[1]
                local result,why=native.requestClass(pc.Pawn,c.path);assert(result,why)
                write('companion-native-'..id..'.txt',result.raw);return
            end
            local Native=assert(loadfile(root..'/../mod/Scripts/companion_native.lua'))()
            local result,why=Native.probe();assert(result,why)
            local rows={result.raw}
            write('companion-native-info.txt',result.raw)
            local classPath='/Game/_Dawnwalker/NPC/MainNPC/NPCDef_Anca.NPCDef_Anca_C'
            write('companion-native-phase.txt','Loading Anca definition through native class loader')
            local class,loadError=Native.loadClass(classPath);assert(valid(class),loadError)
            write('companion-native-phase.txt','Exporting Anca definition soft references')
            local exported,err=Native.inspect(class:GetCDO());assert(exported,err);rows[#rows+1]=exported.raw
            write('companion-native-info.txt',table.concat(rows,'\n'))
            write('companion-native-phase.txt','Completed')
            return
        end
        if action=='catalog' then
            -- A completed command must not rescan thousands of assets every time
            -- application code reloads. A new explicit command id starts a new scan.
            local marker=io.open(root..'/companion-catalog-'..id..'.txt','r')
            if marker then marker:close();return end
            write('companion-catalog-'..id..'.txt','Started '..os.date()..'\n')
            write('companion-asset-catalog.tsv',Engagement.catalog())
            write('companion-catalog-'..id..'.txt','Completed '..os.date()..'\n');return
        end
        if action=='aiinfo' then
            local rows={}
            for _,actor in ipairs(FindAllOf('Pawn')or {})do
                if valid(actor)and actor:GetFullName():lower():find(hint:lower(),1,true)then
                    rows[#rows+1]=Engagement.inspect(actor)
                end
            end
            write('ai-inspection.txt',table.concat(rows,'\n\n'));return
        end
        if action=='identities' then
            local marker=io.open(root..'/identity-dump-'..id..'.txt','r')
            if marker then marker:close();return end
            write('identity-dump-'..id..'.txt','Started\n')
            local rows={'actor\tname\tdefinition\tbodyType\tvoiceTag'}
            for _,actor in ipairs(FindAllOf('Pawn') or {})do
                if valid(actor) then
                    local info=Targeting.identify(actor)
                    table.insert(rows,table.concat({clean(actor:GetFullName()),clean(info.name),clean(info.definition),clean(info.bodyType),clean(info.voiceTag)},'\t'))
                end
            end
            write('npc-identities.tsv',table.concat(rows,'\n'));write('identity-dump-'..id..'.txt','Completed\n');return
        end
        if action=='dump' then
            -- Native UE4SS metadata dumper; never iterate arbitrary property values in Lua.
            local marker=io.open(root..'/native-dump-'..id..'.txt','r')
            if marker then marker:close();return end
            write('native-dump-'..id..'.txt','Started '..os.date()..'\n')
            if selected then stop('Released for native metadata dump') end
            DumpAllObjects()
            write('native-dump-'..id..'.txt','Completed '..os.date()..'\n')
            return
        end
        if action~='inspect' and action~='preview' then error('Unknown development action') end
        local player=UE.GetPlayer();if not valid(player) then error('Player not ready; issue a new command after loading') end
        local candidates={};local p=player:K2_GetActorLocation()
        for _,actor in ipairs(FindAllOf('Pawn') or {}) do
            if valid(actor) and actor:GetFullName()~=player:GetFullName() and actor:GetFName():ToString():lower():find(hint:lower(),1,true) then
                local a=actor:K2_GetActorLocation()
                if actor:GetWorld():GetFullName()==player:GetWorld():GetFullName() and (a.X-p.X)^2+(a.Y-p.Y)^2+(a.Z-p.Z)^2<=config.MaxDistance^2 then table.insert(candidates,actor) end
            end
        end
        if #candidates~=1 then error('Expected one nearby NPC matching '..hint..'; found '..#candidates) end
        if selected then stop('Released previous test target') end
        cachedController=playerController()
        if action=='inspect' then inspect(candidates[1],true);bindings={} else preview(candidates[1]) end
    end)
    write('dev-response.txt',id..'\n'..(ok and 'OK' or tostring(err))..'\n');log('Development '..action..': '..(ok and 'OK' or tostring(err)))
end
local lastBackgroundAttempt=0
local lastUiCommand=''
local lastQuestRead=0
local lastEnvironmentRead,lastEnvironmentGeneration=0,0
local function environmentContext()
    if os.time()-lastEnvironmentRead<5 and lastEnvironmentGeneration==generation then return end
    lastEnvironmentRead=os.time();lastEnvironmentGeneration=generation
    local pc=cachedController
    if not valid(pc)then pc=playerController()end
    local actor=selected or (valid(pc)and pc.Pawn or nil)
    local ok,row,errors=pcall(Targeting.environmentSnapshot,actor)
    if ok then
        write('environment.txt',tostring(os.time())..'\t'..tostring(generation)..'\t'..row..'\n')
        write('environment-status.txt',errors==''and 'Verified region/time/weather reads succeeded' or errors)
    else write('environment-status.txt',tostring(row))end
end
local function questMemory()
    if os.time()-lastQuestRead<10 then return end;lastQuestRead=os.time()
    local ok,rows,journal=pcall(Targeting.questSnapshot)
    if ok then write('quests.txt',tostring(os.time())..'\n'..journal..'\n'..rows..'\n')
    else write('quest-status.txt',tostring(rows))end
end
do local f=io.open(root..'/ui-control.txt','r');if f then lastUiCommand=f:read('*a');f:close()end end
local lastGroupCommand=''
local function groupCommand()
    local f=io.open(root..'/group-control.tsv','r');if not f then return end
    local command=f:read(2048)or '';f:close()
    if command==''or command==lastGroupCommand then return end
    local endRoom,endToken,endGeneration=command:match('^GROUPEND\t1\t([%w%-]+)\t([%w%-]+)\t(%d+)')
    if endToken then
        lastGroupCommand=command
        if conversationMode=='group'and conversationRoom==endRoom and generation==tonumber(endGeneration)and selected then
            releaseConversation();log('Group replies complete; conversation movement released')
        end
        return
    end
    local room,token,member,expected=command:match('^GROUP\t1\t([%w%-]+)\t([%w%-]+)\t([%w%-]+)\t(%d+)')
    if not token then return end
    if conversationMode~='group'or conversationRoom~=room or generation~=tonumber(expected)or not selected then lastGroupCommand=command;write('group-ready.tsv',token..'\tfailed');return end
    local actor,pending=Companions.actor(member)
    -- An arrival/turn action can temporarily own the next companion. Let it
    -- finish; the bridge bounds this wait instead of silently dropping them.
    if not actor then
        if not pending then lastGroupCommand=command;write('group-ready.tsv',token..'\tfailed')end
        return
    end
    lastGroupCommand=command
    -- Do not expose an inactive intermediate selection to the 33 ms bridge.
    local ok=pcall(function()stop('Group speaker handoff',true);speakerTurn=token;toggle('compose',actor)end)
    if not ok then stop('Group speaker unavailable')end
    write('group-ready.tsv',token..'\t'..(ok and selected and 'ready'or 'failed'))
end
local function uiCommand()
    if not config.UseFaceLayer then return end
    if composeController then
        local lease=io.open(root..'/ui-active.txt','r');local stamp=0
        if lease then stamp=tonumber(lease:read('*a'))or 0;lease:close()end
        if os.time()-stamp>4 then restoreFocusPause()end
    end
    local f=io.open(root..'/ui-control.txt','r');if not f then return end
    local command=f:read('*a');f:close()
    if command==lastUiCommand then return end;lastUiCommand=command
    if command:match('^native%-menu:')then
        if selected then stop('Companion menu')else restoreFocusPause()end
        NativeMenu.toggle(playerController())
    elseif command:match('^party:')then
        if selected then stop('Conversation ended for companion menu')else restoreFocusPause()end
        local pc=playerController()
        if not valid(pc)or not valid(pc.Pawn)then write('ui-ready.txt',command..'\nLoad a save first');return end
        local ok,why=acquireUiInput(pc)
        if not ok then write('ui-ready.txt',command..'\n'..why);return end
        write('ui-ready.txt',command..'\nready')
    elseif command:match('^compose%-')or command:match('^select%-')then
        NativeMenu.close()
        local group=command:find('%-group:')~=nil
        -- Resolve before releasing the old selection. A failed lookup must not
        -- destroy a working chat; every key press chooses from current positions.
        local actor,reason=trace(group)
        if not actor then write('ui-ready.txt',command..'\n'..(reason or 'No nearby conversation target'));return end
        if selected then stop('Selecting conversation')else restoreFocusPause()end
        conversationMode=group and 'group'or 'single'
        conversationRoom=command:match(':([%w%-]+)')or '';speakerTurn=''
        toggle('compose',actor)
        if not selected then write('ui-ready.txt',command..'\n'..(status or 'Conversation target unavailable'));return end
        if command:match('^compose%-')and not composeController then
            local pc=activeController
            if not valid(pc)then write('ui-ready.txt',command..'\nPlayer controller unavailable');return end
            local ok,why=acquireUiInput(pc)
            if not ok then write('ui-ready.txt',command..'\n'..why);return end
        end
        write('ui-ready.txt',command..'\nready')
    elseif command:match('^close:')then restoreFocusPause()end
end
local launchBackground
if config.AutoStartConvai then LoopAsync(1000,function()
    local now=os.time()
    if now-lastBackgroundAttempt<30 then return false end
    local f=io.open(root..'/background-heartbeat.txt','r');local heartbeat=0
    if f then heartbeat=tonumber(f:read('*a'))or 0;f:close()end
    local restart=io.open(root..'/background-restart.request','r')
    local requested=restart~=nil;if restart then restart:close()end
    if now-heartbeat>10 or requested then
        lastBackgroundAttempt=now
        -- The native export starts the fixed script without opening a console.
        if not launchBackground then
            local fn,err=package.loadlib(root..'/../bridge/native/background_launcher_v1.dll','start_background_hidden')
            if not fn then log('Background launcher unavailable: '..tostring(err));return false end
            launchBackground=fn
        end
        local ok,err=pcall(launchBackground)
        if not ok then log('Background launch failed: '..tostring(err));return false end
        local failure=io.open(root..'/background-launch-error.txt','r')
        if failure then log((failure:read('*a')or 'Background launch failed'):gsub('%s+$',''));failure:close()end
    end
    return false
end)end
safe(function() status='v0.5.1: companions, conversations and horde mode';publish();log(status) end)
-- One dispatcher owns camera and application work. A lost UE4SS callback must
-- not leave either path permanently marked pending.
local partyElapsed,workElapsed=0,0
local dispatchSerial,dispatchAt=0,0
LoopAsync(16,function()
    partyElapsed=partyElapsed+16;workElapsed=workElapsed+16
    local partyDue=partyElapsed>=250;local workDue=workElapsed>=33
    local cameraDue=Settings.values.FirstPersonCamera==1 or FirstPerson.active()
    local ordinaryDue=workDue and (selected~=nil or partyDue or NativeMenu.isOpen())
    if not cameraDue and not ordinaryDue then return false end
    idleSecond=os.time()
    if pending and os.time()-dispatchAt<2 then return false end
    pending=true;dispatchAt=os.time();dispatchSerial=dispatchSerial+1
    local ticket=dispatchSerial
    if ordinaryDue then workElapsed=workElapsed%33 end
    if ordinaryDue and partyDue then partyElapsed=0 end
    local queued,queueError=pcall(ExecuteInGameThread,function()
        if ticket~=dispatchSerial then return end
        local tickOk=safe(function()
            if partyDue then Settings.poll()end
            -- Text/voice chat owns input, not the viewpoint. Keep first person
            -- throughout single/group chat; native scenes still yield inside tick.
            FirstPerson.tick(playerController(),Settings.values.FirstPersonCamera==1,NativeMenu.isOpen())
            if not ordinaryDue then return end
            if partyDue then Horde.tick(false)end
            NativeMenu.tick()
            uiCommand()
            if partyDue then Companions.tick(playerController(),selected);groupCommand()end
            if (selected or NativeMenu.isOpen())and os.time()-lastRelationshipRead>=2 then
                lastRelationshipRead=os.time()
                local ok,snapshot=pcall(Romance.snapshot,playerController())
                if ok then write('relationships.tsv',snapshot)else write('relationship-status.txt',tostring(snapshot))end
            end
            -- Journal/environment reads are conversation work. Leave them idle
            -- while simply playing; opening chat refreshes overdue snapshots.
            if selected then
                questMemory()
                environmentContext()
            end
            if os.time()~=lastHeartbeat then lastHeartbeat=os.time();write('game-heartbeat.txt',tostring(lastHeartbeat));publish() end
            if os.time()~=devSecond then devSecond=os.time();developmentCommand() end
            if not selected then return end
            -- FindAllOf scans GUObjectArray in this loader build. Never do it per frame.
            local pc=activeController
            if not valid(selected) or not valid(pc) or not valid(pc.Pawn) then forgetConversation('Target unloaded');return end
            local selectedWorld,playerWorld=selected:GetWorld(),pc.Pawn:GetWorld()
            if not valid(selectedWorld)or not valid(playerWorld)or selectedWorld:GetAddress()~=playerWorld:GetAddress() then forgetConversation('World changed');return end
            local a,b=pc.Pawn:K2_GetActorLocation(),selected:K2_GetActorLocation()
            if updateCount%3==0 then
                -- Roughly 10 Hz; no object scan, socket lookup or audio/network work.
                local ok,row=pcall(spatialSnapshot,pc,b)
                if ok then write('spatial.txt',row)end
                local message=ok and 'Camera-space coordinates active' or ('Spatial position failed: '..tostring(row))
                if message~=lastSpatialStatus then lastSpatialStatus=message;write('spatial-status.txt',message);log(message)end
            end
            local following=engagement and engagement.following
            local releaseDistance=following and (config.CompanionMaxDistance or 10000)or 3000
            if (a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2>releaseDistance^2 then stop('Moved away from character');return end
            -- Single chat keeps its distance/facing rule; a group ends only after
            -- the player leaves its shared area for two seconds. Looking between
            -- speakers or receiving a handoff is never evidence of walking away.
            if updateCount%3==0 then
                local away=false
                pcall(function()
                    local forward=UE.GetKismetMathLibrary():GetForwardVector(pc.PlayerCameraManager:GetCameraRotation())
                    away=conversationWalkedAway(a,forward,b,following)
                end)
                if away then
                    lookingAwaySince=lookingAwaySince or os.time()
                    if os.time()-lookingAwaySince>=2 then stop('Conversation ended: walked away');return end
                else lookingAwaySince=nil end
            end
            updateCount=updateCount+1
            if updateCount%150==0 then pcall(function()write('ai-inspection.txt',Engagement.inspect(selected))end)end
            if updateCount%6==0 then applyAction();if not selected then return end end
            if engagement and engagement.following then
                if updateCount%30==0 then
                    local following,reason=Engagement.followTick(engagement,pc.Pawn)
                    if not following then stop(reason or 'Native companion mode ended');return end
                end
            elseif engagement and updateCount%3==0 then
                Engagement.face(engagement,a,pc.Pawn)
                if engagement.blocked then stop('Conversation yielded to native AI');return end
            end
            if config.FaceAndHold and not engagement and updateCount%3==0 then attention=Engagement.attend(attention,selected,pc.Pawn,log,false)end
            if previewEnd>0 then
                if os.time()>=previewEnd then stop('Six-second test finished; NPC controls and morph weights restored');return end
                previewTick=previewTick+1
                local value=(math.sin(previewTick*0.18)+1)*0.3
                if speechLayer then FaceGraph.applyWeights(speechLayer,{JawOpen=value})end
                for _,binding in ipairs(bindings) do if valid(binding.mesh) then
                    local weight=(binding.channel=='JawOpen' or binding.channel=='MouthFunnel') and value or binding.original
                    binding.mesh:SetMorphTarget(FName(binding.name),weight,true)
                end end
                return
            end
            local f=io.open(root..'/frame.txt','r');if not f then
                neutral();if os.time()-selectedAt>5 then stop('No Convai bridge; released NPC') end;return
            end
            local data=f:read('*a');f:close()
            local gen,time=data:match('^(%d+)\t(%d+)\n')
            if tonumber(gen)~=generation or not time or math.abs(os.time()-tonumber(time))>2 then
                neutral();if os.time()-selectedAt>5 then stop('Convai bridge not responding; released NPC') end;return
            end
            selectedAt=os.time()
            releaseCompletedReply(data)
            local weights={}
            for name,value in data:gmatch('\n([%w_]+)\t([%d%.]+)') do weights[name]=math.max(0,math.min(1,tonumber(value) or 0)) end
            if speechLayer then FaceGraph.applyWeights(speechLayer,weights)end
            for _,binding in ipairs(bindings) do
                if valid(binding.mesh) then binding.mesh:SetMorphTarget(FName(binding.name),weights[binding.channel] or 0,true) end
            end
        end)
        pending=false
        if not tickOk and selected then safe(function() stop('Stopped after an update error; restoring NPC') end) end
    end)
    if not queued then pending=false;log('Game-thread queue rejected update: '..tostring(queueError))end
    return false
end)

-- The helper routes configurable keys and consumes them before the pause UI.
-- Keep the stable bootstrap callback inert, including after rebinding F5.
RegisterKeyBind(Key.F5,function()end)
