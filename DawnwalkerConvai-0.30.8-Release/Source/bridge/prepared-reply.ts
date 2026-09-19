import type {ConvaiClient} from '@convai/web-sdk/vanilla';
import {METAHUMAN_ORDER_251} from '@convai/web-sdk/lipsync-helpers';
import {ReplyTracker} from './reply-tracker';
import {ReplyAudio} from './reply-audio';
type Face={at:number;weights:Record<string,number>};
export class PreparedReply {
 readonly reply=new ReplyTracker();readonly audio:ReplyAudio;
 private unlisten:(()=>void)[]=[];private faces:Face[]=[];private captions:{at:number;text:string}[]=[];
 private faceIndex=0;private captionIndex=0;private previous=performance.now();private carry=0;private started=0;
 sent=false;error='';cancelled=false;activated=false;actions:{name:string;target?:string}[]=[];private finishedAt=0;
 constructor(readonly client:ConvaiClient,readonly identity:string,readonly token:string,readonly scope:string){this.audio=new ReplyAudio(client.room);}
 private on(e:string,f:(...args:any[])=>void){this.unlisten.push(this.client.on(e,f));}
 async start(text:string,context:string){
  await this.audio.init();if(this.cancelled)return;
  this.reply.begin(this.token,this.client.chatMessages||[]);this.started=Date.now();
  this.on('messagesChange',m=>this.reply.observe(m));
  this.on('stateChange',()=>this.reply.state(!!this.client.state.isThinking,!!this.client.state.isSpeaking));
  this.on('botOutput',d=>{if(d.text&&(d.spoken||['in-progress','completed'].includes(d.spokenStatus))){this.reply.audio();this.captions.push({at:this.audio.clock,text:d.text});}});
  this.on('actionResponse',d=>this.actions.push(...d.actions.slice(0,8-this.actions.length)));
  this.on('error',()=>{this.error='Prepared Convai response failed';});
  this.on('disconnect',()=>{this.error='Prepared Convai connection closed';});
  this.client.updateContext({mode:'replace',run_llm:'false',text:context});
  this.audio.begin();this.sent=true;this.client.sendUserTextMessage(text);
 }
 tick(){
  if(this.cancelled||!this.sent)return;
  const now=performance.now(),delta=Math.min((now-this.previous)/1000,0.25);this.previous=now;
  const q=this.client.blendshapeQueue;
  if(!this.finishedAt&&q){
   if(q.consumeNormalizationSignal()||q.consumeOwnerReplacementStoppedSpeaking()){this.faces.push({at:this.audio.clock,weights:{}});this.carry=0;}
   if(q.isBotSpeaking()||q.hasReceivedEndSignal()){
    this.carry+=delta*q.getPlaybackFps();const n=Math.floor(this.carry);this.carry-=n;
    if(n>0){const weights:Record<string,number>={};
     if(q.length){const f=q.getFrameWithAlpha(Math.min(n,q.length)-1);q.consumeFrames(Math.min(n,q.length));
      if(f?.length===METAHUMAN_ORDER_251.length)METAHUMAN_ORDER_251.forEach((name,i)=>{if(/^CTRL_expressions_(mouth|jaw|tongue)/.test(name))weights[name]=f[i]||0;});}
     this.faces.push({at:this.audio.clock,weights});
    }
   }
   const done=this.reply.complete({thinking:!!this.client.state.isThinking,speaking:!!this.client.state.isSpeaking,queued:!!(q.length||q.isBotSpeaking()),drained:q.isConversationEnded()});
   if(done)this.finishedAt=Date.now();
  }
  // Allow the final decoded audio block to reach the main thread before closing capture.
  if(this.finishedAt&&Date.now()-this.finishedAt>=150&&!this.audio.finished){
   this.audio.finish();
   if(!this.audio.hasAudio&&this.reply.text)this.error='Convai finished speaking but remote audio capture was empty';
  }
  if(this.activated)this.audio.play();this.audio.pump();
  this.error=this.error||this.audio.error;
  if(!this.audio.hasAudio&&Date.now()-this.started>25000)this.error='Prepared response produced no audio';
 }
 view(){
  const at=this.audio.position;
  while(this.faceIndex+1<this.faces.length&&this.faces[this.faceIndex+1].at<=at)this.faceIndex++;
  while(this.captionIndex+1<this.captions.length&&this.captions[this.captionIndex+1].at<=at)this.captionIndex++;
  return {weights:this.audio.playing&&this.faces[this.faceIndex]?.at<=at?this.faces[this.faceIndex].weights:{},
   subtitle:this.audio.playing?(this.captions[this.captionIndex]?.at<=at?this.captions[this.captionIndex].text:this.reply.text):'',
   done:!this.error&&this.audio.done&&this.reply.finished};
 }
 stop(completed=false){
  this.cancelled=true;this.audio.stop();for(const off of this.unlisten)off?.();this.unlisten=[];
  if(this.sent&&!completed){
   try{this.client.sendInterruptMessage();this.client.updateContext({mode:'append',run_llm:'false',text:'The locally prepared reply was cancelled before it finished playing. Do not assume Coen or other characters heard that reply or acted on it.'});}catch{}
  }
 }
}
