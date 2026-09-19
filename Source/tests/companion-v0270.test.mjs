import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const scripts=process.env.DAWNWALKER_LUA||'mod/Scripts';
async function check(body){
 const source=await readFile(`${scripts}/ai_state.lua`,'utf8');
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 try{const result=lauxlib.luaL_dostring(L,to_luastring(`local M=(function() ${source} end)()\n${setup}\n${body}`));assert.equal(result,lua.LUA_OK,result===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}
}
const setup=`
 EObjectFlags={RF_BeginDestroyed=1,RF_FinishDestroyed=2}
 local function obj(n)return {IsValid=function()return true end,HasAnyFlags=function()return false end,GetFullName=function()return n end}end
 local s,b=obj('stub'),obj('board');s.AIBoard=b;s.IsInitializedAndHasPawn=function()return true end
 local scene=false;s.IsInCinematicMode=function()return scene end;s.IsInCombat=function()return true end
 b.Follower={bIsTemporaryFollower=true,bFollowerModeEnabled=false}
 b.Combat={bInCombat=true};b.HasAnyUnbreakableActiveAction=function()return false end
 local pose='RebelAI.CharacterState.Running';b.CurrentCharacterState={TagName={ToString=function()return pose end}}
 local state={}
`;
test('combat releases the campaign follower distance gate and restores it for travel',()=>check(`
 assert(M.combatFollower(s,b,state));assert(not b.Follower.bIsTemporaryFollower)
 for i=1,10 do assert(M.combatFollower(s,b,state))end
 assert(state.original==true and not b.Follower.bFollowerModeEnabled)
 M.releaseCombatFollower(state);assert(b.Follower.bIsTemporaryFollower and not state.owned)
 b.Follower.bIsTemporaryFollower=false;assert(M.combatFollower(s,b,state));M.releaseCombatFollower(state)
 assert(not b.Follower.bIsTemporaryFollower,'Changed an originally non-temporary identity')
`));
test('scenes release the temporary combat identity; detached boards cannot be written through',()=>check(`
 assert(M.combatFollower(s,b,state));scene=true
 assert(not M.combatFollower(s,b,state));assert(b.Follower.bIsTemporaryFollower and not state.owned)
 scene=false;assert(M.combatFollower(s,b,state));s.AIBoard=nil
 b.Follower=setmetatable({},{__newindex=function()error('Detached board write')end})
 M.releaseCombatFollower(state);assert(not state.owned)
`));
test('arena override is scoped to the supplied live board and refuses detached stubs',()=>check(`
 local library=obj('library');local calls=0
 library.SetIgnoreGuardAreas=function(_,target,enabled)assert(target==s and enabled==true);calls=calls+1 end
 assert(M.ignoreCombatGuardAreas(library,s,b));assert(calls==1)
 assert(not M.ignoreCombatGuardAreas(library,s,obj('different board')));assert(calls==1)
 s.AIBoard=nil;assert(not M.ignoreCombatGuardAreas(library,s,b));assert(calls==1)
`));
const movement=`
 local walk,authored,defense=obj('RebelCharacterMovementProfile /p/DA_NPC_Walker_MovementProfile.DA_NPC_Walker_MovementProfile'),obj('authored combat'),obj('native defense')
 walk.MovementConfig={MaxSpeed=140};authored.MovementConfig={MaxSpeed=425}
 local current=walk;local movement=obj('movement');local pushes,pops=0,0
 movement.GetCurrentMovementProfile=function()return current end
 movement.PushMovementProfile=function()pushes=pushes+1;return pushes end
 movement.PopMovementProfile=function()pops=pops+1 end
`;
test('deferred native movement application is retained and does not push duplicate profiles',()=>check(movement+`
 assert(M.combatMovement(s,b,state,movement,authored,0));assert(current==walk and pops==0)
 assert(M.combatMovement(s,b,state,movement,authored,250));current=authored
 for t=500,5000,250 do assert(M.combatMovement(s,b,state,movement,authored,t))end
 assert(pushes==1 and pops==0)
`));
test('native combat states and defense profiles win even inside the pending window',()=>check(movement+`
 assert(M.combatMovement(s,b,state,movement,authored,0));current=defense
 assert(not M.combatMovement(s,b,state,movement,authored,250));assert(pops==1 and current==defense)
 current=walk;assert(M.combatMovement(s,b,state,movement,authored,500))
 pose='RebelAI.CharacterState.Combat.Sword.Defense'
 assert(not M.combatMovement(s,b,state,movement,authored,600));assert(pops==2)
`));
