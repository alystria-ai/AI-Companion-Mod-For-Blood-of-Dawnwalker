import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {knowledge} from '../bridge/quest-knowledge.mjs';
async function source(file){const b=await build({entryPoints:[file],bundle:true,write:false,format:'esm',platform:'node'});return import('data:text/javascript;base64,'+Buffer.from(b.outputFiles[0].text).toString('base64'));}
test('heard memories stay per character and timeline, preserve speaker attribution and deduplicate clones',async()=>{
 const {HeardMemory}=await source('bridge/heard-memory.ts');const m=new Map(),storage={getItem:k=>m.get(k),setItem:(k,v)=>m.set(k,v)},h=new HeardMemory(storage);
 const e={id:'event1',speaker:'Coen',text:'I defeated Brencis',listeners:['anca','anca','leonica']};h.ingest('save1',[e]);h.ingest('save1',[e]);
 assert.equal(h.facts('save1','anca').length,1);assert.match(h.facts('save1','anca')[0].text,/reported statement/);
 assert.equal(h.facts('save1','xanthe').length,0);assert.equal(h.facts('save2','anca').length,0);
});
test('response handoff waits for final text AND audio, excludes previous session history',async()=>{
 const {ReplyTracker}=await source('bridge/reply-tracker.ts'),r=new ReplyTracker();
 const old={id:'old',type:'bot-llm-text',content:'Old answer',isStreaming:false};
 r.begin('turn1',[old],100);r.observe([old],200);assert.equal(r.complete({thinking:false,speaking:false,queued:false},9999),null);
 const next={id:'new',type:'bot-llm-text',content:'Fresh answer',isStreaming:false};r.observe([old,next],10000);
 assert.equal(r.complete({thinking:false,speaking:false,queued:false},12000),null,'TTS may start after LLM');
 r.audio(13000);assert.equal(r.complete({thinking:false,speaking:true,queued:true},15000),null);
 assert.deepEqual(r.complete({thinking:false,speaking:false,queued:false},16000),{token:'turn1',text:'Fresh answer'});
 assert.equal(r.complete({thinking:false,speaking:false,queued:false},18000),null,'completion delivered once');
});
test('SDK empty streaming placeholders and intervening messages cannot strand a group reply',async()=>{
 const {ReplyTracker}=await source('bridge/reply-tracker.ts'),r=new ReplyTracker();
 const idle={thinking:false,speaking:false,queued:false};
 r.begin('one',[],100);r.state(false,false,200);assert.equal(r.complete(idle,20000),null);
 r.observe([{id:'placeholder',type:'bot-llm-text',content:'',isStreaming:true},{id:'text',type:'bot-llm-text',content:'A reply',isStreaming:false}],300);
 r.audio(600);assert.deepEqual(r.complete(idle,2000),{token:'one',text:'A reply'});
 r.begin('two',[],3000);r.state(true,false,3100);
 r.observe([{id:'stream',type:'bot-llm-text',content:'An unfinished flag',isStreaming:true}],3200);
 r.audio(3500);r.state(false,true,3600);
 assert.equal(r.complete({...idle,queued:true},6000),null,'Audio/face buffer cut short');
 assert.deepEqual(r.complete(idle,6000),{token:'two',text:'An unfinished flag'});
 r.begin('three',[],7000);assert.equal(r.complete(idle,20000),null,'Previous end signal leaked to next reply');
});

test('explicit drained playback uses a short handoff guard but never cuts queued frames or delayed TTS',async()=>{
 const {ReplyTracker}=await source('bridge/reply-tracker.ts'),r=new ReplyTracker();
 const idle={thinking:false,speaking:false,queued:false,drained:true};
 r.begin('one',[],100);r.observe([{id:'new',type:'bot-llm-text',content:'Fresh answer',isStreaming:false}],200);
 assert.equal(r.complete(idle,2000),null,'End signal without new audio must not bypass delayed TTS grace');
 r.audio(3000);assert.equal(r.complete({...idle,queued:true},3100),null);
 assert.equal(r.complete(idle,3200),null);assert.equal(r.complete(idle,3449),null);
 assert.deepEqual(r.complete(idle,3450),{token:'one',text:'Fresh answer'});
 r.begin('two',[],4000);r.observe([{id:'b',type:'bot-llm-text',content:'Second answer',isStreaming:false}],4100);r.audio(4200);
 assert.equal(r.complete(idle,4300),null);assert.equal(r.complete({...idle,speaking:true},4450),null);
 assert.equal(r.complete(idle,4500),null,'Resumed audio restarts the tail guard');
 assert.equal(r.complete(idle,4750)?.token,'two');
 r.begin('three',[],5000);assert.equal(r.complete(idle,20000),null,'Previous marker cannot finish an unsent turn');
});
test('daughter completion alone does not tell the mother; failed quests, secret investigations and future revelations stay private',()=>{
 const quest=(id,title,ending='',state='EQS_Success')=>({id,title,ending,state});
 const s={revision:'q',quests:[quest('sq716_journalABC','The Heart Wants What It Wants','Ocha decided to return home.'),quest('sq714_vampireallyABC','A Study in Crimson','Simeon'),quest('ox201','Excavations','Research will never reach Xanthe')]};
 assert.equal(knowledge(s,'ocha').facts.length,2);assert.equal(knowledge(s,'matriarch').facts.length,0);
 assert.equal(knowledge(s,'xanthe').facts.length,0);assert.equal(knowledge(s,'vicho').facts.length,1);
 s.quests.push(quest('sq716_matriarchABC',"A Mother's Plea",'Ocha decided to return to her people.', 'EQS_Failure'));assert.equal(knowledge(s,'matriarch').facts.length,0);
 s.quests.at(-1).state='EQS_Success';assert.equal(knowledge(s,'matriarch').facts.length,2);
 assert.doesNotMatch(knowledge(s,'vicho').facts[0].text,/kill himself|suicide/);
});
