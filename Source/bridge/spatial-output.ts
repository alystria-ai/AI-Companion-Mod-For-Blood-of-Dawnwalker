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
// Listener stays at the Web Audio origin, looking down -Z. Lua supplies the
// character's camera-relative coordinates in metres, so camera rotation and
// movement affect both live audio and already-buffered speech at playback time.
export class SpatialOutput {
 readonly input:PannerNode;private previous='';
 constructor(private context:BaseAudioContext){
  // Equal-power panning changes channel levels, not the voice's spectrum. HRTF
  // convolution can sound hollow/phasey, especially through speakers or an
  // output device that already applies its own spatial processing.
  const p=this.input=context.createPanner();p.panningModel='equalpower';p.distanceModel='inverse';
  p.refDistance=2;p.maxDistance=60;p.rolloffFactor=0.65;
  p.coneInnerAngle=360;p.coneOuterAngle=360;p.coneOuterGain=1;
  p.positionZ.value=-2;p.connect(context.destination);
 }
 setPosition(position:VoicePosition|null){
  const values=position||[0,0,-2],key=values.join(',');if(key===this.previous)return;this.previous=key;
  const at=this.context.currentTime;
  [this.input.positionX,this.input.positionY,this.input.positionZ].forEach((p,i)=>{
   p.cancelScheduledValues(at);p.setTargetAtTime(values[i],at,0.045);
  });
 }
 destroy(){this.input.disconnect();}
}
