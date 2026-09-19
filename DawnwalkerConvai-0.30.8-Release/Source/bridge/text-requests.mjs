export class TextRequests {
  pending=[];
  seen=new Set();
  enqueue(data,target){
    if(!target.active||data.generation!==target.generation)throw Error('The conversation changed. Select the character again.');
    if(typeof data.id!=='string'||!/^[a-zA-Z0-9-]{1,80}$/.test(data.id))throw Error('Invalid message ID');
    if(typeof data.text!=='string'||!data.text.trim()||data.text.length>1200)throw Error('Enter a message of 1–1200 characters.');
    const key=data.generation+':'+data.id;
    if(this.seen.has(key))return;
    if(this.pending.length>=16)throw Error('Too many pending messages. Wait for a reply.');
    this.seen.add(key);if(this.seen.size>256)this.seen.delete(this.seen.values().next().value);
    this.pending.push({id:data.id,generation:data.generation,text:data.text.trim()});
  }
  forTarget(target){this.pending=this.pending.filter(x=>target.active&&x.generation===target.generation);return this.pending;}
  acknowledge(generation,ids){if(!Array.isArray(ids))return;this.pending=this.pending.filter(x=>x.generation!==generation||!ids.includes(x.id));}
}
