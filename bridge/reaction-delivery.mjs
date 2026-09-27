// Bounded delivery evidence, without dialogue text, credentials or actor paths.
export class ReactionDelivery {
  rows=[];
  observe(message,target,state,now=Date.now()){
    let row=this.rows.find(x=>x.id===message.id&&x.generation===target.generation);
    if(!row){row={id:message.id,generation:target.generation,speaker:String(target.name||'').slice(0,80),created:now};this.rows.push(row);if(this.rows.length>12)this.rows.shift();}
    if(!row.queuedAt){row.state=state;if(state==='queued')row.queuedAt=now;}
  }
  frame(target,data,now=Date.now()){
    const row=this.rows.find(x=>x.id===target.room&&x.generation===target.generation);
    if(!row)return;
    if(Array.isArray(data.ackTextIds)&&data.ackTextIds.includes(row.id))row.acceptedAt??=now;
    const reply=data.replyStatus;
    if(reply?.token!==row.id)return;
    if(reply.finalText)row.textAt??=now;
    if(reply.heardAudio)row.speechEventsAt??=now;
    if(reply.playback){const p=reply.playback;row.playback={muted:p.muted===true,context:String(p.context||'').slice(0,24),tracks:Math.min(64,Math.max(0,Number(p.tracks)||0)),fallback:p.fallback===true};}
    if(reply.audioError)row.audioError=String(reply.audioError).slice(0,160);
    if(reply.finished){row.finishedAt??=now;row.state=row.speechEventsAt?'completed-with-speech-events':'completed-without-speech-events';}
    else row.state=row.speechEventsAt?'speaking':row.textAt?'text-received':row.acceptedAt?'sent-to-provider':'queued';
  }
  snapshot(target,now=Date.now()){
    for(const row of this.rows){
      if(row.finishedAt||row.endedAt)continue;
      if(row.generation!==target.generation||row.id!==target.room||!target.active){row.state='selection-ended-before-completion';row.endedAt=now;}
      else if(now-row.created>60000){row.state='delivery-timed-out';row.endedAt=now;}
    }
    return JSON.stringify({reactions:this.rows});
  }
}
