import test from 'node:test';
import assert from 'node:assert/strict';
import {ambientReady,parseAmbientMessage} from '../bridge/ambient-comments.mjs';
test('ambient observations cannot carry over into another conversation or replay later',()=>{
 const target={active:true,mode:'single',room:'ambient-100-1',generation:5};
 const raw='ambient-100-1\t5\t100\tLook at that tower.';
 assert.equal(parseAmbientMessage(raw,target,100000)?.text,'Look at that tower.');
 for(const change of [{generation:6},{room:'manual-chat'},{active:false},{mode:'group'}])assert.equal(parseAmbientMessage(raw,{...target,...change},100000),null);
 assert.equal(parseAmbientMessage(raw,target,121000),null);
});
test('ambient replies wait for manual input, voice playback and pending group replies',()=>{
 const idle={enabled:true,now:10000,lastGame:9900,lastClient:9900,lastManual:0,microphone:false,pending:false,group:null,reply:null,subtitle:''};
 assert.equal(ambientReady(idle),true);
 for(const change of [{enabled:false},{lastGame:0},{lastClient:0},{lastManual:9000},{microphone:true},{pending:true},{subtitle:'Speaking'},{group:{stage:'preparing'}},{reply:{thinking:true}},{reply:{token:'reply-1',finished:false}},{reply:{speaking:true}}])assert.equal(ambientReady({...idle,...change}),false);
 assert.equal(ambientReady({...idle,reply:{token:'reply-1',finished:true},group:{stage:'done'}}),true);
});
