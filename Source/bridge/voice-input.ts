import type {ConvaiClient} from '@convai/web-sdk/vanilla';

// Keep a stable controller per SDK client. Open only for an explicit voice turn;
// remove the stopped publication on close so the next turn gets a live track.
export class VoiceInput {
  private controllers=new WeakMap<ConvaiClient,{enableAudio():Promise<void>;disableAudio():Promise<void>}>();
  private owner:ConvaiClient|null=null;private track:MediaStreamTrack|null=null;
  private context:AudioContext|null=null;private source:MediaStreamAudioSourceNode|null=null;private analyser:AnalyserNode|null=null;
  private samples=new Float32Array(256);private opened=0;private signalAt=0;
  device='';
  private publication(c:ConvaiClient){return [...c.room.localParticipant.audioTrackPublications.values()].find(p=>p.source==='microphone');}
  controls(c:ConvaiClient){
    let controls=this.controllers.get(c);if(controls)return controls;
    controls={enableAudio:async()=>{
      const old=this.publication(c)?.track;
      if(old?.mediaStreamTrack.readyState==='ended')await c.room.localParticipant.unpublishTrack(old,true);
      c.toggleStt(true);
      await c.audioControls.enableAudio();
      const pub=this.publication(c),track=pub?.track?.mediaStreamTrack;
      if(!track||track.readyState!=='live'||!track.enabled||pub?.isMuted)throw Error('Microphone opened without a live published audio track');
      this.owner=c;this.track=track;this.device=track.label||'Windows default microphone';this.opened=Date.now();this.signalAt=0;
      this.closeMeter();
      if(typeof AudioContext!=='undefined')try{
        this.context=new AudioContext();await this.context.resume();
        this.source=this.context.createMediaStreamSource(new MediaStream([track]));
        this.analyser=this.context.createAnalyser();this.analyser.fftSize=256;this.source.connect(this.analyser);
      }catch{this.closeMeter();}
    },disableAudio:async()=>{
      const pub=this.publication(c),track=pub?.track;
      if(this.owner===c){this.owner=null;this.track=null;this.closeMeter();}
      // LiveKit's disable mutes; Convai also stops the MediaStreamTrack. Remove
      // that publication explicitly instead of retaining a dead microphone.
      try{await c.audioControls.disableAudio();}
      finally{if(track)await c.room.localParticipant.unpublishTrack(track,true);}
    }};
    this.controllers.set(c,controls);return controls;
  }
  private closeMeter(){this.source?.disconnect();this.source=null;this.analyser=null;if(this.context)void this.context.close().catch(()=>{});this.context=null;}
  sample(){
    let level=0;
    if(this.analyser){this.analyser.getFloatTimeDomainData(this.samples);for(const n of this.samples)level+=n*n;level=Math.sqrt(level/this.samples.length);if(level>0.001)this.signalAt=Date.now();}
    return {device:this.device,level:Math.min(1,level*8),trackState:this.track?.readyState||'off',muted:this.track?.muted??false,meter:!!this.analyser,
      signalDetected:!!this.signalAt,silent:!!(this.track&&this.analyser&&!this.signalAt&&Date.now()-this.opened>6000)};
  }
}
