-- One-shot discovery. Never read instance property values or modify animation.
local M={}
local targets={
    '/Script/JALI.JaliAnimPlayer', '/Script/JALI.JaliAnimationComponent',
    '/Script/JALI.JSync', '/Script/JALI.JaliRuntimeAnimLoader',
    '/Script/JALI.JaliRuntime', '/Script/Dawnwalker.HumanoidCharacter',
}
local function valid(o)return o and o:IsValid()end
local function each(array,callback)
    for i=1,#array do callback(array[i])end
end
function M.run(actor,append)
    local function step(s)append('NEXT '..s)end
    local seen={}
    local function schema(cls)
        for depth=1,4 do
            step('validate metadata class')
            if not valid(cls) then return end
            step('class metadata name')
            local name=tostring(cls:GetFullName())
            if seen[name] then return end
            seen[name]=true
            if name:find('/Script/Engine.',1,true) then return end
            append('CLASS '..name)
            local count=0
            step(name..' ForEachProperty')
            cls:ForEachProperty(function(p)
                count=count+1;if count>128 then append('PROPERTY LIMIT');return true end
                step('property metadata '..count)
                append('  PROPERTY '..tostring(p:GetFullName()))
            end)
            count=0
            step(name..' ForEachFunction')
            cls:ForEachFunction(function(fn)
                count=count+1;if count>96 then append('FUNCTION LIMIT');return true end
                step('function metadata '..count)
                local fnName=tostring(fn:GetFullName())
                append('  FUNCTION '..fnName)
                if fnName:find('ExecuteUbergraph',1,true) then return end
                local n=0
                step(fnName..' parameter metadata')
                fn:ForEachProperty(function(p)
                    n=n+1;if n>24 then append('PARAMETER LIMIT');return true end
                    step('parameter metadata '..n)
                    append('    '..tostring(p:GetFullName()))
                end)
            end)
            step(name..' GetSuperStruct')
            cls=cls:GetSuperStruct()
        end
    end
    append('Dawnwalker Convai v0.7 JALI metadata probe')
    for _,path in ipairs(targets)do
        step('StaticFindObject '..path)
        local cls=StaticFindObject(path)
        if valid(cls)then schema(cls)else append('NOT LOADED '..path)end
    end
    if valid(actor)then
        step('selected NPC name')
        append('TARGET '..actor:GetFullName())
        step('find ActorComponent class')
        local componentClass=StaticFindObject('/Script/Engine.ActorComponent')
        if not valid(componentClass)then error('ActorComponent class unavailable')end
        step('selected NPC K2_GetComponentsByClass')
        local components=actor:K2_GetComponentsByClass(componentClass)
        local count=0
        step('enumerate selected NPC components')
        each(components,function(component)
            count=count+1;if count>64 then return end
            step('validate component '..count)
            if not valid(component)then return end
            step('component name '..count)
            local name=tostring(component:GetFullName())
            append('COMPONENT '..name)
            if name:lower():find('jali',1,true)then
                step('JALI component GetClass')
                schema(component:GetClass())
            end
        end)
    else append('No NPC selected; static JALI API metadata still captured')end
    append('COMPLETE: no animation or NPC state was changed')
end
return M
