-- Synchronous, game-thread-only adapter for the narrow native ABI bridge.
-- Native outputs are data; no returned text is evaluated as Lua.
local M={};local invoke,invokeAssets,invokeProtection;local counter=0;local loadedClasses={};local loadedAssets={}
local root=require('runtime_path')
-- One-time recovery of the recorded v0.21 owner after its async action was
-- collected. The native v2 registry is retired, never read/unloaded again.
-- Only the exact old party epoch and explicitly recorded spawner are accepted.
local function retireLegacyOwner()
    local f=io.open(root..'/companion-legacy-owner.tsv','r');if not f then return end
    local row=f:read('*a');f:close()
    local done=io.open(root..'/companion-legacy-retired.txt','r');if done then done:close();return end
    local oldEpoch,spawnerPath=row:match('^(%d+)\t([^\r\n]+)')
    assert(oldEpoch and spawnerPath:match('^/Game/'),'Invalid legacy owner record')
    f=assert(io.open(root..'/companions-state.tsv','r'));local state=f:read('*a');f:close()
    -- A new game/session has no v2 native registry to recover.
    if state:match('^PARTY\t1\t(%d+)')~=oldEpoch then return end
    assert(not state:find('\nMEMBER\t',1,true),'Legacy party must finish dismissing before migration')
    local spawner=StaticFindObject(spawnerPath)
    if spawner and spawner:IsValid()then
        assert(spawner:IsA(StaticFindObject('/Script/Dawnwalker.DogwoodPopulationSimpleSpawner')),'Legacy owner type mismatch')
        spawner:Stop()
    end
    f=assert(io.open(root..'/companion-legacy-retired.txt','w'));f:write(os.date()..' Recorded v0.21 spawner stopped; obsolete pointer registry retired.\n');f:close()
end
function M.prepareUpgrade()retireLegacyOwner()end
M.version=9
local function path(object)
    assert(object and object:IsValid(),'Native bridge object unavailable')
    return object:GetFullName():match('^%S+ (.+)$')
end
function M.run(operation,arguments)
    if not invoke then
        retireLegacyOwner()
        local fn,err=package.loadlib(root..'/../bridge/native/companion_native_v9.dll','companion_native_run')
        assert(fn,'Native companion bridge unavailable: '..tostring(err));invoke=fn
    end
    local dispatch=invoke
    if operation:match('^protect')then
        if not invokeProtection then
            local fn,err=package.loadlib(root..'/../bridge/native/companion_protection_v2.dll','companion_native_run')
            assert(fn,'Companion protection helper unavailable: '..tostring(err));invokeProtection=fn
        end
        dispatch=invokeProtection
    end
    if operation=='loadassetasync'then
        if not invokeAssets then
            local fn,err=package.loadlib(root..'/../bridge/native/companion_assets_v2.dll','companion_native_run')
            assert(fn,'Companion asset loader unavailable: '..tostring(err));invokeAssets=fn
        end
        dispatch=invokeAssets
    end
    counter=counter+1;local id='native_'..os.time()..'_'..counter
    local rows={id,operation}
    for _,value in ipairs(arguments or {})do
        assert(type(value)=='string' and not value:find('[\r\n]'),'Invalid native bridge argument')
        rows[#rows+1]=value
    end
    local f=assert(io.open(root..'/companion-native-request.txt','wb'));f:write(table.concat(rows,'\n')..'\n');f:close()
    dispatch() -- no arguments or Lua runtime crossing; reads only the fixed request
    f=assert(io.open(root..'/companion-native-reply.txt','rb'));local text=f:read(131072);f:close()
    assert(text and text:match('^([^\r\n]+)')==id,'Native companion reply missing or stale')
    local result={raw=text}
    for key,value in text:gmatch('\n([^\t\r\n]+)\t([^\r\n]*)')do result[key]=value end
    if result.ERROR then return nil,result.ERROR end
    assert(result.OK,'Incomplete native companion reply');return result
end
function M.probe()return M.run('probe')end
function M.requestClass(player,classPath)return M.run('loadclassasync',{path(player),classPath})end
function M.requestAsset(player,assetPath)return M.run('loadassetasync',{path(player),assetPath})end
function M.loadedAsset(assetPath)
    local object=loadedAssets[assetPath]
    if not object or not object:IsValid()then object=StaticFindObject(assetPath)end
    if not object or not object:IsValid()then return nil end
    local f=EObjectFlags
    if object:HasAnyFlags(f.RF_BeginDestroyed|f.RF_FinishDestroyed)then loadedAssets[assetPath]=nil;return nil end
    loadedAssets[assetPath]=object
    if object:HasAnyFlags(f.RF_NeedInitialization|f.RF_NeedLoad|f.RF_NeedPostLoad|f.RF_NeedPostLoadSubobjects)then return nil end
    return object
end
function M.loadedClass(classPath)
    local object=loadedClasses[classPath]
    if not object or not object:IsValid()then object=StaticFindObject(classPath)end
    if object and object:IsValid()then
        local destroyed=EObjectFlags.RF_BeginDestroyed|EObjectFlags.RF_FinishDestroyed
        if object:HasAnyFlags(destroyed)then loadedClasses[classPath]=nil;return nil end
        loadedClasses[classPath]=object
        -- A class name may be registered before async serialization/postload
        -- finishes. Mere presence must not trigger early population spawning.
        local f=EObjectFlags
        local pending=f.RF_NeedInitialization|f.RF_NeedLoad|f.RF_NeedPostLoad|f.RF_NeedPostLoadSubobjects|f.RF_BeginDestroyed|f.RF_FinishDestroyed
        if object:HasAnyFlags(pending)then return nil end
        local defaults=object:GetCDO()
        if not defaults or not defaults:IsValid()or defaults:HasAnyFlags(pending)then return nil end
        return object
    end
end
function M.inspect(definition)return M.run('inspect',{path(definition)})end
function M.loadClass(classPath)
    local object=StaticFindObject(classPath)
    if object and object:IsValid()then return object end
    local result,why=M.run('loadclass',{classPath});if not result then return nil,why end
    object=StaticFindObject(M.exportedPath(result.class)or classPath)
    if not object or not object:IsValid()then return nil,'Loaded class could not be resolved'end
    return object
end
function M.spawn(player,npcClass,aiClass,position,yaw)
    return M.run('spawn',{path(player),path(npcClass),aiClass and path(aiClass) or 'None',string.format('%.6f %.6f %.6f',position.X,position.Y,position.Z),string.format('%.6f',yaw)})
end
function M.poll(action)return M.run('poll',{type(action)=='string'and action or path(action)})end
function M.stop(action)return M.run('stop',{type(action)=='string'and action or path(action)})end
function M.stopAll()return M.run('stopall')end
function M.exportedPath(text)
    if type(text)~='string' then return nil end
    return text:match("'([^']+)'") or text:match('"([^"]+)"') or text:match('^(/[^%s]+)$')
end
return M
