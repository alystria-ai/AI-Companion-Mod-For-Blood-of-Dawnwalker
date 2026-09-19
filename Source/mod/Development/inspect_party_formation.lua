-- Paused, explicit read-only navigation sample. No movement or AI writes.
return function(root)
 local router=require('live_reload').router;local cache=assert(router and router.active and router.active.cache,'Live module cache unavailable')
 local AI=assert(cache.ai_state);local R=assert(cache.companion_recovery)
 local pc=require('UEHelpers').GetPlayerController();assert(AI.valid(pc)and AI.valid(pc.Pawn),'Player unavailable')
 local pawn=pc.Pawn;local p=pawn:K2_GetActorLocation();local yaw=pawn:K2_GetActorRotation().Yaw
 local nav=AI.find('/Script/NavigationSystem.Default__NavigationSystemV1')
 local rows={string.format('player=%.2f,%.2f,%.2f yaw=%.2f',p.X,p.Y,p.Z,yaw)}
 rows[#rows+1]='activePlanner='..tostring(cache.party_formation and cache.party_formation.version)..' activeNativeAdapter='..tostring(cache.formation_native and cache.formation_native.version)
 for i=0,5 do
  local task=AI.find('/Game/_Dawnwalker/NPC/BasicNPC/BT_BasicNPC.BT_BasicNPC:BTTask_MoveTo_'..i)
  if AI.valid(task)then local ok,s=pcall(function()return task.BlackboardKey.SelectedKeyName:ToString()..' radius='..tostring(task.AcceptableRadius.DefaultValue)..' radiusKey='..task.AcceptableRadius.Key:ToString()..' trackKey='..task.bTrackMovingGoal.Key:ToString()..' trackDefault='..tostring(task.bTrackMovingGoal.DefaultValue)end);rows[#rows+1]='move task '..i..' '..tostring(s)end
 end
 local values={};for i=1,100 do local k,v=debug.getupvalue(cache.companions.tick,i);if not k then break end;values[k]=v end
 local frame=values.formationFrame;local members=values.members
 if frame and frame.point then rows[#rows+1]=string.format('frame=%.2f,%.2f,%.2f yaw=%.2f moving=%s',frame.point.X,frame.point.Y,frame.point.Z,frame.yaw,tostring(frame.moving))end
 local function read(name)local f=assert(io.open(root..'/'..name,'rb'));local s=f:read('*a');f:close();return s end
 local function project(q)
  local out={X=0,Y=0,Z=0};local ok=nav:K2_ProjectPointToNavigation(pawn,q,out,nil,nil,{X=150,Y=150,Z=250})
  return string.format('ok=%s wanted=%.2f,%.2f,%.2f projected=%.2f,%.2f,%.2f',tostring(ok),q.X,q.Y,q.Z,out.X,out.Y,out.Z)
 end
 for line in read('companion-formation.tsv'):gmatch('[^\r\n]+')do
  local id,name,x,y,sx,sy=line:match('^([^\t]+)\t([^\t]+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)')
  if tonumber(sx)then rows[#rows+1]=name..' recorded seat '..project({X=tonumber(sx),Y=tonumber(sy),Z=p.Z})end
 end
 for i=1,9 do rows[#rows+1]='seat '..i..' '..project(R.followPoint(p,yaw,i,190))end
 if members and frame then
  for _,m in pairs(members)do
   local q=R.followPoint(frame.point,frame.yaw,m.formationSlot,m.formationPitch)
   local occupied={};for _,other in ipairs(values.partyPositions or {})do if other.id~=m.id then
    local owner=members[other.id]
    if other.locked or not owner then occupied[#occupied+1]=other
    else occupied[#occupied+1]=R.followPoint(frame.point,frame.yaw,owner.formationSlot,owner.formationPitch)
     if owner.travelGoal and values.lastGameTime-(owner.travelRequestAt or 0)<3000 then occupied[#occupied+1]=owner.travelGoal end
    end
   end end
   local function navPoint(w)local out={X=0,Y=0,Z=0};if nav:K2_ProjectPointToNavigation(pawn,w,out,nil,nil,{X=150,Y=150,Z=250})then return out end end
   local dest,why=R.travelDestination(q,p,occupied,navPoint,m.formationPitch,frame.yaw,true)
   local progress=m.travelProgress or {}
   rows[#rows+1]=m.name..' seat='..m.formationSlot..' pitch='..m.formationPitch..' destination='..tostring(dest~=nil)..' reason='..tostring(why)..' tries='..tostring(progress.tries)..' separationTries='..tostring(progress.separationTries)..' '..project(q)
  end
 end
 for line in read('companions-state.tsv'):gmatch('[^\r\n]+')do
  local name,full=line:match('^IDENTITY\t[^\t]+\t[^\t]+\t([^\t]+)\t([^\t]+)')
  if full then
   local actor=AI.find(full:match('^%S+ (.+)$')or full)
   if AI.valid(actor)then
    local stub=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(actor)
    local board=AI.board(stub);local c=actor.Controller
    if board and AI.valid(c)then
     rows[#rows+1]=name..' path='..tostring(c:GetMoveStatus())..' suspended='..tostring(board.bMainBehaviorSuspended)
     for _,key in ipairs({'Blackboard','BrainComponent','PathFollowingComponent','RebelRoadsFollowingComponent'})do
      local ok,v=pcall(function()return c[key]end);rows[#rows+1]=key..'='..(ok and AI.valid(v)and v:GetFullName()or 'unavailable')
     end
    end
   end
  end
 end
 return table.concat(rows,'\n')
end
