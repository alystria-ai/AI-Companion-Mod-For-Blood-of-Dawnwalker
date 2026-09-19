import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import {readFile} from 'node:fs/promises';
test('remote audio capture stays silent; deferred playback preserves every sample across gaps',async()=>{
 const classes={};const context={sampleRate:48000,currentTime:0,Float32Array,AudioWorkletProcessor:class{constructor(){this.messages=[];this.port={postMessage:m=>this.messages.push(m)};}},registerProcessor:(n,c)=>classes[n]=c};
 vm.runInNewContext(await readFile('bridge/public/reply-capture.js','utf8'),context);
 const capture=new classes['reply-capture'](),playback=new classes['reply-playback']();
 const samples=[];for(let block=0;block<32;block++){
  const input=Float32Array.from({length:128},(_,i)=>Math.sin((block*128+i)*0.07)*0.3);samples.push(...input);
  const out=new Float32Array(128);capture.process([[input]],[[out]]);assert.ok(out.every(v=>v===0),'Preparation became audible');context.currentTime+=128/48000;
 }
 assert.equal(capture.messages.length,2);
 let out=new Float32Array(128);playback.process([],[[out]]);assert.ok(out.every(v=>v===0));assert.equal(playback.played,0);
 const actual=[];
 for(const chunk of capture.messages){
  playback.port.onmessage({data:{pcm:chunk.pcm}});
  for(let i=0;i<16;i++){out=new Float32Array(128);playback.process([],[[out]]);actual.push(...out);context.currentTime+=128/48000;}
  // A scheduling/network gap must not advance through or discard the next chunk.
  const before=playback.played;playback.process([],[[new Float32Array(128)]]);assert.equal(playback.played,before);
 }
 assert.deepEqual(actual,samples);assert.equal(playback.messages.at(-1).played,samples.length);
});
