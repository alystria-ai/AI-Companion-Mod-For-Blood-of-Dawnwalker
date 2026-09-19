-- Explicit paused-game, reversible probe of one owned clone. No game time
-- advances. It creates one marker, verifies the BT binding, then releases it.
return function(root)
 local router=require('live_reload').router;local cache=assert(router and router.active and router.active.cache)
 local AI=assert(cache.ai_state);local party=assert(cache.companions)
 local pc=require('UEHelpers').GetPlayerController()
 assert(AI.find('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc),'Pause before binding probe')
 local members;for i=1,100 do local key,value=debug.getupvalue(party.tick,i);if not key then break end;if key=='members'then members=value;break end end
 local m;for _,v in pairs(assert(members))do if AI.board(v.stub,v.board)and not v.stub:IsInCombat()and not v.board:HasAnyUnbreakableActiveAction()then m=v;break end end
 assert(m,'No eligible owned companion')
 local env=setmetatable({require=function(name)return cache[name]or require(name)end},{__index=_G})
 local N=assert(loadfile(root..'/session-v0290/lua/formation_native.lua','t',env))()
 local oldLease=m.formationLease;local rows={m.name}
 if AI.ownsFormation(oldLease,m.stub,m.board)then AI.releaseFormation(oldLease)end
 m.formationLease={}
 local ok,err=pcall(function()
  local a=m.actor:K2_GetActorLocation();local goal={point={X=a.X+240,Y=a.Y,Z=a.Z},distance=240,mode='Paused binding probe'}
  local accepted,why=N.update(m,goal,1000000);rows[#rows+1]='accepted='..tostring(accepted)..' '..tostring(why)
  assert(accepted,why)
  local s=m.formationLease;local bb=m.controller.Blackboard
  rows[#rows+1]='marker='..s.marker:GetFullName()
  rows[#rows+1]='nativeTargetMatches='..tostring(AI.same(bb:GetValueAsObject(m.controller.MovementTargetActorBBKey),s.marker))
  rows[#rows+1]='mainSuspended='..tostring(m.board.bMainBehaviorSuspended)
  local task=AI.find('/Game/_Dawnwalker/NPC/BasicNPC/BT_BasicNPC.BT_BasicNPC:BTTask_MoveTo_5')
  if AI.valid(task)then
   for _,key in ipairs({'AcceptableRadius','bTrackMovingGoal','bReachTestIncludesAgentRadius','bReachTestIncludesGoalRadius'})do
    local pass,value=pcall(function()return tostring(task[key].DefaultValue)end);rows[#rows+1]=key..'='..tostring(value)
   end
  end
 end)
 local marker=m.formationLease.marker
 local cleaned,why=pcall(N.release,m.formationLease)
 rows[#rows+1]='cleanup='..tostring(cleaned)..' markerAlive='..tostring(AI.valid(marker))
 m.formationLease=oldLease
 if not ok then rows[#rows+1]='ERROR '..tostring(err)end
 if not cleaned then rows[#rows+1]='CLEANUP ERROR '..tostring(why)end
 return table.concat(rows,'\n')
end
