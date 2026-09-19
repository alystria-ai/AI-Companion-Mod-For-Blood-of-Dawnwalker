import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
async function check(module,body){const source=await readFile('mod/Scripts/'+module+'.lua','utf8');const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(`local M=(function() ${source} end)()\n${body}`));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
test('circling the current enemy never retreats even with a far flanking companion',()=>check('companion_recovery',`
 local m={};local o={follow=true,encounter=true,now=0,gap=4500,spacing=400,speed=600,awaySpeed=600,combat=true,threatDistance=100,fightDistance=150,fightKnown=true,x=0,y=0}
 for t=0,20000,250 do o.now=t;o.x=t;assert(not M.retreat(m,o));assert(not m.separatedAt and not m.returning)end
 m.returning=true;m.noEngageUntil=99999;assert(not M.retreat(m,o)and not m.noEngageUntil,'Returning to same fight left suppression latched')
`));
test('a recent encounter is required and a brief distant separation does not abandon combat',()=>check('companion_recovery',`
 local m={};local o={follow=true,encounter=true,now=0,gap=4200,spacing=400,speed=0,awaySpeed=0,combat=true,threatDistance=500,fightDistance=5000,fightKnown=true,x=0,y=0}
 assert(not M.retreat(m,o));o.now=1750;assert(not M.retreat(m,o));o.gap=2000;o.now=1900;assert(not M.retreat(m,o));assert(not m.separatedAt)
 o.encounter=false;o.gap=7000;for t=4000,15000,250 do o.now=t;assert(not M.retreat(m,o))end
 m={};o.encounter=true;o.gap=4200;o.now=16000;assert(not M.retreat(m,o))
 o.now=18000;assert(M.retreat(m,o),'A sustained distant separation should regroup before streaming loses the pawn')
`));
test('idle followers wake while the player keeps running, with cooldown and finite stationary retries',()=>check('companion_recovery',`
 local m={};local o={allowed=true,pathStatus=0,now=0,x=0,y=0,px=1000,py=0,gap=1500,spacing=400}
 assert(not M.wakeFollow(m,o));o.now=750;o.px=1700;assert(not M.wakeFollow(m,o));o.now=1500;o.px=2400;assert(M.wakeFollow(m,o),'Player movement continually reset stagnation timer')
 o.now=9499;assert(not M.wakeFollow(m,o));o.now=9500;assert(M.wakeFollow(m,o));o.now=30000;assert(not M.wakeFollow(m,o),'Same blocked path retried forever')
 o.px=2800;assert(M.wakeFollow(m,o),'New travel did not refresh recovery budget')
`));
test('wake respects waiting, paused, close, combat and whole-party budgets',()=>check('companion_recovery',`
 local o={allowed=true,pathStatus=0,now=0,x=0,y=0,px=1000,py=0,gap=1500,spacing=400}
 for _,status in ipairs({1,2})do local m={};o.pathStatus=status;assert(not M.wakeFollow(m,o));o.now=10000;assert(not M.wakeFollow(m,o))end
 local m={};o.pathStatus=0;o.now=0;assert(not M.wakeFollow(m,o));o.now=2000;o.allowed=false;assert(not M.wakeFollow(m,o))
 o.allowed=true;o.now=3000;assert(not M.wakeFollow(m,o));o.now=5000;o.partyLast=4900;assert(not M.wakeFollow(m,o));o.partyLast=4750;assert(M.wakeFollow(m,o))
 o.gap=550;o.now=15000;assert(not M.wakeFollow(m,o))
`));
const marker=`
 EObjectFlags={RF_BeginDestroyed=1,RF_FinishDestroyed=2}
 local function object(name)return {IsValid=function()return true end,HasAnyFlags=function()return false end,GetFullName=function()return name end}end
 local root=object('root');root.Mobility=0;local changes=0;root.SetMobility=function(self,n)self.Mobility=n;changes=changes+1 end
 local marker=object('owned marker');marker.RootComponent=root;local point={X=0,Y=0,Z=0};local calls=0
 marker.K2_SetActorLocation=function(_,p,sweep,hit,teleport)assert(root.Mobility==2 and sweep==false and teleport==true);point=p;calls=calls+1;return true end
 marker.K2_GetActorLocation=function()return point end
 local lease={};local dest={X=100,Y=200,Z=300}
`;
test('owned static marker uses movable scene root and restores its original mobility once',()=>check('ai_state',marker+`
 assert(M.moveSpawnAnchor(marker,dest,lease));assert(changes==1 and calls==1)
 assert(M.moveSpawnAnchor(marker,dest,lease));assert(changes==1 and calls==2)
 M.releaseSpawnAnchor(lease);M.releaseSpawnAnchor(lease);assert(root.Mobility==0 and changes==2)
`));
test('marker movement confirms readback and respects native edits, invalid or replaced roots',()=>check('ai_state',marker+`
 marker.K2_SetActorLocation=function()return false end
 assert(not M.moveSpawnAnchor(marker,dest,lease),'Rejected position reported success')
 root.Mobility=1;assert(not M.moveSpawnAnchor(marker,dest,lease));M.releaseSpawnAnchor(lease);assert(root.Mobility==1,'Native mobility edit overwritten')
 root.Mobility=0;M.moveSpawnAnchor(marker,dest,lease);marker.RootComponent=object('replacement')
 assert(not M.moveSpawnAnchor(marker,dest,lease));root.IsValid=function()return false end;local n=changes;M.releaseSpawnAnchor(lease);assert(changes==n)
`));
test('large-party catchup permits one arrival each update while retaining per-companion failure backoff',()=>check('companion_recovery',`
 local o={follow=true,grounded=true,gap=3000,now=1000,partyLast=750,partyInterval=250}
 assert(M.catchup(o));o.partyLast=900;assert(not M.catchup(o));o.partyLast=0;o.attempted=0;o.failures=2;assert(not M.catchup(o));o.now=8000;assert(M.catchup(o))
`));
