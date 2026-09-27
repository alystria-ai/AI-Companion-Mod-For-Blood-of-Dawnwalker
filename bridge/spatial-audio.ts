import type {Room,RemoteTrack} from 'livekit-client';
import {AudioRenderer} from '@convai/web-sdk/vanilla';
import {SpatialOutput,speechAudioOptions,type VoicePosition} from './spatial-output';
export {voicePosition,type SpatialSample} from './spatial-output';
// A silent media element keeps Chromium decoding the remote WebRTC track.
// Only the Web Audio graph is audible; the raw live element never bypasses it.
export class SpatialRenderer {
 private context:AudioContext|null=null;private output:SpatialOutput|null=null;private fallback:AudioRenderer|null=null;
 private gate:GainNode|null=null;private fallbackMode=false;
 private tracks=new Map<RemoteTrack,{element:HTMLAudioElement;source:MediaStreamAudioSourceNode}>();
 error='';
 constructor(private room:Room,private muted=false){
  try{
   this.context=new AudioContext(speechAudioOptions);this.output=new SpatialOutput(this.context);
   // Apply silence before attaching any existing track. Distance gain cannot
   // reopen this separate gate, including during a target or generation change.
   this.gate=this.context.createGain();this.gate.gain.value=muted?0:1;this.gate.connect(this.output.input);
   this.room.on('trackSubscribed',this.attach);this.room.on('trackUnsubscribed',this.detach);
   this.room.remoteParticipants.forEach(p=>p.audioTrackPublications.forEach(pub=>{if(pub.track)this.attach(pub.track);}));
   void this.context.resume().catch(()=>{this.error='Spatial audio context could not resume';});
  }catch{
   this.destroy();this.fallbackMode=true;this.error='Spatial audio unavailable; using ordinary playback';if(!this.muted)this.fallback=new AudioRenderer(room);
  }
 }
 private attach=(track:RemoteTrack)=>{
  if(track.kind!=='audio'||this.tracks.has(track)||!this.context||!this.gate)return;
  const element=document.createElement('audio');element.autoplay=true;element.style.display='none';
  let source:MediaStreamAudioSourceNode|null=null;
  try{
   track.attach(element);element.muted=true;element.volume=0;document.body.appendChild(element);
   source=this.context.createMediaStreamSource(new MediaStream([track.mediaStreamTrack]));source.connect(this.gate);
   this.tracks.set(track,{element,source});
   void element.play().catch(()=>{this.error='Remote voice playback permission failed';});
  }catch{
   source?.disconnect();track.detach(element);element.pause();element.srcObject=null;element.remove();
   this.error='Could not attach spatial voice track';
  }
 };
 private detach=(track:RemoteTrack)=>{
  const item=this.tracks.get(track);if(!item)return;this.tracks.delete(track);item.source.disconnect();
  track.detach(item.element);item.element.pause();item.element.srcObject=null;item.element.remove();
 };
 setPosition(position:VoicePosition|null){this.output?.setPosition(position);}
 diagnostic(){return {muted:this.muted,context:this.context?.state||'none',tracks:this.tracks.size,fallback:this.fallbackMode};}
 setMuted(muted:boolean){
  if(this.muted===muted)return;this.muted=muted;
  if(this.gate){this.gate.gain.cancelScheduledValues(0);this.gate.gain.value=muted?0:1;}
  if(this.fallbackMode){this.fallback?.destroy();this.fallback=null;if(!muted)this.fallback=new AudioRenderer(this.room);}
 }
 destroy(){
  this.room.off?.('trackSubscribed',this.attach);this.room.off?.('trackUnsubscribed',this.detach);
  for(const track of this.tracks.keys())this.detach(track);
  this.gate?.disconnect();this.gate=null;
  this.output?.destroy();this.output=null;void this.context?.close().catch(()=>{});this.context=null;
  this.fallback?.destroy();this.fallback=null;
 }
}
