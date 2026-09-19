import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
import {build} from 'esbuild';
import {GroupChat} from '../bridge/group-chat.mjs';
test('actual browser client sends each group turn once, waits for speech and resumes the shared clone session',async()=>{
 const clients=[],rendered=[],timers=[],elements=new Map(),stored=new Map();let now=10000,uuid=0,micOpens=0,micCloses=0;
 const g=new GroupChat(()=> 'round1');
 const members=['leonica','marat'].map(k=>({id:k,characterId:k,name:k,actor:k,distance:400,available:true}));
 let target={generation:0,active:true,actor:'anca',actorClass:'NPC',name:'Anca',mode:'single',room:'silent1',turn:'',requestId:0,gameAlive:true,microphone:{enabled:true,id:'silent-press',generation:0}};
 const profiles=['anca','leonica','marat'].map(key=>({key,id:key,name:key,kind:'main',aliases:[key]}));
 class FakeClient{
  constructor(options){this.options=options;this.handlers={};this.state={isSpeaking:false,isThinking:false};this.room={on(){},off(){},remoteParticipants:new Map(),owner:this,startAudio:async()=>{this.audioStarted=true;}};this.chatMessages=[];this.sent=[];this.characterSessionId=options.characterId+'-session';clients.push(this);}
  publications=new Map();
  audioControls={enableAudio:async()=>{micOpens++;this.publications.set('mic',{source:'microphone',isMuted:false,track:{mediaStreamTrack:{readyState:'live',enabled:true,muted:false}}});},disableAudio:async()=>{micCloses++;}};
  toggleStt(){}
  on(e,fn){this.handlers[e]=fn;}
  async connect(){this.room.localParticipant={audioTrackPublications:this.publications,unpublishTrack:async()=>{this.publications.clear();}};this.isBotReady=true;this.handlers.botReady?.();}
  async disconnect(){this.isBotReady=false;}
  updateDynamicInfo(){} updateContext(v){this.context=v.text;} sendInterruptMessage(){}
  sendUserTextMessage(text){this.sent.push(text);this.chatMessages.push({id:'u'+this.sent.length,type:'user',content:text,isStreaming:false});}
  speak(text){this.chatMessages.push({id:'b'+this.sent.length,type:'bot-llm-text',content:text,isStreaming:false});this.handlers.messagesChange(this.chatMessages);this.state.isSpeaking=true;this.handlers.stateChange();this.handlers.botOutput({text,spoken:true});}
 }
 const bundle=await build({entryPoints:['bridge/client.ts'],bundle:true,write:false,format:'esm',plugins:[{name:'mock-sdk',setup(b){b.onResolve({filter:/^@convai\/web-sdk/},a=>({path:a.path,namespace:'mock'}));b.onLoad({filter:/.*/,namespace:'mock'},a=>({contents:a.path.endsWith('vanilla')?'export const ConvaiClient=globalThis.FakeClient;export class AudioRenderer{constructor(room){globalThis.rendered.push(room.owner);}destroy(){}}':'export const METAHUMAN_ORDER_251=[];'}));}}]});
 const context={FakeClient,rendered,console,URLSearchParams,location:{search:'?auto=1'},TextEncoder,crypto:{subtle:webcrypto.subtle,randomUUID:()=> 'id'+(++uuid)},Date:{now:()=>now},performance:{now:()=>now},window:{addEventListener(){}},setInterval:(fn,ms)=>timers.push({fn,ms}),
  document:{getElementById(k){if(!elements.has(k))elements.set(k,{value:k==='mapping'?'{}':'',textContent:''});return elements.get(k);}},localStorage:{getItem:k=>stored.get(k)||null,setItem:(k,v)=>stored.set(k,v)},
  fetch:async(path,opts)=>{
   if(path==='/frame'){const f=JSON.parse(opts.body);if(f.groupDone)g.complete(f.groupDone,target,members,now);}
   const group=g.view(target);
   return {ok:true,json:async()=>path==='/session'?{token:'test'}:path==='/config'?{apiKey:'test',characterId:'anca',roster:profiles}:
    {...target,group,textRequests:group?.request?[group.request]:[],questMemory:{recipient:target.name.toLowerCase(),revision:'q',ledger:[],facts:[],text:'Private facts for '+target.name}}};
  }};
 await vm.runInNewContext('(async()=>{'+bundle.outputFiles[0].text+'})()',context);
 const tick=async()=>{timers.find(t=>t.ms===20).fn();for(let i=0;i<8;i++)await new Promise(setImmediate);};
 await tick();await tick();await tick();assert.equal(micOpens,1);
 now+=3000;await tick();target.microphone.enabled=false;await tick();await tick();
 assert.equal(micCloses,1);assert.equal(clients[0].sent.length,0,'Silent microphone fabricated a text request');assert.equal(g.round,null);
 target={...target,generation:1,mode:'group',room:'group1',microphone:{enabled:false,id:'off',generation:1}};
 g.start({generation:1,id:'send1',text:'Hello everyone'},target,members,now);
 await tick();await tick();assert.equal(clients[0].sent.length,1);
 assert.equal(clients.length,2,'Second speaker connects during the first reply');
 assert.equal(rendered.length,1,'Silent warm connection must not create an audio renderer');
 assert.equal(clients[1].sent.length,0,'Do not generate replies before hearing previous speaker');
 assert.equal(clients[1].audioStarted,undefined);
 assert.equal(micOpens,1,'Warming must not open another microphone');
 for(let turn=0;turn<3;turn++){
  const c=clients.find(c=>c.options.characterId===g.round.speakers[turn].characterId);assert.deepEqual(c.sent,['Hello everyone']);
  if(turn>0)assert.match(c.context,/Reply 0/,'Later speaker should hear earlier public reply');
  c.speak('Reply '+turn);now+=2000;await tick();assert.equal(g.round.index,turn,'No handoff during speech');
  c.state.isSpeaking=false;c.handlers.stateChange();now+=1500;await tick();assert.equal(g.round.index,turn+1);
  if(turn<2){const next=g.round.speakers[g.round.index];target={...target,generation:target.generation+2,actor:next.actor,name:next.name,turn:g.round.token};g.tick(target,members,true,now);await tick();await tick();await tick();}
 }
 assert.equal(g.round.stage,'done');assert.equal(clients.length,3);assert.equal(rendered.length,3,'Promote the prepared clients without reconnecting');
 target={...target,generation:9,room:'single2',turn:'',mode:'single',actor:'anca-clone2',name:'Anca'};
 await tick();await tick();assert.equal(clients.at(-1).options.characterId,'anca');
 assert.equal(clients.at(-1).options.characterSessionId,'anca-session','Clone resumes the same named session');
 assert.equal(clients.at(-1).options.endUserId,clients[0].options.endUserId,'Clone shares long-term memory identity');
 assert.equal(new Set(clients.map(c=>c.options.endUserId)).size,1,'Different characters also share the one player end-user ID');
});
