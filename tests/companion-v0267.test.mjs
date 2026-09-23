import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
async function check(module,body){const source=await readFile('mod/Scripts/'+module+'.lua','utf8');const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(`local M=(function() ${source} end)()\n${body}`));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
const fixture=`
 local enters,prepares,starts,stops,clears,following=0,0,0,0,0,true
 local equipmentReady=false;local accept=false
 local c=M.new({settleMs=500,retryMs=3000,enter=function()enters=enters+1;following=false;return true end,
 prepare=function()prepares=prepares+1;return equipmentReady end,target=function()return true end,
 maintain=function()following=false end,start=function()starts=starts+1;return accept end,
 travel=function(v)following=v end,clear=function()clears=clears+1 end,stop=function()stops=stops+1;return true end})
 local o={now=0,allowed=true,key='enemy',nativeCombat=false,busy=false,follow=true}
 local function tick(t)o.now=t;return c:tick(o)end
`;
test('equipment can take time and rejected target eligibility retains combat ownership',()=>check('companion_combat',fixture+`
 assert(tick(0)=='preparing');assert(enters==1 and starts==0)
 equipmentReady=true;assert(tick(250)=='preparing');assert(tick(500)=='preparing');assert(tick(750)=='preparing')
 assert(starts==1 and not following and clears==0)
 for t=1000,3500,250 do assert(tick(t)=='preparing')end
 accept=true;assert(tick(3750)=='combat');assert(starts==2 and enters==1 and prepares==2 and stops==0)
`));
test('native entry after a rejected call is adopted without re-equipping or retrying',()=>check('companion_combat',fixture+`
 equipmentReady=true;tick(0);tick(500);assert(starts==1)
 o.nativeCombat=true;assert(tick(750)=='combat');assert(enters==1 and starts==1 and not following)
 o.key=nil;for t=1000,30000,250 do assert(tick(t)=='combat')end
 assert(stops==0 and starts==1)
`));
test('native entry during a target gap acknowledges already-owned preparation',()=>check('companion_combat',fixture+`
 equipmentReady=true;tick(0);tick(500);assert(starts==1 and c.phase=='preparing')
 o.key=nil;o.nativeCombat=true;assert(tick(750)=='combat')
 assert(c.accepted and c.phase=='combat' and c.lastNativeCombat==750)
 o.nativeCombat=false;o.busy=true;assert(tick(6000)=='combat')
 assert(stops==0 and clears==0 and not following)
`));
test('preparation perception gaps are tolerated, while actual departure releases an unstarted fight',()=>check('companion_combat',fixture+`
 equipmentReady=true;tick(0);o.key=nil;assert(tick(250)=='preparing');assert(tick(1250)=='preparing')
 o.key='enemy';tick(1500);assert(enters==1)
 o.allowed=false;o.busy=true;assert(tick(1750)=='leaving');assert(not following and stops==0)
 o.busy=false;assert(tick(2000)=='travel');assert(following and stops==0 and clears==1)
`));
test('failed equipment has a bounded wait and never repeatedly stops follower goals',()=>check('companion_combat',fixture+`
 for t=0,11750,250 do assert(tick(t)=='preparing')end
 assert(tick(12000)=='cooldown');assert(following and starts==0 and enters==1 and clears==1)
 for t=12250,21750,250 do tick(t)end;assert(enters==1)
`));
test('each of 24 companions gets first access to shared recovery budgets and removal stays safe',()=>check('companion_recovery',`
 local party={};for i=1,24 do party[i]={ordinal=i}end
 local cursor=0;local seen={}
 for i=1,24 do local order;order,cursor=M.updateOrder(party,cursor);assert(#order==24);seen[order[1].ordinal]=true end
 for i=1,24 do assert(seen[i],'Recovery starved a party member')end
 party[3]=nil;local order;order,cursor=M.updateOrder(party,999);assert(#order==23)
 order,cursor=M.updateOrder({},cursor);assert(#order==0 and cursor==0)
`));
test('both native combat flags acknowledge entry before the start gate is changed',()=>check('ai_state',`
 EObjectFlags={RF_BeginDestroyed=1,RF_FinishDestroyed=2}
 local function obj(n)return {IsValid=function()return true end,GetFullName=function()return n end,HasAnyFlags=function()return false end}end
 local s,b,t,tb=obj('s'),obj('b'),obj('t'),obj('tb');s.AIBoard=b;t.AIBoard=tb
 s.IsInitializedAndHasPawn=function()return true end;t.IsInitializedAndHasPawn=s.IsInitializedAndHasPawn
 s.IsInCombat=function()return false end;s.IsInCinematicMode=s.IsInCombat
 local busy=true;b.bCanFight=true;b.Combat={bInCombat=true};b.HasAnyUnbreakableActiveAction=function()return busy end
 local calls=0;local lib={StartCombatBehaviors=function()calls=calls+1;b.Combat.bInCombat=true;return false end}
 assert(M.startCombat(lib,s,b,t));assert(calls==0 and b.bCanFight)
 busy=false
 b.Combat.bInCombat=false;assert(M.startCombat(lib,s,b,t));assert(calls==1 and b.bCanFight)
`));
test('live reload retries a failed queue without duplicating pending work',()=>check('live_reload',`
 local fail=true;local q={};local reports={}
 local r=M.new(_G,require,function(fn)if fail then error('queue unavailable')end;q[#q+1]=fn end,function(s)reports[#reports+1]=s end)
 local files={app='return {}'};assert(r:reload(files))
 r:poll(files,'v');r:poll(files,'v');assert(not r.pending and #q==0)
 fail=false;r:poll(files,'v');r:poll(files,'v');assert(r.pending and #q==1)
 q[1]();assert(not r.pending and r.last=='v');r:poll(files,'v');assert(#q==1)
`));
async function companionPart(from,to,body,preamble=''){
 const source=await readFile('mod/Scripts/companions.lua','utf8');
 const part=source.slice(source.indexOf(from),source.indexOf(to,source.indexOf(from)));
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 try{const rc=lauxlib.luaL_dostring(L,to_luastring(`${preamble}\n${part}\n${body}`));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}
}
test('native opponent wins over player aim; bootstrap target lease releases after entry',()=>companionPart(
 'local function targetFor','local function apply',`
 local own,aimed={id='native'},nil
 aimed={id='aimed'};playerStub.AIBoard={GetTarget=function()return aimed end}
 local forced;local changes,instigators=0,0
 local m={stub={IsInCombat=function()return true end},board={Combat={bInCombat=true},GetTarget=function()return own end,GetForcedTarget=function()return forced end,SetForcedTarget=function(_,t)changes=changes+1;forced=t end}}
 m.combatTarget=assert(targetFor(m,{}));assert(m.combatTarget==own)
 forced=aimed;m.issuedTarget=aimed
 local ops=combatController(m);assert(ops.target());assert(forced==nil and m.issuedTarget==nil and changes==1)
 assert(ops.target());assert(changes==1,'Native combat got another forced-target write')
 local external={id='external'};forced=external;assert(not ops.target());assert(forced==external and changes==1)
 `,`
 local Combat={new=function(ops)return ops end}
 local player,playerPoint={},nil;local playerStub={};local function loc()return {}end
 local function eligible(o)return o~=nil end;local function valid(o)return o~=nil end
 local function same(a,b)return a~=nil and a==b end;local function ready()return true end
 local function enemyPair()return true end
`));
test('long encounters do not fail or consume leases for native hostility',()=>companionPart(
 'local function enemyPair','local function dismiss',`
 local m={enemyAttitudes={}};for i=1,128 do m.enemyAttitudes[i]={}end
 local relation=1;local a={GetFullName=function()return 'a'end,GetAttitudeTowards=function()return relation end,SetAttitudeTowards=function()error('Unexpected extra lease')end}
 local b={GetFullName=function()return 'b'end}
 assert(enemyPair(m,a,b)==false)
 relation=3;assert(enemyPair(m,a,b)==true and #m.enemyAttitudes==128)
`));
