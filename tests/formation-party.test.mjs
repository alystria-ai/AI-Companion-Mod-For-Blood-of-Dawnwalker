import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const scripts=process.env.DAWNWALKER_LUA||'mod/Scripts';
const recovery=await readFile(`${scripts}/companion_recovery.lua`,'utf8');
const companions=await readFile(`${scripts}/companions.lua`,'utf8');
function run(s){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(`local R=(function()${recovery}end)()\n${s}`));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
test('nine moving followers receive fresh goals within a second under a twelve-per-second cap',()=>run(`
 local members={};for i=1,9 do members[i]={id=tostring(i),ordinal=i}end
 local budget,cursor,counts,last={},0,{},{}
 for now=0,10000,250 do
  R.pathBudget(budget,now,9,true)
  local ordered;ordered,cursor=R.updateOrder(members,cursor)
  for _,m in ipairs(ordered)do
   local o={allowed=true,pathStatus=3,now=now,x=now*0.6-500,y=0,px=now*0.6,py=0,gap=500,spacing=250,moving=true,laneDistance=500,goal={X=now*0.6,Y=0,Z=0},budget=budget}
   if R.travelRequest(m,o)then
    if last[m.id]then assert(now-last[m.id]<=1000,'A moving member starved')end
    last[m.id]=now;m.travelGoal=o.goal
    local second=math.floor(now/1000);counts[second]=(counts[second]or 0)+1
   end
  end
 end
 for _,n in pairs(counts)do assert(n<=12,'Unbounded whole-party navigation work')end
 for _,m in ipairs(members)do assert(last[m.id]>=9000,'A late summon never received updates')end
 R.pathBudget(budget,12000,9,false);assert(budget.remaining==1,'Settled party retained travel burst budget')
 local f={moving=true,point={X=1000,Y=0,Z=0}};local p=R.travelOrigin(f,{X=600,Y=0},9)
 assert(p.X>1000 and p.X<=1250);f.moving=false;assert(R.travelOrigin(f,{X=600,Y=0},9)==f.point,'Stopping retained predicted offset')
`));
test('crowded followers retry after blockage clears without actor or player movement',()=>run(`
 local m={};local o={allowed=true,pathStatus=0,now=0,x=0,y=0,px=500,py=0,gap=500,spacing=250,correct=false,laneDistance=400,goal={X=300,Y=0,Z=0},overlap=true}
 for _,now in ipairs({0,500,2000,3500})do o.now=now;R.travelRequest(m,o)end
 o.now=10000;assert(not R.travelRequest(m,o),'Blocked requests retried too rapidly')
 o.now=11500;assert(R.travelRequest(m,o),'A temporary obstacle permanently disabled separation')
 o.now=13000;assert(not R.travelRequest(m,o),'Slow retry opened a fresh burst')
 o.now=19500;assert(R.travelRequest(m,o),'Second recovery probe never happened')
`));
