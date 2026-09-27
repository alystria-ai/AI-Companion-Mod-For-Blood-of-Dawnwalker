-- Pure whole-party planner. Each instance owns one seat and one destination;
-- there is no second separation driver, path retry planner or moving queue.
local R=require('companion_recovery')
local M={version=291}
local function copy(p)return {X=p.X,Y=p.Y,Z=p.Z}end
local function gap(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2)end
function M.new()
 local self={frame={},seats={},goals={}}
 function self:update(rows,player,yaw,speed,now,registered,velocity)
  -- A small party should leave promptly when Coen walks away, without
  -- retreating from him when he approaches its nearest stationary member.
  local approaching=false
  if not self.frame.moving and self.frame.point and #rows<=4 then
   local nearest,before=math.huge,0
   for _,row in ipairs(rows)do
    local d=gap(row.position,player)
    if d<nearest then nearest=d;before=gap(row.position,self.frame.point)end
   end
   approaching=nearest<before-25
  end
  R.formationFrame(self.frame,player,yaw,speed,now,#rows,approaching)
  local frame=self.frame;local present={};local locked={};local assigned={}
  local origin=frame.point
  -- Native paths pursue a sampled destination, not a continuously tracked
  -- actor. Lead by the refresh/response time so beside does not become behind.
  -- Use actual velocity, cap the lead, and remove it immediately on stopping.
  if frame.moving and #rows<=4 and speed>=40 and velocity then
   local lead=math.min(.65,180/math.max(1,speed))
   origin={X=origin.X+velocity.X*lead,Y=origin.Y+velocity.Y*lead,Z=origin.Z}
  end
  table.sort(rows,function(a,b)return a.ordinal<b.ordinal end)
  for _,row in ipairs(rows)do
   present[row.id]=true
   local s=self.seats[row.id]
   if not s then s={epoch=frame.epoch,parked=copy(row.position)};self.seats[row.id]=s end
   if row.creature then
    -- Human companions depart after a short step. A beast keeps its own rest
    -- anchor through those shared-frame changes, including in mixed parties.
    if row.locked then s.creatureRest=nil;s.parked=nil
    elseif not s.creatureRest and (s.parked or not frame.moving and row.settledEpoch==frame.epoch)then
     s.creatureRest={player=copy(player),distance=gap(row.position,player),epoch=frame.epoch}
     s.parked=s.parked or copy(row.position)
    end
    local rest=s.creatureRest
    if rest then
     local distance=gap(row.position,player)
     local leaving=gap(rest.player,player)>=250 and distance>=rest.distance+125
     if leaving or distance>=math.max(700,(row.radius or 55)*2+300)then s.creatureRest=nil;s.parked=nil end
    end
   end
   -- Settings change the next journey, not the spot somebody currently owns.
   if not s.pitch or frame.moving then s.pitch=row.pitch;s.distanceScale=row.distanceScale;s.narrow=row.narrow end
   if row.locked then locked[#locked+1]=row;s.interrupted=true end
   if not s.creatureRest and (frame.moving or s.epoch~=frame.epoch)then s.parked=nil;s.epoch=frame.epoch end
   -- Hold the local group while the player approaches one companion. A new
   -- journey releases the parked seat; turning the camera never reshuffles it.
   local approachGap=row.creature and (row.radius or 55)+120 or 170
   if not row.locked and not frame.moving and (gap(row.position,player)<approachGap or row.creature and row.settledEpoch==frame.epoch)then s.parked=s.parked or copy(row.position)end
   -- A companion approached by Coen owns this resting spot. Reserve it before
   -- resolving arriving seats; otherwise somebody else's planned destination
   -- can send this stationary speaker back onto the arc and release attention.
   if not row.locked and s.parked then
    locked[#locked+1]={id=row.id,position=s.parked,radius=row.radius}
   end
   assigned[row.id]=s.parked or R.followPoint(origin,frame.yaw,row.slot,s.pitch,row.count,s.distanceScale,s.narrow)
  end
  -- Streaming can remove the pawn without dismissing its companion instance.
  -- Preserve that journey/seat so reattachment is not mistaken for a new spawn.
  for id in pairs(self.seats)do if not present[id]and not(registered and registered[id])then self.seats[id]=nil end end
  local goals={};local committed={}
  local function clear(p,row)
   for _,other in ipairs(locked)do if other.id~=row.id and math.abs(p.Z-other.position.Z)<200
    and gap(p,other.position)<(row.radius or 55)+(other.radius or 55)+45 then return false end end
   for _,other in ipairs(rows)do if other.id~=row.id and not other.locked then
    local q=committed[other.id]or assigned[other.id]
    if math.abs(p.Z-q.Z)<200 and gap(p,q)<(row.radius or 55)+(other.radius or 55)+35 then return false end
   end end
   return true
  end
  for _,row in ipairs(rows)do if not row.locked then
   local desired=assigned[row.id];local goal=desired;local mode=self.seats[row.id].parked and 'Parked'or self.seats[row.id].narrow and 'Narrow rows'or #rows<=4 and 'Walking group'or 'Rear arc'
   if not self.seats[row.id].parked and not clear(goal,row)then
    goal=nil
    -- A locked actor may occupy a seat. Search only nearby angles on that arc,
    -- with a little outward clearance; never collapse everyone onto Coen.
    local center=origin;local radius=gap(desired,center)
    local angle=math.atan(desired.Y-center.Y,desired.X-center.X)
    for _,degrees in ipairs({-12,12,-24,24,-36,36})do
     local a=angle+math.rad(degrees)
     local q={X=center.X+math.cos(a)*radius,Y=center.Y+math.sin(a)*radius,Z=desired.Z}
     local heading=math.rad(frame.yaw)
     if (q.X-center.X)*math.cos(heading)+(q.Y-center.Y)*math.sin(heading)<-45 and clear(q,row)then goal=q;mode='Yielding arc';break end
    end
    if not goal then goal=copy(row.position);mode='Waiting for seat'end
   end
   committed[row.id]=goal
   local rest=self.seats[row.id].creatureRest
   goals[row.id]={point=copy(goal),distance=gap(row.position,goal),mode=mode,moving=not rest and frame.moving==true,epoch=rest and rest.epoch or frame.epoch,smallParty=#rows<=4,
    arrival=row.creature and math.min(100,math.max(65,(row.radius or 55)*.5))or nil,
    settledTolerance=row.creature and math.max(175,(row.radius or 55))or nil}
  end end
  self.goals=goals;return goals
 end
 return self
end
return M
