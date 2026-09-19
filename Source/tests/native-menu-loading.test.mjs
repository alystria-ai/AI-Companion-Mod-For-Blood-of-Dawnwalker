import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const source=readFileSync('mod/Scripts/companion_menu.lua','utf8');
function run(body){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(`
 for _,name in ipairs({'ai_state','ui_input','companions','companion_settings'})do package.preload[name]=function()return {}end end
 package.preload.runtime_path=function()return 'test'end
 local M=(function() ${source} end)()
 ${body}`));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
test('each rapid summon has independent progress; one arrival cannot finish the batch',()=>run(`
 local requests={{id='one',name='Anca'},{id='two',name='Anca'},{id='three',name='Crake'}}
 local state={members={{id='unrelated',loading=false},{id='one',loading=false}},summons={{id='one',phase='ready'},{id='two',phase='body',message='Loading model'},{id='three',phase='queued'}}}
 local b=M.batch(requests,state);assert(b.ready==1 and b.pending==2 and b.failed==0);assert(math.abs(b.progress-7/15)<.0001)
 state.members[#state.members+1]={id='two',loading=false};b=M.batch(requests,state);assert(b.ready==2 and b.pending==1)
 state.members[#state.members+1]={id='three',loading=false};state.summons={};b=M.batch(requests,state);assert(b.ready==3 and b.pending==0 and b.progress==1)
 -- Bounded engine history can disappear without losing completed requests.
 b=M.batch(requests,{members={},summons={}});assert(b.ready==3)
`));
test('failure wins over stale actor state; ready history alone cannot claim arrival',()=>run(`
 local requests={{id='a',name='Anca'},{id='b',name='Crake'}}
 local b=M.batch(requests,{members={{id='a',loading=false}},summons={{id='a',phase='failed',message='Load failed'},{id='b',phase='ready'}}})
 assert(b.failed==1 and b.pending==1 and b.ready==0);assert(requests[2].phase=='spawning')
 b=M.batch(requests,{members={{id='b',loading=false}},summons={}});assert(b.ready==1 and b.failed==1 and b.pending==0)
`));
test('a new summon extends a completed batch; long queues bound their visible progress list',()=>run(`
 local requests={{id='a',name='Anca'}};M.batch(requests,{members={{id='a',loading=false}}})
 requests[#requests+1]={id='b',name='Bakir'}
 local b=M.batch(requests,{members={}});assert(b.ready==1 and b.pending==1)
 for i=1,20 do requests[#requests+1]={id='other'..i,name='Companion '..i}end
 b=M.batch(requests,{members={}});assert(b.pending==21 and #b.lines==3 and b.total==22)
`));
const partySource=readFileSync('mod/Scripts/companions.lua','utf8');
const queueCode=partySource.slice(partySource.indexOf('function M.enqueue('),partySource.indexOf('local function command(now,selected)'));
test('rapid requests reserve distinct IDs before any game tick, including a failed spawn',()=>run(`
 local nativeCommands,nativeSequence,summons,members={},0,{},{};local byId={anca={}};local lastFault
 local function clean(s)return tostring(s)end;local function log()end;local function same()return false end
 local fail=false;local spawned={}
 local function spawn(id,now,request)if fail then error('No walkable point')end;spawned[#spawned+1]=request end
 local function dismiss()end
 ${queueCode}
 local unique={}
 for i=1,30 do local id=M.enqueue('spawn','anca');assert(id and not unique[id]);unique[id]=true;assert(summons[i].phase=='queued' and summons[i].id==id)end
 assert(#nativeCommands==30 and #spawned==0)
 local first=nativeCommands[1].request;local second=nativeCommands[2].request
 fail=true;nativeCommand(0,nil);assert(#nativeCommands==29 and summons[1].phase=='failed' and lastFault)
 fail=false;nativeCommand(250,nil);assert(#nativeCommands==28 and spawned[1]==second and spawned[1]~=first)
 for i=1,28 do nativeCommand(i*250,nil)end;assert(#spawned==29 and #nativeCommands==0)
`));
