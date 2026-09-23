export type VoicePosition=[number,number,number];
export type SpatialSample={generation:number;at:number;position:VoicePosition};
// Match WebRTC's speech clock and allow a playback-sized device buffer. The
// browser still owns device resampling; no PCM is rate-converted in JavaScript.
export const speechAudioOptions:AudioContextOptions={sampleRate:48000,latencyHint:'playback'};
export function voicePosition(sample:SpatialSample|null|undefined,generation:number,now=Date.now()):VoicePosition|null{
 if(!sample||sample.generation!==generation||!Number.isFinite(sample.at)||Math.abs(now-sample.at)>2000)return null;
 const p=sample.position;
 return Array.isArray(p)&&p.length===3&&p.every(n=>typeof n==='number'&&Number.isFinite(n)&&Math.abs(n)<=1000)?p:null;
}
// Ordinary centred playback. Distance only changes level very gently; there is
// no panner, filter, convolution, channel remapping or JavaScript resampling.
export function speechGain(position:VoicePosition|null):number{
 if(!position)return 1;
 const distance=Math.hypot(...position);
 if(!Number.isFinite(distance))return 1;
 return 1-0.15*Math.min(1,Math.max(0,(distance-4)/26));
}
export class SpatialOutput {
 readonly input:GainNode;private previous=1;
 constructor(private context:BaseAudioContext){
  this.input=context.createGain();this.input.gain.value=1;this.input.connect(context.destination);
 }
 setPosition(position:VoicePosition|null){
  const level=speechGain(position);if(Math.abs(level-this.previous)<.001)return;this.previous=level;
  const at=this.context.currentTime;
  this.input.gain.cancelScheduledValues(at);this.input.gain.setTargetAtTime(level,at,.15);
 }
 destroy(){this.input.disconnect();}
}
