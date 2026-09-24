import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const scripts=process.env.DAWNWALKER_LUA||'mod/Scripts';
const ai=await readFile(`${scripts}/ai_state.lua`,'utf8');
const recovery=await readFile(`${scripts}/companion_recovery.lua`,'utf8');
function run(s){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(s));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
test('formation navigation owns the path once and restores native behavior on combat or failure',()=>run(`
 local b={bMainBehaviorSuspended=false,Combat={},HasAnyUnbreakableActiveAction=function(self)return self.busy end}
 local s={AIBoard=b,IsInCombat=function()return b.Combat.bInCombat end,IsInCinematicMode=function()return b.cinematic end}
 local M={valid=function(o)return o and not o.invalid end,same=function(a,b)return a==b end,board=function(s,expected)return s.AIBoard==expected and expected end}
 local stops=0;local cancels=0;local path='native player target'
 b.StopAllActions=function()cancels=cancels+1 end
 local c={StopMovement=function()stops=stops+1;path=nil end}
 ${ai.slice(ai.indexOf('function M.ownsFormation('),ai.indexOf('function M.travelPace('))}
 local lease={};assert(M.acquireFormation(s,b,lease,c));path='rear arc seat'
 for i=1,50 do
  if not b.bMainBehaviorSuspended then path='native player target'end
  assert(M.acquireFormation(s,b,lease,c))
 end
 assert(path=='rear arc seat'and cancels==1 and stops==1,'Repeated acquisition reset the path')
 b.Combat.bInCombat=true;assert(not M.acquireFormation(s,b,lease,c))
 assert(not b.bMainBehaviorSuspended and not lease.owned,'Combat must recover native behavior')
 b.Combat.bInCombat=false;b.bMainBehaviorSuspended=true
 assert(not M.acquireFormation(s,b,lease,c));M.releaseFormation(lease)
 assert(b.bMainBehaviorSuspended,'External scene hold was cleared')
 b.bMainBehaviorSuspended=false;b.StopAllActions=function()error('native action failure')end
 assert(not M.acquireFormation(s,b,lease,c));assert(not b.bMainBehaviorSuspended and not lease.owned,'Partial acquire leaked a hold')
 b.StopAllActions=function()end;assert(M.acquireFormation(s,b,lease,c));local replacement={bMainBehaviorSuspended=true};s.AIBoard=replacement
 M.releaseFormation(lease);assert(replacement.bMainBehaviorSuspended,'Detached owner changed a replacement board')
`));
test('strict arc reservations wait for locked occupancy instead of shifting seats into rows',()=>run(`
 local M=(function()${recovery}end)()
 local player={X=0,Y=0,Z=0};local q=M.followPoint(player,0,1,190)
 local count=0;local function project(p)count=count+1;return p end
 local goal,why=M.travelDestination(q,player,{q},project,190,0,true)
 assert(not goal and why=='occupied'and count==1,'Occupied seat shifted sideways/backward')
 goal=M.travelDestination(q,player,{},project,190,0,true)
 assert(goal and goal.X==q.X and goal.Y==q.Y)
 local seats={};for i=1,20 do seats[i]=M.followPoint(player,0,i,190)end
 for i=1,20 do
  local reserved={};for j=1,20 do if j~=i then reserved[#reserved+1]=seats[j]end end
  local p=M.travelDestination(seats[i],player,reserved,project,160,0,true)
  assert(p and p.X==seats[i].X and p.Y==seats[i].Y,'Another reserved arc seat blocked a free destination')
 end
`));
