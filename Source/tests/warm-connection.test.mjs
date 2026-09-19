import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const bundle=await build({entryPoints:['bridge/warm-connection.ts'],bundle:true,write:false,format:'esm',platform:'node'});
const {WarmConnection}=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].text).toString('base64'));
const flush=async()=>{for(let i=0;i<4;i++)await new Promise(setImmediate);};
function fixture(){
 const clients=[];
 const create=()=>{
  const c={isBotReady:false,closed:0,handlers:{},on(e,f){this.handlers[e]=f;},
   connect(){return new Promise((resolve,reject)=>{this.ready=()=>{this.isBotReady=true;resolve();};this.reject=reject;});},
   async disconnect(){this.closed++;this.isBotReady=false;this.handlers.disconnect?.();}};
  clients.push(c);return c;
 };
 const pool=new WarmConnection(async c=>c.disconnect());pool.setScope('round1');
 return {pool,clients,create};
}
test('only one upcoming connection, ready promotion reuses it, active events no longer belong to warmer',async()=>{
 const {pool,clients,create}=fixture();pool.ensure('anca:save',create);pool.ensure('anca:save',create);await flush();
 assert.equal(clients.length,1);clients[0].ready();await flush();assert.equal(pool.diagnostic().state,'ready');
 const prepared=pool.take('anca:save');assert.equal(prepared.client,clients[0]);assert.equal(await prepared.connected,true);
 pool.clear();assert.equal(clients[0].closed,0,'Promotion transfers ownership');
 clients[0].handlers.error();pool.ensure('leonica:save',create);await flush();assert.equal(clients.length,2);
 pool.clear();clients[1].ready();await flush();assert.equal(clients[1].isBotReady,false);
});
test('cancel during HTTP setup closes late connection and bounds replacement attempts',async()=>{
 const {pool,clients,create}=fixture();pool.ensure('anca:save',create);await flush();pool.setScope('round2');
 for(let i=0;i<20;i++)pool.ensure('leonica:save',create);assert.equal(clients.length,1,'Do not accumulate orphan connects');
 assert.equal(clients[0].closed,1);clients[0].ready();await flush();assert.equal(clients[0].closed,2,'Close again after late completion');
 pool.ensure('leonica:save',create);await flush();assert.equal(clients.length,2);
 clients[1].ready();await flush();pool.setScope('');await flush();
 pool.ensure('xanthe:save',create);assert.equal(clients.length,2,'No warming outside an active group round');
});
test('unready promotion awaits original setup; failure and timeout fall back without repeated warm requests',async()=>{
 const {pool,clients,create}=fixture();pool.ensure('anca:save',create);await flush();const prepared=pool.take('anca:save');
 assert.equal(prepared.settled,false);clients[0].ready();assert.equal(await prepared.connected,true);
 pool.ensure('leonica:save',create,100);await flush();clients[1].reject(Error('concurrent session unavailable'));await flush();
 for(let i=0;i<10;i++)pool.ensure('leonica:save',create,1000);assert.equal(clients.length,2);assert.equal(pool.diagnostic().state,'unavailable');
 pool.setScope('round2');pool.ensure('xanthe:save',create,2000);await flush();pool.ensure('xanthe:save',create,23000);
 assert.equal(pool.diagnostic().state,'unavailable');clients[2].ready();await flush();assert.equal(clients[2].isBotReady,false);
});
