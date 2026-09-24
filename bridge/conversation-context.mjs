// Local preferences stay out of character biographies and long-term memories.
export function parseFollowUpQuestions(source){
 let section='',enabled=true;
 for(const raw of source.split(/\r?\n/)){
  const line=raw.replace(/^\uFEFF/,'').trim();
  const heading=line.match(/^\[([^\]]+)\]$/);
  if(heading){section=heading[1].toLowerCase();continue;}
  const setting=line.match(/^FollowUpQuestions\s*=\s*([01](?:\.0+)?)\s*(?:[;#].*)?$/i);
  if(section==='companions'&&setting)enabled=Number(setting[1])===1;
 }
 return enabled;
}

export function conversationContext(enabled,mode='single',index=0,count=1){
 const intermediate=mode==='group'&&index<count-1;
 const text=intermediate
  ? 'Conversation pacing for this turn: another companion speaks after you. Respond to the current topic and the preceding speaker, but do not end with a question to Coen or ask him to reply yet. Leave any closing question to the final companion.'
  : enabled
   ? 'Conversation pacing for this turn: normally end your reply with one short, specific follow-up question addressed to Coen. Be selective about omitting the question: skip it only when there is a clear conversational reason, such as an explicit farewell or request to stop, immediate danger requiring action, or a moment where a question would plainly be intrusive or insensitive. Simply having answered his question is not itself a reason to end the exchange. First respond meaningfully to what was said, then let your question arise from this topic, your own interests and your relationship with him. Make it sound like this character is curious, not like an assistant trying to extend a session. Avoid generic offers of help, repeated or already answered questions, stacked questions, interrogation and abrupt topic changes. In a group, respond to the preceding companion first, then normally bring the conversation back to Coen with your question. Keep the whole reply concise and use the same language as Coen. Never invent his answer; wait for him to choose to speak again.'
   : 'Conversation pacing for this turn: follow-up questions are disabled. Answer naturally without routinely adding a closing question or prompting Coen to keep talking. Ask only a clarification necessary to understand his request. Do not invent Coen’s answer.';
 return {followUpQuestions:enabled,revision:`follow-up-v2:${enabled}:${mode}:${intermediate?'intermediate':'closing'}`,text};
}
