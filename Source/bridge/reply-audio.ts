import type {Room,RemoteTrack} from 'livekit-client';
import {SpatialOutput,speechAudioOptions,type VoicePosition} from './spatial-output';
type Chunk={at:number;pcm:Float32Array};
// Receive decoded remote audio silently; replay the captured stream on a local
// clock at handoff. Muting/unmuting a live track would lose the beginning.
export class ReplyAudio {
 private context:AudioContext|null=null;private node:AudioWorkletNode|null=null;private source:MediaStreamAudioSourceNode|null=null;
 private chunks:Chunk[]=[];private cursor=0;private playback:AudioWorkletNode|null=null;private queued=0;private played=0;private progressAt=0;private stopped=false;
 private prime:HTMLAudioElement|null=null;private track:RemoteTrack|null=null;
 private spatial:SpatialOutput|null=null;
 origin=0;hasAudio=false;end=0;playStart=0;playbackStartedAt=0;finished=false;error='';private lastCapture=0;private armed=false;
 constructor(private room:Room){}
 async init(){
  const ctx=this.context=new AudioContext(speechAudioOptions);await ctx.audioWorklet.addModule('/reply-capture.js');await ctx.resume();
  if(this.stopped){await ctx.close();return;}
  const node=this.node=new AudioWorkletNode(ctx,'reply-capture');node.connect(ctx.destination);
  node.port.onmessage=e=>this.capture(e.data);
  this.playback=new AudioWorkletNode(ctx,'reply-playback',{numberOfInputs:0,numberOfOutputs:1,outputChannelCount:[1]});
  this.playback.port.onmessage=e=>{this.played=e.data.played;this.progressAt=e.data.at;};
  // startAudio unmutes attached elements: call it before installing the
  // deliberately muted capture consumer.
  await this.room.startAudio();
  if(this.stopped){await ctx.close();return;}
  this.spatial=new SpatialOutput(ctx);
  this.room.on('trackSubscribed',this.attach);
  this.room.remoteParticipants.forEach(p=>p.audioTrackPublications.forEach(pub=>{if(pub.track)this.attach(pub.track);}));
 }
 private attach=(track:RemoteTrack)=>{
  if(this.stopped||this.source||track.kind!=='audio'||!this.context||!this.node)return;
  // Chromium can leave a remote WebRTC track silent for Web Audio until a
  // media element consumes it. A muted attachment primes that remote track
  // without playing it early; a synthetic local MediaStream misses this case.
  const prime=this.prime=document.createElement('audio');this.track=track;
  prime.autoplay=true;prime.style.display='none';track.attach(prime);prime.muted=true;prime.volume=0;document.body.appendChild(prime);
  void prime.play().catch(()=>{this.error='Remote audio playback permission failed';});
  this.source=this.context.createMediaStreamSource(new MediaStream([track.mediaStreamTrack]));this.source.connect(this.node);
 };
 private capture(chunk:Chunk){
  if(this.stopped||this.finished||!this.context||!this.armed)return;
  if(!this.hasAudio){if(!chunk.pcm.some(v=>Math.abs(v)>0.00015))return;this.origin=chunk.at;this.hasAudio=true;}
  if(chunk.at-this.origin>60){this.error='Prepared reply exceeded the 60-second buffer';return;}
  this.chunks.push(chunk);this.end=chunk.at+chunk.pcm.length/this.context.sampleRate;this.lastCapture=Date.now();
 }
 begin(){this.armed=true;}
 get clock(){return this.context?.currentTime||0;}
 get ready(){return this.hasAudio&&this.end-this.origin>=0.16;}
 get playing(){return this.playStart>0&&!this.done;}
 get position(){return this.origin+Math.min(this.queued,this.played+Math.max(0,this.clock-this.progressAt)*(this.context?.sampleRate||48000))/(this.context?.sampleRate||48000);}
 get done(){return this.finished&&(!this.hasAudio||!!this.playStart&&this.cursor===this.chunks.length&&this.played>=this.queued);}
 get capturedMs(){return this.hasAudio?Math.round((this.end-this.origin)*1000):0;}
 finish(){this.finished=true;this.detachCapture();}
 setPosition(position:VoicePosition|null){this.spatial?.setPosition(position);}
 play(){if(!this.playStart&&(this.ready||this.finished&&this.hasAudio)){this.playStart=this.clock;this.playbackStartedAt=Date.now();this.progressAt=this.clock;this.playback!.connect(this.spatial!.input);this.pump();}}
 pump(){
  const ctx=this.context;if(!ctx||!this.playStart||this.stopped)return;
  while(this.cursor<this.chunks.length&&this.queued-this.played<ctx.sampleRate*0.5){
   const chunk=this.chunks[this.cursor++];this.queued+=chunk.pcm.length;
   this.playback!.port.postMessage({pcm:chunk.pcm},[chunk.pcm.buffer]);
  }
  if(!this.finished&&this.hasAudio&&Date.now()-this.lastCapture>4000)this.error='Remote audio capture stalled';
 }
 private detachCapture(){this.room.off('trackSubscribed',this.attach);this.source?.disconnect();this.source=null;this.node?.disconnect();this.node=null;
  if(this.prime){this.track?.detach(this.prime);this.prime.pause();this.prime.srcObject=null;this.prime.remove();this.prime=null;this.track=null;}}
 stop(){this.stopped=true;this.detachCapture();this.playback?.disconnect();this.playback=null;this.spatial?.destroy();this.spatial=null;this.chunks=[];void this.context?.close().catch(()=>{});}
}
