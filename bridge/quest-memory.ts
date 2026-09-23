type StorageLike={getItem(key:string):string|null;setItem(key:string,value:string):void};
type Fact={id:string;text:string;stage?:string;endingHash?:string;counter?:number};
type Manager={addMemories(memories:string[]):Promise<unknown>};
// One cloud end-user represents the player across all characters. Convai already
// partitions memory by character. Local quest/conversation timelines still branch
// on a save rollback; that must not consume another end-user slot.
export class QuestMemory {
  timeline:string;private previous:Record<string,Fact|string>;private busy=false;private next=0;
  private account='default';private preferredUser='';
  constructor(private storage:StorageLike,private uuid:()=>string){
    this.timeline=storage.getItem('dawnwalker-scoped-memory-v2-timeline')||uuid();
    this.previous=JSON.parse(storage.getItem('dawnwalker-scoped-memory-v2-quests')||'{}');
    storage.setItem('dawnwalker-scoped-memory-v2-timeline',this.timeline);
  }
  observe(facts:Fact[]){
    const next=Object.fromEntries(facts.map(f=>[f.id,f]));
    const terminal=(stage:string)=>/Success|Failure|complet|finish/i.test(stage);
    const rollback=Object.entries(this.previous).some(([id,old])=>{
      const current=next[id];if(!current)return true;
      if(typeof old==='string')return current.text!==old; // Conservative migration from v0.24 ledger.
      if(current.text===old.text)return false;
      if(Number.isFinite(old.counter)&&Number.isFinite(current.counter))return current.counter!<old.counter!;
      // Active -> success/failure is ordinary progress. A missing quest,
      // reverted state, changed completed ending, or policy change branches.
      if(old.stage&&current.stage&&!terminal(old.stage)&&terminal(current.stage))return false;
      return true;
    });
    if(rollback){this.timeline=this.uuid();this.storage.setItem('dawnwalker-scoped-memory-v2-timeline',this.timeline);}
    this.previous=next;this.storage.setItem('dawnwalker-scoped-memory-v2-quests',JSON.stringify(next));return rollback;
  }
  configurePlayer(account:string,endUserId=''){this.account=account;this.preferredUser=endUserId.trim();}
  user(_identity:string){
    const key='dawnwalker-player-end-user-v3:'+this.account;
    let id=this.preferredUser||this.storage.getItem(key);
    if(!id)id=this.uuid();
    this.storage.setItem(key,id);return id;
  }
  async sync(manager:Manager,scope:string,facts:Fact[],now=Date.now()){
    if(this.busy||now<this.next)return 0;
    const key='dawnwalker-scoped-memory-v2-ack:'+scope;
    const ack:Record<string,string>=JSON.parse(this.storage.getItem(key)||'{}');
    const batch=facts.filter(f=>ack[f.id]!==f.text).slice(0,16);if(!batch.length)return 0;
    this.busy=true;this.next=now+15000;
    try{await manager.addMemories(batch.map(f=>f.text));for(const f of batch)ack[f.id]=f.text;this.storage.setItem(key,JSON.stringify(ack));return batch.length;}
    catch(e){this.next=now+60000;throw e;}finally{this.busy=false;}
  }
}
