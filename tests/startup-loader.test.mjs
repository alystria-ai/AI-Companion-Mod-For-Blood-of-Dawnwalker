import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const literal=s=>'[====['+s+']====]';
const loader=readFileSync('mod/Scripts/live_reload.lua','utf8');
const main=readFileSync('mod/Scripts/main.lua','utf8');
function run(code){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const r=lauxlib.luaL_dostring(L,to_luastring(code));assert.equal(r,lua.LUA_OK,r===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
test('snapshot discovers a newly required module and transitive dependencies with an old manifest',()=>run(`
 local M=assert(load(${literal(loader)}))();M.modules={'app'}
 local disk={app="local x=require('native_subtitles'); RegisterKeyBind(5,function() _G.captionReady=x.ready end)",native_subtitles="return {ready=require('new_dependency').ready}",new_dependency='return {ready=true}'}
 local files,fingerprint=M.snapshot('unused',function(n)return disk[n]end)
 assert(files and files.native_subtitles and files.new_dependency)
 local base=setmetatable({},{__index=_G});local router=M.new(base,function(n)error('Unexpected external require: '..n)end,function(f)f()end,function()end)
 assert(router:reload(files));router:key(5);assert(router.active~=nil)
 local before=router.active;disk.new_dependency=nil
 local incomplete,why=M.snapshot('unused',function(n)return disk[n]end)
 assert(not incomplete and why:find('new_dependency',1,true));assert(router.active==before)
 disk.new_dependency='return {ready=false}'
 local repaired,nextFingerprint=M.snapshot('unused',function(n)return disk[n]end)
 assert(repaired and nextFingerprint~=fingerprint)
 router:poll(repaired,nextFingerprint);router:poll(repaired,nextFingerprint);assert(router.active~=before)
`));
const disk=Object.fromEntries(readdirSync('mod/Scripts').filter(n=>n.endsWith('.lua')).map(n=>[n.slice(0,-4),readFileSync('mod/Scripts/'+n,'utf8')]));
disk.app="local c=require('native_subtitles'); RegisterKeyBind(Key.F5,function() assert(c.ready); pressed=true end)";
disk.native_subtitles='return {ready=true}';
test('fresh bootstrap uses the payload loader even when the bootstrap require copy is stale',()=>run(`
 local disk={${Object.entries(disk).map(([k,v])=>`[ ${literal(k)} ]=${literal(v)}`).join(',')}}
 local originalLoad=load;local loadedPayload=false;local callbacks={};local keys={}
 require=function(n)if n=='runtime_path'then return '/installed/Payload/runtime' end;error('Stale bootstrap require was used: '..n)end
 loadfile=function(path)assert(path=='/installed/Payload/runtime/../mod/Scripts/live_reload.lua');loadedPayload=true;return assert(originalLoad(${literal(loader)}))end
 io.open=function(path,mode)if mode=='w'then return {write=function()end,close=function()end}end;local n=path:match('/([^/]+)%.lua$');if not disk[n]then return nil end;return {read=function()return disk[n]end,close=function()end}end
 print=function()end;Key={F5=5,F6=6,F7=7,F8=8};RegisterKeyBind=function(k,f)keys[k]=f end
 LoopAsync=function(ms,f)callbacks[#callbacks+1]=f end
 EGameThreadMethod={EngineTick=1};ExecuteInGameThread=function(f)f()end
 assert(originalLoad(${literal(main)}))()
 assert(loadedPayload and #callbacks==1);callbacks[1]()
 assert(package.loaded.live_reload.router.active,'Fresh launch did not initialize gameplay')
 keys[5]();callbacks[1]()
 assert(package.loaded.live_reload.router.active.keys[5],'F5 route missing')
`));
