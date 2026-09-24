-- Stable bootstrap. Gameplay code in app.lua is reloaded directly from the workspace.
local root=require('runtime_path')
local source=root..'/../mod/Scripts'
local Loader=require('live_reload')
local function report(message)
    print('[DawnwalkerConvai LiveReload] '..message..'\n')
    local f=io.open(root..'/reload-status.txt','w')
    if f then f:write(os.date('%Y-%m-%d %H:%M:%S')..' '..message..'\n');f:close()end
end
-- One native callback at a time. Reloads, file IO and application timers all run
-- inside that callback, rather than racing the async timer and each other.
local onGameThread=false
local work={}
local function gameQueue(fn)
    if onGameThread then return fn()end
    work[#work+1]=fn
end
local router=Loader.new(_G,require,gameQueue,report)
local function snapshot()
    local files,parts={},{}
    for _,name in ipairs(Loader.modules)do
        local f,err=io.open(source..'/'..name..'.lua','r')
        if not f then return nil,err end
        local text=f:read('*a');f:close();files[name]=text
        table.insert(parts,name..':'..#text..':'..text)
    end
    return files,table.concat(parts,'\0')
end
for _,key in ipairs({Key.F5,Key.F6,Key.F7,Key.F8})do
    RegisterKeyBind(key,function()gameQueue(function()router:key(key)end)end)
end
local files,fingerprint=snapshot()
if files then
    gameQueue(function()if router:reload(files)then router.last=fingerprint end end)
else report('Cannot load workspace Lua: '..tostring(fingerprint))end
local elapsed=0
local inFlight=false
local lastErrorAt=0
local function pump()
    onGameThread=true
    local ok,err=pcall(function()
        local batch=work;work={}
        for _,fn in ipairs(batch)do fn()end
        router:tick(16)
        elapsed=elapsed+16
        if elapsed>=1000 then
            elapsed=0
            local nextFiles,nextFingerprint=snapshot()
            if nextFiles then router:poll(nextFiles,nextFingerprint)end
        end
    end)
    onGameThread=false
    if not ok and os.time()-lastErrorAt>=5 then
        lastErrorAt=os.time()
        pcall(report,'Update callback failed: '..(type(err)=='string'and err or 'non-text Lua error'))
    end
    inFlight=false
end
LoopAsync(16,function()
    if inFlight then return false end
    inFlight=true
    local ok,err=pcall(function()
        assert(EGameThreadMethod and EngineTickAvailable~=false,'UE4SS EngineTick dispatch unavailable')
        ExecuteInGameThread(pump,EGameThreadMethod.EngineTick)
    end)
    if not ok then
        inFlight=false
        if os.time()-lastErrorAt>=5 then
            lastErrorAt=os.time()
            pcall(report,'Update dispatch failed: '..(type(err)=='string'and err or 'non-text Lua error'))
        end
    end
    return false
end)
report('Live reload installed: watching '..source)
