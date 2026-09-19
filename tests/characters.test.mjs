import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
const compiled=await build({entryPoints:['bridge/characters.ts'],bundle:true,write:false,format:'esm'});
const {matchProfile}=await import('data:text/javascript;base64,'+Buffer.from(compiled.outputFiles[0].text).toString('base64'));
const profiles=[{id:'anca',key:'anca',name:'Anca',kind:'main',aliases:['anca']},
 ...['MALE','FEMALE'].flatMap(g=>Array.from({length:5},(_,i)=>({id:g+i,key:g+i,name:g+i,kind:'generic',gender:g,aliases:[]})))];
const npc={actor:'NPC /Map.PersistentLevel.NPC_101',actorClass:'BP_NonPlayerCharacter_C',definition:'NPCDef_Town_C /Game/NPC/NPCDef_Town.Default__NPCDef_Town_C',bodyType:'Woman'};
test('named metadata wins; path fragments cannot turn unrelated NPCs into Anca',()=>{
 assert.equal(matchProfile({...npc,name:'Anca'},profiles,{}).id,'anca');
 assert.equal(matchProfile({...npc,voiceTag:'vt.e.anca'},profiles,{}).id,'anca');
 assert.notEqual(matchProfile({...npc,actor:'/Map/Anca/House.PersistentLevel.Townswoman_101'},profiles,{},()=>0).id,'anca');
});
test('ambient picks remain stable and use the proper five-person gender pool',()=>{
 const assignments={};const first=matchProfile(npc,profiles,assignments,()=>0.8);
 assert.equal(first.id,'FEMALE4');assert.equal(matchProfile(npc,profiles,assignments,()=>0).id,first.id);
 assert.equal(matchProfile({...npc,actor:'other',bodyType:'Man'},profiles,assignments,()=>0.4).id,'MALE2');
 assert.equal(matchProfile({...npc,definition:'/Game/NPC/Animals/NPCDef_Rabbit',bodyType:'Man'},profiles,{}),undefined);
 assert.equal(matchProfile({...npc,bodyType:'Uriash'},profiles,{}),undefined);
 assert.equal(matchProfile({...npc,bodyType:''},profiles,{}),undefined);
});
