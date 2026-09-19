local M = {}
-- UEHelpers.GetPlayerController uses FindAllOf, which scans GUObjectArray.
-- A party tick must reuse the live controller; failed lookups during loading
-- are throttled too. Pawn/world transitions remain checked by each caller.
local cachedPlayerController,nextControllerRetry=nil,0
function M.playerController(find,now)
    if cachedPlayerController and cachedPlayerController:IsValid() then return cachedPlayerController end
    if now<nextControllerRetry then return nil end
    nextControllerRetry=now+2
    cachedPlayerController=find()
    if cachedPlayerController and cachedPlayerController:IsValid() then return cachedPlayerController end
    return nil
end
function M.walkedAway(player,forward,location,radius,following)
    if following then return false end
    local x,y,z=location.X-player.X,location.Y-player.Y,location.Z-player.Z
    if x*x+y*y+z*z<=radius*radius then return false end
    return M.score(player,forward,location,math.huge,80)==nil
end
-- Ground-plane proximity and facing: aiming at a face is not required.
function M.score(player, forward, location, maxDistance, halfAngle)
    local x,y,z=location.X-player.X,location.Y-player.Y,location.Z-player.Z
    local distance=math.sqrt(x*x+y*y+z*z)
    if distance>maxDistance then return nil,distance,'outside range' end
    local flat=math.sqrt(x*x+y*y)
    local length=math.sqrt(forward.X*forward.X+forward.Y*forward.Y)
    local dot=(flat>0.01 and length>0.01) and (x*forward.X+y*forward.Y)/(flat*length) or 1
    if dot<math.cos(math.rad(halfAngle)) then return nil,distance,'outside facing angle' end
    return distance+maxDistance*0.35*(1-dot),distance,'in range'
end
-- These exact reflected functions/types were verified in the native UE4SS dump.
-- Read only known object/name/text fields, once per selection; never SoftObject fields.
function M.identify(actor)
    local result={name='',definition='',bodyType='',voiceTag=''}
    pcall(function()
        local library=StaticFindObject('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary')
        if not library or not library:IsValid() then return end
        local stub=library:GetAIStub(actor)
        if not stub or not stub:IsValid() then return end
        local definition=stub:GetNPCDefinition()
        if not definition or not definition:IsValid() then return end
        result.definition=definition:GetFullName()
        result.bodyType=definition.BodyType:ToString()
        local npcType=StaticFindObject('/Script/Dawnwalker.DogwoodNPCDefinition')
        if npcType and npcType:IsValid() and definition:IsA(npcType) then
            result.name=definition.CharacterName:ToString()
            result.voiceTag=definition.VoiceTag.TagName:ToString()
        end
    end)
    return result
end
local cachedJournal=nil
function M.questSnapshot()
    local journal=cachedJournal
    if not journal or not journal:IsValid()then
    journal=nil
    for _,candidate in ipairs(FindAllOf('Journal') or {})do
        if candidate:IsValid() and candidate:GetFullName():find('/Engine/Transient.',1,true)then
            if journal then error('Multiple live journals; memory update withheld')end
            journal=candidate
        end
    end
    if not journal then error('Live journal unavailable')end
    cachedJournal=journal
    end
    local enum=StaticFindObject('/Script/Quest.EQuestState')
    local states={}
    enum:ForEachName(function(name,value)states[#states+1]={name=name:ToString(),value=value}end)
    local lines={}
    for _,state in ipairs(states)do
        local label=state.name:match('([^:]+)$')or state.name
        if not label:lower():find('max',1,true)then
            local quests={};journal:GetQuests(state.value,quests)
            for i=1,#quests do
                local quest=quests[i]
                if quest and quest:IsValid()then
                    local title=quest.Title:ToString()
                    local ending=''
                    -- Read only the selected ending, never undiscovered alternatives.
                    local chosen=quest.ChosenQuestEnding;local endings=quest.EndingDescriptions
                    if label=='EQS_Success' or label:lower():find('complet') or label:lower():find('finish') or label:lower():find('fail') then
                        for j=1,math.min(#endings,64)do
                            local entry=endings[j]
                            if entry.EndingID==chosen then ending=entry.Description:ToString();break end
                        end
                    end
                    local function clean(s)return (tostring(s):gsub('[\r\n\t]',' '))end
                    lines[#lines+1]=table.concat({clean(quest.InstanceId:ToString()),clean(label),clean(title),clean(ending)},'\t')
                end
            end
        end
    end
    table.sort(lines)
    return table.concat(lines,'\n'),journal:GetFullName()
end
local environmentCache={}
function M.environmentSnapshot(actor)
    if not actor or not actor:IsValid()then error('No observation actor')end
    local world=actor:GetWorld():GetFullName()
    local function instance(class)
        local old=environmentCache[class]
        if old and old.world==world and old.object:IsValid()then return old.object end
        local found=nil
        for _,candidate in ipairs(FindAllOf(class)or{})do
            local name=candidate:GetFullName()
            if candidate:IsValid()and not name:find('Default__',1,true)then
                local cw=candidate:GetWorld()
                if cw and cw:IsValid()and cw:GetFullName()==world then
                    if found then error('Multiple '..class..' instances')end
                    found=candidate
                end
            end
        end
        if not found then error(class..' unavailable')end
        environmentCache[class]={world=world,object=found};return found
    end
    local result,errors={},{}
    local function read(label,fn)local ok,e=pcall(fn);if not ok then errors[#errors+1]=label..': '..tostring(e)end end
    read('region',function()result.region=instance('RegionsSubsystem'):GetRegionForActor(actor).RegionDisplayText:ToString()end)
    read('time',function()
        local time=instance('TimeSystemImpl'):GetCurrentDayTime()
        result.hour=time.Hour;result.minute=time.Minute
    end)
    read('weather',function()
        local fx=instance('SkyCreator'):GetWeatherFXSettings()
        result.rain=fx.RainAmount;result.snow=fx.SnowAmount
    end)
    local function clean(s)return (tostring(s or ''):gsub('[\r\n\t]',' '))end
    return table.concat({clean(result.region),clean(result.hour),clean(result.minute),clean(result.rain),clean(result.snow)},'\t'),table.concat(errors,'; ')
end
-- Pure camera-space conversion, using only the live camera and selected actor.
-- Unreal uses centimetres/+X forward/+Y right/+Z up; Web Audio uses metres,
-- +X right/+Y up/-Z forward. Offset from capsule origin to approximate mouth height.
function M.spatial(camera,rotation,source,generation,stamp)
    local function finite(n)return type(n)=='number'and n==n and math.abs(n)<1e12 end
    -- UE4SS RC5 returns GetCameraRotation as {pitch=...,Yaw=...,Roll=...}.
    -- Other reflected rotators use Pitch. Normalize only these known fields.
    local pitchDegrees=rotation.Pitch;if pitchDegrees==nil then pitchDegrees=rotation.pitch end
    local values={camera.X,camera.Y,camera.Z,source.X,source.Y,source.Z,pitchDegrees,rotation.Yaw,rotation.Roll}
    -- ipairs stops at a nil hole; check every required value explicitly.
    for i=1,9 do
        if not finite(values[i])then error('Invalid spatial coordinate field '..i)end
    end
    local yaw,pitch,roll=math.rad(rotation.Yaw),math.rad(pitchDegrees),math.rad(rotation.Roll)
    local cy,sy,cp,sp,cr,sr=math.cos(yaw),math.sin(yaw),math.cos(pitch),math.sin(pitch),math.cos(roll),math.sin(roll)
    local x,y,z=source.X-camera.X,source.Y-camera.Y,source.Z+60-camera.Z
    local forward=x*cp*cy+y*cp*sy+z*sp
    local right=-x*sy+y*cy
    local up=-x*sp*cy-y*sp*sy+z*cp
    return string.format('%d\t%d\t%.4f\t%.4f\t%.4f\n',stamp,generation,(right*cr-up*sr)/100,(right*sr+up*cr)/100,-forward/100)
end
return M
