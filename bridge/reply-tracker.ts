type Message={id:string;type:string;content:string;isStreaming?:boolean};
export class ReplyTracker {
 token='';before=new Set<string>();text='';finished=false;last=0;finalAt=0;heardAudio=false;private contentKey='';private responding=false;startedAt=0;firstTextAt=0;firstAudioAt=0;private drainedAt=0;
 begin(token:string,messages:Message[],now=Date.now()){
  this.startedAt=now;this.firstTextAt=0;this.firstAudioAt=0;this.drainedAt=0;this.token=token;this.before=new Set(messages.map(m=>m.id));this.text='';this.finished=false;this.last=now;this.finalAt=0;this.heardAudio=false;this.contentKey='';this.responding=false;
 }
 observe(messages:Message[],now=Date.now()){
  if(!this.token)return;
  const fresh=messages.filter(m=>!this.before.has(m.id));
  // SDK 1.7 can leave an empty bot-llm-started placeholder streaming when
  // another message intervenes: bot-llm-stopped finalizes only the last row.
  const llm=fresh.filter(m=>['bot-llm-text','convai'].includes(m.type)&&m.content?.trim());
  const rows=llm.length?llm:fresh.filter(m=>m.type==='bot-output'&&m.content?.trim());
  if(rows.length&&!this.firstTextAt)this.firstTextAt=now;
  const key=JSON.stringify(rows.map(m=>[m.id,m.content,m.isStreaming]));
  if(key!==this.contentKey){this.contentKey=key;this.last=now;this.text=rows.map(m=>m.content).join(' ').slice(0,5000);}
  if(rows.length&&rows.every(m=>m.isStreaming!==true)||fresh.some(m=>m.type==='llm-no-response')){if(!this.finalAt)this.finalAt=now;}
 }
 state(thinking:boolean,speaking:boolean,now=Date.now()){
  if(!this.token||this.finished)return;
  // A real responding -> idle transition is a second SDK completion signal.
  // Initial connection idle is never evidence that this request has completed.
  if(thinking){this.responding=true;this.finalAt=0;}
  else if(this.responding){this.responding=false;this.finalAt=now;this.last=now;}
  if(speaking)this.audio(now);
 }
 audio(now=Date.now()){if(!this.firstAudioAt)this.firstAudioAt=now;this.heardAudio=true;this.last=now;this.drainedAt=0;}
 complete(state:{thinking:boolean;speaking:boolean;queued:boolean;drained?:boolean},now=Date.now()){
  const ended=this.heardAudio&&state.drained&&!state.thinking&&!state.speaking&&!state.queued;
  if(ended){if(!this.drainedAt)this.drainedAt=now;}else this.drainedAt=0;
  // The SDK's turn-stats plus drained face/audio queues permit a short tail
  // guard. Missing end markers retain the conservative quiet-period fallback.
  const quiet=ended?250:1200;
  if(!this.token||this.finished||!this.finalAt||state.thinking||state.speaking||state.queued||now-Math.max(this.last,ended?this.drainedAt:0)<quiet)return null;
  // Give TTS time to start after LLM completion; never advance on initial idle.
  if(!this.heardAudio&&this.text&&now-this.finalAt<6000)return null;
  this.finished=true;return {token:this.token,text:this.text};
 }
}
