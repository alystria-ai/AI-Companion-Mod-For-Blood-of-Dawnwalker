import fs from 'node:fs';
import test from 'node:test';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
function run(script){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);const rc=lauxlib.luaL_dostring(L,to_luastring(script));if(rc!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));}
test('Nightmare pool spans rounds without repeats and is absent from normal themes',()=>run(`
package.path='mod/Scripts/?.lua;'..package.path
local c=require('horde_catalog');assert(#c.preview()==10 and #c.order(11,11,42)==10)
local a,_,bag=c.nightmareDraw(nil,9);local b,_,bag2=c.nightmareDraw(bag,23);assert(bag==bag2)
local seen={};for _,batch in ipairs({a,b})do for _,d in ipairs(batch)do assert(d.hordeEnemy and d.category=='combat' and not seen[d.path]);seen[d.path]=true end end
for _,id in ipairs({'brencis','xanthe','ambrus','bakir'})do local found=false;for _,batch in ipairs({a,b})do for _,d in ipairs(batch)do if d.id=='combat_'..id then found=true end end end;assert(found,id)end
local last=bag.last;local nextBoss=c.nightmareDraw(bag,1);assert(nextBoss[1].id~=last)
assert(#c.wave(1,8,1)==9)
`));
test('Nightmare stages a round, releases the configured group, skips failed AI and rests between rounds',()=>{
const source=fs.readFileSync('mod/Scripts/horde_mode.lua','utf8');
run(`
package.path='mod/Scripts/?.lua;'..package.path
local now=0;local world={};local pawn={};local handles={};local kept=0;local blocked=false
pawn.GetWorld=function()return world end;pawn.K2_GetActorLocation=function()return {X=0,Y=0,Z=0}end
local pc={Pawn=pawn,GetControlRotation=function()return {Yaw=0}end}
local board={Combat={bInCombat=false},bIsDead=false}
local stub={IsInCombat=function()return board.Combat.bInCombat end}
local settings={values={HordeLevels=2,HordeStartEnemies=2,HordeEnemyGrowth=1,HordeBosses=1,HordeTimeout=3,HordeStartingWave=1},poll=function()end}
local lib={GetGameTimeInSeconds=function()return now end,IsGamePaused=function()return false end,GetAIStub=function()return stub end,K2_ProjectPointToNavigation=function(_,_,desired,out)out.X=desired.X;out.Y=desired.Y;out.Z=desired.Z;return true end}
local ai={valid=function(o)return o~=nil end,same=function(a,b)return a==b end,find=function()return lib end,board=function(o)return o==stub and board or o and {}end}
local native={cleanup=function()return true end}
local battles={wave=function()end}
native.create=function(_,def,position,id)local h={def=def,point=position,id=id,stub={SetAttitudeTowards=function()end}};h.actor={K2_GetActorLocation=function()return position end};handles[#handles+1]=h;return h end
native.poll=function(h)h.ready=true;return 'spawned',h.actor,h.stub end
native.recover=function(h)
 if h.dead then return 'dead' end
 if h.missing then return 'unloaded' end
 return 'spawned',h.actor,h.stub,{combat=h.combat or false,engagedPlayer=h.combat or false,target=h.combat and stub or nil}
end
native.activate=function(h)if h.fail then return false end;h.active=true;return true end
native.engage=function(h)assert(h.active,'Inactive boss engaged');h.combat=true;board.Combat.bInCombat=true;return true end
native.destroy=function(h)h.omitted=true;h.active=false;return true end
native.retainCorpse=function(h)kept=kept+1;return true end
native.displayName=function(h)return h.def.name end
package.loaded.ai_state=ai;package.loaded.horde_native=native;package.loaded.companion_settings=settings;package.loaded.companion_combat={battles=battles};package.loaded.runtime_path='unused'
io.open=function()return {write=function()end,close=function()end}end
local m=assert(load(${JSON.stringify(source)}))()
local function tick()now=now+.5;m.tick(false);assert(m.view().phase~='error',m.view().message)end
local function activeCount()local count=0;for _,h in ipairs(handles)do if h.active and not h.dead and not h.omitted then count=count+1 end end;return count end
assert(m.start(pc,'nightmare'))
tick();assert(#handles==1 and activeCount()==0)
tick();assert(#handles==2 and activeCount()==0)
tick();assert(#handles==3 and activeCount()==0)
tick();tick();assert(activeCount()==3 and handles[1].active and handles[2].active and handles[3].active,'Configured group was not released together')
for _=1,4 do tick();assert(activeCount()==3)end
handles[1].dead=true;handles[1].combat=false;board.Combat.bInCombat=false;tick();assert(kept==1 and activeCount()==2 and handles[2].active)
-- Losing one attachment must not block the remaining boss or replace it.
handles[3].missing=true
for _=1,12 do tick()end
assert(activeCount()==1)
assert(handles[3].omitted and m.view().active)
handles[2].dead=true;handles[2].combat=false;board.Combat.bInCombat=false;tick();assert(m.view().phase=='rest' and kept==2)
for _=1,6 do tick()end
for _=1,7 do tick()end
assert(m.view().level==2 and #handles==7 and activeCount()==4,'Growth or rest failed')
for i=4,7 do assert(handles[i].active);handles[i].dead=true;handles[i].combat=false;board.Combat.bInCombat=false;tick()end
assert(m.view().phase=='complete' and not m.view().active and kept==6)
-- Normal waves still release all opponents together.
handles={};assert(m.start(pc,'horde'));for _=1,6 do tick()end;assert(activeCount()==3)
m.stop();assert(not m.view().active)
handles={};board.Combat.bInCombat=false;assert(m.start(pc,'nightmare'));tick();handles[1].fail=true
for _=1,17 do tick()end
assert(handles[1].omitted and handles[2].active and activeCount()==2,'Failed activation blocked the remaining group')
m.stop();assert(not m.view().active)
`);
});
