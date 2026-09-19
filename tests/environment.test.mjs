import test from 'node:test';
import assert from 'node:assert/strict';
import {environmentContext} from '../bridge/environment.mjs';
const target={active:true,generation:7};
test('surroundings require fresh matching conversation; region is not treated as a room',()=>{
 const raw="100\t7\tSt. Tyna's Grove\t21\t30\t0\t0\r\n";
 const e=environmentContext(raw,target,100000);
 assert.match(e.text,/St. Tyna's Grove/);assert.match(e.text,/21:30/);assert.match(e.text,/no rain or snow/);
 assert.match(e.text,/not a specific building/);
 assert.equal(environmentContext(raw,{...target,generation:8},100000).revision,'unavailable');
 assert.equal(environmentContext(raw,{...target,active:false},100000).revision,'unavailable');
 assert.equal(environmentContext(raw,target,120000).revision,'unavailable');
});
test('invalid fields are withheld independently and transient changes replace context',()=>{
 const a=environmentContext('100\t7\tGrove\t99\t30\tNaN\t0',target,100000);
 assert.match(a.text,/Grove/);assert.doesNotMatch(a.text,/Current game time|precipitation/);
 const b=environmentContext('100\t7\tGrove\t21\t30\t1\t0',target,100000);
 assert.match(b.text,/rain is active/);assert.match(b.text,/exposure.*not been established/);assert.notEqual(a.revision,b.revision);
});
