-- Combat owns locomotion between entry and exit. A forced-target lease may be
-- renewed without replaying the native combat-start phase / battle cry.
local M={}
-- Bounded, session-local observations. Keep names/IDs only, never stale UObject
-- references. The conversation bridge reads this independently of combat AI.
local battles={records={},witnesses={},serial=0,stamp=0}
M.battles=battles
local function field(value)return tostring(value or ''):gsub('[\r\n\t,;|]',' '):sub(1,180)end
function battles.reset()
 battles.records={};battles.current=nil;battles.horde=nil;battles.afterHorde=nil;battles.witnesses={};battles.witnessRequested=nil;battles.stamp=0;battles.sampleAt=nil
end
local function record(kind,key,title,level)
 for _,r in ipairs(battles.records)do if r.key==key then return r end end
 local r={key=key,kind=kind,title=title,level=level or 0,state='fighting',enemies={},witnesses={},updated=os.time(),kills=0}
 battles.records[#battles.records+1]=r
 while #battles.records>3 do table.remove(battles.records,1)end
 return r
end
local function witness(r)
 for id in pairs(battles.witnesses)do r.witnesses[id]=true end
end
function battles.observe(active,opponents,now)
 if battles.horde then return end
 if battles.afterHorde then if active then return end;battles.afterHorde=nil end
 local r=battles.current
 if active then
  if not r then
   battles.serial=battles.serial+1;r=record('battle','battle-'..battles.serial,'Recent battle');battles.current=r;witness(r)
   for key,name in pairs(opponents or {})do if (r.count or 0)<64 then
    r.count=(r.count or 0)+1;r.enemies[key]=field(name)
   end end
  end
  r.quietAt=nil
 elseif r then
  r.quietAt=r.quietAt or now
  if now-r.quietAt>=5000 then r.state='combat-ended';r.updated=os.time();battles.current=nil end
 end
end
function battles.wave(s,state)
 if not s.engaged and state~='cleared'and state~='complete'then return end
 if state=='fighting'and not s.released then return end
 local r=record('horde',s.id..'-'..s.level,s.name,s.level)
 if state=='ended'and r.state=='cleared'then return end
 local now=os.time()
 if r.sampleSecond==now and r.state==state and r.kills==(s.kills or 0)then return end
 r.sampleSecond=now
 r.state=state;r.kills=s.kills or 0;r.updated=os.time()
 if not r.captured then
  r.captured=true;witness(r)
  for i,e in ipairs(s.handles)do
   if e.ready and not e.omitted then r.enemies[tostring(i)]=field(e.name or 'Unidentified opponent')end
  end
 end
end
function battles.publish(root)
 local now=os.time();if battles.stamp==now then return end;battles.stamp=now
 local rows={'BATTLES\t1\t'..now}
 for _,r in ipairs(battles.records)do if r.state~='fighting'and now-r.updated<=1800 then
  local names,counts,people={},{},{}
  for _,name in pairs(r.enemies)do counts[name]=(counts[name]or 0)+1 end
  for name,count in pairs(counts)do names[#names+1]=name..' x'..count end;table.sort(names)
  for id in pairs(r.witnesses)do people[#people+1]=field(id)end;table.sort(people)
  rows[#rows+1]=table.concat({field(r.key),r.kind,r.state,r.level,field(r.title),table.concat(names,'; '),table.concat(people,','),r.kills,r.updated},'\t')
 end end
 local f=io.open(root..'/battle-context.tsv','w');if f then f:write(table.concat(rows,'\n')..'\n');f:close()end
end
-- Choose an initial opponent only. Native combat owns later retargeting.
-- Spread available companions over nearby threats instead of queueing every
-- helper behind the attack tickets on whatever Coen happens to be aiming at.
function M.initialTarget(candidates)
 local best,score,key=nil,math.huge,''
 for _,c in ipairs(candidates)do
  local s=c.distance+(c.assigned or 0)*650-(c.attackingPlayer and 250 or 0)-(c.aimed and 100 or 0)
  if s<score or s==score and c.key<key then best,score,key=c.target,s,c.key end
 end
 return best
end
-- Travel pace has separate enter/exit distances so it doesn't oscillate at
-- one threshold. Engine units are centimetres. Use planar player velocity.
function M.followPace(gap,playerSpeed,wasRunning,spacing,wasSprinting)
 local stop=spacing or 180
 -- Native follow restarts only after a meaningful departure. Pace can still
 -- rise promptly on an existing path when Coen begins running.
 local start=stop+250
 local excess=math.max(0,gap-stop)
 local enter=stop+500
 -- Small formation corrections should be walked, even after a sprint.
 -- Separate velocity and distance hysteresis keeps a walking player from
 -- repeatedly triggering the old run/sprint thresholds at every short gap.
 local running=excess>=500 or playerSpeed>=260
  or wasRunning and (excess>250 or playerSpeed>=220)
 local sprinting=running and (excess>=1200 or playerSpeed>=550
  or wasSprinting and (excess>700 or playerSpeed>=480))
 local targetSpeed
 if sprinting then
  targetSpeed=math.min(4000,math.max(590,playerSpeed*1.05)+math.min(900,math.max(0,excess-700)*.35))
 elseif running then
  targetSpeed=playerSpeed>=220 and math.min(550,math.max(280,playerSpeed+math.min(60,excess*.1)))or 360
 else
  targetSpeed=playerSpeed>=40 and math.min(260,math.max(140,playerSpeed+math.min(70,excess*.25)))or 140
 end
 return {stop=stop,start=start,running=running,sprinting=sprinting,enum=sprinting and 2 or running and 1 or 0,runAt=enter,targetSpeed=targetSpeed}
end
function M.new(ops)
 local self={phase='travel',attempts=0,nextStart=0,lastLease=-math.huge}
 function self:leave(o)
  if self.phase~='leaving'and not self.accepted and not self.owned and not o.nativeCombat then
   self.phase='travel';ops.travel(o.follow);return true
  end
  -- Rejected preparation is not a fight. Release its hints without starting
  -- a combat exit that would replay Idle/Follow transitions.
  if self.phase=='preparing'and not self.accepted and not o.nativeCombat then
   if o.busy==true then return false end
   ops.clear();self.owned=false;self.phase='travel';self.key=nil
   ops.travel(o.follow);return true
  end
  -- A request to stop is not acknowledgement that combat has stopped. Keep
  -- combat ownership until native exit; arm the follower at its Idle entry.
  if self.phase~='leaving' then
   self.phase='leaving';self.nextStop=0
   self.needsStop=self.accepted or o.nativeCombat or self.owned
  end
  if ops.inhibit then ops.inhibit(self.nextStop==0)end
  if self.needsStop and o.now>=self.nextStop then
   if ops.stop(o.follow)==false then return false end
   self.needsStop=false;self.nextStop=o.now+3000
  end
  if o.nativeCombat or o.busy==true then
   self.needsStop=true
   return false
  end
  if self.owned then ops.clear();self.owned=false end
  self.phase='travel';self.key=nil;self.accepted=false;self.needsStop=false
  ops.travel(o.follow)
  return true
 end
  function self:tick(o)
   if self.phase=='leaving' or not o.allowed then
    return self:leave(o)and 'travel'or 'leaving'
   end
   -- The adapter supplies whole-encounter evidence separately from a selected
   -- enemy. A stale enemy board can retain its combat flag after every party
   -- member has exited, so target presence alone must not restart the intro.
   -- Native combat and unbreakable actions still own their full exit.
   if o.encounterActive==false and not o.nativeCombat then
    if self.phase=='travel'then self.encounterLostAt=nil;ops.travel(o.follow);return 'travel'end
    if self.phase=='preparing'and not self.accepted then
     return self:leave(o)and 'travel'or 'leaving'
    end
    self.encounterLostAt=self.encounterLostAt or o.now
    if o.busy==true or o.now-self.encounterLostAt<(ops.exitSettleMs or 750)then
     if ops.maintain then ops.maintain()end
     return self.phase=='preparing'and 'preparing'or 'combat'
    end
    return self:leave(o)and 'travel'or 'leaving'
   end
   self.encounterLostAt=nil
   if not o.key then
   self.lostAt=self.lostAt or o.now
   if self.phase=='preparing'and not o.nativeCombat and o.now-self.lostAt<1500 then
    if ops.maintain then ops.maintain()end
    return 'preparing'
   end
   if o.nativeCombat or self.phase=='combat'and (o.busy==true or o.now-self.lostAt<5000)then
    if o.nativeCombat and not self.owned then
     if ops.enter(true)==false then return 'waiting'end
     self.owned=true
    end
    -- Native entry can complete during a perception gap after preparation
    -- already took ownership. Record acknowledgement in that case too.
    if o.nativeCombat then self.accepted=true;self.phase='combat';self.lastNativeCombat=o.now end
    if ops.maintain then ops.maintain()end
    return 'combat'
   end
   if not self:leave(o)then return 'leaving'end
   -- A brief perception gap or different enemy is still the same encounter.
   if o.now-self.lostAt>=10000 then self.attempts=0 end
   return 'travel'
  end
  self.lostAt=nil
  if o.nativeCombat then self.lastNativeCombat=o.now end
  -- An accepted start is not proof that the native combat phase began. Only
  -- recover after a sustained idle rejection, never during a long montage.
  if self.accepted and o.nativeCombat==false and o.busy==false and o.now-(self.lastNativeCombat or self.startedAt or o.now)>=15000 then
   if not self:leave(o)then return 'leaving'end
   self.nextStart=math.max(self.nextStart,o.now+1000)
   return 'cooldown'
  end
  if self.accepted or o.nativeCombat then
   if not self.owned then
    if ops.enter(o.nativeCombat)==false then return 'waiting'end
    self.owned=true
   end
   self.phase='combat';self.accepted=true
   if ops.maintain then ops.maintain()end
   if self.key~=o.key or o.now-self.lastLease>=3000 then
    if ops.target()~=false then self.key=o.key;self.lastLease=o.now end
   end
   return 'combat'
  end
  if self.phase~='preparing' then
   if self.attempts>=3 or o.now<self.nextStart then
    ops.travel(o.follow)
    return self.attempts>=3 and 'declined'or 'cooldown'
   end
   if ops.enter(false)==false then self.nextStart=o.now+750;return 'waiting'end
   self.owned=true;self.phase='preparing';self.prepareAt=o.now
   self.equipmentReady=false;self.settleAt=nil;self.nextStart=o.now
  end
  -- Retain locomotion ownership, weapon selection and hostility between ticks.
  -- Native target eligibility is cached; immediate undo can prevent entry.
  if ops.maintain then ops.maintain()end
  if self.key~=o.key or o.now-self.lastLease>=3000 then
   self.targetReady=ops.target()~=false
   if self.targetReady then self.key=o.key;self.lastLease=o.now end
  end
  if o.busy==true then return 'preparing'end
  if not self.equipmentReady then
   self.equipmentReady=not ops.prepare or ops.prepare()~=false
   if self.equipmentReady then self.settleAt=o.now+(ops.settleMs or 0)end
  end
  local expired=o.now-self.prepareAt>=(ops.prepareTimeoutMs or 12000)
  if not expired and self.attempts<3 then
   if not self.equipmentReady or self.targetReady==false or self.key~=o.key or o.now<(self.settleAt or math.huge)or o.now<self.nextStart then return 'preparing'end
   self.attempts=self.attempts+1;self.nextStart=o.now+(ops.retryMs or 3000)
   self.accepted=ops.start()==true
   if self.accepted then self.startedAt=o.now;self.lastNativeCombat=nil;self.phase='combat';return 'combat'end
   -- Observe one more native tick after even the final rejection: the board
   -- combat flag may precede the stub flag or become active asynchronously.
   return 'preparing'
  end
  ops.clear();self.owned=false;self.phase='travel';self.key=nil
  self.nextStart=o.now+10000;ops.travel(o.follow)
  return self.attempts>=3 and 'declined'or 'cooldown'

 end
 return self
end
return M
