import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const path=process.env.DAWNWALKER_LUA||'mod/Scripts';
const [recovery,planner,companions]=await Promise.all(['companion_recovery','party_formation','companions'].map(n=>readFile(`${path}/${n}.lua`,'utf8')));
function run(s){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(`local R=(function()${recovery}end)()\n${s}`));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
test('streamed-out registered companions keep their journey and resume the rear seat after reattachment',()=>run(`
 local require=function()return R end;local P=(function()${planner}end)();local f=P.new()
 local row={id='crake',ordinal=1,slot=1,pitch=190,radius=55,position={X=200,Y=0,Z=0}};local registered={crake=true}
 f:update({row},{X=0,Y=0,Z=0},0,0,0,registered)
 f:update({row},{X=1000,Y=0,Z=0},0,480,1000,registered)
 f:update({},{X=2000,Y=0,Z=0},0,480,2000,registered)
 f:update({},{X=2000,Y=0,Z=0},0,0,3000,registered)
 assert(f.seats.crake,'Streaming was mistaken for dismissal')
 local g=f:update({row},{X=2000,Y=0,Z=0},0,0,3250,registered).crake
 assert(g.mode=='Rear arc'and g.point.X>1700,'Reattachment parked the old pawn far behind Coen')
 f:update({},{X=2000,Y=0,Z=0},0,0,3500,{});assert(not f.seats.crake,'Dismissal retained its seat')
`));
test('nearby regrouped companions can rejoin a current battle while circling, with no lingering combat block',()=>run(`
 local m={returning=true,returnKind='sustained run',noEngageUntil=99999}
 local o={allowed=true,now=0,gap=450,spacing=462,target='new enemy',targetGap=400,speed=480,targetAwaySpeed=40}
 assert(not R.rejoinBattle(m,o));o.now=250;assert(not R.rejoinBattle(m,o));o.now=500;assert(R.rejoinBattle(m,o))
 assert(not m.returning and not m.noEngageUntil and not m.returnKind)
`));
test('a pursuing enemy does not reopen combat during escape; distant or busy companions keep regrouping',()=>run(`
 local m={returning=true};local o={allowed=true,now=0,gap=450,spacing=462,target='pursuer',targetGap=500,speed=480,targetAwaySpeed=480}
 for now=0,5000,250 do o.now=now;assert(not R.rejoinBattle(m,o))end
 o.targetAwaySpeed=-100;o.gap=1800;o.now=6000;assert(not R.rejoinBattle(m,o));o.now=8000;assert(not R.rejoinBattle(m,o))
 o.gap=450;o.allowed=false;o.now=9000;assert(not R.rejoinBattle(m,o)and m.returning)
`));
test('distant fighters leave an old encounter even if another fight is near Coen, but nearby flanks remain native',()=>run(`
 local m={};local o={follow=true,encounter=true,fightKnown=true,now=0,gap=2800,spacing=462,speed=0,awaySpeed=0,combat=true,threatDistance=500,fightDistance=3400,x=0,y=0}
 assert(not R.retreat(m,o));o.now=1750;assert(not R.retreat(m,o));o.now=2000;assert(R.retreat(m,o))
 m={};o.fightDistance=700
 for now=0,5000,250 do o.now=now;assert(not R.retreat(m,o),'Flanking an enemy beside Coen was mistaken for abandonment')end
`));
test('sprint recovery starts at twelve metres with a shorter cooldown and preserves collision/visibility/combat guards',()=>run(`
 local minimum,cooldown=R.catchupLimits(480,462);assert(minimum==1200 and cooldown==3000)
 local o={follow=true,dead=false,combat=false,busy=false,grounded=true,visible=false,gap=1250,minimum=minimum,now=3500,cooldown=cooldown,last=0}
 assert(R.catchup(o));o.visible=true;assert(not R.catchup(o));o.visible=false;o.combat=true;assert(not R.catchup(o))
 o.combat=false;o.grounded=false;assert(not R.catchup(o))
 local wide=R.catchupLimits(480,1500);assert(wide==2100,'Large party outer arcs must retain room')
`));
test('the actual combat join gate keeps distant travellers following without disabling an existing fight',()=>{
 const start=companions.indexOf('local joiningParty=');const end=companions.indexOf('if canFight and',start);
 const part=companions.slice(start,end);
 run(`local m={combatDefinition=true,mode='follow',followSpacing=462};local suppressed=false
 for _,sample in ipairs({{gap=3000,phase='travel',native=false,want=false},{gap=1000,phase='travel',native=false,want=true},{gap=3000,phase='combat',native=true,want=true}})do
 local gap=sample.gap;local manager={phase=sample.phase};local nativeCombat=sample.native
 ${part}
 assert(canFight==sample.want)
 end`);
});
