import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';
import {webcrypto} from 'node:crypto';import {build} from 'esbuild';import {GroupChat} from '../bridge/group-chat.mjs';
test('actual client prepares later replies before handoff, plays them sequentially and reuses spawned clone connections',async()=>{
 const clients=[],audios=[],renders=[],timers=[],frames=[],storage=new Map(),elements=new Map();let now=10000,uuid=0;
 const members=['leonica','marat'].map(k=>({id:k,characterId:k,actor:k,name:k,distance:400,available:true}));
 const profiles=['anca','leonica','marat'].map(k=>({key:k,id:k,name:k,kind:'main',aliases:[k]}));
 let target={generation:1,active:false,actor:'anca',actorClass:'NPC',name:'anca',mode:'single',room:'idle',turn:'',gameAlive:true,requestId:0,partyCharacters:profiles.map(p=>p.key)};
 const group=new GroupChat(()=> 'g'+(++uuid));
 class FakeAudio{
  constructor(room){this.owner=room.owner;room.audio=this;audios.push(this);this.origin=0;this.hasAudio=false;this.playStart=0;this.finished=false;this.error='';this.stopped=false;}
  async init(){}begin(){}setPosition(){}get clock(){return now/1000;}get ready(){return this.hasAudio;}
  get playing(){return !!this.playStart&&!this.done&&!this.stopped;}get position(){return this.origin+(this.playStart?(now-this.playStart)/1000:0);}
  get done(){return this.finished&&!!this.playStart&&now-this.playStart>=1600;}get capturedMs(){return this.hasAudio?1600:0;}
  finish(){this.finished=true;}play(){if(!this.playStart&&this.ready&&!this.stopped)this.playStart=now;}pump(){}stop(){this.stopped=true;}
 }
 class FakeClient{
  constructor(options){this.options=options;this.events=new Map();this.sent=[];this.chatMessages=[];this.state={isThinking:false,isSpeaking:false};this.isBotReady=false;this.room={owner:this,startAudio:async()=>{}};this.characterSessionId=options.characterId+'-session';this.closed=0;clients.push(this);}
  on(e,f){if(!this.events.has(e))this.events.set(e,new Set());this.events.get(e).add(f);return ()=>this.off(e,f);}off(e,f){this.events.get(e)?.delete(f);}emit(e,v){for(const f of [...this.events.get(e)||[]])f(v);}
  async connect(){this.isBotReady=true;this.emit('botReady');}async disconnect(){this.closed++;this.isBotReady=false;this.emit('disconnect');}
  audioControls={enableAudio:async()=>{throw Error('Microphone opened during prefetch');},disableAudio:async()=>{}};
  updateDynamicInfo(){}updateContext(c){this.context=c.text;}sendInterruptMessage(){this.state.isSpeaking=false;}
  blendshapeQueue={length:0,ended:false,consumeNormalizationSignal:()=>false,consumeOwnerReplacementStoppedSpeaking:()=>false,isBotSpeaking:()=>this.state.isSpeaking,hasReceivedEndSignal:()=>this.blendshapeQueue.ended,isConversationEnded:()=>this.blendshapeQueue.ended&&!this.state.isSpeaking,getPlaybackFps:()=>60,getFrameWithAlpha:()=>new Float32Array([0.6]),consumeFrames:()=>{this.blendshapeQueue.length=0;}};
  sendUserTextMessage(t){this.sent.push({text:t,at:now});this.blendshapeQueue.ended=false;this.chatMessages.push({id:'u'+this.sent.length,type:'user',content:t,isStreaming:false});}
  speak(t){this.started=now;this.chatMessages.push({id:'b'+this.sent.length,type:'bot-llm-text',content:t,isStreaming:false});this.emit('messagesChange',this.chatMessages);this.state.isSpeaking=true;this.blendshapeQueue.length=1;if(this.room.audio){this.room.audio.hasAudio=true;this.room.audio.origin=now/1000;}this.emit('stateChange');this.emit('botOutput',{text:t,spoken:true});}
  stop(){this.state.isSpeaking=false;this.blendshapeQueue.ended=true;this.emit('stateChange');}
 }
 const bundle=await build({entryPoints:['bridge/client.ts'],bundle:true,write:false,format:'esm',plugins:[{name:'mock',setup(b){
  b.onResolve({filter:/^@convai\/web-sdk|^\.\/reply-audio$/},a=>({path:a.path,namespace:'mock'}));
  b.onLoad({filter:/.*/,namespace:'mock'},a=>({contents:a.path==='./reply-audio'?'export const ReplyAudio=globalThis.FakeAudio;':a.path.endsWith('vanilla')?'export const ConvaiClient=globalThis.FakeClient;export class AudioRenderer{constructor(r){globalThis.renders.push(r.owner);}destroy(){}}':'export const METAHUMAN_ORDER_251=["CTRL_expressions_jawOpen"];'}));
 }}]});
 const context={FakeClient,FakeAudio,renders,console,URLSearchParams,location:{search:'?auto=1'},Date:{now:()=>now},performance:{now:()=>now},TextEncoder,crypto:{subtle:webcrypto.subtle,randomUUID:()=> 'id'+(++uuid)},window:{addEventListener(){}},setInterval:(fn,ms)=>timers.push({fn,ms}),
  localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v)},document:{getElementById(k){if(!elements.has(k))elements.set(k,{value:k==='mapping'?'{}':'',textContent:''});return elements.get(k);}},
  fetch:async(path,opts)=>{
   if(path==='/frame'){const frame=JSON.parse(opts.body);frames.push(frame);if(frame.groupDone)group.complete(frame.groupDone,target,members,now);}
   const g=group.view(target),next=path.startsWith('/group-context')?g?.upcoming?.find(s=>s.token===new URLSearchParams(path.split('?')[1]).get('token')):g?.upcoming?.[0];
   return {ok:true,json:async()=>path==='/session'?{token:'test'}:path==='/config'?{apiKey:'test',characterId:'anca',roster:profiles}:path.startsWith('/group-context')?{questMemory:{text:'Private facts for '+next.characterId},environment:{text:'Rain'}}:
    {...target,group:g,textRequests:g?.request?[g.request]:[],questMemory:{recipient:target.name,revision:'q',text:'Private facts for '+target.name,ledger:[],facts:[]}}};
  }};
 await vm.runInNewContext('(async()=>{'+bundle.outputFiles[0].text+'})()',context);
 const tick=async(ms=100)=>{now+=ms;timers.find(t=>t.ms===16).fn();timers.find(t=>t.ms===20).fn();for(let i=0;i<10;i++)await new Promise(setImmediate);};
 for(let i=0;i<20;i++)await tick();assert.equal(clients.length,3,'Spawned profiles were not initialized');assert.ok(clients.every(c=>c.isBotReady));assert.equal(renders.length,1);
 target={...target,generation:2,active:true,mode:'group',room:'room1'};group.start({generation:2,id:'send1',text:'Hello everyone'},target,members,now);await tick();
 const first=clients.find(c=>c.options.characterId==="anca");first.speak('First reply');await tick();await tick();
 const second=clients.find(c=>c.options.characterId===group.round.speakers[1].characterId);
 assert.equal(second.sent.length,1,'Next reply must start while first is speaking');assert.equal(group.round.index,0);assert.equal(audios[0].playStart,0,'Prepared reply played over the first');
 second.speak('Second reply');for(let i=0;i<16;i++)await tick();second.stop();for(let i=0;i<8;i++)await tick();
 assert.equal(audios[0].finished,true);assert.equal(audios[0].playStart,0);assert.equal(group.round.index,0);
 first.stop();for(let i=0;i<6;i++)await tick();assert.equal(group.round.stage,'handoff');
 const handoff=()=>{const next=group.round.speakers[group.round.index];target={...target,generation:target.generation+2,actor:next.actor,name:next.name,turn:group.round.token};group.tick(target,members,true,now);};
 handoff();const selectedAt=now;await tick();await tick();await tick();
 assert.ok(audios[0].playStart-selectedAt<=300,'Prepared audio did not start promptly at handoff');assert.equal(second.sent.length,1,'Handoff resent the prepared message');
 assert.ok(frames.some(f=>f.subtitle==='Second reply'));assert.ok(frames.some(f=>f.weights.CTRL_expressions_jawOpen>0),'Buffered lip frames were lost');
 const third=clients.find(c=>c.options.characterId===group.round.speakers[2].characterId);assert.equal(third.sent.length,1);assert.ok(third.sent[0].at<selectedAt,'Third reply did not start during the first speaker');assert.match(third.context,/Second reply/);assert.match(third.context,new RegExp('Private facts for '+third.options.characterId));
 third.speak('Third reply');for(let i=0;i<18;i++){await tick();assert.ok(audios.filter(a=>a.playing).length<=1,'Overlapping group voices');}
 third.stop();assert.equal(group.round.stage,'handoff');handoff();for(let i=0;i<30;i++)await tick();
 assert.equal(group.round.stage,'done');assert.ok(frames.some(f=>f.subtitle==='Third reply'));assert.equal(clients.length,3);
 target={...target,generation:9,mode:'single',room:'single2',actor:'anca-clone2',name:'anca',turn:''};await tick();await tick();
 assert.equal(clients.length,3,'Selecting another copy created a separate live connection');assert.equal(first.closed,0);
 target={...target,generation:10,mode:'group',room:'cancelled'};group.start({generation:10,id:'send2',text:'Another question'},target,members,now);await tick();first.speak('Another first reply');await tick();await tick();
 const pending=audios.at(-1);pending.owner.emit('actionResponse',{actions:[{name:'Follow',target:'Coen'}]});
 target={...target,active:false};await tick();assert.equal(pending.stopped,true);assert.equal(pending.playStart,0,'Cancelled reply became audible');
 assert.equal(frames.at(-1).actionRequests.length,0,'Unplayed reply executed its prepared action');

});
