import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const app=await readFile(process.env.DAWNWALKER_APP||'mod/Scripts/app.lua','utf8');
const targeting=await readFile('mod/Scripts/targeting.lua','utf8');
const policy=app.slice(app.indexOf('local function conversationWalkedAway'),app.indexOf('if RegisterModCleanup then RegisterModCleanup'));
const handoff=app.slice(app.indexOf("local lastGroupCommand=''"),app.indexOf('local function uiCommand()'));
function execute(code){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(code));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}

test('actual Lua group handoff cannot interpret looking at the first speaker as leaving the group',()=>execute(`
 local Targeting=(function() ${targeting} end)();local config={MaxDistance=450}
 local conversationMode='group';local conversationRoom='room1';local groupOrigin=nil;local lookingAwaySince=nil
 local selected='first';local generation=5;local speakerTurn='';local status;local root='test';local speechLayer=nil
 local function restoreFocusPause()end;local function releaseConversation()end;local function neutral()end
 local function publish()end;local function log()end;local function write()end
 ${policy}
 local text='GROUP\\t1\\troom1\\tturn1\\tmember1\\t5'
 io.open=function()return {read=function()return text end,close=function()end}end
 local Companions={actor=function()return 'second',false end}
 local function toggle(_,actor)selected=actor;generation=generation+1 end
 ${handoff}
 local p={X=0,Y=0,Z=0};local forward={X=1,Y=0,Z=0}
 assert(not conversationWalkedAway(p,forward,{X=300,Y=0,Z=0},false))
 local origin=groupOrigin;groupCommand();assert(selected=='second' and groupOrigin==origin)
 -- This was the failure: another member beyond single-chat range and behind
 -- the camera. Repeat for longer than the old two-second release debounce.
 for i=1,100 do
  assert(not conversationWalkedAway(p,forward,{X=-700,Y=150,Z=0},false),'Stationary group was cancelled')
 end
 assert(not conversationWalkedAway({X=1100,Y=0,Z=0},forward,{X=-700,Y=150,Z=0},false))
 assert(conversationWalkedAway({X=1201,Y=0,Z=0},forward,{X=1500,Y=0,Z=0},false),'Real departure did not release group')
 groupCommand();assert(groupOrigin==origin,'Repeated handoff moved the group origin')
 stop('Conversation ended');assert(groupOrigin==nil)
 conversationWalkedAway({X=5000,Y=0,Z=0},forward,{X=5500,Y=0,Z=0},false)
 assert(groupOrigin.X==5000,'Next conversation inherited the old area')
 conversationMode='single'
 assert(conversationWalkedAway(p,forward,{X=-700,Y=150,Z=0},false),'Single chat lost its walk-away rule')
 assert(not conversationWalkedAway(p,forward,{X=-700,Y=150,Z=0},true),'Single following chat changed')
`));
