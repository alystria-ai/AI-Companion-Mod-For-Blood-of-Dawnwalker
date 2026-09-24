-- Inspect class metadata and linked layers belonging to the selected face only.
-- Fixed, verified numeric inputs only; no array callbacks or arbitrary property traversal.
local M={}
local AI=require('ai_state')
local ambientFaces={}
local upperNames={}
for _,name in ipairs({'eyeBlink','eyeWiden','eyeSquintInner','eyeCheekRaise','browDown','browLateral','browRaiseIn','browRaiseOuter','noseWrinkle'})do
    for _,side in ipairs({'L','R'})do upperNames[#upperNames+1]='CTRL_expressions_'..name..side end
end
local function bounded(value)
    return type(value)=='number'and value==value and math.max(0,math.min(1,value))or 0
end
function M.catalog(log)
    log('NEXT FindObjects animation class metadata')
    local classes=FindObjects(0,'AnimBlueprintGeneratedClass',nil,0,0,false)or{}
    log('Class definitions returned: '..#classes)
    local seen={}
    for _,cls in ipairs(classes)do
        if cls and cls:IsValid()then
            local name=cls:GetFullName();local lower=name:lower()
            if lower:find('face',1,true)or lower:find('jali',1,true)or lower:find('lipsync',1,true)then
                log('CANDIDATE '..name)
                local parent=cls
                for depth=1,4 do
                    if not parent or not parent:IsValid()then break end
                    local full=parent:GetFullName()
                    if seen[full]or full:find('/Script/Engine.',1,true)then break end
                    seen[full]=true;log('CLASS '..full)
                    local count=0
                    parent:ForEachProperty(function(p)
                        count=count+1;if count>128 then return true end
                        log('  '..tostring(p:GetFullName()))
                    end)
                    parent=parent:GetSuperStruct()
                end
            end
        end
    end
    -- Exact actor path from the user's latest successful report; read-only lookup.
    local actor=StaticFindObject('/Game/Map_Blockout_Valley/Blockout_Valley.Blockout_Valley:PersistentLevel.Anca_241')
    if actor and actor:IsValid()then
        local meshes=actor:K2_GetComponentsByClass(StaticFindObject('/Script/Engine.SkeletalMeshComponent'))
        for _,mesh in ipairs(meshes)do
            if mesh:IsValid()and mesh:GetFName():ToString():lower():find('face',1,true)then
                local main=mesh:GetAnimInstance()
                if main and main:IsValid()then
                    for _,cls in ipairs(classes)do
                        if cls and cls:IsValid()then
                            local linked=main:GetLinkedAnimLayerInstanceByClass(cls,false)
                            if linked and linked:IsValid()then log('EXACT ATTACHED '..cls:GetFullName())end
                        end
                    end
                end
            end
        end
    end
    log('CATALOG COMPLETE')
end
local function valid(o)return o and o:IsValid()end
function M.isCurrent(state)
    if not state or state.restored or not valid(state.main)or not valid(state.instance)or not valid(state.desired)then return false end
    local ok,current=pcall(function()return state.main:GetLinkedAnimLayerInstanceByClass(state.desired,false)end)
    return ok and valid(current)and current:GetAddress()==state.instance:GetAddress()
end
local function each(a,fn)
    for i=1,#a do fn(a[i])end
end
-- Exact 129-name order captured from this game's face-layer CDO; no runtime name iteration.
local directNames={
    'CTRL_expressions_mouthCheekSuckL',
    'CTRL_expressions_mouthCheekSuckR',
    'CTRL_expressions_mouthCheekBlowR',
    'CTRL_expressions_mouthCheekBlowL',
    'CTRL_expressions_mouthLeft',
    'CTRL_expressions_mouthUp',
    'CTRL_expressions_mouthUpperLipRaiseL',
    'CTRL_expressions_mouthUpperLipRaiseR',
    'CTRL_expressions_mouthLowerLipDepressL',
    'CTRL_expressions_mouthLowerLipDepressR',
    'CTRL_expressions_mouthCornerPullL',
    'CTRL_expressions_mouthCornerPullR',
    'CTRL_expressions_mouthStretchL',
    'CTRL_expressions_mouthStretchR',
    'CTRL_expressions_mouthDimpleL',
    'CTRL_expressions_mouthDimpleR',
    'CTRL_expressions_mouthCornerDepressL',
    'CTRL_expressions_mouthCornerDepressR',
    'CTRL_expressions_mouthLipsPurseUL',
    'CTRL_expressions_mouthLipsPurseUR',
    'CTRL_expressions_mouthLipsPurseDL',
    'CTRL_expressions_mouthLipsPurseDR',
    'CTRL_expressions_mouthLipsTowardsUL',
    'CTRL_expressions_mouthLipsTowardsUR',
    'CTRL_expressions_mouthLipsTowardsDL',
    'CTRL_expressions_mouthLipsTowardsDR',
    'CTRL_expressions_mouthFunnelUL',
    'CTRL_expressions_mouthFunnelUR',
    'CTRL_expressions_mouthFunnelDL',
    'CTRL_expressions_mouthFunnelDR',
    'CTRL_expressions_mouthLipsTogetherDL',
    'CTRL_expressions_mouthUpperLipBiteL',
    'CTRL_expressions_mouthUpperLipBiteR',
    'CTRL_expressions_mouthLowerLipBiteL',
    'CTRL_expressions_mouthLowerLipBiteR',
    'CTRL_expressions_mouthLipsTightenUL',
    'CTRL_expressions_mouthLipsTightenUR',
    'CTRL_expressions_mouthLipsTightenDL',
    'CTRL_expressions_mouthLipsTightenDR',
    'CTRL_expressions_mouthLipsPressL',
    'CTRL_expressions_mouthLipsPressR',
    'CTRL_expressions_mouthSharpCornerPullL',
    'CTRL_expressions_mouthSharpCornerPullR',
    'CTRL_expressions_mouthStickyUC',
    'CTRL_expressions_mouthStickyUINL',
    'CTRL_expressions_mouthStickyUINR',
    'CTRL_expressions_mouthStickyUOUTL',
    'CTRL_expressions_mouthStickyUOUTR',
    'CTRL_expressions_mouthStickyDC',
    'CTRL_expressions_mouthStickyDINL',
    'CTRL_expressions_mouthStickyDINR',
    'CTRL_expressions_mouthStickyDOUTL',
    'CTRL_expressions_mouthStickyDOUTR',
    'CTRL_expressions_mouthLipsPushUL',
    'CTRL_expressions_mouthLipsPushUR',
    'CTRL_expressions_mouthLipsPushDL',
    'CTRL_expressions_mouthLipsPushDR',
    'CTRL_expressions_mouthLipsPullUL',
    'CTRL_expressions_mouthLipsPullUR',
    'CTRL_expressions_mouthLipsPullDL',
    'CTRL_expressions_mouthLipsPullDR',
    'CTRL_expressions_mouthLipsThinUL',
    'CTRL_expressions_mouthLipsThinDR',
    'CTRL_expressions_mouthLipsThinUR',
    'CTRL_expressions_mouthLipsThinDL',
    'CTRL_expressions_mouthLipsThickUL',
    'CTRL_expressions_mouthLipsThickUR',
    'CTRL_expressions_mouthLipsThickDL',
    'CTRL_expressions_mouthLipsThickDR',
    'CTRL_expressions_mouthCornerSharpenUL',
    'CTRL_expressions_mouthCornerSharpenUR',
    'CTRL_expressions_mouthCornerSharpenDL',
    'CTRL_expressions_mouthCornerSharpenDR',
    'CTRL_expressions_mouthCornerRounderUL',
    'CTRL_expressions_mouthCornerRounderUR',
    'CTRL_expressions_mouthCornerRounderDL',
    'CTRL_expressions_mouthCornerRounderDR',
    'CTRL_expressions_mouthLowerLipShiftLeft',
    'CTRL_expressions_mouthLowerLipShiftRight',
    'CTRL_expressions_mouthUpperLipShiftLeft',
    'CTRL_expressions_mouthUpperLipShiftRight',
    'CTRL_expressions_mouthLowerLipRollInL',
    'CTRL_expressions_mouthLowerLipRollInR',
    'CTRL_expressions_mouthLowerLipRollOutL',
    'CTRL_expressions_mouthLowerLipRollOutR',
    'CTRL_expressions_mouthUpperLipRollInL',
    'CTRL_expressions_mouthUpperLipRollInR',
    'CTRL_expressions_mouthUpperLipRollOutL',
    'CTRL_expressions_mouthUpperLipRollOutR',
    'CTRL_expressions_mouthCornerUpL',
    'CTRL_expressions_mouthCornerUpR',
    'CTRL_expressions_mouthCornerDownL',
    'CTRL_expressions_mouthCornerDownR',
    'CTRL_expressions_jawOpen',
    'CTRL_expressions_jawOpenExtreme',
    'CTRL_expressions_jawLeft',
    'CTRL_expressions_jawRight',
    'CTRL_expressions_jawFwd',
    'CTRL_expressions_jawBack',
    'CTRL_expressions_jawChinCompressL',
    'CTRL_expressions_jawChinCompressR',
    'CTRL_expressions_jawChinRaiseDL',
    'CTRL_expressions_jawChinRaiseDR',
    'CTRL_expressions_jawChinRaiseUL',
    'CTRL_expressions_jawChinRaiseUR',
    'CTRL_expressions_tongueBendDown',
    'CTRL_expressions_tongueBendUp',
    'CTRL_expressions_tongueDown',
    'CTRL_expressions_tongueIn',
    'CTRL_expressions_tongueLeft',
    'CTRL_expressions_tongueNarrow',
    'CTRL_expressions_tongueOut',
    'CTRL_expressions_tonguePress',
    'CTRL_expressions_tongueRight',
    'CTRL_expressions_tongueRoll',
    'CTRL_expressions_tongueRollDown',
    'CTRL_expressions_tongueRollLeft',
    'CTRL_expressions_tongueRollRight',
    'CTRL_expressions_tongueRollUp',
    'CTRL_expressions_tongueThick',
    'CTRL_expressions_tongueThin',
    'CTRL_expressions_tongueTipDown',
    'CTRL_expressions_tongueTipLeft',
    'CTRL_expressions_tongueTipRight',
    'CTRL_expressions_tongueTipUp',
    'CTRL_expressions_tongueTwistLeft',
    'CTRL_expressions_tongueTwistRight',
    'CTRL_expressions_tongueUp',
    'CTRL_expressions_tongueWide',
}
function M.restoreLayer(state)
    if not state or state.restored then return end
    ambientFaces[state]=nil
    if state.upper and valid(state.instance)then
        pcall(function()
            for _,entry in ipairs(state.upper)do
                if state.upperMap:Contains(entry.key)then state.upperMap:Find(entry.key):set(entry.original)end
            end
        end)
    end
    if state.directNodes and valid(state.instance)then
        for _,node in ipairs(state.directNodes)do
            local ok,err=pcall(function()
                if #node.values~=#node.original then error('Curve array size changed')end
                for i,value in ipairs(node.original)do node.values[i]=value end
            end)
            if not ok then state.log('Direct curves restore failed: '..tostring(err))end
        end
    end
    if state.originalJaw~=nil and valid(state.instance)then
        local ok,err=pcall(function()state.instance.JawOpenAlpha=state.originalJaw end)
        state.log(ok and ('Restored JawOpenAlpha='..state.originalJaw)or('Jaw restore error: '..tostring(err)))
    end
    if not state.changed then state.restored=true;return end
    if not valid(state.main)then state.restored=true;return end
    state.log('NEXT restore previous face layers')
    state.main:UnlinkAnimClassLayers(state.desired)
    for _,cls in ipairs(state.previous)do
        if valid(cls)then state.main:LinkAnimClassLayers(cls)end
    end
    state.restored=true
    state.log('Previous face layers restored')
end
local function prepareUpperFace(state)
    -- Initialize only our newly linked instance, before its first animation tick.
    -- Never resize arrays or an existing game's curve map during playback.
    if not state.changed then return end
    local ok,err=pcall(function()
        local map=state.instance.AnimGraphNode_ModifyCurve_3.CurveMap
        local entries={}
        for _,name in ipairs(upperNames)do
            local key=FName(name)
            local original=map:Contains(key)and map:Find(key):get()or 0
            entries[#entries+1]={key=key,name=name,original=original}
            if not map:Contains(key)then map:Add(key,0.0)end
        end
        state.upperMap=map;state.upper=entries;state.upperWeights={}
        state.blinkAt=1.2+math.random()*2;state.faceTime=0;state.faceLast=os.clock()
        ambientFaces[state]=true
        state.log('Upper face ready: eyelids, cheeks, brows and nose; gaze remains native')
    end)
    if not ok then state.log('Upper face unavailable: '..tostring(err))end
end
function M.hasAmbientFaces()return next(ambientFaces)~=nil end
function M.tickAmbient()
    local now=os.clock()
    for state in pairs(ambientFaces)do
        if state.restored or not valid(state.instance)or not valid(state.main)then ambientFaces[state]=nil
        else
            local ok,err=pcall(function()
                local delta=math.max(0,math.min(.08,now-state.faceLast));state.faceLast=now
                -- The animation clock must stop with the game, including menus.
                if not state.gameplay then state.gameplay=AI.find('/Script/Engine.Default__GameplayStatics')end
                if not valid(state.gameplay)or state.gameplay:IsGamePaused(state.main)then return end
                state.faceTime=state.faceTime+delta
                local t=state.faceTime-state.blinkAt;local blink=0
                if t>=0 and t<.28 then
                    -- Fast closure, brief full closure, softer reopening.
                    blink=t<.085 and t/.085 or(t<.115 and 1 or 1-(t-.115)/.165)
                    blink=blink*blink*(3-2*blink)
                elseif t>=.28 then state.blinkAt=state.faceTime+2.8+math.random()*3.7 end
                local refresh=now>=(state.upperRefreshAt or 0)
                if refresh then state.upperRefreshAt=now+1 end
                for _,entry in ipairs(state.upper)do
                    local value=bounded(state.upperWeights[entry.name])
                    if entry.name:find('eyeBlink',1,true)then value=math.max(value,blink)end
                    -- No Add/Remove here: only existing float storage is updated.
                    if refresh or not entry.last or math.abs(value-entry.last)>.0001 then
                        if not state.upperMap:Contains(entry.key)then error('Upper-face map replaced by animation owner')end
                        state.upperMap:Find(entry.key):set(value);entry.last=value
                    end
                end
            end)
            if not ok then
                ambientFaces[state]=nil
                pcall(function()for _,entry in ipairs(state.upper)do
                    if state.upperMap:Contains(entry.key)then state.upperMap:Find(entry.key):set(entry.original)end
                end end)
                state.log('Upper face stopped: '..tostring(err))
            end
        end
    end
end
function M.linkSpeechLayer(graph,log)
    if not graph or not valid(graph.main)then error('Face graph unavailable; refusing layer change')end
    local main=graph.main
    local desired=AI.find('/Game/_Dawnwalker/Animation_MH/Humans/LinkedLayers/ABP_FaceDefaultLayers.ABP_FaceDefaultLayers_C')
    if not valid(desired)then error('Verified JALI face layer is not loaded')end
    local state={main=main,desired=desired,previous={},log=log}
    state.instance=main:GetLinkedAnimLayerInstanceByClass(desired,false)
    if valid(state.instance)then log('JALI face layer already attached');return state end
    local mainName=main:GetFullName()
    -- This game's expression layers are in the ungrouped layer set. Enumerate
    -- only this face's linked instances, never every animation class in memory.
    local linked={};main:GetLinkedAnimLayerInstancesByGroup(FName('None'),linked)
    local seen={}
    for _,instance in ipairs(linked)do
        if valid(instance)and instance:GetFullName()~=mainName then
            local cls=instance:GetClass();local name=cls:GetFullName()
            if not seen[name]then state.previous[#state.previous+1]=cls;seen[name]=true end
        end
    end
    if #state.previous==0 then error('No owned expression layer found; leaving native face unchanged')end
    -- Anca has exactly one expression class. Multiple overlapping classes need ordering evidence.
    if #state.previous>1 then error('Multiple existing face classes; refusing an ambiguous restore order')end
    local ok,err=pcall(function()
        log('NEXT LinkAnimClassLayers: ABP_FaceDefaultLayers (JALI + RigLogic)')
        state.changed=true;main:LinkAnimClassLayers(desired)
        local linked=main:GetLinkedAnimLayerInstanceByClass(desired,false)
        if not valid(linked)then error('Speech layer did not attach')end
        state.instance=linked
        log('Speech layer attached: '..linked:GetFullName())
    end)
    if not ok then M.restoreLayer(state);error(err)end
    prepareUpperFace(state)
    return state
end
function M.beginJaw(state,actor,now)
    if not state or not valid(state.instance)then error('Speech instance unavailable')end
    state.log('NEXT capture verified DoubleProperty JawOpenAlpha')
    local original=state.instance.JawOpenAlpha
    if type(original)~='number' or original~=original or math.abs(original)==math.huge then error('Invalid JawOpenAlpha')end
    state.originalJaw=original
    state.log('Captured JawOpenAlpha='..original..'; direct scalar test, no JALI playback')
    return {actor=actor,layer=state,deadline=now+6,frame=0},'Direct jaw test: six seconds; F7 releases'
end
function M.tickJaw(test,now)
    if now>=test.deadline or not valid(test.actor)or not valid(test.layer.instance)then return true end
    local layer=test.layer
    -- Capture readback before writing to detect an animation update resetting our input.
    local previous=layer.instance.JawOpenAlpha
    test.frame=test.frame+1
    local value=(test.frame%40<20)and 0.8 or 0.0
    layer.instance.JawOpenAlpha=value
    if test.frame==1 or test.frame%10==0 then
        layer.log('Jaw input: previous='..tostring(previous)..'; requested='..value..'; readback='..tostring(layer.instance.JawOpenAlpha))
    end
    return false
end
function M.applyWeights(state,weights)
    if not state or not valid(state.instance)then error('Face layer unloaded')end
    if state.upper then
        for _,entry in ipairs(state.upper)do state.upperWeights[entry.name]=bounded(weights[entry.name])end
    end
    local jaw=weights.CTRL_expressions_jawOpen or weights.JawOpen or 0
    if type(jaw)~='number'or jaw~=jaw then jaw=0 end
    state.instance.JawOpenAlpha=math.max(0,math.min(1,jaw))
    if not state.directDisabled and (state.directNodes or weights.CTRL_expressions_jawOpen~=nil)then
        local directOK,directError=pcall(function()
            if not state.directNodes then
                local layouts={
                    {field='AnimGraphNode_ModifyCurve_3',names=directNames},
                    {field='AnimGraphNode_ModifyCurve_8',names={'CTRL_expressions_mouthLipsTogetherDL','CTRL_expressions_mouthLipsTogetherDR','CTRL_expressions_mouthLipsTogetherUL','CTRL_expressions_mouthLipsTogetherUR'}},
                }
                local prepared={}
                for _,layout in ipairs(layouts)do
                    local node=state.instance[layout.field]
                    local values=node.CurveValues
                    if #values~=#layout.names then error('Unexpected fixed curve count: '..layout.field)end
                    local original={}
                    for i=1,#layout.names do
                        local v=values[i]
                        if type(v)~='number'or v~=v then error('Invalid numeric curve input')end
                        original[i]=v
                    end
                    table.insert(prepared,{node=node,values=values,original=original,names=layout.names})
                end
                state.directNodes=prepared
                state.log('Direct numeric lip inputs captured: 129 mouth/jaw/tongue + 4 lip-closure controls')
            end
            for _,node in ipairs(state.directNodes)do
                if #node.values~=#node.names then error('Curve array changed during playback')end
                for i,name in ipairs(node.names)do
                    local value=weights[name]or 0
                    if type(value)~='number'or value~=value then value=0 end
                    node.values[i]=math.max(0,math.min(1,value))
                end
            end
        end)
        if directOK then return end
        state.directDisabled=true;state.mapDisabled=true
        state.log('Direct curve inputs unavailable; jaw only: '..tostring(directError))
        return
    end
end
function M.capture(actor,log,lightweight)
    local meshes=actor:K2_GetComponentsByClass(AI.find('/Script/Engine.SkeletalMeshComponent'))
    local face
    each(meshes,function(mesh)
        if valid(mesh)and mesh:GetFName():ToString():lower():find('face',1,true)then face=mesh end
    end)
    if not valid(face)then log('No face mesh');return nil end
    log('NEXT selected face GetAnimInstance')
    local main=face:GetAnimInstance()
    if not valid(main)then log('No face animation instance');return nil end
    log('FACE '..face:GetFullName()..' MAIN '..main:GetFullName())
    if lightweight then return {main=main,log=log}end
    local seen={}
    local function schema(cls)
        local name=cls:GetFullName();if seen[name]then return end;seen[name]=true
        log('CLASS '..name)
        local count=0
        cls:ForEachProperty(function(p)
            count=count+1;if count>100 then return true end
            log('NEXT property metadata '..count)
            local full=tostring(p:GetFullName());log('  '..full)
            if full:find('StructProperty',1,true)then
                log('NEXT struct schema (metadata only)')
                local struct=p:GetStruct()
                if valid(struct)then
                    log('    TYPE '..struct:GetFullName())
                    local n=0;struct:ForEachProperty(function(field)
                        n=n+1;if n>24 then return true end
                        log('      '..tostring(field:GetFullName()))
                    end)
                end
            end
        end)
    end
    schema(main:GetClass())
    local base=StaticFindObject('/Script/Engine.AnimInstance')
    local attached={}
    local function record(instance)
        if not valid(instance)then return end
        local name=instance:GetFullName()
        if attached[name]then return end
        attached[name]=true
        log('ATTACHED '..name);schema(instance:GetClass())
    end
    local function linkedLayers()
        if not valid(base)then log('AnimInstance base class unavailable');return end
        log('NEXT direct linked-layer lookup by AnimInstance base class')
        local ok,result=pcall(function()return main:GetLinkedAnimLayerInstanceByClass(base,true)end)
        if ok then record(result)else log('Direct layer lookup error: '..tostring(result))end
        -- None is Unreal's ungrouped layer group; other named groups may exist.
        log('NEXT ungrouped linked-layer lookup')
        local group={}
        local groupOK,groupError=pcall(function()main:GetLinkedAnimLayerInstancesByGroup(FName('None'),group)end)
        if groupOK then each(group,record)else log('Ungrouped lookup error: '..tostring(groupError))end
        log('Ungrouped lookup complete (not an exhaustive list of named groups)')
    end
    linkedLayers()
    log('GRAPH CAPTURE COMPLETE')
    return {main=main,log=log,linkedLayers=linkedLayers}
end
function M.sample(state)
    if not state or not valid(state.main)then return end
    state.linkedLayers()
    local names={}
    state.log('NEXT refresh curve names during playback')
    state.main:GetAllCurveNames(names)
    local samples={};local total=0;local mouth={}
    each(names,function(name)
        local text=type(name)=='string'and name or name:ToString()
        total=total+1
        local lower=text:lower()
        if lower:find('jaw',1,true)or lower:find('mouth',1,true)or lower:find('lip',1,true)then
            table.insert(mouth,text)
        end
    end)
    table.sort(mouth,function(a,b)
        local function priority(s)return s:lower():find('jawopen',1,true)and 0 or 1 end
        if priority(a)~=priority(b)then return priority(a)<priority(b)end
        return a<b
    end)
    for i=1,math.min(16,#mouth)do
        local text=mouth[i];table.insert(samples,text..'='..tostring(state.main:GetCurveValue(FName(text))))
    end
    state.log('FACE curve count='..total..'; mouth samples='..#samples..'; '..table.concat(samples,'; '))
end
return M
