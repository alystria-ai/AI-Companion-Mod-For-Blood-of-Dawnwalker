import {createHash} from 'node:crypto';
const keys=['anca','lacra'];
export function parseRelationships(raw,now=Date.now()){
 const [header,...lines]=raw.trim().split(/\r?\n/),[kind,version,stamp,epoch,romanceProfiles]=header.split('\t');
 if(kind!=='RELATIONSHIPS'||!['2','3'].includes(version)||!/^\d+$/.test(stamp)||Math.abs(now-Number(stamp)*1000)>10000||(version==='2'&&!['0','1'].includes(romanceProfiles)))throw Error('Relationship snapshot unavailable');
 if(epoch==='unavailable')return {updated:Number(stamp)*1000,characters:{}};
 if(!/^\d+$/.test(epoch)||lines.length!==2)throw Error('Incomplete relationship snapshot');
 const characters={};
 for(const line of lines){
  const [key,story,count,...tail]=line.split('\t');
  const enabled=version==='3'?tail[0]:romanceProfiles;
  const extra=version==='3'?tail.slice(1):tail;
  if(!keys.includes(key)||characters[key]||extra.length||!['0','1'].includes(enabled)||!['0','1'].includes(story)||!/^\d+$/.test(count)||Number(count)>100000)throw Error('Invalid relationship snapshot');
  characters[key]={story:story==='1',completed:Number(count),unlocked:enabled==='1'};
 }
 return {updated:Number(stamp)*1000,characters};
}
export function relationshipKnowledge(base,state,npc,now=Date.now()){
 if(!state||now-state.updated>10000)return base;
 const characters=state.characters||{},own=characters[npc],ledger=[...(base.ledger||[])],facts=[...base.facts];
 for(const key of keys){const value=characters[key];if(!value)continue;
  if(value.story)ledger.push({id:'relationship:'+key+':story',text:'Story romance completed'});
  if(value.completed)ledger.push({id:'relationship:'+key+':encounters',text:String(value.completed),counter:value.completed});
 }
 let text='';
 if(own){
  text=own.story?'Your story romance with Coen is confirmed in the currently loaded save. You remember becoming lovers.':
   own.completed?'You and Coen have shared a romantic encounter in this save. This does not establish completion of unrelated story quests.':
   own.unlocked?'Romance conversation profiles are enabled. You may begin a romantic relationship with Coen, but no previous romantic encounter is confirmed.':
   'No romance with Coen is confirmed in this save. Do not claim a past romantic encounter.';
  if(own.completed)text+=' Completed shared encounters through this mod: '+own.completed+'.';
  text+=' This current-save relationship state overrides conflicting recollections from another save. The mod does not play romance scenes or advance game time. Keep romantic requests within conversation and do not invent completed encounters.';
  if(own.story||own.completed)facts.push({id:'relationship:'+npc,text});
 }
 const revision=base.revision==='unavailable'?'unavailable':createHash('sha256').update(JSON.stringify([base.revision,characters])).digest('hex');
 return {...base,revision,ledger,facts,text:base.text+(text?'\nRELATIONSHIP\n'+text:'')};
}
export function relationshipProfiles(config,variants){
 return {...config,roster:(config.roster||[]).map(p=>{
  const variant=variants?.profiles?.find(v=>v.key===p.key&&v.baseId===p.id);
  return variant?{...p,romanceId:variant.id}:p;
 })};
}
