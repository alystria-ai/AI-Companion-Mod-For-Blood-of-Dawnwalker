type Controls={enableAudio():Promise<void>;disableAudio():Promise<void>};
// Serialize hardware transitions. A stale enable is immediately closed if the
// target changed while permission/capture was pending. Errors require a new press.
export class Microphone {
  on=false;status='Microphone off';private wanted:Controls|null=null;private active:Controls|null=null;
  private running:Promise<void>|null=null;private lastRequest='';private failed='';
  constructor(private onControlFailure:()=>void=()=>{}){}
  get requestId(){return this.lastRequest;}
  request(controls:Controls|null,enabled:boolean,request:string){
    if(request!==this.lastRequest){this.failed='';this.lastRequest=request;}
    this.wanted=enabled&&request!==this.failed?controls:null;
    if(!this.running&&this.wanted!==this.active){this.running=this.pump().catch(e=>{this.wanted=null;this.failed=this.lastRequest;this.status='Microphone control failed: '+String(e);this.onControlFailure();}).finally(()=>{this.running=null;if(this.wanted!==this.active)this.request(this.wanted,!!this.wanted,this.lastRequest);});}
  }
  async stop(){
    this.failed=this.lastRequest;this.wanted=null;
    if(this.running)await this.running;
    // A device disappearing can reject disableAudio. Release our ownership
    // before awaiting it, so reconnect/text input never inherits a stale mic.
    const old=this.active;this.active=null;this.on=false;this.status='Microphone off';
    if(old)try{await old.disableAudio();}catch(e){this.status='Microphone disconnected: '+String(e);this.onControlFailure();}
  }
  private async pump(){
    while(this.wanted!==this.active){
      if(this.active){const old=this.active;this.active=null;this.on=false;await old.disableAudio();}
      const next=this.wanted;if(!next){this.status='Microphone off';continue;}
      this.status='Starting microphone';
      try{await next.enableAudio();if(this.wanted===next){this.active=next;this.on=true;this.status='Listening · press F7 / F9 again to stop';}else await next.disableAudio();}
      catch(e){await next.disableAudio().catch(()=>{});this.failed=this.lastRequest;this.wanted=null;this.on=false;this.status='Microphone unavailable: '+String(e);}
    }
  }
}
