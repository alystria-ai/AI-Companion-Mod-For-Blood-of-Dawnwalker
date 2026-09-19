import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const bundle=await build({entryPoints:['bridge/quest-memory.ts'],bundle:true,write:false,format:'esm'});
const {QuestMemory}=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].text).toString('base64'));
test('cloud quest facts deduplicate while one player identity survives character changes and local rollbacks',async()=>{
 const data=new Map(),storage={getItem:k=>data.get(k)||null,setItem:(k,v)=>data.set(k,v)};let uuid=0;
 const memory=new QuestMemory(storage,()=>String(++uuid));const facts=[{id:'q1',text:'Coen completed q1.'}];
 assert.equal(memory.observe(facts),false);const firstUser=memory.user('anca');let writes=0;
 const manager={addMemories:async rows=>{writes++;assert.deepEqual(rows,['Coen completed q1.']);}};
 await memory.sync(manager,firstUser,facts,100000);await memory.sync(manager,firstUser,facts,130000);assert.equal(writes,1);
 const restored=new QuestMemory(storage,()=>String(++uuid));assert.equal(restored.user('anca'),firstUser);
 const firstTimeline=restored.timeline;
 assert.equal(restored.observe([]),true);assert.notEqual(restored.timeline,firstTimeline);
 assert.equal(restored.user('anca'),firstUser);
 assert.equal(restored.user('villager1'),restored.user('villager2'));
});
test('failed cloud writes remain pending and use retry backoff',async()=>{
 const data=new Map(),memory=new QuestMemory({getItem:k=>data.get(k)||null,setItem:(k,v)=>data.set(k,v)},()=> 'id');let calls=0;
 const manager={addMemories:async()=>{calls++;throw Error('offline');}},facts=[{id:'q',text:'Resolved'}];
 await assert.rejects(memory.sync(manager,'scope',facts,100000));await memory.sync(manager,'scope',facts,110000);assert.equal(calls,1);
 await assert.rejects(memory.sync(manager,'scope',facts,161000));assert.equal(calls,2);
});

test('normal quest completion retains history; rewinds branch the local timeline without allocating an end-user',()=>{
 const data=new Map();let seq=0;
 const memory=new QuestMemory({getItem:k=>data.get(k)||null,setItem:(k,v)=>data.set(k,v)},()=>String(++seq));
 const active={id:'q1',text:'active-hash',stage:'EQS_Active',endingHash:'empty'};
 const complete={id:'q1',text:'complete-hash',stage:'EQS_Success',endingHash:'ending-a'};
 memory.observe([active]);const user=memory.user('anca');
 assert.equal(memory.observe([complete]),false);assert.equal(memory.user('anca'),user);
 assert.equal(memory.observe([complete,{id:'q2',text:'new',stage:'EQS_Active'}]),false);
 assert.equal(memory.observe([{...complete,text:'other',endingHash:'ending-b'},{id:'q2',text:'new',stage:'EQS_Active'}]),true);
 assert.equal(memory.user('anca'),user);
 assert.equal(memory.observe([active]),true);
});

test('explicit end-user selection and different API accounts do not mix player IDs',()=>{
 const data=new Map();let sequence=0;
 const m=new QuestMemory({getItem:k=>data.get(k)||null,setItem:(k,v)=>data.set(k,v)},()=>String(++sequence));
 m.configurePlayer('account-a','existing-player');
 assert.equal(m.user('anca'),'existing-player');assert.equal(m.user('lacra'),'existing-player');
 m.configurePlayer('account-b');const second=m.user('anca');assert.notEqual(second,'existing-player');
 assert.equal(m.user('brencis'),second);
 m.configurePlayer('account-a');assert.equal(m.user('new-companion'),'existing-player');
});
