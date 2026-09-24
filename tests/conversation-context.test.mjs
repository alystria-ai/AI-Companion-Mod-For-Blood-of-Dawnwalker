import test from 'node:test';
import assert from 'node:assert/strict';
import {parseFollowUpQuestions,conversationContext} from '../bridge/conversation-context.mjs';

test('older configurations default on; decimal toggle values and section boundaries are respected',()=>{
 assert.equal(parseFollowUpQuestions('[Companions]\nDamagePercent=250'),true);
 assert.equal(parseFollowUpQuestions('[Companions]\nFollowUpQuestions = 0.0 ; native toggle\n[Other]\nFollowUpQuestions=1'),false);
 assert.equal(parseFollowUpQuestions('[Companions]\nFollowUpQuestions=1.0'),true);
});

test('only the closing speaker is prompted to ask, including a one-person group',()=>{
 for(const count of [1,2,3]){
  for(let index=0;index<count;index++){
   const policy=conversationContext(true,'group',index,count);
   assert.match(policy.text,index===count-1?/normally end your reply with one short, specific follow-up question/:/do not end with a question to Coen/);
  }
 }
 assert.match(conversationContext(true).text,/normally end your reply with one short, specific follow-up question/);
});

test('toggling off replaces the closing instruction and changes its context revision',()=>{
 const on=conversationContext(true),off=conversationContext(false);
 assert.notEqual(on.revision,off.revision);
 assert.match(off.text,/follow-up questions are disabled/);
 assert.match(conversationContext(false,'group',0,3).text,/do not end with a question to Coen/);
});
