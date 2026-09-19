-- Stable bootstrap. Gameplay code in app.lua is reloaded directly from the workspace.
local root=require('runtime_path')
local source=root..'/../mod/Scripts'
local Loader=require('live_reload')
local function report(message)
    print('[DawnwalkerConvai LiveReload] '..message..'\n')
    local f=io.open(root..'/reload-status.txt','w')
    if f then f:write(os.date('%Y-%m-%d %H:%M:%S')..' '..message..'\n');f:close()end
end
local function gameQueue(fn)
    assert(EGameThreadMethod and EngineTickAvailable~=false,'UE4SS EngineTick dispatch unavailable')
    ExecuteInGameThread(fn,EGameThreadMethod.EngineTick)
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
    RegisterKeyBind(key,function()router:key(key)end)
end
local files,fingerprint=snapshot()
if files then
    gameQueue(function()if router:reload(files)then router.last=fingerprint end end)
else report('Cannot load workspace Lua: '..tostring(fingerprint))end
local elapsed=0
LoopAsync(33,function()
    router:tick(33)
    elapsed=elapsed+33
    if elapsed>=1000 then
        elapsed=0
        local nextFiles,nextFingerprint=snapshot()
        if nextFiles then router:poll(nextFiles,nextFingerprint)end
    end
    return false
end)
report('Live reload installed: watching '..source)
