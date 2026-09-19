import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const bundle=await build({entryPoints:['bridge/microphone.ts'],bundle:true,write:false,format:'esm'});
const {Microphone}=await import('data:text/javascript;base64,'+Buffer.from(bundle.outputFiles[0].text).toString('base64'));
const settle=()=>new Promise(setImmediate);
test('mock capture stays off initially; explicit start/stop releases hardware and does not reopen on reconnect',async()=>{
 let opens=0,closes=0;const controls={enableAudio:async()=>{opens++;},disableAudio:async()=>{closes++;}};
 const mic=new Microphone();mic.request(controls,false,'initial');await settle();assert.equal(opens,0);
 mic.request(controls,true,'press1');await settle();assert.equal(mic.on,true);assert.equal(opens,1);
 await mic.stop();assert.equal(mic.on,false);assert.equal(closes,1);
 mic.request(controls,true,'press1');await settle();assert.equal(opens,1);
 mic.request(controls,true,'press2');await settle();assert.equal(opens,2);await mic.stop();
});
test('pending mock permission is closed when conversation or foreground is lost',async()=>{
 let finish,closes=0;const controls={enableAudio:()=>new Promise(r=>finish=r),disableAudio:async()=>{closes++;}};
 const mic=new Microphone();mic.request(controls,true,'press');mic.request(null,false,'released');finish();await settle();
 assert.equal(mic.on,false);assert.equal(closes,1);
});
test('mock permission denial is visible and never retried without a new command',async()=>{
 let calls=0;const controls={enableAudio:async()=>{calls++;throw Error('permission denied');},disableAudio:async()=>{}};
 const mic=new Microphone();mic.request(controls,true,'press');await settle();assert.match(mic.status,/permission denied/);
 for(let i=0;i<5;i++)mic.request(controls,true,'press');await settle();assert.equal(calls,1);assert.equal(mic.on,false);
});
test('silence then stop sends no input and a removed device cannot retain capture ownership',async()=>{
 let failures=0,closes=0,opens=0;
 const mic=new Microphone(()=>{failures++;});
 const broken={enableAudio:async()=>{opens++;},disableAudio:async()=>{closes++;throw Error('device removed');}};
 mic.request(broken,true,'silent');await settle();assert.equal(mic.on,true);
 await mic.stop();assert.equal(mic.on,false);assert.equal(closes,1);assert.equal(failures,1);
 mic.request(broken,true,'silent');await settle();assert.equal(opens,1,'Failed/stopped capture restarted itself');
 const next={enableAudio:async()=>{opens++;},disableAudio:async()=>{closes++;}};
 mic.request(next,true,'new-press');await settle();assert.equal(mic.on,true);assert.equal(opens,2);
 await mic.stop();assert.equal(closes,2);assert.equal(mic.on,false);
});
