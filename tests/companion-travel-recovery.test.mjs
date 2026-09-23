import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';

const scripts=process.env.DAWNWALKER_LUA||'mod/Scripts';
const recovery=await readFile(`${scripts}/companion_recovery.lua`,'utf8');
const companions=await readFile(`${scripts}/companions.lua`,'utf8');
function run(body){
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 try{
  const rc=lauxlib.luaL_dostring(L,to_luastring(`local M=(function()${recovery}end)()\n${body}`));
  assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));
 }finally{lua.lua_close(L);}
}
function extract(start,end){
 const from=companions.indexOf(start);const to=companions.indexOf(end,from);
 assert.ok(from>=0&&to>from,`Missing source section ${start}`);return companions.slice(from,to);
}
function execute(source){
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 try{const rc=lauxlib.luaL_dostring(L,to_luastring(source));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}
 finally{lua.lua_close(L);}
}

test('loading budget yields after four quick steps or four milliseconds without starving queued members',()=>run(`
 local budget={}
 assert(M.admitLoadStep(budget,100))
 assert(M.admitLoadStep(budget,100.001))
 assert(not M.admitLoadStep(budget,100.005),'Spent frame budget admitted another setup')
 budget={};for i=1,4 do assert(M.admitLoadStep(budget,200))end
 assert(not M.admitLoadStep(budget,200),'A ready batch ran all work in one tick')
 local members={};for i=1,12 do members[i]={ordinal=i,id=i}end
 local seen,cursor={},0
 for tick=1,12 do
  local order;order,cursor=M.updateOrder(members,cursor);local b={}
  for i,m in ipairs(order)do if M.admitLoadStep(b,i*.005)then seen[m.id]=true end end
 end
 for i=1,12 do assert(seen[i],'Round-robin loading starved a later companion')end
`));

test('fast travel and rapid movement form bounded recovery epochs',()=>run(`
 local s={epoch=0};local function sample(now,x,speed,world,player)
  return M.travelTransition(s,{now=now,world=world or 'world',player=player or 'player',point={X=x,Y=0,Z=0},speed=speed or 0})
 end
 local kind,epoch=sample(0,0,0);assert(not kind and epoch==0)
 kind,epoch=sample(250,300,600);assert(not kind and epoch==0)
 kind,epoch=sample(500,800,1300);assert(kind=='rapid travel'and epoch==1)
 kind,epoch=sample(750,1300,1300);assert(kind=='rapid travel'and epoch==1,'One speed leg created repeated recovery epochs')
 kind,epoch=sample(6000,1400,0);assert(not kind and epoch==1)
 kind,epoch=sample(6250,5000,0);assert(kind=='fast travel'and epoch==2)
 kind,epoch=sample(12000,5000,0);assert(not kind and epoch==2)
 kind,epoch=sample(12250,5000,0,'world','new player');assert(kind=='player'and epoch==3)
 kind,epoch=sample(18000,5000,0,'new world','new player');assert(kind=='world'and epoch==4)
 local active={epoch=0};M.travelTransition(active,{now=0,world='w',player='p',point={X=0,Y=0,Z=0},speed=0})
 kind,epoch=M.travelTransition(active,{now=250,world='w',player='p',point={X=300,Y=0,Z=0},speed=1200});assert(kind=='rapid travel'and epoch==1)
 local discontinuity;kind,epoch,discontinuity=M.travelTransition(active,{now=500,world='w',player='p',point={X=4000,Y=0,Z=0},speed=0})
 assert(kind=='fast travel'and epoch==2 and discontinuity,'Jump inside rapid travel reused its recovery epoch')
 kind,epoch,discontinuity=M.travelTransition(active,{now=100,world='w',player='p',point={X=4000,Y=0,Z=0},speed=0,reset=true})
 assert(kind=='time reset'and epoch==3 and discontinuity,'Clock rewind reused its old recovery epoch')
`));

test('reposition evidence cannot be mistaken for leaving combat',()=>run(`
 local m={returning=true,returnKind='distant separation',departure={kind='running'},separatedAt=1,sprintDeparture={at=1}}
 assert(M.repositioning(m,true));assert(m.returning and m.returnKind=='distant separation')
 assert(not m.departure and not m.separatedAt and not m.sprintDeparture)
 assert(not M.repositioning(m,false))
`));

test('continuous super speed still disengages a fight after sustained outward travel',()=>run(`
 local state={epoch=0};local m={};local o={follow=true,encounter=true,gap=2200,spacing=400,speed=1200,awaySpeed=1200,combat=true,threatDistance=3000,fightDistance=3000,fightKnown=true,y=0}
 for now=0,2000,250 do
  local x=now/250*300;o.now=now;o.x=x
  local kind,epoch,discontinuity=M.travelTransition(state,{now=now,world='world',player='player',point={X=x,Y=0,Z=0},speed=1200})
  assert(not discontinuity,'Continuous speed was classified as a teleport')
  M.retreat(m,o)
 end
 assert(m.returning and m.returnKind=='sustained run','Rapid travel suppressed the normal combat departure detector')
`));

test('travel recovery relocates only safe hidden pawns and bypasses a stale cooldown',()=>run(`
 local base={follow=true,dead=false,combat=false,busy=false,grounded=true,visible=false,gap=4000,minimum=1200,now=5000,last=4500,attempted=0,partyLast=0,reposition=true}
 assert(M.catchup(base),'Travel epoch did not bypass an unrelated old arrival cooldown')
 for key,value in pairs({dead=true,combat=true,busy=true,grounded=false,visible=true})do
  local old=base[key];base[key]=value;assert(not M.catchup(base),'Unsafe travel relocation: '..key);base[key]=old
 end
`));

test('a vanished population owner gets one delayed replacement per travel epoch',()=>run(`
 local o={now=11999,since=0,owner=false,travelEpoch=7,follow=true,dead=false}
 assert(not M.replaceMissing(o));o.now=12000;assert(M.replaceMissing(o))
 o.owner=true;assert(not M.replaceMissing(o));o.owner=false;o.replacedEpoch=7;assert(not M.replaceMissing(o))
 o.travelEpoch=8;assert(M.replaceMissing(o));o.travelEpoch=nil;assert(not M.replaceMissing(o))
`));

test('an owned anchor that moved successfully gets one last-resort replacement after thirty seconds',()=>run(`
 local o={now=29999,since=0,owner=true,anchorMoved=true,travelEpoch=4,follow=true,dead=false}
 assert(not M.replaceMissing(o));o.now=30000;assert(M.replaceMissing(o))
 o.anchorMoved=false;assert(not M.replaceMissing(o));o.anchorMoved=true;o.follow=false;assert(not M.replaceMissing(o))
 o.follow=true;o.dead=true;assert(not M.replaceMissing(o));o.dead=false;o.replacedEpoch=4;assert(not M.replaceMissing(o))
`));

test('world snapshot retains pending members, defeat tombstones and queued intent',()=>{
 const source=extract('local function resetParty','function M.cleanup');
 execute(`
  local members={live={id='live',characterId='anca',ordinal=2,mode='follow',spawnSlot=2},dead={id='dead',characterId='lacra',ordinal=3,mode='stop',spawnSlot=3,defeated=true,peaceSince=55}}
  local pendingWorldParty={entries={{id='loading',characterId='xanthe',ordinal=1,mode='follow',spawnSlot=1}}}
  local nativeCommands={{op='dismiss',id='live'},{op='spawn',id='ambrus',request='p1'}}
  local beforeReset=nil;local formation={};local formationFrame={};local partyDeparture=false;local partyPositions={};local updateCursor=4
  local lastFollowWake,lastPartyCatchup,lastReconnectPoll,lastDiagnosticTick,lastAnchorUpdate,travelHeading,playerStub=true,true,true,true,true,true,true
  local Formation={new=function()return {frame={}}end};local Native={stopAll=function()return true end}
  local Protection={cleanup=function()end}
  local function ready(m)return m.id=='live'end;members.live.board={bIsDead=false}
  local function dismiss(m)members[m.id]=nil end
  ${source}
  local snapshot=resetParty('world',true)
  assert(#snapshot.entries==3 and snapshot.entries[1].id=='loading'and snapshot.entries[3].id=='dead')
  assert(snapshot.entries[3].defeated and snapshot.entries[3].peaceSince==55)
  assert(#nativeCommands==2 and nativeCommands[1].op=='dismiss'and nativeCommands[2].op=='spawn','Queued user intent was discarded')
  assert(next(members)==nil)
 `);
});

test('world restoration advances one member per tick and keeps defeated members unloaded',()=>{
 const source=extract('local function restoreWorldParty','local function eligible');
 execute(`
  local pendingWorldParty={entries={{id='dead',characterId='lacra',ordinal=1,mode='stop',spawnSlot=1,defeated=true,peaceSince=25},{id='live',characterId='anca',ordinal=2,mode='follow',spawnSlot=2}},retryAt=0}
  local members={};local spawns=0;local travelEpoch=9;local note='';local logs={}
  local byId={lacra={name='Lacra',archetype='lacra'},anca={name='Anca',archetype='anca'}}
  local Recovery={layout=function()end};local function log(v)logs[#logs+1]=v end;local function clean(v)return tostring(v)end
  local function spawn(character,now,id)spawns=spawns+1;members[id]={id=id,characterId=character,ordinal=99,mode='follow',spawnSlot=99}end
  ${source}
  restoreWorldParty(100)
  assert(spawns==0 and members.dead and members.dead.defeated and members.dead.health==0 and members.dead.loading==nil and members.dead.peaceSince==nil)
  assert(members.dead.mode=='stop'and #pendingWorldParty.entries==1,'Defeated member was respawned or queue was drained in one tick')
  restoreWorldParty(350)
  assert(spawns==1 and members.live and members.live.ordinal==2 and members.live.spawnSlot==2)
  assert(pendingWorldParty==nil,'Completed restore queue was retained')
 `);
});

test('queued dismissal cancels blocked restoration without reordering summons',()=>{
 const source=extract('local function cancelPendingWorldDismissals','local function restoreWorldParty');
 execute(`
  local pendingWorldParty={entries={{id='a'},{id='b'}}}
  local first={op='spawn',id='anca',request='p1'};local second={op='spawn',id='lacra',request='p2'}
  local nativeCommands={first,{op='dismiss',id='a'},second}
  ${source}
  cancelPendingWorldDismissals()
  assert(#pendingWorldParty.entries==1 and pendingWorldParty.entries[1].id=='b')
  assert(#nativeCommands==2 and nativeCommands[1]==first and nativeCommands[2]==second,'Summon queue order changed')
  nativeCommands[#nativeCommands+1]={op='dismiss_all'};cancelPendingWorldDismissals()
  assert(#pendingWorldParty.entries==0 and nativeCommands[1]==first and nativeCommands[2]==second and nativeCommands[3].op=='dismiss_all')
 `);
});
