-- Session-local challenge. No campaign actors, shared definitions or save facts are changed.
local AI=require('ai_state')
local Native=require('horde_native')
local Catalog=require('horde_catalog')
local Settings=require('companion_settings')
local root=require('runtime_path')
local M={};local run;local serial=0;local last={active=false,phase='idle',level=0,levels=10,alive=0,total=0,message='Start in an open area. Companions can fight alongside you.'}
local lastPublished='';local lastStamp=0;local lastDiagnostic
local function lib()return AI.find('/Script/Engine.Default__GameplayStatics')end
local function clock(pc)return AI.find('/Script/Engine.Default__KismetSystemLibrary'):GetGameTimeInSeconds(pc)end
local function distance(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)end
local function playerState(pc)
 if not AI.valid(pc)or not AI.valid(pc.Pawn)then return end
 local stub=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(pc.Pawn)
 local board=AI.board(stub);return stub,board
end
local function publish()
 local v=M.view()
 local diagnostic=v.phase..' · level '..v.level..' / '..v.levels..' · '..v.alive..' alive\n'..(v.message or '')
 if diagnostic~=lastDiagnostic then
  lastDiagnostic=diagnostic;local f=io.open(root..'/horde-status.txt','w');if f then f:write(diagnostic..'\n');f:close()end
 end
 local remaining=v.phase=='rest'and v.restSeconds or 0
 local phase=run and run.suspended and 'suspended'or v.phase
 local value=(v.active and '1'or '0')..'\t'..phase..'\t'..v.level..'\t'..v.levels..'\t'..remaining
 if value==lastPublished and os.time()==lastStamp then return end
 lastPublished=value;lastStamp=os.time()
 local f=io.open(root..'/horde-state.tsv','w');if f then f:write('HORDE\t1\t'..lastStamp..'\t'..value..'\n');f:close()end
end
function M.view()
 if not run then return last end
 return {active=true,id=run.id,released=run.released==true,phase=run.phase,level=run.level,levels=run.levels,alive=run.alive or 0,total=#(run.queue or {}),
  restSeconds=run.phase=='rest'and math.max(0,math.ceil(run.restUntil-(run.now or run.restUntil)))or 0,message=run.message}
end
function M.levels()return Catalog.preview()end
local function finish(message,phase,discardBodies)
 local s=run;run=nil
 local ok,why=Native.cleanup(not discardBodies)
 last={active=false,phase=phase or 'ended',level=s and s.level or 0,levels=s and s.levels or 10,alive=0,total=0,message=message}
 if not ok then last.message=message..' Some enemy cleanup is pending: '..tostring(why)end
 publish()
end
function M.stop(reason,discardBodies)finish(reason or 'Horde ended.','ended',discardBodies)end
function M.start(pc)
 if run then return false,'A horde is already running.'end
 Settings.poll()
 local _,board=playerState(pc)
 if not board or board.bIsDead then return false,'Load a save with a living player first.'end
 if board.Combat.bInCombat then return false,'Finish your current fight before starting a horde.'end
 local ok,why=Native.cleanup(true);if not ok then return false,'Previous horde cleanup is pending: '..tostring(why)end
 serial=serial+1
 run={pc=pc,pawn=pc.Pawn,world=pc.Pawn:GetWorld(),id=os.time()..'-'..serial,phase='preparing',level=0,
  levels=math.floor(Settings.values.HordeLevels),start=math.floor(Settings.values.HordeStartEnemies),growth=math.floor(Settings.values.HordeEnemyGrowth),
  bosses=math.floor(Settings.values.HordeBosses),timeout=math.floor(Settings.values.HordeTimeout),handles={},now=clock(pc),message='Unpause to prepare the first horde.'}
 publish();return true,'Horde queued. Unpause in an open area to begin.'
end
local function beginWave(s)
 s.level=s.level+1;s.queue,s.name=Catalog.wave(s.level,s.start+(s.level-1)*s.growth,s.bosses)
 s.handles={};s.next=1;s.alive=0;s.kills=0;s.engaged=false;s.quietSince=nil;s.loadingSince=s.now;s.pending=nil;s.released=false;s.readyAt=nil;s.lastActivationNote=nil
 s.anchor=s.pawn:K2_GetActorLocation();s.yaw=s.pc:GetControlRotation().Yaw;s.phase='loading';s.message='Preparing '..s.name..'.'
end
local function spawnPoint(s,index)
 local nav=AI.find('/Script/NavigationSystem.Default__NavigationSystemV1')
 if not AI.valid(nav)then return end
 local a=math.rad(s.yaw);local row=math.floor((index-1)/6);local col=(index-1)%6-2.5
 for attempt=0,3 do
  local front=1800+row*420+attempt*260;local side=col*360
  local desired={X=s.anchor.X+math.cos(a)*front-math.sin(a)*side,Y=s.anchor.Y+math.sin(a)*front+math.cos(a)*side,Z=s.anchor.Z}
  local out={X=0,Y=0,Z=0}
  if nav:K2_ProjectPointToNavigation(s.pawn,desired,out,nil,nil,{X=160,Y=160,Z=700})and distance(out,desired)<750 and distance(out,s.anchor)>900 then
   local clear=true;for _,entry in ipairs(s.handles)do if distance(out,entry.point)<260 then clear=false;break end end
   if clear then return {X=out.X,Y=out.Y,Z=out.Z}end
  end
 end
end
local function update(s,suspended)
 if not AI.valid(s.pc)or not AI.same(s.pc.Pawn,s.pawn)or not AI.same(s.pawn:GetWorld(),s.world)then finish('Horde ended because the player or world changed.');return end
 local playerStub,board=playerState(s.pc)
 if not board then finish('Horde ended because player AI became unavailable.');return end
 if board.bIsDead then finish('Defeated. Start a new horde when you are ready.');return end
 if lib():IsGamePaused(s.pc)then s.message='Paused. Unpause to continue the horde.';publish();return end
 local previousTime=s.now;s.now=clock(s.pc)
 if suspended or s.suspended then
  if s.restUntil then s.restUntil=s.restUntil+math.max(0,s.now-previousTime)end
  s.suspended=suspended;s.previous=nil
  if suspended then s.message='Horde paused during the cinematic.';publish();return end
 end
 if s.lastTick and s.now-s.lastTick<.25 then return end;s.lastTick=s.now
 if s.phase=='preparing'then beginWave(s)end
 local point=s.pawn:K2_GetActorLocation()
 if s.previous and distance(point,s.previous)>12000 then finish('Horde ended after travel.');return end;s.previous=point
 if s.phase=='rest'then
  if playerStub:IsInCombat()or board.Combat.bInCombat then s.restUntil=s.now+s.timeout;s.message='Finish the current fight before the next horde.'
  elseif s.now>=s.restUntil then beginWave(s)
  else s.message='Next level in '..math.ceil(s.restUntil-s.now)..' seconds.'end
  publish();return
 end
 if distance(point,s.anchor)>14000 then finish('Horde ended: you left the encounter area.');return end
 -- One queued population is advanced at a time. Completed enemies remain under native AI.
 if not s.pending and s.next<=#s.queue then
  local destination=spawnPoint(s,s.next)
  if not destination then finish('No clear walkable space ahead. Try a more open area.','error');return end
  local handle=Native.create(s.pc,s.queue[s.next],destination,s.id..'-'..s.level..'-'..s.next)
  local entry={handle=handle,point=destination};s.handles[#s.handles+1]=entry;s.pending=entry;s.next=s.next+1
 end
 if s.pending then
  local entry=s.pending;local phase,actor,stub,detail=Native.poll(entry.handle)
  if phase=='failed'then finish('Enemy preparation failed: '..tostring(detail),'error');return end
  if phase=='spawned'then
   entry.ready=true;entry.stub=stub;s.pending=nil
   -- Keep different horde species from attacking each other. Only these owned
   -- instances receive pairwise attitudes; companions and campaign NPCs are untouched.
   for _,other in ipairs(s.handles)do if other~=entry and other.ready and not other.dead and AI.board(other.stub)and AI.board(stub)then
    stub:SetAttitudeTowards(other.stub,1,false);other.stub:SetAttitudeTowards(stub,1,false)
   end end
  end
 end
 local loading=s.pending~=nil or s.next<=#s.queue
 if not loading and not s.released then
  s.readyAt=s.readyAt or s.now
  -- Let post-load equipment/animation initialization settle before releasing AI.
  if s.now-s.readyAt>=1 then
   for _,entry in ipairs(s.handles)do
    local ok,why=Native.activate(entry.handle)
    if not ok then finish('Wave activation failed: '..tostring(why),'error');return end
   end
   s.released=true
  end
 end
 local alive,combat,nearest,targetingPlayer,missing=0,false,math.huge,false,0
 for _,entry in ipairs(s.handles)do if entry.ready and not entry.dead then
  local phase,actor,stub,info=Native.status(entry.handle)
  if phase=='dead'then entry.dead=true;s.kills=s.kills+1;Native.retainCorpse(entry.handle)
  elseif phase=='unloaded'then
   entry.missingAt=entry.missingAt or s.now
   -- Losing the AI attachment is not a death or a retreat. Keep the other
   -- enemies alive and allow the native actor to reattach.
   alive=alive+1;missing=missing+1
  elseif phase=='spawned'then
   entry.missingAt=nil;alive=alive+1;nearest=math.min(nearest,distance(point,actor:K2_GetActorLocation()))
   combat=combat or info.combat;targetingPlayer=targetingPlayer or info.engagedPlayer
   if s.released and (not info.combat or not AI.valid(info.target))and s.now>=(entry.retryAt or 0)then
    local accepted,why=Native.engage(entry.handle,s.pc);entry.retryAt=s.now+2
    s.lastActivationNote=tostring(why or accepted)
   end
  else finish('An owned enemy was interrupted; horde ended.');return end
 end end
 s.alive=alive
 local playerCombat=playerStub:IsInCombat()or board.Combat.bInCombat
 if combat and (playerCombat or targetingPlayer)then s.engaged=true end
 if s.released and not loading and alive==0 and s.kills==#s.queue then
  if s.level>=s.levels then finish('All '..s.levels..' horde levels cleared!','complete');return end
  s.phase='rest';s.restUntil=s.now+s.timeout;s.message='Level cleared. Rest before the next horde.';publish();return
 end
 if missing==0 and s.engaged and not playerCombat and not targetingPlayer and (not combat or nearest>3000)then
  s.quietSince=s.quietSince or s.now
  if s.now-s.quietSince>=5 then finish('Horde ended after leaving combat.');return end
 else s.quietSince=nil end
 s.phase=(loading or not s.released)and 'loading'or s.engaged and 'combat'or 'armed'
 s.message=not s.released and ('Preparing '..s.name..' · '..alive..' / '..#s.queue..' loaded. Combat starts when everyone is ready.')or ('Level '..s.level..': '..s.name..' · '..alive..' enemies remaining'..(not s.engaged and s.lastActivationNote and '\n'..s.lastActivationNote or ''))
 if missing>0 then s.message=s.message..'\nWaiting for '..missing..' enemy AI attachment(s). End horde remains available.'end
 publish()
end
local lastCleanup=0
function M.tick(suspended)
 if not run then
  if os.time()-lastCleanup>=5 then lastCleanup=os.time();pcall(Native.cleanup,true)end
  publish();return
 end
 local ok,err=pcall(update,run,suspended)
 if not ok then pcall(finish,'Horde stopped: '..tostring(err),'error')end
end
return M
