type Connection={isBotReady:boolean;connect():Promise<void>;disconnect():Promise<void>;on(e:string,f:()=>void):unknown;off?(e:string,f:()=>void):unknown};
export type ConnectionSpec={id:string;identity:string};
export type ConnectionEntry<C>={client:C;identity:string;connected:Promise<boolean>;started:number;settled:boolean;cancelled:boolean;unlisten:()=>void};
// One session per named character, regardless of how many clones are summoned.
// Only setup is staggered; there is no party-size limit on ready connections.
export class CharacterConnections<C extends Connection>{
 private entries=new Map<string,ConnectionEntry<C>>();private desired=new Map<string,ConnectionSpec>();
 private retries=new Map<string,number>();private nextStart=0;private pending=0;
 constructor(private create:(id:string,identity:string)=>C,private close:(c:C,identity:string)=>Promise<void>){}
 reconcile(specs:ConnectionSpec[],active:string,now=Date.now(),switching=false){
  this.desired=new Map(specs.filter(s=>s.id).map(s=>[s.identity,s]));
  for(const [id,e]of this.entries){if(!this.desired.has(id)||!e.client.isBotReady&&now-e.started>25000)this.drop(id,now);}
  if(switching||this.pending>=2||now<this.nextStart)return;
  const spec=specs.find(s=>s.identity!==active&&!this.entries.has(s.identity)&&now>=(this.retries.get(s.identity)||0));
  if(!spec)return;this.nextStart=now+500;
  let c:C;try{c=this.create(spec.id,spec.identity);}catch{this.retries.set(spec.identity,now+30000);return;}
  const e=this.store(c,spec.identity,now);this.pending++;
  e.connected=Promise.resolve().then(()=>e.cancelled?false:c.connect().then(()=>true)).then(ok=>{
   e.settled=true;if(e.cancelled)void this.close(c,e.identity).catch(()=>{});else if(!ok)this.drop(e.identity);return ok;
  },()=>{e.settled=true;if(e.cancelled)void this.close(c,e.identity).catch(()=>{});else this.drop(e.identity);return false;}).finally(()=>{this.pending--;});
 }
 private store(c:C,identity:string,now:number){
  const e:ConnectionEntry<C>={client:c,identity,started:now,connected:Promise.resolve(true),settled:false,cancelled:false,unlisten:()=>{}};
  const fail=()=>{if(this.entries.get(identity)===e)this.drop(identity);};
  c.on('error',fail);c.on('disconnect',fail);e.unlisten=()=>{c.off?.('error',fail);c.off?.('disconnect',fail);};
  this.entries.set(identity,e);return e;
 }
 get(identity:string){return this.entries.get(identity);}
 take(identity:string){const e=this.entries.get(identity);if(e){this.entries.delete(identity);e.unlisten();}return e||null;}
 release(c:C,identity:string){
  if(!this.desired.has(identity)||!c.isBotReady||this.entries.has(identity))return false;
  const e=this.store(c,identity,Date.now());e.settled=true;return true;
 }
 drop(identity:string,now=Date.now()){
  const e=this.entries.get(identity);if(!e)return;this.entries.delete(identity);e.unlisten();e.cancelled=true;
  this.retries.set(identity,now+30000);void this.close(e.client,identity).catch(()=>{});
 }
 clear(){this.desired.clear();for(const id of this.entries.keys())this.drop(id);}
 diagnostic(){return {ready:[...this.entries.values()].filter(e=>e.client.isBotReady).length,connecting:this.pending,wanted:this.desired.size};}
}
