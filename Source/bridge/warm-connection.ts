type Connection={isBotReady:boolean;connect():Promise<void>;disconnect():Promise<void>;on(event:'error'|'disconnect',fn:()=>void):unknown};
type Entry<C>={identity:string;client:C;started:number;connected:Promise<boolean>;settled:boolean;cancelled:boolean};

// One silent upcoming speaker, not a second conversation. Audio rendering and
// microphone ownership are attached only after take() promotes this client.
export class WarmConnection<C extends Connection> {
 private slot:Entry<C>|null=null;
 private scope='';private failed=false;private retiring=0;
 constructor(private close:(client:C,identity:string)=>Promise<void>){}
 setScope(scope:string){if(scope===this.scope)return;this.clear();this.scope=scope;this.failed=false;}
 clear(){const old=this.slot;this.slot=null;if(old)this.retire(old);}
 private retire(entry:Entry<C>){
  if(entry.cancelled)return;entry.cancelled=true;this.retiring++;
  // disconnect() alone cannot cancel the SDK's in-flight HTTP connect request.
  // Close again after it settles, and don't accumulate pending replacements.
  void this.close(entry.client,entry.identity).catch(()=>{});
  void entry.connected.then(()=>this.close(entry.client,entry.identity)).catch(()=>{}).finally(()=>{this.retiring--;});
 }
 ensure(identity:string,create:()=>C,now=Date.now()){
  if(this.slot?.identity===identity){
   if(now-this.slot.started>20000&&!this.slot.client.isBotReady){this.failed=true;this.clear();}
   return;
  }
  this.clear();
  if(!identity||!this.scope||this.failed||this.retiring)return;
  let client:C;try{client=create();}catch{this.failed=true;return;}
  const entry:Entry<C>={identity,client,started:now,connected:Promise.resolve(false),settled:false,cancelled:false};
  this.slot=entry;
  const fail=()=>{if(this.slot===entry){this.failed=true;this.clear();}};
  client.on('error',fail);client.on('disconnect',fail);
  entry.connected=Promise.resolve().then(()=>entry.cancelled?false:client.connect().then(()=>true)).then(ok=>{
   entry.settled=true;if(!ok)fail();return ok;
  },()=>{entry.settled=true;fail();return false;});
 }
 take(identity:string){
  const entry=this.slot;if(!entry||entry.identity!==identity||entry.cancelled)return null;
  this.slot=null;return entry;
 }
 diagnostic(){const s=this.slot;return {state:this.failed?'unavailable':s?(s.client.isBotReady?'ready':'connecting'):'idle',ageMs:s?Date.now()-s.started:0};}
}
