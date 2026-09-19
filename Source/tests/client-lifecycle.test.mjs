import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {webcrypto} from 'node:crypto';
import {build} from 'esbuild';

test('idle default connection survives release; repeats requests and reconnects without replay',async()=>{
 const clients=[],intervals=[],storage=new Map(),frames=[];let now=10000;
 let target={generation:1,active:false,actor:'Anca',actorClass:'NPC',status:'Ready',gameAlive:true,mode:'single',requestId:0};
 class FakeClient{
   constructor(options){this.options=options;this.handlers={};this.isBotReady=false;this.state={agentState:'connected'};this.room={startAudio:async()=>{}};this.sent=[];this.closed=0;this.interrupts=0;this.characterSessionId='saved-session';clients.push(this);}
   on(event,fn){this.handlers[event]=fn;}
   async connect(){this.isBotReady=true;this.handlers.botReady?.();}
   async disconnect(){this.closed++;this.isBotReady=false;this.handlers.disconnect?.();}
   updateDynamicInfo(){}
   updateContext(value){this.lastContext=value;}
   sendUserTextMessage(text){this.sent.push(text);}
   sendInterruptMessage(){this.interrupts++;}
 }
 const bundle=await build({entryPoints:['bridge/client.ts'],bundle:true,write:false,format:'esm',plugins:[{
   name:'fake-convai',setup(b){b.onResolve({filter:/^@convai\/web-sdk/},args=>({path:args.path,namespace:'fake'}));b.onLoad({filter:/.*/,namespace:'fake'},args=>({contents:args.path.endsWith('vanilla')?'export const ConvaiClient=globalThis.FakeClient; export class AudioRenderer{destroy(){}}':'export const METAHUMAN_ORDER_251=[];'}));}
 }]});
 const elements=new Map();
 const context={TextEncoder,crypto:{subtle:webcrypto.subtle,randomUUID:()=>"test-user"},FakeClient,console,URLSearchParams,location:{search:'?auto=1'},performance:{now:()=>now},Date:{now:()=>now},
   document:{getElementById(id){if(!elements.has(id))elements.set(id,{value:id==='mapping'?'{}':'',textContent:''});return elements.get(id);}},
   localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v)},
   window:{addEventListener(){}},setInterval:(fn,ms)=>intervals.push({fn,ms}),
   fetch:async(path,options)=>{if(path==='/frame')frames.push(JSON.parse(options.body));return {ok:true,json:async()=>path==='/session'?{token:'test'}:path==='/config'?{apiKey:'test',characterId:'anca',testText:'Hello',roster:[{key:'anca',id:'anca',name:'Anca',kind:'main',aliases:['anca']},{key:'male-1',id:'shared-villager',name:'Villager',kind:'generic',gender:'MALE',aliases:[]}]}:target};}};
 await vm.runInNewContext('(async()=>{'+bundle.outputFiles[0].text+'})()',context);
 const tick=async()=>{intervals.find(i=>i.ms===20).fn();for(let i=0;i<4;i++)await new Promise(setImmediate);};
 await tick();assert.equal(clients.length,1);assert.equal(clients[0].sent.length,0,'preconnect must not send a message');
 target={...target,generation:2,active:true,requestId:1};await tick();await tick();
 assert.deepEqual(clients[0].sent,['Hello']);
 clients[0].handlers.messagesChange?.([{type:'bot-llm-text',content:'A previous reply'}]);await tick();
 assert.equal(frames.at(-1).subtitle,'','history must not become a subtitle');
 clients[0].handlers.botOutput({text:'A spoken sentence',spoken:true});await tick();
 assert.equal(frames.at(-1).subtitle,'A spoken sentence');
 clients[0].state.isSpeaking=true;clients[0].handlers.stateChange();now+=9000;await tick();
 assert.equal(frames.at(-1).subtitle,'A spoken sentence','keep caption while audio is playing');
 clients[0].state.isSpeaking=false;clients[0].handlers.stateChange();now+=1900;await tick();
 assert.equal(frames.at(-1).subtitle,'','hide caption shortly after speech finishes');
 target={...target,requestId:2};await tick();assert.equal(clients[0].sent.length,2);
 clients[0].handlers.botTtsStarted();
 clients[0].handlers.messagesChange?.([{type:'bot-llm-text',content:'A spoken sentence'}]);await tick();
 assert.equal(frames.at(-1).subtitle,'','new TTS must not resurrect the previous response');
 clients[0].handlers.botOutput({text:'The new reply',spoken:true});await tick();
 assert.equal(frames.at(-1).subtitle,'The new reply');
 // This backend can send LLM text before TTS, without spoken text events.
 clients[0].chatMessages=[{id:'old-reply',type:'bot-llm-text',content:'The new reply'}];
 clients[0].state.isThinking=true;clients[0].handlers.stateChange();
 clients[0].handlers.messagesChange(clients[0].chatMessages);await tick();
 assert.equal(frames.at(-1).subtitle,'','exclude prior reply by ID');
 const fresh={id:'fresh-reply',type:'bot-llm-text',content:'Current streamed response'};
 clients[0].handlers.messagesChange([...clients[0].chatMessages,fresh]);await tick();
 assert.equal(frames.at(-1).subtitle,fresh.content,'new LLM-only text must be visible');
 clients[0].handlers.botTtsStarted();await tick();
 assert.equal(frames.at(-1).subtitle,fresh.content,'late TTS start must preserve current reply');
 now+=16000;await tick();clients[0].handlers.messagesChange([...clients[0].chatMessages,fresh]);await tick();
 assert.equal(frames.at(-1).subtitle,'','same history must not resurrect expired text');
 target={...target,generation:3,active:false,requestId:0};await tick();
 assert.equal(clients[0].closed,0,'F7 must retain the connection');assert.equal(clients[0].interrupts,1);
 target={...target,generation:4,active:true,requestId:1};await tick();assert.equal(clients.length,1);assert.equal(clients[0].sent.length,3);
 clients[0].handlers.disconnect();await new Promise(setImmediate);now+=2000;await tick();await tick();
 assert.equal(clients.length,2,'retry automatically');assert.equal(clients[1].sent.length,0,'reconnect must not replay an acknowledged request');
 assert.equal(clients[1].options.characterSessionId,'saved-session');
 target={...target,textRequests:[{id:'typed-1',generation:4,text:'My own question'}]};await tick();await tick();
 assert.deepEqual(clients[1].sent,['My own question']);assert.deepEqual(frames.at(-1).ackTextIds,['typed-1']);
 assert.equal(frames.at(-1).singleDone,null,'Connection idle must not release a pending reply');
 clients[1].handlers.messagesChange([{id:'reply-typed-1',type:'bot-llm-text',content:'Hello',isStreaming:false}]);
 now+=2000;await tick();assert.equal(frames.at(-1).singleDone,null,'Wait for delayed TTS');
 clients[1].handlers.botOutput({text:'Hello',spoken:true});clients[1].state.isSpeaking=true;clients[1].handlers.stateChange();
 now+=2000;await tick();assert.equal(frames.at(-1).singleDone,null,'Do not release during speech');
 clients[1].state.isSpeaking=false;clients[1].handlers.stateChange();
 clients[1].blendshapeQueue={length:4,isBotSpeaking:()=>false,isConversationEnded:()=>true};
 now+=1500;await tick();assert.equal(frames.at(-1).singleDone,null,'Do not release before face queue drains');
 clients[1].blendshapeQueue.length=0;await tick();now+=300;await tick();
 assert.equal(frames.at(-1).singleDone,'typed-1');await tick();assert.equal(frames.at(-1).singleDone,'typed-1','Repeat marker until game reads it');
 assert.equal(clients[1].closed,0,'Completion must keep the warm connection');
 target={...target,generation:5,actor:'NPC /Map.PersistentLevel.Villager_1',actorClass:'BP_NonPlayerCharacter_C',definition:'NPCDef_Town_C',bodyType:'Man',name:'Villager',requestId:1,textRequests:[]};
 await tick();await tick();assert.equal(clients.at(-1).options.characterId,'shared-villager');
 assert.notEqual(frames.at(-1).singleDone,'typed-1','Old completion must not leak into a new target');
 assert.equal(clients.at(-1).options.characterSessionId,undefined,'first villager gets a fresh session');
 target={...target,generation:6,actor:'NPC /Map.PersistentLevel.Villager_2'};await tick();await tick();
 assert.equal(clients.at(-1).options.characterSessionId,undefined,'a different actor must not inherit another villager memory');
 target={...target,generation:7,actor:'NPC /Map.PersistentLevel.Villager_1'};await tick();await tick();
 assert.equal(clients.at(-1).options.characterSessionId,'saved-session','returning to the original villager resumes that actor session');
 target={...target,questMemory:{revision:'q1',text:'Completed: A verified quest',facts:[]}};await tick();
 assert.match(clients.at(-1).lastContext.text,/A verified quest/);
 clients.at(-1).handlers.actionResponse({actions:[{name:'Follow',target:'Coen'},{name:'Execute Lua'},{name:'Follow',target:'Other NPC'}]});await tick();
 assert.equal(frames.at(-1).actionRequests.length,1);
 const action=frames.at(-1).actionRequests[0];target={...target,actionResult:{generation:7,id:action.id,ok:true,message:'Following Coen'}};await tick();
 assert.equal(frames.at(-1).actionRequests.length,0);assert.match(clients.at(-1).lastContext.text,/success: Following Coen/);
 target={...target,generation:8,active:false,questMemory:{recipient:'anca',revision:'wrong-recipient',text:'PRIVATE ANCA FACT',facts:[{id:'secret',text:'PRIVATE ANCA FACT'}]}};
 await tick();assert.doesNotMatch(clients.at(-1).lastContext.text,/PRIVATE ANCA/);
 assert.match(clients.at(-1).lastContext.text,/No verified quest knowledge/);
});
