import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {knowledge,recipient} from '../bridge/quest-knowledge.mjs';
const policy=JSON.parse(readFileSync(new URL('../characters/quest-knowledge.json',import.meta.url),'utf8'));
const recipients=['anca','lacra','marat','brencis','xanthe','ambrus','bakir','matriarch','leonica','ocha','vicho','drogos','sara','catalin','pieter','vladimir','isbrand','coen',...Array.from({length:5},(_,i)=>'male-'+(i+1)),...Array.from({length:5},(_,i)=>'female-'+(i+1))];
const quest=(title,idPrefix,ending,state='EQS_Success')=>({id:idPrefix+'A'.repeat(32),title,state,ending});
const snapshot=(...quests)=>({revision:'fixture',quests});
const ids=(s,npc)=>knowledge(s,npc).facts.map(f=>f.id).sort();
const prose=(s,npc)=>knowledge(s,npc).facts.map(f=>f.text).join('\n');

// Authored fixture summaries preserve only short matching fragments from reviewed
// journal outcomes. IDs/titles and expected recipients are independent of policy.
const cases=[
 ['herbs','Withering Away','q002_herbs','Medicine was supplied.',{anca:['anca-1']}],
 ['Laslea','Smoke and Ashes','q101_laslea','The village is ruined.',{anca:['anca-2']}],
 ['convent encounter','Echoes of Silenced Bells','q101_journal_','Leonica was responsible.',{anca:['anca-3'],leonica:['leonica-confrontation']}],
 ['ritual allowed','Echoes of Silenced Bells','q101_journal_', "Leonica left a plan. I didn't stop her.",{anca:['anca-3','anca-ritual-performed'],leonica:['leonica-confrontation']}],
 ['ritual refused','Echoes of Silenced Bells','q101_journal_', "Leonica left a plan, but I couldn't allow it.",{anca:['anca-3','anca-ritual-prevented'],leonica:['leonica-confrontation']}],
 ['book research','Between the Words','q101_ending','We found the sword lead.',{anca:['anca-4']}],
 ['ruins','Where Old Devils Lie','sq721_Anca','The riddle led into ruins.',{anca:['anca-ruins']}],
 ['Font to Anca','Stronger Than Achilles','sq721_Anca_Trials','I let her use the Font.',{anca:['anca-font-used']}],
 ['Font to Coen','Stronger Than Achilles','sq721_Anca_Trials','At the Font I decided to use it.',{anca:['anca-font-coen']}],
 ['Font destroyed','Stronger Than Achilles','sq721_Anca_Trials','At the Font I destroyed it.',{anca:['anca-font-destroyed']}],
 ['mountain lead','A Friend Like This','q103_journal_investigation','We should find the village.',{lacra:['lacra-5']}],
 ['Elder report','Song of the Mountain','q103_journal_uriashes','The Elder told us the way.',{lacra:['lacra-6'],matriarch:['matriarch-directions']}],
 ['Isbrand rescued','Hive and Seek','q103_journal_caves','We returned to the abandoned fort.',{lacra:['lacra-7'],isbrand:['isbrand-rescued']}],
 ['memory journey','Our Rotten Roots','q104_journal','Isbrand gave us the clue.',{lacra:['lacra-8'],isbrand:['isbrand-broken-shade']}],
 ['mandrake shared','The Night of Horrors','sq717_journal','A mandrake was in Kallias’s lair and absorbed power passed to us.',{lacra:['lacra-mandrake-shared']}],
 ['mandrake declined','The Night of Horrors','sq717_journal','Inside Kallias’s lair, Lacra absorbed the mandrake. I wanted nothing of it.',{lacra:['lacra-mandrake-alone']}],
 ['camp introduction','Shadows in the Woods','Q105_Journal_after_Guard_Post','I spoke with Crake at camp.',{marat:['marat-introduction'],sara:['sara-rescue'],drogos:['drogos-camp-meeting']}],
 ['induction before report','Where Loyalty Lies','q106_journal_01_Joining_rebels','Crake needs to hear the findings.',{marat:['marat-induction'],sara:['sara-hideout-escort']}],
 ['scout report','What Hunts the Night','q106_journal_02_Troubles_in_The_Middens','The inquiry continued.',{marat:['marat-scouts-reported']}],
 ['alchemist search','What Moves the Dead','q106_journal_03_Mystery_Alchemist','The book was by Silas.',{marat:['marat-dead-investigation']}],
 ['hex report','Who Pulls the Strings','q106_journal_04_Astrologers_Tower','I showed Marat the result.',{marat:['marat-hex-reported']}],
 ['outpost','Rise at Dawn','q302_rebel_attack_outpost','The army entered.',{catalin:['catalin-outpost'],marat:['marat-outpost']}],
 ['Simeon theory','A Study in Crimson','sq714_vampireally','Doctor Simeon transformed.',{vicho:['vicho-simeon']}],
 ['Vicho chooses life','A Study in Crimson','sq714_vampireally','After I confronted him, he would keep on living; I promised human blood.',{vicho:['vicho-truth-blood-promise']}],
 ['Vicho supported at dawn','A Study in Crimson','sq714_vampireally','After I confronted him, he awaited the morning sun. I stood beside him.',{vicho:['vicho-truth-dawn-supported']}],
 ['Vicho left at dawn','A Study in Crimson','sq714_vampireally','After I confronted him, he awaited the morning sun. I walked away.',{vicho:['vicho-truth-dawn-alone']}],
 ['Ocha returns','The Heart Wants What It Wants','sq716_journal','Ocha decided to return home.',{ocha:['ocha-shared-resolution','ocha-home']}],
 ['Ocha stays','The Heart Wants What It Wants','sq716_journal','Ocha decided to stay within Svartrau.',{ocha:['ocha-shared-resolution','ocha-city']}],
 ['Ocha travels','The Heart Wants What It Wants','sq716_journal','Ocha decided she wouldn’t return home; she would leave the valley.',{ocha:['ocha-shared-resolution','ocha-world']}],
 ['mother learns return',"A Mother's Plea",'sq716_matriarch','Ocha decided to return to her people.',{matriarch:['matriarch-ocha-report','matriarch-ocha-home']}],
 ['mother learns independence',"A Mother's Plea",'sq716_matriarch','Ocha decided not to return home.',{matriarch:['matriarch-ocha-report','matriarch-ocha-independent']}],
 ['Esme survives','Sacred Covenant','q002_mass','Mum made it through the ordeal.',{pieter:['pieter-mass-esme-survived'],brencis:['brencis-mass-esme-survived']}],
 ['Esme killed','Sacred Covenant','q002_mass','She is dead by Brencis’s hand.',{pieter:['pieter-mass-esme-killed'],brencis:['brencis-mass-esme-killed']}],
 ['sparring','Like Father, Like Son','q002_sparring','My father spoke.',{pieter:['pieter-sparring']}],
 ['Brencis wins','Bad Blood','q001_journal','I failed to stop Brencis.',{brencis:['brencis-laslea'],pieter:['pieter-laslea'],vladimir:['vladimir-mines']}],
 ['crucifix','Disturbed','sq001_journal','The dispute ended.',{vladimir:['vladimir-crucifix']}],
 ['Ambrus duel','The Gilded Gauntlet','sq708a_journal','Ambrus is dead.',{ambrus:['ambrus-duel']}],
 ['Bakir encounter','The Lunar Game','sq710_journal','The plan let me kill Bakir.',{bakir:['bakir-tournament']}],
 ['Xanthe generic','The Cycle of Love','sq709_xanthe','The encounter ended.',{xanthe:['xanthe-confrontation']}],
 ['Xanthe keep','The Cycle of Love','sq709_xanthe','I was inside Xanthe’s keep.',{xanthe:['xanthe-confrontation','xanthe-keep-confrontation']}],
];
for(const [label,title,prefix,ending,expected] of cases)test(label+': exact knowledge reaches only its participants',()=>{
 const q=quest(title,prefix,ending),s=snapshot(q);
 for(const npc of recipients)assert.deepEqual(ids(s,npc),(expected[npc]||[]).sort(),label+' -> '+npc);
 // Every supported path is checked against wrong identity, title and state.
 for(const bad of [{...q,id:'unrelated'+q.id},{...q,title:q.title+' (different)'},{...q,state:'EQS_Active'},{...q,state:'EQS_Failure'}])
  for(const npc of Object.keys(expected))assert.deepEqual(ids(snapshot(bad),npc),[],label+' must fail closed');
});
test('all reviewed grants have an independent positive fixture',()=>{
 const covered=[...new Set(cases.flatMap(c=>Object.values(c[4]).flat()))].sort();
 assert.deepEqual(policy.rules.map(r=>r.key).sort(),covered);
});
test('unknown and abandoned endings do not become optional memories',()=>{
 const absent=[
  ['Echoes of Silenced Bells','q101_journal_','We ignored the books.','anca'],
  ['Stronger Than Achilles','sq721_Anca_Trials','Anca was left behind and is dead.','anca'],
  ['Stronger Than Achilles','sq721_Anca_Trials','There is no time to finish.','anca'],
  ['The Night of Horrors','sq717_journal','I chose to forfeit the search.','lacra'],
  ['Where Loyalty Lies','q106_journal_01_Joining_rebels','We have not investigated.','marat'],
  ['The Heart Wants What It Wants','sq716_journal','Ocha died.','ocha'],
  ['The Heart Wants What It Wants','sq716_journal','Ocha decided something unknown.','ocha'],
  ['The Heart Wants What It Wants','sq716_journal','The work was never finished.','ocha'],
  ["A Mother's Plea",'sq716_matriarch','I never fulfilled the request.','matriarch'],
  ['A Study in Crimson','sq714_vampireally','I learned the truth. Should I have told him?','vicho'],
  ['Sacred Covenant','q002_mass','The service finished.','pieter'],
  ['Sacred Covenant','q002_mass','The service finished.','brencis'],
 ];
 for(const [title,prefix,ending,npc] of absent)assert.deepEqual(ids(snapshot(quest(title,prefix,ending)),npc),[],title+': '+ending);
});
test('explicit negative gates reject contradictory branch evidence',()=>{
 const rejected=[
  ['Echoes of Silenced Bells','q101_journal_', "Leonica: I didn't stop her, but I couldn't allow it.",'anca',['anca-ritual-performed','anca-ritual-prevented']],
  ['Stronger Than Achilles','sq721_Anca_Trials','I let her use the Font. I decided to use it. I destroyed it.','anca',['anca-font-used','anca-font-coen','anca-font-destroyed']],
  ['Stronger Than Achilles','sq721_Anca_Trials','I let her use the Font. Anca is dead.','anca',['anca-font-used']],
  ['The Night of Horrors','sq717_journal','A mandrake in Kallias’s lair and absorbed power; Lacra absorbed it and I wanted nothing.','lacra',['lacra-mandrake-shared','lacra-mandrake-alone']],
  ['The Night of Horrors','sq717_journal','A mandrake in Kallias’s lair and absorbed power; we forfeit.','lacra',['lacra-mandrake-shared']],
  ['The Night of Horrors','sq717_journal','Kallias: Lacra absorbed it, I wanted nothing; forfeit.','lacra',['lacra-mandrake-alone']],
  ['The Heart Wants What It Wants','sq716_journal','Ocha decided to return. Ocha decided to stay in Svartrau and leave the valley.','ocha',['ocha-home','ocha-city']],
  ["A Mother's Plea",'sq716_matriarch','Ocha decided to return. Ocha decided not to return.','matriarch',['matriarch-ocha-home','matriarch-ocha-independent']],
  ['A Study in Crimson','sq714_vampireally','After I confronted him: keep on living with human blood. Then morning sun: stood beside him and walked away.','vicho',['vicho-truth-blood-promise','vicho-truth-dawn-supported','vicho-truth-dawn-alone']],
  ['Sacred Covenant','q002_mass','Mum made it through, but dead by Brencis.','pieter',['pieter-mass-esme-survived','pieter-mass-esme-killed']],
  ['Sacred Covenant','q002_mass','Mum made it through, but dead by Brencis.','brencis',['brencis-mass-esme-survived','brencis-mass-esme-killed']],
  ['The Cycle of Love','sq709_xanthe','I was inside Xanthe’s keep, then a cathedral.','xanthe',['xanthe-keep-confrontation']],
 ];
 for(const [title,prefix,ending,npc,blocked] of rejected)for(const id of blocked)
  assert.ok(!ids(snapshot(quest(title,prefix,ending)),npc).includes(id),id);
});
test('clan vengeance overrides every Ocha destination and both reported choices',()=>{
 const ocha=cases.filter(c=>c[0].startsWith('Ocha '));
 const mother=cases.filter(c=>c[0].startsWith('mother learns'));
 for(const [,,prefix,ending,expected] of [...ocha,...mother])
  for(const hostile of ['Ocha died','She wanted vengeance for her clan','She planned revenge'])
   for(const npc of Object.keys(expected)){
    const title=npc==='ocha'?'The Heart Wants What It Wants':"A Mother's Plea";
    assert.deepEqual(ids(snapshot(quest(title,prefix,ending+' '+hostile)),npc),[]);
   }
});
test('Ocha private choices do not report themselves to her mother',()=>{
 const s=snapshot(quest('The Heart Wants What It Wants','sq716_journal','Ocha decided to stay in Svartrau.'));
 assert.equal(ids(s,'ocha').length,2);assert.deepEqual(ids(s,'matriarch'),[]);
 s.quests.push(quest("A Mother's Plea",'sq716_matriarch','Ocha decided not to return.'));
 assert.deepEqual(ids(s,'matriarch'),['matriarch-ocha-independent','matriarch-ocha-report']);
 assert.doesNotMatch(prose(s,'matriarch'),/chose to remain|Andrei.s death/);
});
test('ritual choice never becomes Leonica witnessing events after her defeat',()=>{
 const allowed=snapshot(quest('Echoes of Silenced Bells','q101_journal_', "Leonica: I didn't stop her."));
 const blocked=snapshot(quest('Echoes of Silenced Bells','q101_journal_', "Leonica: I couldn't allow it."));
 assert.deepEqual(ids(allowed,'leonica'),['leonica-confrontation']);
 assert.deepEqual(ids(blocked,'leonica'),['leonica-confrontation']);
});
test('induction grants no scout report, private rescue or hideout reunion to Vladimir',()=>{
 const s=snapshot(quest('Where Loyalty Lies','q106_journal_01_Joining_rebels','Crake needs to hear the news.'));
 assert.deepEqual(ids(s,'marat'),['marat-induction']);
 assert.deepEqual(ids(s,'vladimir'),[]);
 s.quests.push(quest('What Hunts the Night','q106_journal_02_Troubles_in_The_Middens','The investigation finished.'));
 assert.deepEqual(ids(s,'marat'),['marat-induction','marat-scouts-reported']);
 assert.deepEqual(ids(s,'sara'),['sara-hideout-escort']);
 assert.deepEqual(ids(s,'drogos'),[]);
});
test('Xanthe cathedral route cannot acquire a keep visit or accepted bargain',()=>{
 const s=snapshot(quest('The Cycle of Love','sq709_xanthe','Coen confronted Xanthe in the cathedral.'));
 assert.deepEqual(ids(s,'xanthe'),['xanthe-confrontation']);
 assert.doesNotMatch(prose(s,'xanthe'),/reached.*keep|accepted.*bargain|agreed to cooperate/);
 assert.deepEqual(ids(s,'brencis'),[]);
});
test('truth concealed from Vicho remains absent even when the player journal contains it',()=>{
 const ending='Simeon was investigated. PRIVATE_DISCOVERY: Vicho did it. Should I have told him?';
 const s=snapshot(quest('A Study in Crimson','sq714_vampireally',ending));
 assert.deepEqual(ids(s,'vicho'),['vicho-simeon']);
 assert.doesNotMatch(prose(s,'vicho'),/PRIVATE_DISCOVERY|Coen confronted you with/);
});
test('branch changes and rollback replace current-save facts; biography is a separate layer',()=>{
 const a=snapshot(quest('Stronger Than Achilles','sq721_Anca_Trials','I let her use the Font.'));
 const b={revision:'older-save',quests:[quest('Stronger Than Achilles','sq721_Anca_Trials','The Font: I destroyed it.')]};
 assert.deepEqual(ids(a,'anca'),['anca-font-used']);
 assert.deepEqual(ids(b,'anca'),['anca-font-destroyed']);
 assert.notEqual(knowledge(a,'anca').revision,knowledge(b,'anca').revision);
 assert.deepEqual(knowledge(null,'anca').facts,[]);
 assert.equal(knowledge(null,'anca').revision,'unavailable');
 assert.match(knowledge(null,'anca').text,/Journal unavailable/);
});
test('NPC facts exclude private journal prose; switching NPC preserves the rollback ledger',()=>{
 const s=snapshot(
  quest('Between the Words','q101_ending','sword PRIVATE JOURNAL'),
  quest('Hive and Seek','q103_journal_caves','abandoned fort'),
  quest('Our Rotten Roots','q104_journal','Isbrand secret optional vision'));
 const a=knowledge(s,'anca'),l=knowledge(s,'lacra');
 assert.deepEqual(a.facts.map(f=>f.id),['anca-4']);
 assert.doesNotMatch(a.facts.map(f=>f.text).join('\n'),/Isbrand|PRIVATE/);
 assert.equal(l.facts.length,2);assert.doesNotMatch(l.facts.map(f=>f.text).join('\n'),/sword|secret optional vision/);
 assert.deepEqual(a.ledger,l.ledger);assert.notEqual(a.revision,l.revision);
 assert.equal(a.ledger[0].id,'knowledge-policy');
 assert.deepEqual(ids(s,'male-1'),[]);assert.deepEqual(ids(s,'brencis'),[]);
});
test('a nonmatching journal instance cannot hide a later matching instance, and grants are unique',()=>{
 const wrong=quest('Stronger Than Achilles','sq721_Anca_Trials','The outcome is unknown.');
 const right={...quest('Stronger Than Achilles','sq721_Anca_Trials','I let her use the Font.'),id:'sq721_Anca_Trials'+'B'.repeat(32)};
 assert.deepEqual(ids(snapshot(wrong,right,right),'anca'),['anca-font-used']);
});
test('straight and typographic apostrophes both recognize the reviewed decisions',()=>{
 for(const mark of ["'",'’']){
  assert.ok(ids(snapshot(quest('Echoes of Silenced Bells','q101_journal_','Leonica: I didn'+mark+'t stop her.')),'anca').includes('anca-ritual-performed'));
  assert.ok(ids(snapshot(quest('Echoes of Silenced Bells','q101_journal_','Leonica: I couldn'+mark+'t allow it.')),'anca').includes('anca-ritual-prevented'));
  assert.ok(ids(snapshot(quest('The Heart Wants What It Wants','sq716_journal','Ocha decided she wouldn'+mark+'t return and would leave the valley.')),'ocha').includes('ocha-world'));
  assert.ok(ids(snapshot(quest('The Cycle of Love','sq709_xanthe','I was inside Xanthe'+mark+'s keep.')),'xanthe').includes('xanthe-keep-confrontation'));
 }
});
test('pending candidates never enter runtime facts just because a matching title completes',()=>{
 const pending=snapshot(
  quest('Buried Past','sq719_pieters_past','Pieter donated gold and Coen read every private letter.'),
  quest('Midnight Reckoning','q301_journal','My family is safe.'),
  quest('A Deal with the Devil','sq715_journal','The deal was accepted.'),
  quest('Distant Shadows','unmapped','Coen learned about Ascar.'),
  quest('Unquenchable Thirst','unmapped','Coen delivered blood.'));
 for(const npc of recipients)assert.deepEqual(ids(pending,npc),[]);
});
test('recipient requires exact identity and recognizes Crake alias',()=>{
 assert.equal(recipient({active:true,name:'Crake'}),'marat');
 assert.equal(recipient({active:true,name:'Anca fan'}),'');
 assert.equal(recipient({active:true,name:'Anca',voiceTag:'vt.lacra'}),'');
 assert.equal(recipient({active:false}),'anca');
});
