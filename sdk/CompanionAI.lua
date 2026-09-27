-- Load this SDK with dofile from DawnwalkerConvai/Payload/sdk/CompanionAI.lua.
-- Call update(playerController) on the game thread about once each second.
local SDK={version=1}
local allowedActions={['Follow']=true,['Stop Walking']=true,['Look At Player']=true,['Leave']=true,['Come Here']=true,['Attack Nearby Enemies']=true}
local defaultActions={'Follow','Stop Walking','Look At Player','Leave'}
local function clean(s,n)return tostring(s or ''):gsub('[\r\n\t]',' '):sub(1,n)end
local function token(s)return type(s)=='string'and #s<=48 and s:match('^[a-z][a-z0-9_-]*$')end
local function valid(o)
 if not o or not o:IsValid()then return false end
 if EObjectFlags and o:HasAnyFlags(EObjectFlags.RF_BeginDestroyed|EObjectFlags.RF_FinishDestroyed)then return false end
 return true
end
local function rows(raw)local r={};for s in(raw or''):gmatch('[^\r\n]+')do r[#r+1]=s end;return r end
local function read(path,limit)local f=io.open(path,'r');if not f then return ''end;local s=f:read(limit)or'';f:close();return s end
function SDK.new(runtime,addon)
 assert(token(addon)and addon~='registry'and not addon:match('^action%-')and not addon:match('^ui%-')and not addon:match('^camera%-'),'Use a lowercase add-on ID, at most 48 characters; registry and action-/ui-/camera- prefixes are reserved')
 assert(type(runtime)=='string'and runtime~='','The shared Payload/runtime path is required')
 local self={runtime=runtime,addon=addon,actors={},revision=0,lastAction='',status='Not registered'}
 local path=runtime..'/addon-'..addon..'.tsv'
 local actionPath=runtime..'/addon-action-'..addon..'.tsv'
 self.lastActionRaw=read(actionPath,1024)
 function self:register(id,actor,profile)
  assert(token(id),'Use a lowercase actor registration ID')
  assert(valid(actor),'Register a live pawn')
  assert(type(profile)=='table'and type(profile.characterId)=='string'and profile.characterId:match('^[%x%-]+$')and #profile.characterId==36,'A Convai character UUID is required')
  local old=self.actors[id]
  if not old or not valid(old.actor)or old.actor:GetAddress()~=actor:GetAddress()then self.lastActionRaw=read(actionPath,1024)end
  local same=old and valid(old.actor)and old.actor:GetAddress()==actor:GetAddress()
  local actions,seen={},{};assert(profile.actions==nil or type(profile.actions)=='table','Actions must be a list')
  for _,name in ipairs(profile.actions or defaultActions)do assert(allowedActions[name]and not seen[name],'Unsupported or duplicate action');seen[name]=true;actions[#actions+1]=name end
  self.actors[id]={actor=actor,name=clean(profile.name or id,100),profile=profile.characterId,context=clean(profile.context,2400),silentReplies=profile.silentReplies==true or profile.localActionsOnly==true,localActionsOnly=profile.localActionsOnly==true,actions=actions,cameraLease=same and old.cameraLease or false,cameraRequestedAt=same and old.cameraRequestedAt or nil}
  self.lastUpdate=nil
 end
 function self:unregister(id)self.actors[id]=nil;self.lastUpdate=nil end
 function self:setCameraLease(id,on)
  local entry=assert(self.actors[id],'Register the actor before requesting its camera lease')
  assert(type(on)=='boolean','Camera lease must be true or false')
  if entry.cameraLease==on then return end
  entry.cameraLease=on;entry.cameraRequestedAt=on and os.time()or nil
  self.lastUpdate=nil;self.cameraReadAt=nil;self.cameraRaw=nil
 end
 function self:update(pc)
  local now=os.time();if self.lastUpdate==now then return end;self.lastUpdate=now
  self.revision=self.revision+1;local rev='r'..now..'-'..self.revision
  local out={table.concat({'COMPANION-AI','1',addon,tostring(now),rev},'\t')};local count=0
  if valid(pc)and not pc:IsActorBeingDestroyed()and valid(pc.Pawn)and not pc.Pawn:IsActorBeingDestroyed()and valid(pc.Pawn:GetWorld())then
   local w=pc.Pawn:GetWorld();local world=w:GetFullName()..'#'..tostring(w:GetAddress());local player=pc.Pawn:GetFullName()..'#'..tostring(pc.Pawn:GetAddress())
   self.cameraController=pc;self.cameraWorld=world;self.cameraPlayer=player
   for id,e in pairs(self.actors)do
    local ok=pcall(function()
     if not valid(e.actor)or e.actor:IsActorBeingDestroyed()or not valid(e.actor:GetWorld())or e.actor:GetWorld():GetFullName()..'#'..tostring(e.actor:GetWorld():GetAddress())~=world then self.actors[id]=nil;return end
     if count<32 then out[#out+1]=table.concat({id,clean(e.actor:GetFullName(),512),tostring(e.actor:GetAddress()),clean(world,512),clean(player,512),e.name,e.profile,e.context,e.cameraLease and '1'or '0',e.silentReplies and '1'or '0',table.concat(e.actions,','),e.localActionsOnly and '1'or '0'},'\t');count=count+1 end
    end)
    if not ok then self.actors[id]=nil end
   end
  else self.actors={};self.cameraController=nil;self.cameraWorld=nil;self.cameraPlayer=nil end
  out[#out+1]='END\t'..rev
  local f,err=io.open(path,'w');if not f then self.status='Shared runtime unavailable: '..tostring(err);return false end
  f:write(table.concat(out,'\n'));f:close();self.status='Registered '..count..' actor(s)';return true
 end
 function self:cameraReady(id)
  local entry=self.actors[id];local pc=self.cameraController;local now=os.time()
  if not entry or not entry.cameraLease or not entry.cameraRequestedAt then return false end
  local ok,ready=pcall(function()
   if not valid(pc)or pc:IsActorBeingDestroyed()or not valid(pc.Pawn)or pc.Pawn:IsActorBeingDestroyed()or not valid(entry.actor)or entry.actor:IsActorBeingDestroyed()then return false end
   local world=pc.Pawn:GetWorld();local actorWorld=entry.actor:GetWorld()
   if not valid(world)or not valid(actorWorld)then return false end
   local worldId=world:GetFullName()..'#'..tostring(world:GetAddress());local playerId=pc.Pawn:GetFullName()..'#'..tostring(pc.Pawn:GetAddress())
   if worldId~=self.cameraWorld or playerId~=self.cameraPlayer or actorWorld:GetFullName()..'#'..tostring(actorWorld:GetAddress())~=worldId then return false end
   if self.cameraReadAt~=now then self.cameraReadAt=now;self.cameraRaw=read(runtime..'/addon-camera-ready.tsv',2048)end
   local stamp,owner,actorId,instance,boundWorld,boundPlayer=(self.cameraRaw or ''):match('^COMPANION%-CAMERA\t1\t(%d+)\t([a-z][a-z0-9_-]*)\t([a-z][a-z0-9_-]*)\t([^\r\n\t]+)\t([^\r\n\t]+)\t([^\r\n\t]+)$')
   stamp=tonumber(stamp)
   return stamp~=nil and stamp>entry.cameraRequestedAt and now-stamp>=0 and now-stamp<=3 and owner==addon and actorId==id and instance==tostring(entry.actor:GetAddress())and boundWorld==worldId and boundPlayer==playerId
  end)
  return ok and ready==true
 end
 function self:available()
  local stamp=tonumber(read(runtime..'/background-heartbeat.txt',64))or 0
  return math.abs(os.time()-stamp)<5
 end
 function self:cameraPreferences()
  -- Read the same saved settings as F4 and the main Settings page. Cache this
  -- small file; mounted camera updates must not do disk I/O every frame.
  local now=os.clock()
  if not self.cameraSettingsAt or now>=self.cameraSettingsAt then
   self.cameraSettingsAt=now+.25
   local source=read(runtime..'/../../config.ini',16384)
   local function value(key,default,lo,hi)
    local n=tonumber(source:match(key..'%s*=%s*([%d.+-]+)'))or default
    return math.max(lo,math.min(hi,n))
   end
   self.cameraSettings={firstPerson=value('FirstPersonCamera',0,0,1)==1,fov=value('FirstPersonFOV',90,60,120),height=value('FirstPersonHeight',0,-20,20),forward=value('FirstPersonForward',42,20,70)}
  end
  return self.cameraSettings
 end
 function self:pollAction()
  local raw=read(actionPath,1024);if raw==self.lastActionRaw then return end
  local stamp,id,actor,action,instance=raw:match('^COMPANION%-AI\t1\t(%d+)\t([%w_-]+)\t([%w_-]+)\t([^\r\n\t]+)\t([%w]+)$')
  if not stamp or math.abs(os.time()-tonumber(stamp))>4 or id==self.lastAction or not self.actors[actor]or not valid(self.actors[actor].actor)or tostring(self.actors[actor].actor:GetAddress())~=instance then return end
  local permitted=false;for _,name in ipairs(self.actors[actor].actions)do if name==action then permitted=true;break end end;if not permitted then return end
  self.lastAction=id;self.lastActionRaw=raw;return {id=id,actorId=actor,actor=self.actors[actor].actor,name=action}
 end
 function self:faceFrame(id)
  local target={};for line in(read(runtime..'/target.txt',8192)..'\n'):gmatch('(.-)\n')do target[#target+1]=line:gsub('\r$','')end;local entry=self.actors[id]
  if not entry or entry.silentReplies or target[2]~='1'or target[14]~=addon or target[15]~=id or not valid(entry.actor)or target[16]~=tostring(entry.actor:GetAddress())then return end
  local frame=rows(read(runtime..'/frame.txt',32768));local generation,stamp=(frame[1]or''):match('^(%d+)\t(%d+)$')
  if generation~=target[1]or math.abs(os.time()-(tonumber(stamp)or 0))>2 then return end
  local weights={};for i=2,#frame do local key,value=frame[i]:match('^([%w_]+)\t([%d.]+)$');value=tonumber(value);if key and value and value<=1 then weights[key]=value end end
  return weights
 end
 function self:close()self.actors={};self.cameraController=nil;self.cameraWorld=nil;self.cameraPlayer=nil;self.cameraRaw=nil;os.remove(path);self.status='Closed'end
 return self
end
return SDK
