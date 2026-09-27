-- Narrow creature ownership service. Protocol 2 header, in both directions:
-- COMPANION-CREATURES / 2 / time / owner / world / player / hostEpoch / client / ack.
-- REQUEST rows carry key / operation / target / monotonic sequence / argument.
-- Empty epoch is handshake only. Host reset invalidates old commands/leases;
-- the sequence high-water prevents replay after bounded history expires.
local M={};local AI=require('ai_state');local Party=require('companions')
local Guard=require('mount_failsafe');local root=require('runtime_path')
local Native=require('companion_native')
local posePath='/Game/_Dawnwalker/Animation_MH/Humans/Male_Human/Animation/Community/Male_Human_Community_Background_Sitting_B/Male_Human_Community_Sitting_Reading_Book_Loop_01.Male_Human_Community_Sitting_Reading_Book_Loop_01'
local poseState={};local currentPawn
local poseReferencer
local function retainPose(asset)
 assert(AI.valid(asset)and asset:IsA('/Script/Engine.AnimSequence')and asset:GetFullName():match('^%S+ (.+)$')==posePath,'Unexpected riding animation asset')
 if not AI.valid(poseReferencer)then
  poseReferencer=StaticFindObject('/Engine/Transient.DawnwalkerCreature_RiderAssets')
  if not AI.valid(poseReferencer)then
   local outer=FindObject('Package','/Engine/Transient');assert(AI.valid(outer),'Rider asset package unavailable')
   poseReferencer=StaticConstructObject(AI.find('/Script/Engine.ObjectReferencer'),outer,FName('DawnwalkerCreature_RiderAssets'),EObjectFlags.RF_Transient,EInternalObjectFlags.RootSet)
  end
 end
 assert(AI.valid(poseReferencer)and poseReferencer:IsA('/Script/Engine.ObjectReferencer')and poseReferencer:HasAnyInternalFlags(EInternalObjectFlags.RootSet),'Rider animation retention unavailable')
 -- Exactly one immutable content asset. Never retain an actor, world, player,
 -- controller or native component across a saved-game transition.
 poseReferencer.ReferencedObjects=nil;poseReferencer.ReferencedObjects={asset}
 return asset
end
local owner='creature-companion-mounts';local MAX_MEMBERS,MAX_HISTORY=32,64
local requests,members,guards={},{},{};local sequence={};local revoked={}
local lastRead=0;local worldId,playerId,clientId;local highWater=0;local resetting=false
local generation=0
local function newEpoch()
 generation=generation+1
 return ('h'..os.time()..'_'..math.floor(os.clock()*1000000)..'_'..tostring({})..'_'..generation):gsub('[^a-zA-Z0-9_-]','')
end
local epoch=newEpoch()
local function identity(o)return o:GetFullName()..'#'..tostring(o:GetAddress())end
local function token(s)return type(s)=='string'and #s>0 and #s<=80 and s:match('^[a-zA-Z0-9_-]+$')end
local function clean(s)return tostring(s or''):gsub('[\r\n\t]',' '):sub(1,400)end
local function split(s)local r={};for v in(s..'\t'):gmatch('(.-)\t')do r[#r+1]=v end;return r end
local function liveActor(actor)
 return AI.valid(actor)and not actor:IsActorBeingDestroyed()and AI.valid(actor:GetWorld())and identity(actor:GetWorld())==worldId
end
local function release(id)
 local snapshot=guards[id];if not snapshot then return true end
 snapshot.serviceReleasing=true
 local ok,done,why,outcome=pcall(Guard.restore,snapshot)
 if not ok or not done or outcome=='retry'then
  local m=Party.addonMember(id,owner);if m then m.mountError=clean(ok and why or done)end
  return false,clean(ok and why or done)
 end
 -- A retired world's board must not receive an AI-resume write.
 local m=Party.addonMember(id,owner)
 if m then
  local resumed,result=pcall(Party.addonControl,id,owner,false,outcome=='retired')
  if not resumed or result~=true then m.mountError=clean(result);return false,clean(result)end
 end
 guards[id]=nil;return true
end
local function releaseAll()
 local failed
 for id in pairs(guards)do local ok,why=release(id);if not ok then failed=why or 'Rider restoration pending'end end
 return failed==nil,failed
end
function M.reset()
 if not resetting then epoch=newEpoch();resetting=true;clientId=nil;highWater=0;requests={};sequence={};poseState={};currentPawn=nil end
 Party.addonCancel(owner)
 local ok,why=releaseAll()
 -- Abort party destruction until a current rider has been restored.
 assert(ok,why or 'Rider restoration pending')
 members={};revoked={};worldId=nil;playerId=nil;lastRead=0;resetting=false
end
local function preparePose(now)
 if poseState.ready then
  if AI.valid(poseState.asset)and poseState.asset:GetFullName():match('^%S+ (.+)$')==posePath and AI.valid(poseReferencer)then return end
  poseState={}
 end
 if poseState.error then return end
 local ok,asset=pcall(Native.loadedAsset,posePath)
 if ok and AI.valid(asset)then
  local retained,held=pcall(retainPose,asset)
  if retained then poseState.ready=true;poseState.asset=held
  else poseState.error='The riding animation could not be retained: '..clean(held)end
  return
 end
 if poseState.started then
  if now-poseState.started>=60 then poseState.error='The riding animation did not finish loading'end
  return
 end
 poseState.started=now
 local accepted,result,why=pcall(Native.requestAsset,currentPawn,posePath)
 if not accepted or not result then poseState.error='Riding animation unavailable: '..clean(accepted and why or result)end
end
local function info(id)
 local m=Party.addonMember(id,owner)
 if not m then
  if Party.addonPending(id,owner)then return {phase='queued',memberId=id}end
  return {phase='unavailable',memberId=id,error='Creature no longer present'}
 end
 if m.fault then return {phase='failed',memberId=id,error=m.detail or m.fault}end
 if m.loading or m.created then return {phase='loading',memberId=id,error=m.status}end
 if not liveActor(m.actor)or not AI.board(m.stub,m.board)then return {phase='unavailable',memberId=id,error='Creature is unavailable'}end
 return {phase='ready',memberId=id,actorPath=m.actor:GetFullName(),actorAddress=tostring(m.actor:GetAddress()),
  controlled=guards[id]~=nil and not guards[id].serviceReleasing and Party.addonControlValid(id,owner)==true,
  error=m.board.bIsDead and 'Creature is defeated'or m.mountError or poseState.error or not poseState.ready and 'The riding animation is loading'or nil}
end
local function requestInfo(r)
 if r.terminal then return r.terminal end
 if r.op=='spawn'and r.memberId then
  local s=info(r.memberId)
  if s.phase=='unavailable'or s.phase=='failed'then r.terminal=s end
  return s
 end
 if r.op=='dismiss'and r.memberId then
  local m=Party.addonMember(r.memberId,owner);local s
  if m and m.addonDismissError then s={phase='failed',memberId=r.memberId,error=m.addonDismissError}
  elseif m or Party.addonPending(r.memberId,owner)then return {phase='dismissing',memberId=r.memberId}
  else s={phase='dismissed',memberId=r.memberId}end
  r.actor=nil;r.terminal=s;return s
 end
 return r
end
local function publish(now)
 local rows={table.concat({'COMPANION-CREATURES','2',now,owner,worldId or'',playerId or'',epoch,clientId or'',highWater},'\t')}
 local function row(kind,key,s)
  rows[#rows+1]=table.concat({kind,key,s.phase or'queued',s.memberId or'',s.actorPath or'',s.actorAddress or'',s.controlled and '1'or'0',clean(s.error)},'\t')
 end
 for _,key in ipairs(sequence)do row('REQUEST',key,requestInfo(requests[key]))end
 for id in pairs(members)do row('MEMBER',id,info(id))end
 rows[#rows+1]='END';local f=io.open(root..'/creature-service-'..owner..'.reply','w')
 if f then f:write(table.concat(rows,'\n'));f:close()end
end
local function prune()
 -- Freeze terminal results before forgetting departed or failed members.
 for _,key in ipairs(sequence)do requestInfo(requests[key])end
 for id,record in pairs(members)do
  local s=info(id)
  if (s.phase=='unavailable'or s.phase=='failed')and not guards[id]then
   local m=Party.addonMember(id,owner)
   if not m and not Party.addonPending(id,owner)then members[id]=nil;revoked[id]=nil
   elseif m and not record.cleaning and not m.addonControl then
    local ok=pcall(Party.addonDismiss,id,owner);if ok then record.cleaning=true end
   elseif m and record.cleaning and m.addonDismissError then record.cleaning=nil end
  end
 end
end
local function dismiss(id)
 assert(members[id],'Creature belongs to another owner')
 local m=Party.addonMember(id,owner)
 assert(not guards[id]and(not m or not m.addonControl),'Dismount before dismissing')
 local actor=m and m.actor;Party.addonDismiss(id,owner)
 return {op='dismiss',phase='dismissing',memberId=id,actor=actor}
end
local function execute(r)
 if r[3]=='spawn' then
  local count=0;for _ in pairs(members)do count=count+1 end
  assert(count<MAX_MEMBERS,'This add-on already owns 32 creatures; dismiss one before summoning another')
  preparePose(os.time())
  local id=Party.enqueueCreature(r[4],owner);members[id]={}
  return {op='spawn',phase='queued',memberId=id}
 elseif r[3]=='dismiss'then return dismiss(r[4])
 elseif r[3]=='action'then
  assert(members[r[4]],'Creature belongs to another owner')
  local m=assert(Party.addonMember(r[4],owner),'Creature is unavailable')
  assert(not guards[r[4]]and not m.addonControl,'Dismount before giving this order')
  assert(liveActor(m.actor),'Creature is unavailable')
  local ok,why=Party.addonAction(r[4],owner,r[6]);assert(ok,why or 'Unsupported creature action')
  return {phase='completed',memberId=r[4]}
 end
 error('Unsupported creature request')
end
function M.tick(pc)
 local now=os.time();if now==lastRead then return end;lastRead=now
 local pawn,world=AI.playerReady(pc)
 if not pawn then if worldId or next(guards)or resetting then M.reset()end;return end
 local w,p=identity(world),identity(pawn)
 if resetting or worldId and(worldId~=w or playerId~=p)then M.reset()end
 worldId=w;playerId=p;currentPawn=pawn;lastRead=now
 local f=io.open(root..'/creature-service-'..owner..'.tsv','r')
 local raw=f and f:read(32769)or'';if f then f:close()end
 local lines={};for line in raw:gmatch('[^\r\n]+')do lines[#lines+1]=line end
 local h=split(lines[1]or'')
 local fresh=#raw<=32768 and #lines<=35 and #h==9 and h[1]=='COMPANION-CREATURES'and h[2]=='2'and h[4]==owner
  and math.abs(now-(tonumber(h[3])or 0))<=3 and h[5]==w and h[6]==p and token(h[8])and lines[#lines]=='END'
 local leases={}
 -- Only an empty-epoch handshake can replace a client. Rotating the host epoch
 -- prevents the old process reclaiming control with its previous packet.
 if fresh and h[7]==''and h[8]~=clientId then
  local released=releaseAll()
  if released then
   Party.addonCancel(owner);epoch=newEpoch();clientId=h[8];highWater=0;requests={};sequence={};poseState={};revoked={}
  end
 end
 prune()
 local accepted=fresh and h[7]==epoch and h[8]==clientId
 -- Read the whole heartbeat before any operation. A normal dismount can send
 -- its OFF lease and a replacement/dismiss request in the very same packet.
 -- Restore existing control first so that request does not fail against a
 -- guard which this packet has already released.
 if accepted then
  for i=2,#lines-1 do
   local r=split(lines[i])
   if r[1]=='LEASE'and #r==2 and token(r[2])and members[r[2]]then leases[r[2]]=true end
  end
 end
 -- Once an expired or unsafe lease begins rollback, require an explicit OFF
 -- heartbeat before ON can acquire it again. A late heartbeat cannot revive a
 -- half-restored riding session or incorrectly acknowledge control.
 if accepted then for id in pairs(revoked)do if not leases[id]then revoked[id]=nil end end end
 for id,snapshot in pairs(guards)do
  if snapshot.serviceReleasing or not leases[id]or not Party.addonControlValid(id,owner)then
   if not accepted or leases[id]then revoked[id]=true end
   release(id)
  end
 end
 if accepted then
  for i=2,#lines-1 do
   local r=split(lines[i])
   if r[1]=='REQUEST'and #r==6 and token(r[2])and token(r[4])then
    local seq=tonumber(r[5])
    if seq and seq==highWater+1 and seq<=2147483647 then
     highWater=seq
     if not requests[r[2]]then
      local ok,result=pcall(execute,r)
      if not ok then result={phase='failed',error=clean(result)}end
      requests[r[2]]=result;sequence[#sequence+1]=r[2]
      if #sequence>MAX_HISTORY then requests[table.remove(sequence,1)]=nil end
     end
    end
   end
  end
 end
 if poseState.started and not poseState.error then preparePose(now)end
 local active=next(guards)
 for id in pairs(leases)do
  local m=Party.addonMember(id,owner)
  if m and not guards[id]and not revoked[id]and not active then
   local ok,why=pcall(function()
    assert(liveActor(m.actor)and AI.board(m.stub,m.board)and not m.board.bIsDead,'Creature is unavailable')
    if not poseState.started and not poseState.ready and not poseState.error then preparePose(now)end
    assert(poseState.ready and AI.valid(poseState.asset),poseState.error or 'The riding animation is loading')
    -- The add-on activates only after menu input ownership ends. Capture that
    -- same baseline so the emergency guard can remove exactly its ignore count.
    assert(not pc:IsMoveInputIgnored()and not pc:IsAnyGameInputBlockerActive()
     and not AI.find('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc),'Return to gameplay to mount')
    local snapshot=assert(Guard.capture(pc,m.actor),'Rider state could not be captured')
    guards[id]=snapshot;active=id
    assert(Party.addonControl(id,owner,true),'Creature control not ready')
   end)
   if not ok then
    m.mountError=clean(why)
    if guards[id]then release(id);active=next(guards)end
   end
  end
 end
 publish(now)
end
return M
