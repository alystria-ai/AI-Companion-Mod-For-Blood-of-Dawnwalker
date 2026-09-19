import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const source=readFileSync('mod/Scripts/companion_settings.lua','utf8');
function run(body){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(`
 local disk={['runtime/mod-directory.txt']='installed'}
 package.preload.runtime_path=function()return 'runtime'end
 io.open=function(path,mode)
  if mode=='w'then disk[path]='';return {write=function(_,...) for _,s in ipairs({...})do disk[path]=disk[path]..s end end,close=function()end}end
  if not disk[path]then return nil end
  return {read=function()return disk[path]end,close=function()end}
 end
 local M=(function() ${source} end)()
 ${body}`));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
test('bindings persist separately, reload, reject duplicates and reserve navigation keys',()=>run(`
 assert(M.bind('Menu','F10'));assert(M.bindings.Menu=='F10')
 assert(disk['installed/keybindings.ini']:find('Menu = F10',1,true))
 local before=disk['installed/keybindings.ini']
 assert(not M.bind('SingleVoice','F10'));assert(disk['installed/keybindings.ini']==before)
 for _,key in ipairs({'Escape','Enter','Up','Ctrl+K','None','F12','F13'})do assert(not M.bind('Menu',key))end
 assert(M.bind('GroupText','9'));assert(M.bind('Menu','Home'))
 disk['installed/keybindings.ini']=disk['installed/keybindings.ini']:gsub('Menu = Home','Menu = End')
 M.pollBindings();assert(M.bindings.Menu=='End')
 M.change('DamagePercent',1);assert(M.bindings.Menu=='End');assert(disk['installed/keybindings.ini']:find('Menu = End',1,true))
`));
test('partial or duplicate hand edits retain the entire last good mapping',()=>run(`
 assert(M.bind('Menu','F10'));local good=disk['installed/keybindings.ini']
 disk['installed/keybindings.ini']='[Keybindings]\\nMenu = F2\\n';M.pollBindings();assert(M.bindings.Menu=='F10' and M.bindingError)
 disk['installed/keybindings.ini']=good:gsub('SingleVoice = F7','SingleVoice = F10');M.pollBindings();assert(M.bindings.SingleVoice=='F7' and M.bindingError)
 disk['installed/keybindings.ini']=good;M.pollBindings();assert(not M.bindingError)
`));
