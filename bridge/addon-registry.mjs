import {readdir,readFile,stat} from 'node:fs/promises';
import {resolve} from 'node:path';

const token=/^[a-z][a-z0-9_-]{0,47}$/;
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const ADDON_ACTIONS=['Follow','Stop Walking','Look At Player','Leave','Come Here','Attack Nearby Enemies'];
const defaultActions=ADDON_ACTIONS.slice(0,4);
// Data only. An add-on retains actor ownership; this bridge never loads its code.
export function parseAddonManifest(raw,fileId,now=Date.now()){
 if(typeof raw!=='string'||raw.length>65536||!token.test(fileId))return null;
 const lines=raw.trimEnd().split(/\r?\n/),header=lines.shift()?.split('\t');
 if(header?.length!==5||header[0]!=='COMPANION-AI'||header[1]!=='1'||header[2]!==fileId||!/^\d+$/.test(header[3])||Math.abs(now/1000-Number(header[3]))>8||!token.test(header[4]))return null;
 if(lines.pop()!==`END\t${header[4]}`||lines.length>32)return null;
 const ids=new Set(),actors=new Set(),entries=[];
 for(const line of lines){
  const [id,actor,actorInstance,world,player,name,profileId,context,cameraLease,silentReplies,actionList,localActionsOnly,...extra]=line.split('\t');
  const actions=actionList===undefined?defaultActions:actionList===''?[]:actionList.split(',');
  if(extra.length||(localActionsOnly!==undefined&&localActionsOnly!=='0'&&localActionsOnly!=='1')||(cameraLease!==undefined&&cameraLease!=='0'&&cameraLease!=='1')||(silentReplies!==undefined&&silentReplies!=='0'&&silentReplies!=='1')||actions.length>ADDON_ACTIONS.length||new Set(actions).size!==actions.length||actions.some(a=>!ADDON_ACTIONS.includes(a))||!token.test(id)||ids.has(id)||!actor||actor.length>512||!(/^(?:0x)?[0-9a-f]{1,32}$/i.test(actorInstance||''))||!world||world.length>512||!player||player.length>512||!name||name.length>100||!uuid.test(profileId)||context===undefined||context.length>2400||actors.has(actor))return null;
  ids.add(id);actors.add(actor);entries.push({addon:fileId,id,actor,actorInstance,world,player,name,profileId,context,cameraLease:cameraLease==='1',silentReplies:silentReplies==='1'||localActionsOnly==='1',localActionsOnly:localActionsOnly==='1',actions});
 }
 return entries;
}
export class AddonRegistry{
 constructor(runtime){this.runtime=runtime;this.entries=[];this.next=0;this.cached=new Map();}
 async tick(now=Date.now()){
  if(now<this.next)return null;this.next=now+1000;
  const files=(await readdir(this.runtime).catch(()=>[])).filter(f=>/^addon-[a-z][a-z0-9_-]{0,47}\.tsv$/.test(f)&&f!=='addon-registry.tsv'&&!/^addon-(action|ui|camera)-/.test(f)).sort().slice(0,16);
  const records=await Promise.all(files.map(async file=>{
   const path=resolve(this.runtime,file);const info=await stat(path).catch(()=>null);
   if(!info?.isFile()||info.size>65536||Math.abs(now-info.mtimeMs)>12000){this.cached.delete(file);return [];}
   const parsed=parseAddonManifest(await readFile(path,'utf8').catch(()=>''),file.slice(6,-4),now);
   if(parsed){this.cached.set(file,{at:now,entries:parsed});return parsed;}
   // A writer may be between header and footer. Retain the last complete
   // heartbeat briefly; repeated invalid data cannot extend this grace period.
   const old=this.cached.get(file);return old&&now-old.at<3000?old.entries:[];
  }));
  const seen=new Set();this.entries=records.flat().filter(e=>{if(seen.has(e.actor))return false;seen.add(e.actor);return true;}).slice(0,128);
  for(const file of this.cached.keys())if(!files.includes(file))this.cached.delete(file);
  return ['COMPANION-AI\t1\t'+Math.floor(now/1000),...this.entries.map(e=>[e.addon,e.id,e.actor,e.actorInstance,e.world,e.player,e.name,e.profileId,e.context,e.cameraLease?'1':'0',e.silentReplies?'1':'0',e.actions.join(','),e.localActionsOnly?'1':'0'].join('\t')),'END'].join('\n');
 }
 profile(target){
  if(!target.active||!target.addon||!target.addonActor)return null;
  const entry=this.entries.find(e=>e.addon===target.addon&&e.id===target.addonActor&&e.actor===target.actor&&e.actorInstance===target.addonInstance);
  return entry?{key:'addon:'+entry.addon+':'+entry.id+':'+entry.profileId,id:entry.profileId,name:entry.name,kind:'main',gender:'',aliases:[],context:entry.context,silentReplies:entry.silentReplies,localActionsOnly:entry.localActionsOnly,actions:entry.actions}:null;
 }
}
