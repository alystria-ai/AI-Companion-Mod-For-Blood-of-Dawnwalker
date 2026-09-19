import test from 'node:test';
import assert from 'node:assert/strict';
import {parseQuests,ActionQueue} from '../bridge/game-context.mjs';
const raw=rows=>'100\nJournal /Engine/Transient.Game.Journal\n'+rows;
test('quest memory excludes active quests, distinguishes failure and replaces rolled-back progress',()=>{
 const snapshot=parseQuests(raw('one\tEQS_Success\tAnca helped\tCoen saved Anca.\ntwo\tEQS_Active\tSecret\tHidden outcome\nthree\tEQS_Failure\tRescue\t'),100000);
 assert.equal(snapshot.quests.length,2);
 const rollback=parseQuests(raw('one\tEQS_Active\tAnca helped\t'),100000);
 assert.notEqual(snapshot.revision,rollback.revision);
 assert.throws(()=>parseQuests(raw(''),200000),/stale/);
});
test('actions require active matching generation, allowlisted verbs and matching acknowledgements',()=>{
 const queue=new ActionQueue(),target={generation:7,active:true};
 const command={generation:7,id:'event-1',name:'Follow'};
 queue.add(target,[command,command,{...command,id:'bad',name:'Execute Lua'},{...command,generation:6}]);
 assert.equal(queue.pending.length,1);queue.ack('6\tevent-1\t1\tok');assert.equal(queue.pending.length,1);
 queue.ack('7\tevent-1\t1\tFollowing Coen');assert.equal(queue.pending.length,0);assert.equal(queue.result.ok,true);
 queue.add(target,[command]);assert.equal(queue.pending.length,0);
 queue.add(target,[{...command,id:'event-2'}]);assert.equal(queue.current({...target,generation:8}),undefined);
});
