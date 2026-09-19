import test from 'node:test';import assert from 'node:assert/strict';import {build} from 'esbuild';
import {Companions} from '../bridge/companions.mjs';
const b=await build({entryPoints:['bridge/character-connections.ts'],bundle:true,write:false,format:'esm',platform:'node'});
const {CharacterConnections}=await import('data:text/javascript;base64,'+Buffer.from(b.outputFiles[0].text).toString('base64'));
const flush=async()=>{for(let i=0;i<4;i++)await new Promise(setImmediate);};
test('summoning initializes distinct identities, staggers setup, reuses clones and releases dismissed sessions',async()=>{
 const created=[];const p=new CharacterConnections((id,identity)=>{
  const c={id,identity,isBotReady:false,closed:0,on(){},off(){},connect(){return new Promise(resolve=>{this.ready=()=>{this.isBotReady=true;resolve();};});},async disconnect(){this.closed++;this.isBotReady=false;}};created.push(c);return c;
 },async c=>c.disconnect());
 const a={id:'anca',identity:'anca:save'},b={id:'bakir',identity:'bakir:save'},x={id:'xanthe',identity:'xanthe:save'};
 p.reconcile([a,a,b,x],'anca:save',1000);await flush();assert.equal(created.length,1);assert.equal(created[0].id,'bakir','Active connection must not be duplicated');
 p.reconcile([a,a,b,x],'anca:save',1100);assert.equal(created.length,1);
 p.reconcile([a,a,b,x],'anca:save',1500);await flush();assert.equal(created.length,2);
 created[0].ready();created[1].ready();await flush();
 const borrowed=p.take('bakir:save');assert.equal(await borrowed.connected,true);assert.equal(p.release(borrowed.client,'bakir:save'),true);
 assert.equal(p.take('bakir:save').client,created[0],'Same character clone reuses the live client');
 p.reconcile([b],'bakir:save',2000);await flush();assert.ok(created[1].closed);assert.equal(p.release(created[1],'xanthe:save'),false);
});
test('cancelled setup closes after a late connection and failures back off',async()=>{
 let made=0,closed=0,resolve;const p=new CharacterConnections(()=>{made++;return {isBotReady:false,on(){},off(){},connect(){return new Promise(r=>resolve=r);},async disconnect(){closed++;}};},async c=>c.disconnect());
 const s={id:'anca',identity:'anca:save'};p.reconcile([s],'',1000);await flush();p.clear();assert.equal(closed,1);
 resolve();await flush();assert.equal(closed,2,'Late connection escaped cancellation');
 p.reconcile([s],'',2000);assert.equal(made,1,'Cancelled connection retried immediately');
});
test('summon requests expose connection intent before the character finishes loading and deduplicate clones',async()=>{
 const c=new Companions('unused',{limit:0,characters:[{id:'anca'}]});c.state={epoch:'1',updated:Date.now(),members:[],summons:[]};
 const a=await c.command({epoch:'1',op:'spawn',member:'anca'}),b=await c.command({epoch:'1',op:'spawn',member:'anca'});
 assert.deepEqual(c.connectionCharacters(),['anca']);assert.equal(c.state.members.length,0);
 c.state.summons=[{id:a.id,phase:'failed'}];assert.deepEqual(c.connectionCharacters(),['anca'],'Another pending clone still needs this connection');
 c.state.summons.push({id:b.id,phase:'failed'});assert.deepEqual(c.connectionCharacters(),[]);
 c.state.members.push({id:a.id,characterId:'anca'},{id:b.id,characterId:'anca'});assert.deepEqual(c.connectionCharacters(),['anca']);
});
