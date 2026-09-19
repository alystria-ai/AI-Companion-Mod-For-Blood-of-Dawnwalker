import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
test('local server rejects cross-origin and unauthenticated writes; accepts bounded frames',async()=>{
 const runtime=await mkdtemp(join(tmpdir(),'dawnwalker-test-'));
 await writeFile(join(runtime,'convai-config.json'),JSON.stringify({apiKey:'test-only',characterId:'test'}));
 const server=spawn(process.execPath,['bridge/server.mjs'],{stdio:'pipe',env:{...process.env,DAWNWALKER_PORT:'32124',DAWNWALKER_RUNTIME:runtime}});
 let error='';server.stderr.on('data',d=>error+=d);
 try{
  let ready=false;server.stdout.on('data',()=>{ready=true;});
  for(let i=0;i<50&&!ready;i++)await delay(100);
  assert.ok(ready,error);
  const base='http://127.0.0.1:32124';
  assert.equal((await fetch(base+'/')).status,200);
  assert.equal((await fetch(base+'/session',{headers:{Origin:'https://example.com'}})).status,403);
  assert.equal((await fetch(base+'/target')).status,403);
  assert.equal((await fetch(base+'/config')).status,403);
  const {token}=await (await fetch(base+'/session')).json();
  const headers={'x-bridge-token':token,'Content-Type':'application/json'};
  assert.equal((await (await fetch(base+'/config',{headers})).json()).apiKey,'test-only');
  const target=await (await fetch(base+'/target',{headers})).json();
  assert.equal(target.microphone.enabled,false,'capture defaults off');
  assert.equal((await fetch(base+'/microphone',{method:'POST',headers,body:JSON.stringify({generation:target.generation,enabled:true})})).status,409,'cannot enable without an active target');
  assert.equal((await fetch(base+'/microphone',{method:'POST',headers,body:JSON.stringify({generation:target.generation,enabled:false,id:'stale'})})).status,409,'old disconnect cannot cancel a newer microphone command');
  assert.equal((await fetch(base+'/frame',{method:'POST',headers,body:JSON.stringify({generation:target.generation,weights:{JawOpen:0.2}})})).status,204);
  assert.equal((await fetch(base+'/frame',{method:'POST',headers,body:JSON.stringify({generation:target.generation+1,weights:{}})})).status,409);
  assert.equal((await fetch(base+'/frame',{method:'POST',headers,body:JSON.stringify({generation:target.generation,weights:{JawOpen:'oops'}})})).status,400);
  assert.equal((await fetch(base+'/../package.json')).status,403);
 }finally{server.kill();await new Promise(resolve=>server.once('exit',resolve));await rm(runtime,{recursive:true,force:true});}
});
