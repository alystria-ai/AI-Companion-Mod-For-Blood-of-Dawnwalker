-- Protocol 2: a host epoch + SDK session handshake precedes commands and leases.
-- REQUEST key/op/target/sequence/argument uses a monotonic sequence acknowledged
-- in header field 9. Host history is bounded without replaying old commands.
local M={version=2}
local function valid(o)
 return o and o:IsValid()and not o:HasAnyFlags(EObjectFlags.RF_BeginDestroyed|EObjectFlags.RF_FinishDestroyed)
end
local function identity(o)return o:GetFullName()..'#'..tostring(o:GetAddress())end
local function token(s)return type(s)=='string'and #s>0 and #s<=80 and s:match('^[a-zA-Z0-9_-]+$')end
local function split(s)local r={};for v in(s..'\t'):gmatch('(.-)\t')do r[#r+1]=v end;return r end
local function ready(pc)
 if not valid(pc)or pc:IsActorBeingDestroyed()or not valid(pc.Pawn)or pc.Pawn:IsActorBeingDestroyed()then return end
 local p=pc.Pawn;local w=p:GetWorld()
 if not valid(p.Controller)or p.Controller:GetAddress()~=pc:GetAddress()or not valid(p.RootComponent)
  or not valid(w)or not valid(w.PersistentLevel)or not valid(pc:GetWorld())or pc:GetWorld():GetAddress()~=w:GetAddress()then return end
 return p,w
end
local names={['Follow']='follow',['Stop Walking']='stop',['Come Here']='come',['Attack Nearby Enemies']='attack',['Leave']='leave',['Look At Player']='look'}
local phases={queued=true,loading=true,ready=true,unavailable=true,failed=true,dismissing=true,dismissed=true,completed=true}
function M.new(root,owner)
 assert(owner=='creature-companion-mounts','Unsupported creature service owner')
 local nonce=0
 local function newSession()
  nonce=nonce+1
  return ('c'..os.time()..'_'..math.floor(os.clock()*1000000)..'_'..tostring({})..'_'..nonce):gsub('[^a-zA-Z0-9_-]','')
 end
 local session=newSession()
 local self={pending={},leases={},serial=0,wireSerial=0,requests={},members={},actors={},client=session}
 local function invalidate(clearPending)
  -- The host polls once per second and can miss a brief loss of possession.
  -- Retire our session too, so restarting sequence numbers cannot collide with
  -- its previous high-water mark when this is still the same world/player.
  -- Before the first handshake, an initial queued summon retains its session.
  if self.epoch~=nil or clearPending and self.world~=nil then session=newSession();self.client=session end
  if clearPending then self.pending={}end
  self.leases={};self.requests={};self.members={};self.actors={};self.epoch=nil;self.acceptedAt=nil
  self.wireSerial=0;self.lastWrite=nil;self.lastRead=nil
 end
 local function request(op,id,arg)
  assert(token(id),'Invalid creature or member ID');assert(#self.pending<32,'Wait for the creature queue')
  self.serial=self.serial+1;local key=session..'_'..self.serial
  self.pending[#self.pending+1]={key=key,op=op,id=id,arg=arg or''};self.lastWrite=nil;return key
 end
 function self:summon(id)return request('spawn',id)end
 function self:dismiss(id)return request('dismiss',id)end
 function self:action(id,name)return request('action',id,assert(names[name],'Unsupported creature action'))end
 function self:setControlLease(id,on)
  assert(token(id),'Invalid member');if on then self.leases={}end
  self.leases[id]=on==true or nil;self.lastWrite=nil
 end
 local function read(now,world,player)
  local f=io.open(root..'/creature-service-'..owner..'.reply','r');if not f then return end
  local raw=f:read(131073)or'';f:close();if #raw>131072 then return end
  local lines={};for l in raw:gmatch('[^\r\n]+')do lines[#lines+1]=l end
  if #lines>98 then return end
  local h=split(lines[1]or'');local stamp=tonumber(h[3]);local ack=tonumber(h[9])
  if #h~=9 or h[1]~='COMPANION-CREATURES'or h[2]~='2'or h[4]~=owner
   or not stamp or math.abs(now-stamp)>3 or h[5]~=world or h[6]~=player or not token(h[7])
   or not ack or ack<0 or ack%1~=0 or ack>2147483647 or lines[#lines]~='END'then return end
  if self.epoch and(self.epoch~=h[7]or h[8]~=session)then invalidate(true)end
  -- Preserve a user's initial pre-handshake summon. Only a previously accepted
  -- host or a retired player/world may invalidate already-issued work.
  if h[8]~=session then return end
  if not self.epoch then self.epoch=h[7];self.lastWrite=nil end
  local requests,members={},{}
  for i=2,#lines-1 do
   local r=split(lines[i])
   if #r~=8 or not token(r[2])or not phases[r[3]]or(r[4]~=''and not token(r[4]))or(r[7]~='0'and r[7]~='1')then return end
   local item={phase=r[3],memberId=r[4],actorPath=r[5],actorAddress=r[6],controlled=r[7]=='1',error=r[8]~=''and r[8]or nil,epoch=h[7],stamp=stamp}
   if r[1]=='REQUEST'then requests[r[2]]=item elseif r[1]=='MEMBER'then members[r[2]]=item else return end
  end
  self.requests=requests;self.members=members;self.acceptedAt=stamp
  local pending={}
  for _,r in ipairs(self.pending)do
   if not requests[r.key]and(not r.seq or r.seq>ack)then pending[#pending+1]=r
   elseif not requests[r.key]then
    requests[r.key]={phase='failed',error='Request result expired; it will not be repeated',epoch=h[7],stamp=stamp}
   end
  end
  self.pending=pending
  -- Bound cached wrappers to members present in this accepted snapshot.
  for id in pairs(self.actors)do if not members[id]then self.actors[id]=nil end end
 end
 function self:tick(pc)
  local now=os.time();local pawn,w=ready(pc)
  if not pawn then
   invalidate(self.world~=nil);self.pc=nil;self.world=nil;self.player=nil
   return false
  end
  local world,player=identity(w),identity(pawn)
  if self.world and(self.world~=world or self.player~=player)then invalidate(true)end
  self.pc=pc;self.world=world;self.player=player
  if self.lastRead~=now then self.lastRead=now;read(now,world,player);self.lastRead=now end
  if self.lastWrite~=now then
   local rows={table.concat({'COMPANION-CREATURES','2',now,owner,world,player,self.epoch or'',session,'0'},'\t')}
   if self.epoch then
    for _,r in ipairs(self.pending)do
     if not r.seq then self.wireSerial=self.wireSerial+1;r.seq=self.wireSerial end
     rows[#rows+1]=table.concat({'REQUEST',r.key,r.op,r.id,r.seq,r.arg},'\t')
    end
    for id in pairs(self.leases)do rows[#rows+1]='LEASE\t'..id end
   end
   rows[#rows+1]='END';local f=io.open(root..'/creature-service-'..owner..'.tsv','w')
   if f then f:write(table.concat(rows,'\n'));f:close();self.lastWrite=now end
  end
  return true
 end
 local function live(item)
  if not item then return end
  local p,w=ready(self.pc);local now=os.time()
  if not p or identity(p)~=self.player or identity(w)~=self.world or not self.epoch
   or item.epoch~=self.epoch or not item.stamp or math.abs(now-item.stamp)>3 then
   item.actor=nil;item.controlled=false;item.phase='unavailable';return item
  end
  if item.phase=='ready'and item.actorPath~=''then
   local key=item.memberId;local cached=self.actors[key]
   local actor=cached and cached.path==item.actorPath and cached.address==item.actorAddress and cached.actor
   if not valid(actor)then
    -- This UE4SS build scans the object array on StaticFindObject. Resolve only
    -- once per changed identity/snapshot, never once per mounted frame.
    if not cached or cached.path~=item.actorPath or cached.address~=item.actorAddress or cached.at~=item.stamp then
     actor=StaticFindObject(item.actorPath:match('^%S+ (.+)$')or item.actorPath)
     cached={path=item.actorPath,address=item.actorAddress,actor=actor,at=item.stamp};self.actors[key]=cached
    end
   end
   if valid(actor)and not actor:IsActorBeingDestroyed()and tostring(actor:GetAddress())==item.actorAddress
    and valid(actor:GetWorld())and identity(actor:GetWorld())==self.world then item.actor=actor
   else item.actor=nil;item.controlled=false;item.phase='unavailable'end
  end
  return item
 end
 function self:status(id)return live(self.requests[id]or self.members[id])end
 function self:controlReady(id)
  local s=live(self.members[id]);return self.leases[id]==true and s~=nil and s.actor~=nil and s.controlled==true
 end
 function self:close()
  invalidate(true);self.pc=nil;self.world=nil;self.player=nil
  os.remove(root..'/creature-service-'..owner..'.tsv')
 end
 return self
end
return M
