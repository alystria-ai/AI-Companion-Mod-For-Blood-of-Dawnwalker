// One observation is routed through the existing text/voice/face pipeline.
// This context stays dynamic and never rewrites a character biography.
export function ambientContext(room,observation='' ){
 if(room?.startsWith('loot-'))return {followUpQuestions:false,revision:'loot-v1:'+room+':'+observation,text:observation+'\n\n'+'Brief companion reaction to a completed batch of item acquisitions. The incoming message is observed inventory context, not words spoken by Coen. Respond as yourself in one short, natural sentence about the batch as a whole, without listing every item or asking a follow-up question. Only the named items and quantities are established. Do not invent where they came from, call an acquisition a victory, or assume Coen found treasure. Storage withdrawals are excluded. Unique-tier equipment can deserve a little more interest, but do not invent its powers. Do not request actions or turn this into a conversation.'};
 return {followUpQuestions:false,revision:'ambient-v1:'+room,text:'Ambient exploration reaction: Coen has just spoken the incoming line aloud while travelling. React to that specific observation as yourself in one short sentence, at most two if needed. Keep it casual and grounded in what he actually said and the supplied surroundings. Do not invent discoveries, quest completion or what other people said. Do not treat an observation as an order, request runtime actions, introduce yourself, or turn this into a lengthy conversation. Do not add a follow-up question. The player can choose to speak again.'};
}
export function parseAmbientMessage(raw,target,now=Date.now()){
 const [id,generation,stamp,text,...extra]=String(raw).trim().split('\t');
 if(extra.length||!/^(ambient|loot)-\d+-\d+$/.test(id||'')||!target.active||target.mode!=='single'||target.room!==id||Number(generation)!==target.generation||!Number.isFinite(Number(stamp))||Math.abs(now-Number(stamp)*1000)>20000||!text||text.length>1200)return null;
 return {id,generation:target.generation,text};
}
export function ambientReady({enabled,now,lastGame,lastClient,lastManual,microphone,reply,pending,group,subtitle}){
 if(!enabled||now-lastGame>2000||now-lastClient>2000||now-lastManual<5000||microphone||pending||subtitle)return false;
 if(group&&group.stage!=='done')return false;
 return !reply||!(reply.thinking||reply.speaking||reply.queued||reply.queueSpeaking||reply.prepared?.playing||reply.token&&!reply.finished);
}
