import {readFile,writeFile,rename} from 'node:fs/promises';
import {resolve} from 'node:path';
import {randomBytes} from 'node:crypto';
const id=()=> 'p'+randomBytes(10).toString('hex');
export function parseParty(text){
 if(typeof text!=='string'||text.length>4*1024*1024)throw Error('Invalid party state');
 const lines=text.trim().split(/\r?\n/).map(l=>l.split('\t'));
 const h=lines.shift();if(h.length!==5||h[0]!=='PARTY'||h[1]!=='1'||!/^\d+$/.test(h[2]))throw Error('Invalid party header');
 const end=lines.pop();if(!end||end.length!==2||end[0]!=='END'||end[1]!==h[2])throw Error('Incomplete party snapshot');
 const state={epoch:h[2],updated:Number(h[3])*1000,limit:Number(h[4]),members:[],summons:[],ack:null,note:''};
 for(const p of lines){
  if(p[0]==='ACK'&&p.length===4)state.ack={id:p[1],ok:p[2]==='ok',message:p[3]};
  if(p[0]==='NOTE')state.note=p[1]||'';
  if(p[0]==='SUMMON'&&p.length===5&&/^p[0-9a-f]+$/.test(p[1])&&state.summons.length<4096)
   state.summons.push({id:p[1],member:p[2],phase:p[3],message:p[4]});
  if(p[0]==='MEMBER'&&p.length===18){
   // Legacy tactic, plan and power columns stay reserved for rolling reloads.
   state.members.push({id:p[1],name:p[2],status:p[3],mode:p[4],health:p[12]===''?null:Number(p[12]),stamina:p[13]===''?null:Number(p[13]),canFight:p[15]==='1',detail:p[17]});
  }
 }
 for(const p of lines)if(p[0]==='IDENTITY'&&p.length===7){const m=state.members.find(m=>m.id===p[1]);if(m)Object.assign(m,{characterId:p[2],label:p[3],actor:p[4],distance:Number(p[5]),available:p[6]==='1'});}
 return state;
}
export class Companions {
 constructor(runtime,config){this.runtime=runtime;this.config=config;this.queue=[];this.connectionIntents=new Map();this.result=null;this.state={epoch:'',members:[],updated:0,limit:config.limit,note:'Waiting for companion Lua'};this.busy=false;}
 connectionCharacters(){
  const keys=this.state.members.map(m=>m.characterId).filter(Boolean);
  for(const [id,intent]of this.connectionIntents){
   const failed=this.state.summons?.some(s=>s.id===id&&s.phase==='failed');
   if(failed||Date.now()-intent.created>60000||this.state.members.some(m=>m.id===id&&m.characterId)){this.connectionIntents.delete(id);continue;}
   keys.push(intent.characterId);
  }
  return [...new Set(keys)];
 }
 async init(){} // Legacy saved plans are retained on disk but never activated.
 canSummon(){
  const age=Date.now()-this.state.updated;
  return !!this.state.epoch&&(age<5000||age<60000&&(this.queue.some(q=>q.op==='spawn')||this.state.summons?.some(s=>!['ready','failed'].includes(s.phase))));
 }
 view(){return {...this.state,roster:this.config.characters,canSummon:this.canSummon(),gameAlive:Date.now()-this.state.updated<5000,queued:this.queue.length,result:this.result};}
 async tick(){
  if(this.busy)return;this.busy=true;
  try{
   const next=parseParty(await readFile(resolve(this.runtime,'companions-state.tsv'),'utf8'));
   if(this.state.epoch&&next.epoch!==this.state.epoch){this.queue=[];this.connectionIntents.clear();this.result={ok:false,message:'Party reset after reload or world change.'};}
   this.state=next;
   if(this.queue[0]&&next.ack?.id===this.queue[0].id){this.result=next.ack;this.queue.shift();}
   while(this.queue[0]&&Date.now()-this.queue[0].created>60000){this.result={id:this.queue[0].id,ok:false,message:'Command expired; unpause and try again.'};this.queue.shift();}
   const command=this.queue[0];
   await this.atomic('companions-command.tsv',command?command.wire:'');
  }catch{/* Startup or incomplete Lua write: retain the last complete snapshot. */}
  try{await this.atomic('companions-panel.json',JSON.stringify(this.view()));}catch{}
  finally{this.busy=false;}
 }
 async atomic(name,text){const path=resolve(this.runtime,name);await writeFile(path+'.tmp',text);await rename(path+'.tmp',path);}
 async command(body){
  if(!body||typeof body!=='object')throw Error('Invalid command');
  if(!['spawn','dismiss','dismiss_all','follow','stop'].includes(body.op))throw Error('Companions use native combat. Tactical settings and plans have been removed.');
  if(String(body.epoch)!==this.state.epoch||(body.op==='spawn'?!this.canSummon():Date.now()-this.state.updated>=5000))throw Error('Party changed or game unavailable; reopen F5');
  if(this.queue.length>=32)throw Error('Wait for the queued commands to finish');
  const character=this.config.characters.find(c=>c.id===body.member);
  const member=this.state.members.find(m=>m.id===body.member);
  if(body.op==='spawn'?!character:body.op!=='dismiss_all'&&!member)throw Error('Choose a current party member, or a roster character to summon');
  const request={id:id(),created:Date.now(),op:body.op};
  request.wire=['CMD',this.state.epoch,Math.floor(request.created/1000),request.id,body.op,body.op==='spawn'?character.id:member?.id||'all',''].join('\t')+'\n';
  if(body.op==='spawn')this.connectionIntents.set(request.id,{characterId:character.id,created:request.created});
  if(body.op==='dismiss_all')this.connectionIntents.clear();
  if(body.op==='dismiss')this.connectionIntents.delete(member.id);
  this.queue.push(request);return {ok:true,id:request.id,message:'Queued; unpause to execute'};
 }
}
