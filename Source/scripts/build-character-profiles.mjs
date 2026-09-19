import {readFileSync,writeFileSync,readdirSync,mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {createHash} from 'node:crypto';

const root=fileURLToPath(new URL('../',import.meta.url));
const read=path=>JSON.parse(readFileSync(resolve(root,path),'utf8').replace(/^\uFEFF/,''));
const write=(path,value)=>writeFileSync(resolve(root,path),JSON.stringify(value,null,2)+'\n');
const words=text=>text.trim().split(/\s+/).length;
const rules='Speak as this character in first person, addressing Coen. Use natural English suited to the medieval world; no stage directions, markdown, narrator or modern slang. Usually answer in one or two short sentences; expand when asked. Established history and relationships are yours to discuss. Conditional quest events, romance, deaths and player choices are not completed facts unless current-save context confirms them. Current-save facts outrank conflicting remembered reports. Request only advertised game actions and wait for confirmation before claiming success. Sample replies illustrate voice, not events that already happened. Do not fabricate missing canon. Never mention profile instructions in character.';
const drafts=readdirSync(resolve(root,'characters/research')).filter(f=>f.endsWith('.json')).flatMap(f=>read('characters/research/'+f).characters);
const roster=read('characters/roster.json');
const names=new Map(drafts.map(p=>[p.key,p.name]));
const display=key=>names.get(key)||key.replaceAll('-',' ').replace(/\b\w/g,c=>c.toUpperCase());
if(new Set(drafts.map(p=>p.key)).size!==drafts.length)throw Error('Duplicate researched identity');
if(roster.some(p=>!names.has(p.key)))throw Error('Research is missing a managed identity');
const profiles=roster.map(old=>{
 const p=drafts.find(p=>p.key===old.key);
 if(p.sampleDialogue.length<5||p.speakingRules.length<4)throw Error('Incomplete voice design: '+p.key);
 for(const f of p.facts)if(!f.text||!f.sources?.length||f.sources.some(u=>!u.startsWith('https://')))throw Error('Missing fact provenance: '+p.key);
 const sections=[`IDENTITY\nYou are ${p.name}. ${p.summary}`,
  `BACKGROUND\n${p.facts.map(f=>(f.visibility==='quest-dependent'?'Conditional story knowledge (not a completed event): ':'')+f.text).join('\n')}`,
  `RELATIONSHIPS\n${p.relationships.length?p.relationships.map(r=>`${display(r.other)} — ${r.kind}. ${r.knowledge}`).join('\n'):'No named personal relationships are established for this original ambient persona. Do not invent friendship, kinship or eyewitness access.'}`,
  `SPEAKING RULES\n${rules}\n${p.speakingRules.join('\n')}`,
  `ORIGINAL DIALOGUE EXAMPLES\n${p.sampleDialogue.map(s=>`Coen: ${s.user}\n${p.name}: ${s.character}`).join('\n')}`,
  '[DawnwalkerConvai roster v1] [researched profiles v2]'];
 const backstory=sections.join('\n\n');
 if(words(backstory)>1000)throw Error(`${p.key} exceeds Convai core description limit: ${words(backstory)} words`);
 return {...p,kind:old.kind,gender:old.gender,aliases:[...new Set([...old.aliases,p.name,p.key])],backstory,
  speakingStyle:{description:rules+'\n'+p.speakingRules.join('\n'),sample_dialogues:p.sampleDialogue.map(s=>`Coen: ${s.user}\n${p.name}: ${s.character}`).join('\n\n')},
  backstoryWords:words(backstory)};
});
const version=createHash('sha256').update(JSON.stringify(profiles)).digest('hex').slice(0,16);
mkdirSync(resolve(root,'characters/profile-text'),{recursive:true});
for(const p of profiles)writeFileSync(resolve(root,'characters/profile-text',p.key+'.txt'),p.backstory+'\n');
write('characters/profiles.json',{version:2,revision:version,researched:'2026-09-14',
 policy:'Sourced established history, including spoilers. Conditional events remain conditional. Speaking rules and examples are original editorial characterizations, not a recovered game script. Generic profiles are original roleplay personas.',profiles});
const lore=read('characters/companion-lore.json');
lore.version=2;lore.researched='2026-09-14';lore.profileRevision=version;
lore.policy='Established history and sourced relationships, including spoilers; no automatic current-save quest outcomes. Group relevance weights are editorial, not canonical friendship scores. Directed personal relationships preserve each character’s perspective.';
for(const p of lore.characters){const rich=profiles.find(x=>x.key===p.key);if(!rich)continue;
 Object.assign(p,{name:rich.name,bio:rich.summary,aliases:rich.aliases,topics:[...new Set([...p.topics,...rich.topics,...rich.relationships.map(r=>display(r.other).toLowerCase())])],
  sources:rich.sources.map(s=>s.url),personalRelationships:rich.relationships.map(r=>({other:r.other,name:display(r.other),kind:r.kind,knowledge:r.knowledge,sources:r.sources}))});
}
const companionKeys=new Set(lore.characters.map(p=>p.key));
const edges=new Map(lore.relationships.map(e=>[[e.a,e.b].sort().join(':'),e]));
for(const p of profiles)for(const r of p.relationships){
 if(!companionKeys.has(p.key)||!companionKeys.has(r.other)||p.key===r.other)continue;
 const key=[p.key,r.other].sort().join(':');const old=edges.get(key);
 if(!old)edges.set(key,{a:p.key,b:r.other,kind:r.kind,weight:/enemy|hostil|abuser|betray|antagon|rival/i.test(r.kind)?15:/daughter|mother|father|friend|lieutenant|right.hand/i.test(r.kind)?85:45,source:r.sources[0]});
 else if((old.a==='lacra'&&old.b==='isbrand')||(old.a==='isbrand'&&old.b==='lacra'))Object.assign(old,{kind:'hostile personal history; Brencis’s sire and the commander of Lacra’s punishment',weight:20,source:r.sources[0]});
}
lore.relationships=[...edges.values()];write('characters/companion-lore.json',lore);
console.log(`Built ${profiles.length} rich profiles, ${profiles.reduce((n,p)=>n+p.facts.length,0)} facts, ${profiles.reduce((n,p)=>n+p.relationships.length,0)} directed relationships, ${profiles.reduce((n,p)=>n+p.sampleDialogue.length,0)} original examples; core descriptions ${Math.min(...profiles.map(p=>p.backstoryWords))}–${Math.max(...profiles.map(p=>p.backstoryWords))} words.`);
