import test from 'node:test';
import assert from 'node:assert/strict';
import {GroupChat,chooseSpeakers} from '../bridge/group-chat.mjs';
import {characterKey,lore} from '../bridge/companion-lore.mjs';
import {readFileSync} from 'node:fs';
const target={generation:5,mode:'group',room:'room1',active:true,actor:'Actor Anca_1',name:'Anca'};
const member=(key,id=key,distance=400)=>({id,characterId:key,name:key,actor:'Actor '+id,distance,available:true});
test('addressed first, closest clone skipped, friends preferred, explicit topic can outweigh association',()=>{
 const members=[member('anca','anca2',100),member('leonica'),member('marat','marat',500),member('sara'),member('vicho')];
 assert.deepEqual(chooseSpeakers(target,members,'Hello everyone').map(s=>s.characterId),['anca','leonica','sara']);
 assert.deepEqual(chooseSpeakers(target,members,'Marat, tell us about the rebels and manumits').map(s=>s.characterId),['anca','marat','leonica']);
 assert.equal(chooseSpeakers(target,[member('leonica','l',1201)],'hello').length,1);
 assert.equal(chooseSpeakers(target,[{...member('leonica'),available:false}],'hello').length,1);
});
test('sequential turns require Lua handoff, deduplicate retries, cancel old rooms and skip missing speakers',()=>{
 const g=new GroupChat(()=> 'round1'),members=[member('leonica'),member('vicho')];
 g.start({generation:5,id:'send1',text:'Hello'},target,members,100);
 assert.equal(g.view(target).request.text,'Hello');assert.equal(g.view(target).request.id,'round1-0');assert.equal(g.command(),'');
 g.start({generation:5,id:'send1',text:'Hello'},target,members,150);assert.equal(g.round.started,100);
 assert.equal(g.complete({token:'old',text:'Wrong'},target,members,200),false);
 assert.equal(g.complete({token:'round1-0',text:'Anca reply'},target,members,200),true);
 assert.match(g.command(),/room1\tround1-1\tleonica\t5/);assert.equal(g.view(target).request,null);
 const next={...target,generation:7,actor:'Actor leonica',turn:'round1-1',name:'Leonica'};
 g.tick(next,members,true,250);assert.equal(g.view(next).request.generation,7);
 assert.equal(g.view(next).request.text,'Anca: Anca reply');assert.match(g.view(next).context,/Anca reply/);
 g.complete({token:'round1-1',text:'Leonica reply'},next,members,300);
 g.tick(next,members,true,350,'round1-2\tfailed');assert.equal(g.round.stage,'done');
 assert.equal(g.round.heard.length,3);assert.equal(g.view(next).request,null);
 g.tick({...next,room:'different'},members,true,400);assert.equal(g.round,null);
});
test('voice round does not resend the first utterance; group hearing excludes absent characters',()=>{
 const g=new GroupChat(()=> 'voice1'),members=[member('leonica'),member('vicho','far',2000)];
 g.start({generation:5,id:'mic1',text:'A spoken question'},target,members,100,true);
 assert.equal(g.view(target).request,null);
 g.complete({token:'voice1-0',text:'A reply'},target,members,200);
 assert.deepEqual(g.round.heard[1].listeners,['anca','leonica']);
 const next={...target,generation:7,actor:'Actor leonica',turn:'voice1-1',name:'Leonica'};
 g.tick(next,members,true,250);assert.equal(g.view(next).request.text,'Anca: A reply');
 g.tick(next,members,false,300);assert.equal(g.round,null);
});
test('three distinct speakers finish in order, brief action delays wait and final audio releases the hold',()=>{
 const g=new GroupChat(()=> 'three'),members=[member('anca','copy'),member('leonica'),member('sara'),member('vicho')];
 g.start({generation:5,id:'group1',text:'Hello'},target,members,100);
 assert.equal(g.round.speakers.length,3);
 g.complete({token:'three-0',text:'First'},target,members,200);
 g.tick(target,members,true,8200);assert.equal(g.round.stage,'handoff','Brief native action discarded next speaker');
 const second={...target,generation:7,actor:'Actor leonica',turn:'three-1'};
 g.tick(second,members,true,8300);assert.equal(g.view(second).request.id,'three-1');
 g.complete({token:'three-1',text:'Second'},second,members,8500);
 const third={...target,generation:9,actor:'Actor sara',turn:'three-2'};
 g.tick(third,members,true,8600);assert.equal(g.view(third).request.text,'leonica: Second');assert.match(g.view(third).context,/Second/);
 g.complete({token:'three-2',text:'Third'},third,members,9000);
 assert.equal(g.round.stage,'done');assert.equal(g.command(),'GROUPEND\t1\troom1\tthree-3\t9\n');
 assert.equal(g.round.heard.length,4);assert.deepEqual(g.diagnostic().speakers,['anca','leonica','sara']);
 assert.equal(g.complete({token:'three-2',text:'Duplicate'},third,members,9100),false);
});
test('story companion paths identify profiles; combat-only roster does not require a conversation profile',()=>{
 const config=JSON.parse(readFileSync('characters/companion-config.json','utf8'));
 for(const c of config.characters){if(c.chat===false){assert.equal(c.category,'combat');continue;}assert.equal(characterKey({name:c.name,definition:c.path}),c.id==='lunka-turned'?'lunka':c.id,c.id);}
 assert.equal(characterKey({name:'Anca',voiceTag:'vt.lacra'}),'');
});
