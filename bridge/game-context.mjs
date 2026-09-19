import {createHash} from 'node:crypto';
export const ACTIONS=['Follow','Stop Walking','Look At Player','Leave'];
export function parseQuests(raw,now=Date.now()){
  const [stamp,journal,...lines]=raw.split(/\r?\n/);
  if(!journal?.startsWith('Journal /Engine/Transient.')||Math.abs(now-Number(stamp)*1000)>25000)throw Error('Quest snapshot unavailable or stale');
  const rows=lines.filter(Boolean).map(line=>{const [id,state,title,ending='']=line.split('\t');return {id,state,title,ending};});
  if(rows.length>2000||rows.some(q=>!q.id||!q.title||!/^EQS_\w+$/.test(q.state)))throw Error('Invalid quest snapshot');
  const completed=rows.filter(q=>q.state==='EQS_Success'||q.state==='EQS_Failure');
  return {revision:createHash('sha256').update(JSON.stringify(completed)).digest('hex'),updated:Number(stamp)*1000,quests:completed};
}
export class ActionQueue{
  pending=[];seen=new Set();result=null;
  add(target,requests){
    if(!Array.isArray(requests)||requests.length>8)return;
    for(const r of requests){
      if(!target.active||r.generation!==target.generation||!ACTIONS.includes(r.name)||!/^[-\w]{1,80}$/.test(r.id||''))continue;
      const key=r.generation+':'+r.id;if(this.seen.has(key)||this.pending.length>=8)continue;
      this.seen.add(key);this.pending.push(r);
    }
    if(this.seen.size>2048)this.seen=new Set([...this.seen].slice(-1024));
  }
  current(target){this.pending=this.pending.filter(r=>target.active&&r.generation===target.generation);return this.pending[0];}
  ack(raw){const [gen,id,ok,message]=raw.trim().split('\t');const r=this.pending[0];if(r&&r.generation===Number(gen)&&r.id===id){this.pending.shift();this.result={generation:Number(gen),id,ok:ok==='1',message};}}
}
