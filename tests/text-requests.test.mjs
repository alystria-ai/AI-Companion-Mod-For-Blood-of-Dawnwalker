import test from 'node:test';
import assert from 'node:assert/strict';
import {TextRequests} from '../bridge/text-requests.mjs';
test('typed replies are bounded, idempotent, and tied to the selected conversation',()=>{
 const queue=new TextRequests(),target={generation:5,active:true};
 const request={id:'reply-1',generation:5,text:'  Tell me about this place.  '};
 queue.enqueue(request,target);queue.enqueue(request,target);
 assert.equal(queue.forTarget(target).length,1);assert.equal(queue.pending[0].text,'Tell me about this place.');
 assert.throws(()=>queue.enqueue({...request,id:'old',generation:4},target));
 assert.throws(()=>queue.enqueue({...request,id:'empty',text:'  '},target));
 assert.throws(()=>queue.enqueue({...request,id:'long',text:'x'.repeat(1201)},target));
 queue.acknowledge(4,['reply-1']);assert.equal(queue.pending.length,1);
 queue.acknowledge(5,['reply-1']);assert.equal(queue.pending.length,0);
 queue.enqueue({...request,id:'reply-2'},target);
 assert.equal(queue.forTarget({generation:6,active:true}).length,0,'never deliver an old NPC message to a new selection');
 assert.throws(()=>queue.enqueue(request,{generation:5,active:false}));
});
