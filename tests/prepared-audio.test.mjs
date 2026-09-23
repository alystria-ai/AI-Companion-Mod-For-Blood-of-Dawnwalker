import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {build} from 'esbuild';

test('remote capture primes a muted media consumer and keeps it silent when LiveKit starts audio again',async()=>{
 const b=await build({entryPoints:['bridge/reply-audio.ts'],bundle:true,write:false,format:'iife',globalName:'M'});
 const elements=[],attached=[],events=[];let audio,sourceConnected=false;
 const track={kind:'audio',mediaStreamTrack:{},attach(el){events.push('attach');attached.push(el);el.muted=false;return el;},detach(el){attached.splice(attached.indexOf(el),1);}};
 const room={async startAudio(){events.push('startAudio');for(const el of attached){el.muted=false;await el.play();}},on(){},off(){},remoteParticipants:new Map([['bot',{audioTrackPublications:new Map([['audio',{track}]])}]])};
 class Context {currentTime=1;sampleRate=48000;destination={};audioWorklet={addModule:async()=>{}};async resume(){}async close(){}createGain(){return {gain:{value:1,cancelScheduledValues(){},setTargetAtTime(){}},connect(){},disconnect(){}};}createPanner(){const p=()=>({value:0,cancelScheduledValues(){},setTargetAtTime(){}});return {positionX:p(),positionY:p(),positionZ:p(),connect(){},disconnect(){}};}createMediaStreamSource(){return {connect(){sourceConnected=true;},disconnect(){sourceConnected=false;}};}}
 class Worklet {port={postMessage(){},onmessage:null};connect(){}disconnect(){}}
 const context={AudioContext:Context,AudioWorkletNode:Worklet,MediaStream:class{},Date,Float32Array,
  document:{createElement(){const el={muted:false,volume:1,style:{},async play(){assert.ok(this.muted||this.volume===0,'Prepared audio escaped into audible playback');},pause(){},remove(){this.removed=true;}};elements.push(el);return el;},body:{appendChild(){}}}};
 vm.runInNewContext(b.outputFiles[0].text,context);audio=new context.M.ReplyAudio(room);await audio.init();
 assert.deepEqual(events,['startAudio','attach']);assert.ok(sourceConnected);assert.equal(elements[0].muted,true);assert.equal(elements[0].volume,0);
 await room.startAudio();assert.equal(elements[0].volume,0,'handoff cannot make the original remote stream audible');
 audio.begin();audio.capture({at:1,pcm:new Float32Array(9600).fill(.2)});assert.equal(audio.ready,true);assert.equal(audio.playStart,0);
 audio.finish();assert.equal(sourceConnected,false);assert.equal(attached.length,0);assert.equal(elements[0].removed,true);audio.stop();
});

test('completed remote speech with empty capture fails promptly instead of advancing a silent group turn',async()=>{
 let now=10000;
 class EmptyAudio {hasAudio=false;finished=false;error='';clock=0;position=0;playing=false;async init(){}begin(){}finish(){this.finished=true;}play(){}pump(){}stop(){}get done(){return this.finished;}}
 const b=await build({entryPoints:['bridge/prepared-reply.ts'],bundle:true,write:false,format:'iife',globalName:'M',plugins:[{name:'mock',setup(b){
  b.onResolve({filter:/^\.\/reply-audio$|^@convai\/web-sdk\/lipsync-helpers$/},a=>({path:a.path,namespace:'mock'}));
  b.onLoad({filter:/.*/,namespace:'mock'},a=>({contents:a.path==='./reply-audio'?'export const ReplyAudio=globalThis.EmptyAudio;':'export const METAHUMAN_ORDER_251=[];'}));
 }}]});
 const ctx={EmptyAudio,Date:{now:()=>now},performance:{now:()=>now}};vm.runInNewContext(b.outputFiles[0].text,ctx);
 const client={room:{},chatMessages:[],state:{isThinking:false,isSpeaking:false},on(){return ()=>{};},updateContext(){},sendUserTextMessage(){},
  blendshapeQueue:{length:0,consumeNormalizationSignal:()=>false,consumeOwnerReplacementStoppedSpeaking:()=>false,isBotSpeaking:()=>false,hasReceivedEndSignal:()=>false,isConversationEnded:()=>true}};
 const prepared=new ctx.M.PreparedReply(client,'identity','turn','room');await prepared.start('hello','context');
 prepared.reply.observe([{id:'reply',type:'bot-llm-text',content:'Hello, Coen.',isStreaming:false}]);prepared.reply.audio();
 prepared.tick();now+=300;prepared.tick();now+=160;prepared.tick();
 assert.match(prepared.error,/remote audio capture was empty/);assert.equal(prepared.view().done,false);assert.ok(now-10000<1000);
});
