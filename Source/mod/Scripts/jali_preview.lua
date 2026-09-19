-- Silent replay of Anca's existing JALI curve table, using reflected setters only.
local M={}
local function valid(o)return o and o:IsValid()end
local function identity(o)return valid(o) and o:GetFullName() or nil end
function M.begin(actor,now,log)
    local cls=StaticFindObject('/Script/JALI.JaliAnimationComponent')
    if not valid(cls)then return nil,'JALI component class unavailable'end
    local components=actor:K2_GetComponentsByClass(cls)
    local component
    if #components>0 then component=components[1]end
    if not valid(component)then return nil,'Selected NPC has no JALI component'end
    local player=component:GetAnimPlayer()
    if not valid(player)then return nil,'JALI player not initialized'end
    -- Explicit ObjectProperty verified by v0.7; no soft-reference/struct reads.
    local animation=player.CurrentAnimation
    if not valid(animation)then return nil,'No retained JALI animation. Hear one normal game dialogue line, exit dialogue, then try F6 again.'end
    local curveClass=StaticFindObject('/Script/Engine.CurveTable')
    if not valid(curveClass) or not animation:IsA(curveClass)then return nil,'Current JALI animation is not a CurveTable'end
    if player:IsPlaying()then return nil,'JALI is playing dialogue. Wait until the line finishes before F6.'end
    local audio=player.AudioComponent
    if not valid(audio)then return nil,'JALI audio component unavailable; Play requires a valid component'end
    if audio:IsPlaying()then return nil,'JALI audio is active; wait until dialogue finishes'end
    local volume=audio.VolumeMultiplier
    if type(volume)~='number' or volume~=volume or math.abs(volume)==math.huge then return nil,'Cannot capture JALI audio volume'end
    local time=player:GetTime()
    local hold=player:GetShouldHoldPose()
    if type(time)~='number' or time~=time or time==math.huge or time==-math.huge or type(hold)~='boolean'then return nil,'Invalid JALI playback state'end
    local state={actor=actor,player=player,audio=audio,volume=volume,animation=animation,animationName=animation:GetFullName(),time=time,hold=hold,deadline=now+6,frame=0,log=log}
    log('Captured '..state.animationName..'; original time='..time..'; hold='..tostring(hold))
    local ok,err=pcall(function()
        log('NEXT mute JALI audio and enable hold pose')
        audio:SetVolumeMultiplier(0);player:SetShouldHoldPose(true)
        log('NEXT JALI Play(0): enable playback, not only seek')
        state.started=true;player:Play(0)
        log('Playing after Play: '..tostring(player:IsPlaying()))
    end)
    if not ok then M.finish(state,'setup error');error(err)end
    return state,'JALI playback test: six seconds, facing you and held still. F7 releases.'
end
function M.finish(state,reason,relinquish)
    if not state or state.finished then return end
    state.finished=true
    local p=state.player
    if valid(p)then
        if state.started and not relinquish then
            local ok,err=pcall(function()p:Pause()end)
            if not ok then state.log('Pause failed: '..tostring(err))end
        end
        -- If normal dialogue started, leave its current playback position alone.
        local timeOK,timeError=pcall(function()
            if not relinquish and identity(p.CurrentAnimation)==state.animationName and not p:IsPlaying()then p:SetTime(state.time)end
        end)
        if not timeOK then state.log('Restore time failed: '..tostring(timeError))end
        local ok,err=pcall(function()p:SetShouldHoldPose(state.hold)end)
        if not ok then state.log('Restore hold failed: '..tostring(err))end
    end
    if valid(state.audio)then
        local ok,err=pcall(function()state.audio:SetVolumeMultiplier(state.volume)end)
        if not ok then state.log('Restore volume failed: '..tostring(err))end
    end
    state.log('END '..reason)
end
function M.tick(state,now)
    if state.finished then return true end
    if not valid(state.actor)or not valid(state.player)then M.finish(state,'target unloaded',true);return true end
    local p=state.player
    if identity(p.CurrentAnimation)~=state.animationName then
        M.finish(state,'game took over JALI playback',true);return true
    end
    if now>=state.deadline then M.finish(state,'six-second test complete');return true end
    state.frame=state.frame+1
    -- Traverse the first four seconds of the retained line, then loop briefly.
    p:SetTime((state.frame*0.05)%4)
    if state.frame==1 or state.frame%20==0 then state.log('Sample time='..p:GetTime()..'; playing='..tostring(p:IsPlaying()))end
    return false
end
return M
