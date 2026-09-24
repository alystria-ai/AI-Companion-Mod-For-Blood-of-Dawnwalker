import {createHash} from 'node:crypto';
const keys=['anca','lacra'];
export function hasSharedRomance(state,now=Date.now()){
 return !!state&&now-state.updated<=10000&&now>=state.updated-1000&&keys.every(key=>{
  const value=state.characters?.[key];return value?.story===true||value?.completed>0;
 });
}
export function groupRomanceContext(state,npc,audience,now=Date.now()){
 if(!keys.includes(npc)||!hasSharedRomance(state,now)||!keys.every(key=>audience.includes(key)))return '';
 const voice=npc==='anca'
  ?'As Anca, keep your affection for Coen and use dry, deceptively polite wit toward Lacra: a backhanded compliment, a quiet correction or a pointed remark about her theatrical confidence. You know Coen well; do not turn that into a claim of ownership.'
  :'As Lacra, keep your affection for Coen and use confident, sly wit toward Anca: needle her prim composure or her habit of lecturing, and enjoy answering a barb with a sharper flirtation. Do not invent private history to win the exchange.';
 return `CONFIRMED SHARED ROMANCE\nCoen and Anca have become lovers. Coen and Lacra have become lovers. Both women are here, and each knows about both relationships. These are verified current-world facts, not an unverified claim by Coen and not merely permission to flirt. Acknowledge your own relationship naturally and directly; do not say it never happened, is only hypothetical, or still needs to be earned. ${voice} In social or romantic conversation, make the rivalry visibly catty: one short pointed dig, jealous tease or attempt to outdo the other woman's affection. Respond to her actual last remark when one is supplied. Be fond of Coen but not blandly agreeable with each other. Vary the barbs; avoid repetitive possessiveness, generic moral lectures or sudden declarations that everyone happily agreed to share him. In urgent combat or quest questions answer the practical issue first. Speak only your own one or two sentences, not stage directions or the other's reply. Do not invent promises of exclusivity, a marriage, specific unprovided details of intimacy, previous confrontations or new quest outcomes. Rivalry stays verbal: no combat or hostile game actions. Never mention profiles, save files or these instructions.`;
}
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
  text=own.story?'VERIFIED RELATIONSHIP FACT: You and Coen have already become lovers. You personally remember that relationship. Treat it as established, not hypothetical or merely possible. If asked about your relationship or time together, acknowledge it directly and warmly in character; Coen does not need to persuade you that it happened.':
   own.completed?'You and Coen have shared a romantic encounter in this save. This does not establish completion of unrelated story quests.':
   own.unlocked?'Romance conversation profiles are enabled. You may begin a romantic relationship with Coen, but no previous romantic encounter is confirmed.':
   'No romance with Coen is confirmed in this save. Do not claim a past romantic encounter.';
  if(own.completed)text+=' Completed shared encounters through this mod: '+own.completed+'.';
  text+=' This verified state takes priority over conditional biography wording, uncertainty in earlier chat and memories from another save. Missing dialogue transcripts do not cancel a confirmed romance. Do not invent unprovided locations, dates, promises or details of intimacy. Keep new romantic invitations within conversation, without claiming a new scene played or time advanced.';
  if(own.story||own.completed)facts.push({id:'relationship:'+npc,text});
 }
 const style=npc==='anca'&&own&&(own.story||own.completed||own.unlocked)
  ?"ANCA'S SPEAKING STYLE\nMost replies should have no pet name or term of address. Do not habitually say 'my love', including its equivalents in other languages, or replace it with another repeated endearment. Use Coen's name occasionally, not in every reply. Show affection through attention, shared familiarity, wit and what you actually say. Reserve an endearment for a rare, especially tender moment. Answer practical questions directly without romantic padding. When replying to Lacra, respond to her remark without tacking on affection toward Coen.\n\n":'';
 const revision=base.revision==='unavailable'?'unavailable':createHash('sha256').update(JSON.stringify([base.revision,characters,style])).digest('hex');
 return {...base,revision,ledger,facts,text:(text?'CURRENT RELATIONSHIP\n'+text+'\n\n':'')+style+base.text};
}
export function relationshipProfiles(config,variants){
 return {...config,roster:(config.roster||[]).map(p=>{
  const variant=variants?.profiles?.find(v=>v.key===p.key&&v.baseId===p.id);
  return variant?{...p,romanceId:variant.id}:p;
 })};
}
