import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
async function run(code){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(code));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
async function check(body){const source=await readFile(`${process.env.DAWNWALKER_LUA||'mod/Scripts'}/companion_recovery.lua`,'utf8');return run(`local M=(function() ${source} end)()\n${body}`);}
test('rear arcs keep 18 companions close, distinct and compact after dismissing',()=>check(`
 local party={};for i=1,18 do party[i]={ordinal=i,baseName='Anca',characterId='anca',capsuleRadius=55}end
 local ordered=M.layout(party);local points={}
 for i,m in ipairs(ordered)do
  local p,r=M.followPoint({X=0,Y=0,Z=0},0,m.formationSlot,m.formationPitch)
  assert(r<1700,'Party trails too far behind');assert(m.followSpacing==r+15)
  for _,q in ipairs(points)do assert((p.X-q.X)^2+(p.Y-q.Y)^2>=190^2)end
  points[#points+1]=p
 end
 assert(points[3].Y<0 and points[4].Y>0 and points[3].X<0 and points[4].X<0,'Missing rear arc wings')
 party[1]=nil;M.layout(party);assert(party[2].formationSlot==1 and party[18].formationSlot==17)
 party[3].capsuleRadius=250;ordered=M.layout(party);assert(ordered[1].formationPitch==580)
 local a=M.followPoint({X=100,Y=200,Z=0},90,4);assert(a.X<100 and a.Y<200,'Rear arc did not rotate with travel heading')
`));
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
test('formation never registers a reentrant engine MoveToLocation callback',async()=>{
 const source=await readFile('mod/Scripts/companions.lua','utf8');
 assert.doesNotMatch(source,/RegisterHook|ensureMovementHook|controllerMembers/);
});
