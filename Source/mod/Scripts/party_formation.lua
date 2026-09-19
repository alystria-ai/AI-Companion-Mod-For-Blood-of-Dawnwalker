-- Pure whole-party planner. Each instance owns one seat and one destination;
-- there is no second separation driver, path retry planner or moving queue.
local R=require('companion_recovery')
local M={version=291}
local function copy(p)return {X=p.X,Y=p.Y,Z=p.Z}end
local function gap(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2)end
function M.new()
 local self={frame={},seats={},goals={}}
 function self:update(rows,player,yaw,speed,now,registered)
  R.formationFrame(self.frame,player,yaw,speed,now)
  local frame=self.frame;local present={};local locked={};local assigned={}
  table.sort(rows,function(a,b)return a.ordinal<b.ordinal end)
  for _,row in ipairs(rows)do
   present[row.id]=true
   local s=self.seats[row.id]
   if not s then s={epoch=frame.epoch,parked=copy(row.position)};self.seats[row.id]=s end
   if row.locked then locked[#locked+1]=row;s.interrupted=true end
   if frame.moving or s.epoch~=frame.epoch then s.parked=nil;s.epoch=frame.epoch end
   -- Hold the local group while the player approaches one companion. A new
   -- journey releases the parked seat; turning the camera never reshuffles it.
   if not row.locked and not frame.moving and gap(row.position,player)<170 then s.parked=s.parked or copy(row.position)end
   assigned[row.id]=s.parked or R.followPoint(frame.point,frame.yaw,row.slot,row.pitch)
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
   local desired=assigned[row.id];local goal=desired;local mode=self.seats[row.id].parked and 'Parked'or 'Rear arc'
   if not clear(goal,row)then
    goal=nil
    -- A locked actor may occupy a seat. Search only nearby angles on that arc,
    -- with a little outward clearance; never collapse everyone onto Coen.
    local center=frame.point;local radius=gap(desired,center)
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
   goals[row.id]={point=copy(goal),distance=gap(row.position,goal),mode=mode,moving=frame.moving==true,epoch=frame.epoch}
  end end
  self.goals=goals;return goals
 end
 return self
end
return M
