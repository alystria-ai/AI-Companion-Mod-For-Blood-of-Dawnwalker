import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {heartbeatMs} from '../bridge/heartbeat.mjs';
const b=await build({entryPoints:['bridge/voice-input.ts'],bundle:true,write:false,format:'esm'});
const {VoiceInput}=await import('data:text/javascript;base64,'+Buffer.from(b.outputFiles[0].text).toString('base64'));

test('partial heartbeat reads cannot cancel capture, but explicit focus loss and stale samples still do',()=>{
 const now=1789375000000;let focus=heartbeatMs(String(now),0,now);
 assert.equal(focus,now);for(const partial of ['',null,'\n','writing','123x'])focus=heartbeatMs(partial,focus,now+100);
 assert.equal(focus,now);assert.equal(heartbeatMs('1789375000',0,now),now,'legacy seconds still supported');
 assert.equal(heartbeatMs('0',focus,now),0,'real Alt-Tab cancels immediately');
 assert.ok(now+1600-heartbeatMs('',focus,now+1600)>1500,'partial reads cannot keep a dead helper alive');
 assert.equal(heartbeatMs(String(now+10000),focus,now),focus,'reject a future clock sample');
});

function fake(){
 const pubs=new Map();let sequence=0;const calls=[];
 const c={room:{localParticipant:{audioTrackPublications:pubs,unpublishTrack:async(track,stop)=>{calls.push('unpublish');assert.equal(stop,true);track.mediaStreamTrack.readyState='ended';pubs.clear();}}},
 toggleStt:value=>{assert.equal(value,true);calls.push('stt');},audioControls:{
 enableAudio:async()=>{calls.push('open-default');pubs.set('mic',{source:'microphone',isMuted:false,track:{id:++sequence,mediaStreamTrack:{label:'Windows selected input',enabled:true,readyState:'live',muted:false}}});},
 disableAudio:async()=>{calls.push('close');const p=pubs.get('mic');if(p){p.isMuted=true;p.track.mediaStreamTrack.readyState='ended';}}
 }};return {c,pubs,calls};
}
test('voice uses the Windows default, verifies a live publication and removes stopped tracks between turns',async()=>{
 const {c,pubs,calls}=fake(),v=new VoiceInput(),controls=v.controls(c);
 assert.equal(v.controls(c),controls);assert.deepEqual(calls,[],'warming a client must never open hardware');
 await controls.enableAudio();const first=pubs.get('mic').track.id;
 assert.equal(v.sample().trackState,'live');assert.equal(v.sample().device,'Windows selected input');
 await controls.disableAudio();assert.equal(pubs.size,0);assert.equal(v.sample().trackState,'off');
 await controls.enableAudio();assert.notEqual(pubs.get('mic').track.id,first);await controls.disableAudio();
 assert.deepEqual(calls,['stt','open-default','close','unpublish','stt','open-default','close','unpublish']);
});
test('dead prior publications are removed and an SDK success without live capture is not reported as listening',async()=>{
 const {c,pubs,calls}=fake();pubs.set('mic',{source:'microphone',track:{mediaStreamTrack:{readyState:'ended'}}});
 const controls=new VoiceInput().controls(c);await controls.enableAudio();assert.equal(calls[0],'unpublish');await controls.disableAudio();
 c.audioControls.enableAudio=async()=>{};await assert.rejects(controls.enableAudio(),/live published audio track/);
});
