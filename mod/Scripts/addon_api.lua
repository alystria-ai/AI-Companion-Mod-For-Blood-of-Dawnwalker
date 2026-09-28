-- Versioned registration records from the existing local bridge. No add-on code
-- is evaluated here, and its movement, mount and facial systems remain its own.
local M={};local root=require('runtime_path');local AI=require('ai_state')
local entries={};local lastRead=0;local playerName,worldName;local registryStamp=0
local cameraEntry;local ackKey,ackAt
local uiEntry,uiAt
local uiOwner='creature-companion-mounts'
local function valid(o)return o and o:IsValid()end
local function fields(line)local r={};for v in(line..'\t'):gmatch('(.-)\t')do r[#r+1]=v end;return r end
function M.clearCameraAck()
 if ackKey=='0'then return end
 local f=io.open(root..'/addon-camera-ready.tsv','w')
 if f then f:write('COMPANION-CAMERA\t1\t'..os.time()..'\t0');f:close();ackKey='0';ackAt=nil end
end
function M.reset()entries={};lastRead=0;playerName=nil;worldName=nil;registryStamp=0;cameraEntry=nil;uiEntry=nil;uiAt=nil;M.clearCameraAck()end
function M.uiOpen(pc,force)
 local now=os.time()
 if force or uiAt~=now then
  uiAt=now;uiEntry=nil
  local f=io.open(root..'/addon-ui-'..uiOwner..'.tsv','r')
  local raw=f and f:read(2049)or'';if f then f:close()end
  local r=fields(raw)
  if #raw<=2048 and #r==7 and r[1]=='COMPANION-UI'and r[2]=='1'and r[4]=='1'
   and math.abs(now-(tonumber(r[3])or 0))<=3 and r[5]:match('^[%w_-]+$')then uiEntry={session=r[5],world=r[6],player=r[7],stamp=tonumber(r[3])}end
 end
 local e=uiEntry;if not e or now-e.stamp>3 then return false end
 local pawn,world=AI.playerReady(pc);if not pawn then return false end
 return e.world==world:GetFullName()..'#'..tostring(world:GetAddress())and e.player==pawn:GetFullName()..'#'..tostring(pawn:GetAddress())
end
function M.ackUi(pc,session)
 if not M.uiOpen(pc,true)or uiEntry.session~=session then return false end
 local f=io.open(root..'/addon-ui-ready-'..uiOwner..'.tsv','w');if not f then return false end
 f:write(table.concat({'COMPANION-UI','1',os.time(),'1',session,uiEntry.world,uiEntry.player},'\t'));f:close();return true
end
function M.refresh(pc)
 local now=os.time();if now==lastRead then return end;lastRead=now;local previous=entries;entries={};cameraEntry=nil;registryStamp=0
 local pawn,world=AI.playerReady(pc);if not pawn then return end
 playerName=pawn:GetFullName()..'#'..tostring(pawn:GetAddress());worldName=world:GetFullName()..'#'..tostring(world:GetAddress())
 local f=io.open(root..'/addon-registry.tsv','r');if not f then return end
 local raw=f:read(524289)or '';f:close();if #raw>524288 then return end
 local lines={};for line in raw:gmatch('[^\r\n]+')do lines[#lines+1]=line end
 local h=fields(lines[1]or'')
 if h[1]~='COMPANION-AI'or h[2]~='1'or math.abs(now-(tonumber(h[3])or 0))>3 or lines[#lines]~='END'then return end
 registryStamp=tonumber(h[3]);local cameraCandidates={}
 for i=2,math.min(#lines-1,129)do
  local r=fields(lines[i])
  if (#r==9 or #r==10 or #r==12 or #r==13 or #r==14)and(r[10]==nil or r[10]=='0'or r[10]=='1')and(r[11]==nil or r[11]=='0'or r[11]=='1')and(r[13]==nil or r[13]=='0'or r[13]=='1')and(r[14]==nil or r[14]=='0'or r[14]=='1')and r[5]==worldName and r[6]==playerName then
   local key=r[3]..'#'..r[4]
   local actions={};for action in(r[12]or'Follow,Stop Walking,Look At Player,Leave'):gmatch('[^,]+')do actions[action]=true end
   local entry={name=r[7],definition='',chat=true,addon=r[1],addonActor=r[2],addonInstance=r[4],profileId=r[8],actorName=r[3],world=worldName,player=playerName,cameraLease=r[10]=='1',silentReplies=r[11]=='1',localActionsOnly=r[13]=='1',automaticReactions=r[14]~='0',actions=actions}
   entries[key]=entry
   if entry.cameraLease then
    local old=previous[key];entry.actor=old and old.actor
    if not valid(entry.actor)then
     -- Only mounted registrations are resolved, at most once per refresh. The
     -- cached actor then supplies per-tick identity checks without world scans.
     entry.actor=AI.find(r[3]:match('^%S+ (.+)$')or r[3])
    end
    if valid(entry.actor)and entry.actor:GetFullName()==r[3]and tostring(entry.actor:GetAddress())==r[4]then cameraCandidates[#cameraCandidates+1]=entry end
   end
  end
 end
 table.sort(cameraCandidates,function(a,b)return a.addon..'/'..a.addonActor<b.addon..'/'..b.addonActor end)
 cameraEntry=cameraCandidates[1]
end
function M.cameraOwner(pc)
 M.refresh(pc)
 local entry=cameraEntry;local now=os.time()
 if not entry or now-registryStamp<0 or now-registryStamp>3 then return end
 local pawn,world=AI.playerReady(pc)
 if not pawn or world:GetFullName()..'#'..tostring(world:GetAddress())~=entry.world or pawn:GetFullName()..'#'..tostring(pawn:GetAddress())~=entry.player then return end
 local actor=entry.actor
 if not valid(actor)or actor:IsActorBeingDestroyed()or actor:GetFullName()~=entry.actorName or tostring(actor:GetAddress())~=entry.addonInstance then return end
 local actorWorld=actor:GetWorld()
 if valid(actorWorld)and actorWorld:GetFullName()..'#'..tostring(actorWorld:GetAddress())==entry.world then return entry end
end
function M.ackCamera(entry,pc)
 if not entry or M.cameraOwner(pc)~=entry then M.clearCameraAck();return false end
 local now=os.time();local key=table.concat({entry.addon,entry.addonActor,entry.addonInstance,entry.world,entry.player},'\t')
 if ackKey==key and ackAt==now then return true end
 local f=io.open(root..'/addon-camera-ready.tsv','w');if not f then return false end
 f:write('COMPANION-CAMERA\t1\t'..now..'\t'..key);f:close();ackKey=key;ackAt=now;return true
end
function M.identity(actor)
 if not valid(actor)then return end
 local result=entries[actor:GetFullName()..'#'..tostring(actor:GetAddress())]
 if result then local world=actor:GetWorld();if valid(world)and world:GetFullName()..'#'..tostring(world:GetAddress())==worldName then return result end end
end
function M.action(actor,name,id)
 local entry=M.identity(actor);if not entry then return false,'Add-on registration expired'end
 if not entry.actions[name]then return false,'This creature does not support that order'end
 local f=io.open(root..'/addon-action-'..entry.addon..'.tsv','w')
 if not f then return false,'Add-on action mailbox unavailable'end
 f:write(table.concat({'COMPANION-AI','1',tostring(os.time()),id,entry.addonActor,name,entry.addonInstance},'\t'));f:close()
 return true,'Action delivered to '..entry.name.."'s owning mod"
end
return M
