import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const app=readFileSync('mod/Scripts/app.lua','utf8'),party=readFileSync('mod/Scripts/companions.lua','utf8');
test('party cleanup clears conversation references before native destruction and heartbeat publishing reads no actors',()=>{
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const code=`
 local selected=setmetatable({}, {__index=function()error('Dereferenced an unloading actor')end})
 local selectedName='cached actor';local selectedClass='cached class';local generation=10;local previewEnd=0
 local status='ready';local identity={name='Anca'};local conversationMode='single';local requestId=0;local conversationRoom='room';local speakerTurn=''
 local speechLayer={};local attention={};local engagement={};local composeController={};local inputLease={};local bindings={}
 local FirstPerson={release=function()end};local Horde={stop=function()end}
 local Companions={};local published='';local function write(_,value)published=value end;local function clean(s)return tostring(s)end
 local M=Companions;local members={one={},two={}};local destroyed=0
 local Formation={new=function()return {frame={}}end};local Native={stopAll=function()assert(selected==nil);return true end}
 local Combat={battles={reset=function()end}};local function releaseGaze()end
 local AI={clearFindCache=function()end};Native.clearAssetCache=function()end
 local protected=true;local Protection={cleanup=function()assert(destroyed==2);protected=false end}
 local function dismiss(m)assert(selected==nil and speechLayer==nil and attention==nil and inputLease==nil);destroyed=destroyed+1 end
 ${party.slice(party.indexOf('local beforeReset=nil'),party.indexOf('local function readAbilities'))}
 ${app.slice(app.indexOf('local function publish()'),app.indexOf('local function neutral()'))}
 publish();assert(published:find('cached actor',1,true),'Cache must preserve selected identity without touching UObject')
 M.cleanup();assert(destroyed==2 and selected==nil and generation==11 and not protected);assert(published:find('11\\n0\\n',1,true))
 `;
 try{const rc=lauxlib.luaL_dostring(L,to_luastring(code));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}
});
