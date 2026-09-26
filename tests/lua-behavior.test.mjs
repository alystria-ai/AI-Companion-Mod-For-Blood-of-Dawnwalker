import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
async function run(module,body){
 const source=await readFile(module==='engagement'&&process.env.DAWNWALKER_ENGAGEMENT||`mod/Scripts/${module}.lua`,'utf8');
 const ai=await readFile('mod/Scripts/ai_state.lua','utf8');
 const state=lauxlib.luaL_newstate();lualib.luaL_openlibs(state);
 const result=lauxlib.luaL_dostring(state,to_luastring(`package.preload.ai_state=function() ${ai} end\nlocal M=(function()\n${source}\nend)()\n${body}`));
 const error=result===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(state,-1));lua.lua_close(state);
 assert.equal(result,lua.LUA_OK,error);
}
test('live reload preserves working code on errors and cancels old queued callbacks',()=>run('live_reload',`
 local queue,events,reports={},{},{}
 record=function(s)table.insert(events,s)end
 local router=M.new(_G,function()error('unexpected external require')end,function(fn)table.insert(queue,fn)end,function(s)table.insert(reports,s)end)
 local function app(label)return "RegisterKeyBind('F6',function()ExecuteInGameThread(function()record('"..label.." key')end)end);RegisterModCleanup(function()record('"..label.." cleanup')end);LoopAsync(33,function()record('"..label.." tick');return true end)"end
 assert(router:reload({app=app('old')}))
 router:key('F6') -- Leave old work queued while switching versions.
 assert(router:reload({app=app('new')}));queue[1]();queue={}
 assert(#events==1 and events[1]=='old cleanup','old queued callbacks must not run')
 router:tick(33);router:tick(33);assert(events[2]=='new tick' and #events==2,'only current timer runs')
 assert(not router:reload({app=app('bad'),config='this is broken Lua'}))
 assert(not router:reload({app="error('init failed')"}))
 router:key('F6');queue[1]();queue={};assert(events[3]=='new key','previous working version must survive errors')
 router:poll({app=app('next')},'next');assert(#queue==0,'wait for a stable save')
 router:poll({app=app('next')},'next');assert(#queue==1);queue[1]();queue={}
 assert(events[4]=='new cleanup')
 router:poll({app=app('next')},'next');assert(#queue==0,'unchanged code must not reload')
`));
test('face inspector only reads metadata, never arbitrary runtime values',()=>run('face_inspector',`
 local function property(n)return {GetFName=function()return {ToString=function()return n end}end,GetFullName=function()return 'ObjectProperty Face:'..n end}end
 local base={IsValid=function()return true end,GetFullName=function()return 'Base' end,GetSuperStruct=function()return nil end,ForEachProperty=function(_,cb)cb(property('LaterInput'))end,ForEachFunction=function()end}
 local cls={IsValid=function()return true end,GetFullName=function()return 'Face' end,GetSuperStruct=function()return base end,ForEachProperty=function(_,cb)cb(property('EmptyReference'))end,ForEachFunction=function()end}
 local object={IsValid=function()return true end,GetFullName=function()return 'FaceInstance' end,GetClass=function()return cls end,LaterInput=0.75,EmptyReference={GetFullName=function()return nil end,ToString=function()return nil end}}
 object.EmptyReference=nil;object.LaterInput=nil
 setmetatable(object,{__index=function(_,key)error('Runtime value read: '..key)end})
 local report={};M.object(object,report,'Face')
 local text=table.concat(report,'\\n')
 assert(text:find('EmptyReference',1,true),'null reference must be recorded')
 assert(text:find('LaterInput',1,true),'base class must still be inspected')
 assert(not text:find('Runtime value read',1,true),'runtime getters must not be used')
 assert(not text:find('Reflection unavailable',1,true),'null is not a traversal error')
`));
test('JALI probe records soft-reference types without fetching runtime values',()=>run('jali_probe',`
 local lines={};local function valid()return true end
 local prop={GetFullName=function()return 'SoftObjectProperty JALI:Animation' end}
 local parameter={GetFullName=function()return 'FloatProperty JALI:Test:Weight' end}
 local fn={GetFullName=function()return 'Function JALI:Test' end,ForEachProperty=function(_,cb)cb(parameter)end}
 local cls={IsValid=valid,GetFullName=function()return 'Class /Script/JALI.JaliAnimPlayer' end,GetSuperStruct=function()return nil end,ForEachProperty=function(_,cb)cb(prop)end,ForEachFunction=function(_,cb)cb(fn)end}
 local component=setmetatable({IsValid=valid,GetFullName=function()return 'JaliAnimationComponent Anca.Jali' end,GetClass=function()return cls end},{__index=function(_,key)error('Forbidden runtime value '..key)end})
 local actor={IsValid=valid,GetFullName=function()return 'Anca' end,K2_GetComponentsByClass=function()return {component}end}
 StaticFindObject=function()return cls end
 FindAllOf=function()error('Global scan forbidden')end
 M.run(actor,function(s)table.insert(lines,s)end)
 local text=table.concat(lines,'\\n')
 assert(text:find('SoftObjectProperty JALI:Animation',1,true))
 assert(text:find('FloatProperty JALI:Test:Weight',1,true))
 assert(text:find('COMPONENT JaliAnimationComponent Anca.Jali',1,true))
 assert(text:find('COMPLETE:',1,true))
`));
test('JALI preview seeks silently, restores state, and yields to game dialogue',()=>run('jali_preview',`
 local function valid()return true end
 local animation={IsValid=valid,GetFullName=function()return 'CurveTable speech' end,IsA=function()return true end}
 local audio={IsValid=valid,VolumeMultiplier=0.7,IsPlaying=function()return false end}
 function audio:SetVolumeMultiplier(v)self.VolumeMultiplier=v end
 local p={IsValid=valid,CurrentAnimation=animation,AudioComponent=audio,time=8,hold=false,playing=false}
 function p:Play(t)assert(audio.VolumeMultiplier==0,'mute before playback');self.time=t;self.playing=true end
 function p:Pause()self.playing=false end
 function p:GetTime()return self.time end
 function p:SetTime(t)self.time=t end
 function p:GetShouldHoldPose()return self.hold end
 function p:SetShouldHoldPose(h)self.hold=h end
 function p:IsPlaying()return self.playing end
 setmetatable(p,{__index=function(_,k)if k=='CurrentAnimation' then return nil end;error('Unapproved player access: '..k)end})
 local component={IsValid=valid,GetAnimPlayer=function()return p end}
 local actor={IsValid=valid,K2_GetComponentsByClass=function()return {component}end}
 StaticFindObject=function()return {IsValid=valid}end
 local logs={};local function log(s)table.insert(logs,s)end
 local state=M.begin(actor,100,log);assert(state and p.hold and p.time==0 and p.playing)
 assert(not M.tick(state,101));assert(p.time==0.05)
 assert(M.tick(state,106));assert(p.time==8 and not p.hold and not p.playing and audio.VolumeMultiplier==0.7)
 M.finish(state,'repeat');assert(p.time==8)
 state=M.begin(actor,200,log);p.playing=true;p.time=2;p.CurrentAnimation={IsValid=valid,GetFullName=function()return 'New speech' end,IsA=function()return true end}
 assert(M.tick(state,201));assert(p.time==2 and not p.hold,'do not rewind game dialogue')
 assert(M.begin(actor,202,log)==nil,'refuse active dialogue')
 p.playing=false;p.CurrentAnimation=nil
 assert(M.begin(actor,203,log)==nil,'no asset must not trigger a speculative fallback')
`));
test('face graph resolves only owned linked instances and samples without rescanning',()=>run('face_graph',`
 local function valid()return true end
 local function cls(name)return {IsValid=valid,GetFullName=function()return name end,ForEachProperty=function()end}end
 local mainClass=cls('Face Main');local linkedClass=cls('Face Lipsync');local bodyClass=cls('Body Main')
 local linked={IsValid=valid,GetFullName=function()return 'OwnedFace.Lipsync' end,GetClass=function()return linkedClass end}
 local main={IsValid=valid,GetFullName=function()return 'OwnedFace.Main' end,GetClass=function()return mainClass end}
 local calls=0
 function main:GetLinkedAnimLayerInstanceByClass(c,children)assert(children==true);calls=calls+1;return linked end
 function main:GetLinkedAnimLayerInstancesByGroup(group,out)assert(group=='None');out[1]=linked end
 local reads=0
 function main:GetAllCurveNames(out)reads=reads+1;if reads>1 then out[1]={ToString=function()return 'jawOpen' end}end end
 function main:GetCurveValue(n)assert(n=='jawOpen');return 0.5 end
 setmetatable(main,{__index=function(_,k)error('runtime property read '..k)end})
 local face={IsValid=valid,GetFName=function()return {ToString=function()return 'Face Mesh' end}end,GetFullName=function()return 'Face Mesh' end,GetAnimInstance=function()return main end}
 local actor={K2_GetComponentsByClass=function()return {face}end}
 local scans=0
 StaticFindObject=function()return {IsValid=valid}end
 require('ai_state').find=StaticFindObject
 FindAllOf=function()scans=scans+1;error('Global scan prohibited')end
 FName=function(s)return s end
 local lines={};local state=M.capture(actor,function(s)table.insert(lines,s)end)
 M.sample(state);M.sample(state)
 assert(scans==0 and calls==3,'only direct owned-layer lookups permitted')
 assert(reads==2,'refresh curve names during playback, including newly appearing curves')
 assert(table.concat(lines,'\\n'):find('ATTACHED OwnedFace.Lipsync',1,true))
 assert(table.concat(lines,'\\n'):find('jawOpen=0.5',1,true))
`));
test('speech layer links temporarily and restores the captured expression layer',()=>run('face_graph',`
 local function valid()return true end
 local desired={IsValid=valid};local previous={IsValid=valid,GetFullName=function()return 'FemaleExpression' end}
 local old={IsValid=valid,GetFullName=function()return 'Expression instance' end,GetClass=function()return previous end}
 local new={IsValid=valid,JawOpenAlpha=0.12,GetFullName=function()return 'JALI instance' end}
 local main={IsValid=valid,GetFullName=function()return 'Main' end,active=previous}
 function main:GetLinkedAnimLayerInstanceByClass(cls)if self.active==cls then return cls==desired and new or old end end
 function main:GetLinkedAnimLayerInstancesByGroup(group,out)assert(group=='None');out[1]=main;out[2]=old end
 function main:LinkAnimClassLayers(cls)self.active=cls end
 function main:UnlinkAnimClassLayers(cls)assert(self.active==cls);self.active=nil end
 StaticFindObject=function()return desired end
 require('ai_state').find=StaticFindObject
 FName=function(s)return s end
 FindObjects=function()error('Global animation scan prohibited')end
 local state=M.linkSpeechLayer({main=main},function()end)
 assert(main.active==desired and state.previous[1]==previous)
 local preview=M.beginJaw(state,{IsValid=valid},100)
 assert(not M.tickJaw(preview,101)and new.JawOpenAlpha==0.8)
 for i=1,19 do M.tickJaw(preview,101)end
 assert(new.JawOpenAlpha==0,'pulse must close too')
 assert(M.tickJaw(preview,106),'timeout must end test')
 M.restoreLayer(state);M.restoreLayer(state);assert(main.active==previous and new.JawOpenAlpha==0.12)
 main.active=desired;state=M.linkSpeechLayer({main=main},function()end)
 preview=M.beginJaw(state,{IsValid=valid},200);M.tickJaw(preview,201)
 M.restoreLayer(state);assert(main.active==desired and new.JawOpenAlpha==0.12,'restore existing layer control without unlinking')
`));
test('direct numeric lip inputs neutralize and restore without name or map traversal',()=>run('face_graph',`
 local values={};for i=1,129 do values[i]=0 end;values[27]=0.2
 local closure={0.1,0.2,0.3,0.4}
 local instance={IsValid=function()return true end,JawOpenAlpha=0.1,
   AnimGraphNode_ModifyCurve_3={CurveValues=values},AnimGraphNode_ModifyCurve_8={CurveValues=closure}}
 setmetatable(instance,{__index=function(_,k)error('Forbidden property read: '..k)end})
 local state={instance=instance,originalJaw=0.1,log=function()end}
 M.applyWeights(state,{CTRL_expressions_jawOpen=0.6,CTRL_expressions_mouthFunnelUL=0.7,CTRL_expressions_mouthLipsTogetherDL=0.4})
 assert(instance.JawOpenAlpha==0.6 and values[27]==0.7 and closure[1]==0.4)
 M.applyWeights(state,{})
 assert(instance.JawOpenAlpha==0 and values[27]==0 and closure[1]==0,'missing frame must neutralize')
 M.restoreLayer(state)
 assert(instance.JawOpenAlpha==0.1 and values[27]==0.2 and closure[1]==0.1 and closure[4]==0.4,'restore exact prior state')
 assert(#values==129 and #closure==4,'never resize arrays')
`));
test('proximity selection accepts body-height offsets; excludes behind and outside range',()=>run('targeting',`
 local p={X=0,Y=0,Z=0};local forward={X=1,Y=0,Z=-0.8}
 local front=M.score(p,forward,{X=200,Y=10,Z=90},450,80)
 assert(front~=nil,'body-height offset must not break targeting')
 assert(M.score(p,forward,{X=-100,Y=0,Z=0},450,80)==nil,'behind player')
 assert(M.score(p,forward,{X=500,Y=0,Z=0},450,80)==nil,'outside range')
 assert(front<M.score(p,forward,{X=200,Y=160,Z=90},450,80),'prefer facing direction')
`));
test('walking away releases only an out-of-range non-follower behind the view',()=>run('targeting',`
 local p={X=0,Y=0,Z=0};local f={X=1,Y=0,Z=0}
 assert(not M.walkedAway(p,f,{X=-200,Y=0,Z=0},450,false),'looking away nearby is not leaving')
 assert(not M.walkedAway(p,f,{X=600,Y=0,Z=0},450,false),'still looking at distant NPC')
 assert(M.walkedAway(p,f,{X=-600,Y=0,Z=0},450,false),'walked away and looking away')
 assert(not M.walkedAway(p,f,{X=-600,Y=0,Z=0},450,true),'followers are exempt')
`));
test('native hold and companion transitions preserve idle and restore owned state',()=>run('engagement',`
 EObjectFlags={RF_BeginDestroyed=0x8000,RF_FinishDestroyed=0x10000}
 local function noFlags()return false end
 local function valid()return true end
 local movement={MovementMode=1,CustomMovementMode=0,bOrientRotationToMovement=true,bUseControllerDesiredRotation=true,IsValid=valid}
 function movement:StopMovementImmediately()self.stopped=true end
 function movement:GetOverrideInputSize()return self.input or -1 end
 function movement:SetOverrideInputSize(value)self.input=math.max(0,math.min(1,value))end
 function movement:ResetOverrideInputSize()self.input=-1;self.resets=(self.resets or 0)+1 end
 function movement:DisableMovement()self.MovementMode=0 end
 function movement:SetMovementMode(mode,custom)self.MovementMode=mode end
 local controller={IsValid=valid,StopMovement=function()end,MoveToActor=function()error('Generic navigation must not compete with RebelAI')end}
 local actor={IsValid=valid,bUseControllerRotationYaw=true,GetController=function()return controller end,GetMovementComponent=function()return movement end,K2_GetActorLocation=function()return {X=0,Y=0,Z=0}end,K2_GetActorRotation=function()return {Pitch=0,Yaw=0,Roll=0}end,K2_SetActorRotation=function(self,r)self.rotation=r end}
 local board={IsValid=valid,Combat={bInCombat=false},HasAnyUnbreakableActiveAction=function(self)return self.busy==true end,bMainBehaviorSuspended=false,bIsDead=false,bCanFight=false,Follower={bFollowerModeEnabled=false,bIsTemporaryFollower=false,bIsPlayerInFollowArea=false,bReturnToAP=true},Leader={bLeaderModeEnabled=false},StopAllActions=function(self)self.stops=(self.stops or 0)+1 end,StopPlayingMontagesByActions=function(self)self.stoppedMontages=true end}
 local stub={IsValid=valid,AIBoard=board,cinematic=false,combat=false,hostile=false,IsInCinematicMode=function(self)return self.cinematic end,IsInCombat=function(self)return self.combat end,IsHostileTowardsPlayer=function(self)return self.hostile end}
 local enemyBoard={bIsDead=false}
 local enemy={IsValid=valid,AIBoard=enemyBoard,IsPlayer=function()return false end,IsInCinematicMode=function()return false end,IsHostileTowardsPlayer=function()return true end,GetActor=function()return actor end}
 local playerBoard={GetTarget=function()return enemy end}
 local playerStub={IsValid=valid,AIBoard=playerBoard,IsInCombat=function()return true end}
 local player={IsValid=valid,K2_GetActorLocation=actor.K2_GetActorLocation}
 for i,o in ipairs({movement,controller,actor,board,stub,enemyBoard,enemy,playerBoard,playerStub,player})do
  o.IsValid=valid;o.HasAnyFlags=noFlags;o.GetFullName=function()return 'object'..i end
 end
 stub.IsInitializedAndHasPawn=valid;enemy.IsInitializedAndHasPawn=valid;playerStub.IsInitializedAndHasPawn=valid
 local combats=0
 board.GetForcedTarget=function(self)return self.forced end
 board.SetForcedTarget=function(self,target,duration)assert(target==enemy and duration==2);self.assist=target end
 StaticFindObject=function(path)
   if path:find('CombatBlueprint',1,true)then return {GetFullName=function()return 'Object '..path end,IsValid=valid,HasAnyFlags=noFlags,StartCombatBehaviors=function()combats=combats+1;return true end}end
   if path:find('BoardBlueprint',1,true)then return {GetFullName=function()return 'Object '..path end,IsValid=valid,HasAnyFlags=noFlags,GetIsInFollowerMode=function(_,s)return s.AIBoard.Follower.bFollowerModeEnabled end}end
   return {GetFullName=function()return 'Object '..path end,IsValid=valid,HasAnyFlags=noFlags,GetAIStub=function(_,a)return a==player and playerStub or stub end}
 end
 local logs={};local function log(s)logs[#logs+1]=s end
 local held=M.begin(actor,log)
 assert(not held.blocked and board.bMainBehaviorSuspended and board.stops==1 and board.stoppedMontages)
 assert(movement.MovementMode==1 and movement:GetOverrideInputSize()==0 and not movement.bOrientRotationToMovement and not actor.bUseControllerRotationYaw)
 M.face(held,{X=0,Y=200,Z=0});assert(actor.rotation==nil,'No capsule rotation fallback without a native attention target')
 local followed,message=M.follow(held,player);assert(followed and message:find('combat disabled',1,true))
 assert(movement.MovementMode==1 and movement:GetOverrideInputSize()==-1 and actor.bUseControllerRotationYaw and not board.bMainBehaviorSuspended)
 assert(board.Follower.bFollowerModeEnabled and board.Follower.bIsTemporaryFollower and not board.Follower.bReturnToAP)
 local stops=board.stops;assert(M.follow(held,player));assert(board.stops==stops,'repeat Follow is idempotent')
 M.face(held,{X=0,Y=-200,Z=0});assert(actor.rotation==nil,'follower must own its rotation')
 assert(M.followTick(held,player)and combats==0,'noncombat NPC must not be forced into combat')
 board.bCanFight=true;assert(M.followTick(held,player)and combats==1 and board.assist==enemy)
 M.followTick(held,player);assert(combats==1,'combat requests are throttled')
 held.lastAssist=nil;enemyBoard.bIsDead=true;M.followTick(held,player);assert(combats==1,'no dead targets')
 enemyBoard.bIsDead=false;enemy.IsHostileTowardsPlayer=function()return false end;M.followTick(held,player);assert(combats==1,'no neutral targets')
 enemy.IsHostileTowardsPlayer=function()return true end;board.forced=enemy;M.followTick(held,player);assert(combats==1,'preserve game forced targets')
 board.forced=nil
 M.finish(held);local stopped=board.stops;M.finish(held)
 assert(board.stops==stopped and not board.Follower.bFollowerModeEnabled and board.Follower.bReturnToAP and not board.Follower.bIsPlayerInFollowArea)
 assert(not board.Follower.bIsTemporaryFollower and movement.bOrientRotationToMovement and movement.bUseControllerDesiredRotation)
 assert(movement.resets==1,'Following release must use the native reset, not the clamping setter')
 movement:SetOverrideInputSize(0.6);held=M.begin(actor,log);M.finish(held)
 assert(movement:GetOverrideInputSize()==0.6 and movement.resets==1,'Restore an existing positive override without resetting it')
 movement:ResetOverrideInputSize();held=M.begin(actor,log);movement:SetOverrideInputSize(0.8);M.finish(held)
 assert(movement:GetOverrideInputSize()==0.8,'Do not overwrite a new native action value')
 movement:ResetOverrideInputSize()
 board.Combat.bInCombat=true;local before=board.stops;held=M.begin(actor,log);assert(held.blocked and board.stops==before and movement.MovementMode==1);board.Combat.bInCombat=false
 board.busy=true;held=M.begin(actor,log);assert(held.blocked and board.stops==before);board.busy=false
 stub.cinematic=true;held=M.begin(actor,log);assert(held.blocked and not board.bMainBehaviorSuspended and movement.MovementMode==1)
 stub.cinematic=false;board.bMainBehaviorSuspended=true;held=M.begin(actor,log);assert(held.blocked);M.finish(held);assert(board.bMainBehaviorSuspended,'must preserve external holds')
 board.bMainBehaviorSuspended=false;held=M.begin(actor,log);assert(M.follow(held,player));board.Follower.bFollowerModeEnabled=false
 assert(not M.followTick(held,player),'game override ends follow rather than fighting it');M.finish(held)
 -- Already-settled speakers keep their animation rather than cancelling an empty action queue.
 board.ActiveActions={};actor.GetVelocity=function()return {X=0,Y=0,Z=0}end
 controller.GetMoveStatus=function()return 0 end
 local stoppedBefore=board.stops;movement.stopped=false;board.stoppedMontages=false
 held=M.begin(actor,log);assert(not held.blocked and held.alreadyIdle and M.canReuseHold(held))
 assert(board.stops==stoppedBefore and not board.stoppedMontages and not movement.stopped,'Idle conversation cancelled animation')
 board.busy=true;assert(not M.canReuseHold(held),'Busy native action cannot reuse a hold');board.busy=false
 M.finish(held);assert(not M.canReuseHold(held),'Released hold cannot be reused')
 actor.GetVelocity=function()return {X=100,Y=0,Z=0}end
 -- A native error after the first write must restore the earlier mutation.
 board.StopAllActions=function()error('unavailable')end
 held=M.begin(actor,log);assert(held.blocked and not board.bMainBehaviorSuspended and movement.MovementMode==1)
 -- A still-valid stub whose board detached must not call native diagnostics.
 stub.AIBoard=nil;stub.IsMoving=function()error('Native function touched after teardown')end
 local report=M.inspect(actor);assert(report:find('detached or uninitialized',1,true))
 held=M.begin(actor,log);assert(held.blocked and movement.MovementMode==1)
`));
for(const mode of ['legacy','probe','stream'])test('actual mod integration: '+mode,async()=>{
 const probeMode=mode==='probe',streamMode=mode==='stream';
 const sources={};for(const name of ['ai_state','targeting','engagement','config','face_inspector','jali_probe','jali_preview','face_graph','app'])sources[name]=await readFile(name==='app'&&process.env.DAWNWALKER_APP||name==='engagement'&&process.env.DAWNWALKER_ENGAGEMENT||`mod/Scripts/${name}.lua`,'utf8');
 sources.config=sources.config.replace('FacialProbeOnly = false',`FacialProbeOnly = ${probeMode}`).replace('UseFaceLayer = true',`UseFaceLayer = ${streamMode}`).replace('AutoStartConvai = true','AutoStartConvai = false');
 const state=lauxlib.luaL_newstate();lualib.luaL_openlibs(state);
 const script=`
 local files,keys={},{};local now=100;local tick
 local unload
 RegisterModCleanup=function(fn)unload=fn end
 os.time=function()return now end
 local logs={};print=function(s)logs[#logs+1]=s end
 io.open=function(path,mode)
   if mode=='r' and not files[path] then return nil end
   if mode=='w' then files[path]='' end
   return {write=function(_,text)files[path]=(files[path] or '')..text end,read=function(_,count)if type(count)=='number' and files[path]=='' then return nil end;return files[path] end,close=function()end}
 end
 FName=function(s)return s end
 Key={F5='F5',F6='F6',F7='F7',F8='F8'}
 RegisterKeyBind=function(key,callback)keys[key]=callback end
 ExecuteInGameThread=function(fn)fn()end
 LoopAsync=function(ms,fn)tick=function()for i=1,math.ceil(33/ms)do fn()end end end
 local function valid()return true end
 local world={IsValid=valid,GetFullName=function()return 'World' end}
 local class={IsValid=valid,GetFullName=function()return 'NPCClass' end,ForEachProperty=function()end,ForEachFunction=function()end,GetSuperStruct=function()return nil end}
 local function name(s)return {ToString=function()return s end}end
 local morph={IsValid=valid,GetFName=function()return name('jawOpen')end}
 local mesh={IsValid=valid,weight=0.12};local metadataOnly=true
 function mesh:GetFullName()return 'Face mesh' end
 function mesh:GetFName()return name('Face Mesh')end
 function mesh:GetClass()return class end
 function mesh:GetSkeletalMeshAsset()assert(not metadataOnly,'F8 must never read mesh assets');return {IsValid=valid,GetFullName=function()return 'Face asset' end,MorphTargets={morph}} end
 local faceAnim={IsValid=valid,JawOpenAlpha=0.15,GetFullName=function()return 'FaceInstance' end,GetClass=function()return class end,GetAddress=function()return 2 end}
 local expressionClass={IsValid=valid,GetFullName=function()return 'FemaleExpression' end}
 local expression={IsValid=valid,GetFullName=function()return 'ExpressionInstance' end,GetClass=function()return expressionClass end}
 function faceAnim:GetLinkedAnimLayerInstanceByClass(c)if self.linked then return c==class and self or nil end;return c==expressionClass and expression or nil end
 function faceAnim:GetLinkedAnimLayerInstancesByGroup(_,out)out[1]=expression end
 function faceAnim:GetAllCurveNames()end
 function faceAnim:LinkAnimClassLayers(c)self.linked=c==class end
 function faceAnim:UnlinkAnimClassLayers()self.linked=false end
 function mesh:GetAnimInstance()return faceAnim end
 function mesh:GetNumBones()return 0 end
 function mesh:GetMorphTarget()return self.weight end
 function mesh:SetMorphTarget(name,value)assert(name=='jawOpen');self.weight=value end
 local audio={IsValid=valid,VolumeMultiplier=0.8,IsPlaying=function()return false end}
 function audio:SetVolumeMultiplier(v)self.VolumeMultiplier=v end
 local jali={IsValid=valid,AudioComponent=audio,time=2,hold=false,playing=false,CurrentAnimation={IsValid=valid,IsA=function()return true end,GetFullName=function()return 'CurveTable retained' end}}
 function jali:IsPlaying()return self.playing end
 function jali:GetTime()return self.time end
 function jali:GetShouldHoldPose()return self.hold end
 function jali:SetTime(v)self.time=v end
 function jali:SetShouldHoldPose(v)self.hold=v end
 function jali:Play(v)self.playing=true;self.time=v end
 function jali:Pause()self.playing=false end
 function mesh:GetAnimPlayer()return jali end
 local movement={MovementMode=1,CustomMovementMode=0,IsValid=valid}
 function movement:StopMovementImmediately()end
 function movement:GetOverrideInputSize()return self.input or -1 end
 function movement:SetOverrideInputSize(v)self.input=math.max(0,math.min(1,v))end
 function movement:ResetOverrideInputSize()self.input=-1 end
 function movement:DisableMovement()self.MovementMode=0 end
 function movement:SetMovementMode(value)self.MovementMode=value end
 local npc={IsValid=valid,bUseControllerRotationYaw=true}
 function npc:IsA()return true end
 function npc:GetFName()return name('Anca_241') end
 function npc:GetFullName()return 'NPC Anca_241' end
 function npc:GetClass()return class end
 function npc:GetWorld()return world end
 function npc:IsPlayerControlled()return false end
 function npc:K2_GetActorLocation()return {X=200,Y=0,Z=0} end
 function npc:K2_GetActorRotation()return {Pitch=0,Yaw=0,Roll=0} end
 function npc:K2_SetActorRotation(r)self.rotation=r end
 function npc:K2_GetComponentsByClass()return {mesh} end
 function npc:GetMovementComponent()return movement end
 function npc:GetController()return nil end
 local player={IsValid=valid,GetFullName=function()return 'Player' end,GetWorld=function()return world end,K2_GetActorLocation=function()return {X=0,Y=0,Z=0} end}
 local camera={IsValid=valid,GetCameraLocation=function()return {X=-100,Y=0,Z=150} end,GetCameraRotation=function()return {} end}
 local pc={IsValid=valid,Pawn=player,PlayerCameraManager=camera,LineOfSightTo=function()return true end}
 local controllerScans=0
 local UE={GetPlayerController=function()controllerScans=controllerScans+1;return pc end,GetPlayer=function()return player end,GetKismetMathLibrary=function()return {GetForwardVector=function()return {X=1,Y=0,Z=0} end} end}
 FindAllOf=function(name)assert(name=='Pawn','global component/animation scans prohibited');return {player,npc} end
 StaticFindObject=function()return class end
 FindObjects=function()return {}end
 package.preload.UEHelpers=function()return UE end
 package.preload.runtime_path=function()return 'memory' end
 EObjectFlags={RF_BeginDestroyed=1,RF_FinishDestroyed=2}
 world.GetAddress=function()return 1 end
 for _,object in ipairs({world,class,mesh,faceAnim,audio,jali,movement,npc,player,camera,pc})do object.HasAnyFlags=function()return false end end
 package.preload.live_reload=function()return {modules={}}end
 package.preload.first_person_camera=function()return {active=function()return false end,tick=function()end,release=function()end}end
 package.preload.horde_mode=function()return {tick=function()end,stop=function()end}end
 for _,name in ipairs({'player_abilities','player_passives','skills_anywhere','auto_loot','ambient_comments','loot_comments'})do package.preload[name]=function()return {tick=function()end,cleanup=function()end,reset=function()end}end end
 package.preload.fast_travel=function()return {tick=function()end,cleanup=function()end,active=function()return false end,uiReady=function()return true end}end
 package.preload.companion_romance=function()return {snapshot=function()return ''end}end
 package.preload.companion_settings=function()return {values={},poll=function()end}end
 package.preload.companion_native=function()return {version=6}end
 local ownedParty=false;local partyAction=nil
 package.preload.companion_menu=function()return {close=function()end,isOpen=function()return false end,tick=function()end,toggle=function()end}end
 package.preload.companions=function()return {beforeReset=function()end,
  identity=function(actor)if ownedParty and actor==npc then return {name='Anca',characterId='anca'}end end,
  conversationAction=function(actor,action)assert(actor==npc and ownedParty);partyAction=action;return true,'Party action accepted'end,
  ambientSpeaker=function()return nil end,selectForChat=function()return nil end,returnChatFace=function()return false end,
  beforeConversation=function()end,afterConversation=function()end,cleanup=function()end,tick=function()end,actor=function()return npc end
 }end
 package.preload.ui_input=function()return {acquire=function()return {}end,release=function()end}end
 ${['ai_state','targeting','engagement','config','face_inspector','jali_probe','jali_preview','face_graph'].map(name=>`package.preload.${name}=function()\n${sources[name]}\nend`).join('\n')}
 require('ai_state').find=StaticFindObject
 ${sources.app}
 if ${streamMode} then
   files['memory/ui-control.txt']='select-single:first';for i=1,8 do tick()end;assert(movement.MovementMode==1 and movement:GetOverrideInputSize()==0 and faceAnim.linked,'conversation must hold NPC and attach face: '..table.concat(logs,' | '))
   keys.F6();keys.F7();keys.F8();assert(files['memory/target.txt']:find('\\nsingle\\n0\\n',1,true)and movement.MovementMode==1 and movement:GetOverrideInputSize()==0,'UE callbacks must not duplicate helper hotkeys')
   local gen=files['memory/target.txt']:match('^(%d+)')
   files['memory/frame.txt']=gen..'\\t100\\nJawOpen\\t0.63\\nMouthFunnel\\t0.9\\n'
   tick();assert(faceAnim.JawOpenAlpha==0.63,'Convai JawOpen must drive the proven scalar')
   files['memory/actions.txt']=''
   for i=1,12 do tick()end
   assert(movement.MovementMode==1 and movement:GetOverrideInputSize()==0 and faceAnim.linked and faceAnim.JawOpenAlpha==0.63,'empty action mailbox must keep the conversation and face active')
   files['memory/frame.txt']='1\\t100\\nJawOpen\\t1\\nREPLY-END\\told-reply\\n';tick()
   assert(faceAnim.JawOpenAlpha==0,'wrong generation must neutralize')
   files['memory/frame.txt']=gen..'\\t90\\nJawOpen\\t1\\nREPLY-END\\told-reply\\n';tick()
   assert(faceAnim.JawOpenAlpha==0,'stale frame must neutralize')
   assert(movement:GetOverrideInputSize()==0,'Stale completion released a live hold')
   files['memory/frame.txt']=gen..'\\t100\\nJawOpen\\t0\\nREPLY-END\\treply1\\n';tick()
   assert(movement:GetOverrideInputSize()==-1 and faceAnim.linked,'Completion must restore movement and retain face/selection')
   files['memory/ui-control.txt']='select-single:second';for i=1,8 do tick()end
   gen=files['memory/target.txt']:match('^(%d+)')
   assert(movement:GetOverrideInputSize()==0,'Next conversation must reacquire its own hold: '..table.concat(logs,' | '))
   ownedParty=true
   files['memory/actions.txt']=gen..'\\t100\\townedfollow\\tFollow\\n'
   for i=1,12 do tick()end
   assert(partyAction=='Follow'and movement.MovementMode==1,'Owned Follow did not release conversation hold / use party manager: '..table.concat(logs,' | '))
   assert(files['memory/action-result.txt']:find('\\townedfollow\\t1\\t',1,true),'Owned Follow failed')
   files['memory/actions.txt']=gen..'\\t100\\townedstop\\tStop Walking\\n'
   for i=1,12 do tick()end
   assert(partyAction=='Stop Walking'and movement.MovementMode==1 and movement:GetOverrideInputSize()==0,'Owned Stop did not route to party state and retain idle hold')
   assert(files['memory/action-result.txt']:find('\\townedstop\\t1\\t',1,true),'Owned Stop failed')
   files['memory/actions.txt']=''
   now=101;unload();assert(movement.MovementMode==1 and faceAnim.JawOpenAlpha==0.15 and not faceAnim.linked,'end restores face and movement')
   now=102;files['memory/ui-control.txt']='select-group:group1';for i=1,8 do tick()end;assert(files['memory/target.txt']:find('\\ngroup\\n',1,true),'group selection must publish group mode');unload()
   assert(movement.MovementMode==1 and faceAnim.JawOpenAlpha==0.15 and not faceAnim.linked,'reload restores active conversation')
   return
 end
 keys.F8()
 if ${probeMode} then
   assert(files['memory/jali-probe.txt']:find('COMPLETE:',1,true),'probe must complete')
   local scans=controllerScans;local report=files['memory/jali-probe.txt']
   keys.F8();keys.F7();for i=1,100 do tick()end
   assert(controllerScans==scans,'repeated keys must not scan or start conversations')
   assert(report==files['memory/jali-probe.txt'],'repeat F8 must preserve first report')
   assert(movement.MovementMode==1 and mesh.weight==0.12,'probe must leave movement and face alone')
   keys.F6();assert(movement.MovementMode==1 and movement:GetOverrideInputSize()==0 and not npc.rotation,'F6 must hold without directly rotating the capsule')
   local scansActive=controllerScans
   tick();assert(controllerScans==scansActive and faceAnim.JawOpenAlpha==0.8,'held preview drives jaw without scanning controllers')
   keys.F7();assert(movement.MovementMode==1 and faceAnim.JawOpenAlpha==0.15 and not jali.playing and jali.time==2 and audio.VolumeMultiplier==0.8,'F7 restores jaw and movement; JALI stays untouched')
   keys.F6();now=107;tick();assert(movement.MovementMode==1 and not jali.playing,'timeout must release NPC')
   keys.F6();assert(movement.MovementMode==1 and movement:GetOverrideInputSize()==0);unload()
   assert(movement.MovementMode==1 and not jali.playing and audio.VolumeMultiplier==0.8,'live reload must restore NPC and audio before replacing code')
   return
 end
 assert(files['memory/face-api-diagnostics.txt']:find('FaceInstance',1,true),'F8 must inspect only face animation metadata')
 assert(not files['memory/face-api-diagnostics.txt']:find('Bound JawOpen',1,true),'F8 must not enter morph binding')
 assert(files['memory/face-api-checkpoints.txt']:find('NEXT COMPLETE',1,true),'must persist checkpoints and completion')
 metadataOnly=false
 keys.F6();assert(movement.MovementMode==1,'facial test must not alter movement')
 local scansBefore=controllerScans
 tick();assert(mesh.weight~=0.12,'preview must move mouth')
 for i=1,60 do tick()end
 assert(controllerScans==scansBefore,'animation loop must not rescan player controllers')
 now=107;tick();assert(mesh.weight==0.12 and movement.MovementMode==1,'must restore after test')
 files['memory/dev-command.txt']='probe1\\ninspect\\nAnca\\n'
 now=108;tick();assert(files['memory/dev-response.txt']==nil,'development mailbox is disabled after crash')
 `;
 const result=lauxlib.luaL_dostring(state,to_luastring(script));
 const error=result===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(state,-1));lua.lua_close(state);
 assert.equal(result,lua.LUA_OK,error);
});
