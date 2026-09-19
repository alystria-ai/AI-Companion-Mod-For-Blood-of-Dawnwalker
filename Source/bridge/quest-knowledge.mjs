import {characterKey,personalLore} from './companion-lore.mjs';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
const policy=JSON.parse(readFileSync(new URL('../characters/quest-knowledge.json',import.meta.url),'utf8'));
const hash=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
const policyId=hash(policy);
// Compile the reviewed branch gates once; the live journal never supplies a regex.
const rules=policy.rules.map(rule=>({...rule,
  include:rule.endingPattern?new RegExp(rule.endingPattern,'i'):null,
  exclude:rule.endingNotPattern?new RegExp(rule.endingNotPattern,'i'):null}));
export function recipient(target){
  if(!target.active)return 'anca';
  // Exact identity only: never infer an NPC from a quest mentioning their name.
  return characterKey(target);
}
export function knowledge(snapshot,npc){
  const ledger=snapshot?.quests.map(q=>({id:q.id,text:hash([q.state,q.ending]),stage:q.state,endingHash:hash(q.ending)}))||[];
  const facts=[];
  if(snapshot)for(const r of rules){
    if(r.recipient!==npc)continue;
    const q=snapshot.quests.find(q=>q.title===r.quest&&q.id.startsWith(r.idPrefix)&&q.state===r.state
      &&(!r.include||r.include.test(q.ending||''))&&(!r.exclude||!r.exclude.test(q.ending||'')));
    if(!q)continue;
    facts.push({id:r.key,text:r.text});
  }
  return {recipient:npc,revision:snapshot?hash([policyId,snapshot.revision,npc]):'unavailable',
    ledger:[{id:'knowledge-policy',text:policyId},...ledger],facts,
    text:personalLore(npc)+'\nCurrent-save knowledge specifically established for you. These facts replace prior quest context. Do not infer other quests, optional choices, secrets or outcomes. Missing information is unknown to you, not proof it did not happen. Do not claim you witnessed events merely because Coen tells you about them.\n'+(snapshot?(facts.map(f=>f.text).join('\n')||'No additional quest knowledge is established for you.'):'Journal unavailable; do not rely on older quest outcomes.')};
}
