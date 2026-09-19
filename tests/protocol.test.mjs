import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import lua from 'luaparse';
import {encodeFrame,parseTarget} from '../bridge/protocol.mjs';
test('weights are bounded, generation and timestamp preserved',()=>{
 assert.equal(encodeFrame({generation:42,weights:{JawOpen:1.4,MouthClose:-1}},123456),'42\t123\nJawOpen\t1.0000\nMouthClose\t0.0000\n');
});
test('rejects malformed channels and non-finite weights',()=>{
 for(const weights of [{'JawOpen\nreturn evil()':1},{JawOpen:NaN},{JawOpen:'1'}])assert.throws(()=>encodeFrame({generation:1,weights}));
 assert.throws(()=>encodeFrame({generation:-1}));
});
test('reply completion travels atomically with its generation and rejects injected records',()=>{
 assert.equal(encodeFrame({generation:42,weights:{JawOpen:0},singleDone:'voice-turn1'},123456),'42\t123\nJawOpen\t0.0000\nREPLY-END\tvoice-turn1\n');
 for(const singleDone of ['x\nREPLY-END\tx','x\ty','x'.repeat(129),{},true])assert.throws(()=>encodeFrame({generation:42,singleDone}));
 assert.doesNotMatch(encodeFrame({generation:42,singleDone:null}),/REPLY-END/);
});
test('target parser preserves actor identity and rejects incomplete writes',()=>{
 assert.deepEqual(parseTarget('42\n1\nActor one\nClass two\nReady\n'),{generation:42,active:true,actor:'Actor one',actorClass:'Class two',status:'Ready',mode:'single',room:'',turn:'',requestId:1});
 assert.equal(parseTarget('42\n1\nActor one\nClass two\nReady\ntext\n3\n').requestId,3);
 assert.equal(parseTarget('42\n1\nActor one\nClass two\nReady\ntext\n').mode,'single');
 assert.equal(parseTarget('42\r\n1\r\nActor one\r\nClass two\r\nReady\r\ntext\r\n').active,true);
 assert.throws(()=>parseTarget('42\n'));
});
test('Lua source parses (engine calls still require runtime test)',async()=>{
 for(const name of ['main','config','targeting','engagement','face_inspector'])lua.parse(await readFile(`mod/Scripts/${name}.lua`,'utf8'),{luaVersion:'5.3'});
});
