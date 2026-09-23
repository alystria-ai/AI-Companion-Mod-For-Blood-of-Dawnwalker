import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
async function run(code){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(code));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
async function check(body){const source=await readFile(`${process.env.DAWNWALKER_LUA||'mod/Scripts'}/companion_recovery.lua`,'utf8');return run(`local M=(function() ${source} end)()\n${body}`);}
test('an obstructed lane yields for twelve seconds, while moving followers keep their lanes',()=>check(`
 local m={};local o={active=true,now=0,x=0,y=0,gap=2000,spacing=400}
 assert(not M.formationBlocked(m,o));o.now=3499;assert(not M.formationBlocked(m,o))
 o.now=3500;assert(M.formationBlocked(m,o));o.now=15000;assert(M.formationBlocked(m,o))
 o.now=15500;assert(not M.formationBlocked(m,o));o.now=19000;o.x=300;assert(not M.formationBlocked(m,o))
 o.active=false;assert(not M.formationBlocked(m,o)and not m.laneSample)
`));
test('failed recovery backs off to thirty seconds and successful recovery resets the delay',()=>check(`
 assert(M.retryDelay(0)==2000 and M.retryDelay(1)==4000 and M.retryDelay(4)==30000 and M.retryDelay(99)==30000)
 local o={follow=true,grounded=true,gap=5000,now=10000,attempted=0,failures=4}
 assert(not M.catchup(o));o.now=30000;assert(M.catchup(o));o.combat=true;assert(not M.catchup(o))
 o.combat=false;o.failures=nil;o.now=2000;assert(M.catchup(o))
`));
