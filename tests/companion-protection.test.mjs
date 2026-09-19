import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
test('source protection owns its effect and marker leases; player changes and reload remove exact handles',async()=>{
 const source=await readFile('mod/Scripts/companion_protection.lua','utf8');const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const setup=`
 local calls={};local sequence=0
 local function obj(name)
  return {name=name,GetFullName=function(self)return 'Object /Transient.'..self.name end,Reflection=function()return {
   GetProperty=function(_,key)return {ContainerPtrToValuePtr=function()return {}end,ImportText=function(_,text)table.insert(calls,'import:'..key)end}end}end}
 end
 local player,asc,asc2,ally= obj('player'),obj('asc'),obj('asc2'),obj('ally')
 local playerStub={GetAbilitySystemComponent=function()return asc end}
 local allyAsc=obj('allyASC');local member={actor=ally,board={},stub={GetAbilitySystemComponent=function()return allyAsc end}}
 package.preload.ai_state=function()return {valid=function(o)return o~=nil end,board=function(s)return s end,same=function(a,b)return a~=nil and a==b end,find=function(s)return s end}end
 package.preload.companion_native=function()return {run=function(op,args)
  calls[#calls+1]=op..':'..table.concat(args,'|')
  if op=='protectapply'then return {handle='42'}end
  return {}
 end}end
 function StaticConstructObject()sequence=sequence+1;return obj('private'..sequence)end
 `;
 const body=`
 assert(M.ensure(player,playerStub));local count=#calls
 assert(M.ensure(player,playerStub)and #calls==count,'Protection stacked on a polling tick')
 M.mark(member,playerStub);assert(calls[#calls]=='protecttag:/Transient.ally|/Transient.allyASC|1')
 count=#calls;M.mark(member,playerStub);assert(#calls==count,'Marker stacked on a polling tick')
 local bad={actor=player,stub=playerStub,board={}}
 assert(not pcall(M.mark,bad,playerStub)and #calls==count,'Player was tagged as a source')
 M.unmark(member);assert(calls[#calls]=='protecttag:/Transient.ally|/Transient.allyASC|0')
 count=#calls;M.unmark(member);assert(#calls==count)
 asc=asc2;assert(M.ensure(player,playerStub))
 assert(calls[count+1]=='protectremove:/Transient.asc|42|/Transient.private1')
 assert(calls[count+2]=='protectrelease:/Transient.private1')
 M.cleanup();assert(calls[#calls-1]=='protectremove:/Transient.asc2|42|/Transient.private3')
 assert(calls[#calls]=='protectrelease:/Transient.private3');count=#calls;M.cleanup();assert(#calls==count)
 `;
 try{const rc=lauxlib.luaL_dostring(L,to_luastring(setup+'\nlocal M=(function()\n'+source+'\nend)()\n'+body));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}
});
