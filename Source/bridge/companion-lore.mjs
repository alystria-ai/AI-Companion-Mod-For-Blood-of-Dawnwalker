import {readFileSync} from 'node:fs';
export const lore=JSON.parse(readFileSync(new URL('../characters/companion-lore.json',import.meta.url),'utf8'));
export function characterKey(target){
 const tokens=[target.name||'',(target.voiceTag||'').split('.').at(-1)||'',(target.definition||'').split('.').at(-1)?.replace(/^Default__/,'').replace(/_C$/,'')||''].map(s=>s.toLowerCase());
 const keys=lore.characters.filter(p=>p.aliases.some(a=>tokens.includes(a.toLowerCase()))).map(p=>p.key);
 return keys.length===1?keys[0]:'';
}
export function personalLore(key){
 const p=lore.characters.find(p=>p.key===key);if(!p)return '';
 const ties=p.personalRelationships?.map(r=>`${r.name}: ${r.kind}. ${r.knowledge}`)||lore.relationships.filter(e=>e.a===key||e.b===key).map(e=>`${lore.characters.find(p=>p.key===(e.a===key?e.b:e.a))?.name}: ${e.kind}.`);
 return `Your established background: ${p.bio}\nKnown connections (not current loyalty or quest outcomes): ${ties.join(' ')}\nQuest names and walkthroughs are not evidence of completed events. A summoned companion is a mod-created actor; its presence does not reverse deaths or change the story.`;
}
export function relevance(addressed,candidate,text){
 const p=lore.characters.find(p=>p.key===candidate.characterId);
 const lower=text.toLowerCase();
 const tie=lore.relationships.find(e=>e.a===addressed&&e.b===candidate.characterId||e.b===addressed&&e.a===candidate.characterId);
 const named=p?.aliases.some(a=>new RegExp('(?:^|\\W)'+a.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'(?:$|\\W)','i').test(lower));
 const topics=(p?.topics||[]).filter(t=>lower.includes(t)).length;
 return (tie?.weight||0)+(named?120:0)+Math.min(3,topics)*25-Math.min(1200,candidate.distance||0)/120;
}
