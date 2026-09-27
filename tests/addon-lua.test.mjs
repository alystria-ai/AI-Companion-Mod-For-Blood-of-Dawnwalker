import test from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
function run(source){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const result=lauxlib.luaL_dostring(L,to_luastring(source));assert.equal(result,lua.LUA_OK,result===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
test('add-on actor identity rejects a replacement world even if its UObject names are reused',()=>run(`
 local now=100;os.time=function()return now end
 local registry='COMPANION-AI\\t1\\t100\\ndragon\\tdragon\\tPawn Dragon\\t3\\tWorld#1\\tPawn Coen#2\\tDragon\\tprofile\\tcontext\\nEND'
 io.open=function()return {read=function()return registry end,close=function()end}end
 package.preload.runtime_path=function()return '.'end
 package.preload.ai_state=function()return {playerReady=function(pc)return pc.Pawn,pc.Pawn:GetWorld()end}end
 local M=(function()${readFileSync('mod/Scripts/addon_api.lua','utf8')} end)()
 local world={IsValid=function()return true end,GetFullName=function()return 'World'end,GetAddress=function()return 1 end}
 local function pawn(name,address)return {IsValid=function()return true end,GetFullName=function()return 'Pawn '..name end,GetAddress=function()return address end,GetWorld=function()return world end}end
 local pc={IsValid=function()return true end,Pawn=pawn('Coen',2)};local dragon=pawn('Dragon',3)
 M.refresh(pc);assert(M.identity(dragon).name=='Dragon')
 world.GetAddress=function()return 8 end;assert(M.identity(dragon)==nil,'a stale registry must not bind a replacement world')
 now=101;M.refresh(pc);assert(M.identity(dragon)==nil)
`));
test('new SDK owners do not replay old actions, and replacement actors reject the old instance',()=>run(`
 os.time=function()return 100 end
 local raw='COMPANION-AI\\t1\\t100\\told\\tdragon\\tFollow\\t3'
 io.open=function()return {read=function()return raw end,close=function()end}end
 local SDK=(function()${readFileSync('sdk/CompanionAI.lua','utf8')} end)()
 local function actor(address)return {IsValid=function()return true end,GetAddress=function()return address end}end
 local ai=SDK.new('.','dragon');local profile={name='Dragon',characterId='12345678-1234-1234-1234-123456789abc'}
 ai:register('dragon',actor(3),profile);assert(ai:pollAction()==nil)
 raw='COMPANION-AI\\t1\\t100\\tnew\\tdragon\\tFollow\\t3';assert(ai:pollAction().name=='Follow');assert(ai:pollAction()==nil)
 ai:register('dragon',actor(4),profile)
 raw='COMPANION-AI\\t1\\t100\\tlate\\tdragon\\tLeave\\t3';assert(ai:pollAction()==nil)
 raw='COMPANION-AI\\t1\\t100\\tcurrent\\tdragon\\tFollow\\t4';assert(ai:pollAction().id=='current')
`));
test('SDK facial frames only belong to the registered active target and fresh generation',()=>run(`
 local now=100;os.time=function()return now end
 local target='7\\n1\\nPawn Dragon\\nDragonClass\\nReady\\nsingle\\n0\\nDragon\\n\\n\\n\\nroom\\n\\ndragon\\ndragon\\n3\\n'
 local frame='7\\t100\\nJawOpen\\t0.5\\n'
 io.open=function(path)return {read=function()return path:find('target.txt',1,true)and target or frame end,close=function()end}end
 local SDK=(function()${readFileSync('sdk/CompanionAI.lua','utf8')} end)()
 local ai=SDK.new('.','dragon');ai:register('dragon',{IsValid=function()return true end,GetAddress=function()return 3 end}, {name='Dragon',characterId='12345678-1234-1234-1234-123456789abc'})
 assert(ai:faceFrame('dragon').JawOpen==.5)
 frame='8\\t100\\nJawOpen\\t.8\\n';assert(ai:faceFrame('dragon')==nil)
 frame='7\\t90\\nJawOpen\\t.8\\n';assert(ai:faceFrame('dragon')==nil)
`));
test('mounted SDK waits for a fresh bound acknowledgement and republishes lease changes immediately',()=>run(`
 local now=100;os.time=function()return now end
 local files,writes={},0
 io.open=function(path,mode)
  if mode=='w'then return {write=function(_,value)files[path]=value;writes=writes+1 end,close=function()end}end
  return {read=function()return files[path]or''end,close=function()end}
 end
 local SDK=(function()${readFileSync('sdk/CompanionAI.lua','utf8')} end)()
 local world={IsValid=function()return true end,GetFullName=function()return 'World'end,GetAddress=function()return 1 end}
 local function pawn(name,address)return {IsValid=function()return true end,IsActorBeingDestroyed=function()return false end,GetFullName=function()return 'Pawn '..name end,GetAddress=function()return address end,GetWorld=function()return world end}end
 local pc=pawn('Controller',8);pc.Pawn=pawn('Coen',2)
 local dragon=pawn('Dragon',3);local ai=SDK.new('.','dragon');local profile={name='Dragon',characterId='12345678-1234-1234-1234-123456789abc'}
 ai:register('dragon',dragon,profile);ai:update(pc);assert(writes==1)
 ai:setCameraLease('dragon',true);ai:update(pc);assert(writes==2 and files['./addon-dragon.tsv']:find('\\t1\\t0\\tFollow,Stop Walking,Look At Player,Leave\\t0\\nEND\\tr100-2',1,true))
 local function ack(stamp,w,p,a)return 'COMPANION-CAMERA\\t1\\t'..stamp..'\\tdragon\\tdragon\\t'..(a or 3)..'\\t'..(w or'World#1')..'\\t'..(p or'Pawn Coen#2')end
 files['./addon-camera-ready.tsv']=ack(100);assert(not ai:cameraReady('dragon'),'prior same-second ack must not grant a new request')
 now=101;files['./addon-camera-ready.tsv']=ack(now);assert(ai:cameraReady('dragon'))
 ai:register('dragon',dragon,profile);assert(ai.actors.dragon.cameraLease,'context refresh must preserve an active lease')
 now=105;assert(not ai:cameraReady('dragon'),'stopped core heartbeat must expire')
 now=106;files['./addon-camera-ready.tsv']=ack(now,'World#9');assert(not ai:cameraReady('dragon'))
 now=107;files['./addon-camera-ready.tsv']=ack(now,nil,'Pawn Coen#9');assert(not ai:cameraReady('dragon'))
 now=108;files['./addon-camera-ready.tsv']=ack(now,nil,nil,9);assert(not ai:cameraReady('dragon'))
 now=109;files['./addon-camera-ready.tsv']=ack(now);assert(ai:cameraReady('dragon'))
 pc.Pawn=pawn('Coen',99);assert(not ai:cameraReady('dragon'),'player replacement must reject cached ack immediately')
 pc.Pawn=pawn('Coen',2);ai:setCameraLease('dragon',false);ai:update(pc);assert(not ai:cameraReady('dragon'))
`));
test('core camera ownership expires and rejects actor, world or player replacement',()=>run(`
 local now=100;os.time=function()return now end
 local files,writeCount={},0
 io.open=function(path,mode)
  if mode=='w'then return {write=function(_,value)files[path]=value;writeCount=writeCount+1 end,close=function()end}end
  if not files[path]then return end
  return {read=function()return files[path]end,close=function()end}
 end
 local worldAddress,playerAddress,actorAddress=1,2,3
 local world={IsValid=function()return true end,GetFullName=function()return 'World'end,GetAddress=function()return worldAddress end}
 local player={IsValid=function()return true end,GetFullName=function()return 'Pawn Coen'end,GetAddress=function()return playerAddress end,GetWorld=function()return world end}
 local actor={IsValid=function()return true end,IsActorBeingDestroyed=function()return false end,GetFullName=function()return 'Pawn Dragon'end,GetAddress=function()return actorAddress end,GetWorld=function()return world end}
 local pc={Pawn=player};local finds=0
 package.preload.runtime_path=function()return '.'end
 package.preload.ai_state=function()return {playerReady=function()return player,world end,find=function()finds=finds+1;return actor end}end
 local M=(function()${readFileSync('mod/Scripts/addon_api.lua','utf8')} end)()
 files['./addon-registry.tsv']='COMPANION-AI\\t1\\t100\\ndragon\\tdragon\\tPawn Dragon\\t3\\tWorld#1\\tPawn Coen#2\\tDragon\\tprofile\\tcontext\\t1\\nEND'
 local owner=M.cameraOwner(pc);assert(owner and finds==1);assert(M.ackCamera(owner,pc));assert(writeCount==1)
 for i=1,50 do assert(M.cameraOwner(pc)==owner);assert(M.ackCamera(owner,pc))end
 assert(finds==1 and writeCount==1,'per-frame checks must not scan or write')
 actorAddress=9;assert(not M.cameraOwner(pc));actorAddress=3
 worldAddress=9;assert(not M.cameraOwner(pc));worldAddress=1
 playerAddress=9;assert(not M.cameraOwner(pc));playerAddress=2
 now=104;assert(not M.cameraOwner(pc),'old combined registry must expire')
 M.clearCameraAck();assert(files['./addon-camera-ready.tsv']=='COMPANION-CAMERA\\t1\\t104\\t0')
 local before=writeCount;M.clearCameraAck();assert(writeCount==before)
 M.reset();assert(not M.cameraOwner(pc))
`));
test('first-person handoff restores the body and view before acknowledging even when the setting is Off',()=>run(`
 local files={};io.open=function(path,mode)return {write=function(_,value)files[path]=value end,close=function()end}end
 local function valid(o)return o~=nil and not o.dead end
 local world={};local player={GetWorld=function()return world end};local camera={}
 local current=camera;local events={};local pc={Pawn=player,GetViewTarget=function()return current end,SetViewTargetWithBlend=function(_,target)current=target;events[#events+1]='view'end}
 camera.K2_DestroyActor=function()camera.dead=true;events[#events+1]='destroy'end
 local body={bOwnerNoSee=true,bHiddenInGame=true,bCastHiddenShadow=true,GetOwner=function()return player end}
 function body:SetOwnerNoSee(v)self.bOwnerNoSee=v;events[#events+1]='body'end
 function body:SetHiddenInGame(v)self.bHiddenInGame=v end
 function body:SetCastHiddenShadow(v)self.bCastHiddenShadow=v end
 local mounted={addon='dragon'};local acks=0
 local addons={cameraOwner=function()return mounted end,clearCameraAck=function()events[#events+1]='clear'end,
 ackCamera=function(owner)
  assert(owner==mounted and current==player and not body.bOwnerNoSee and not body.bHiddenInGame and camera.dead,'ACK before cleanup is unsafe')
  acks=acks+1;events[#events+1]='ack'
 end}
 local modules={ai_state={same=function(a,b)return a==b end,valid=valid},companion_settings={values={}},addon_api=addons,runtime_path='.'}
 require=function(name)return modules[name]end
 local M=(function()${readFileSync('mod/Scripts/first_person_camera.lua','utf8')} end)()
 local release
 for i=1,30 do local name,value=debug.getupvalue(M.tick,i);if name=='release'then release=value;break end end
 assert(release)
 for i=1,30 do local name=debug.getupvalue(release,i);if name=='lease'then debug.setupvalue(release,i,{pc=pc,pawn=player,world=world,camera=camera,visibility={body={component=body,ownerNoSee=false,hiddenInGame=false,hiddenShadow=false}}});break end end
 assert(M.tick(pc,false,false)==false and acks==1 and events[#events]=='ack')
 mounted=nil;M.tick(pc,false,false);assert(events[#events]=='clear')
`));
