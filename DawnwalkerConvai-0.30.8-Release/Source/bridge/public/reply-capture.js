// Remote NPC audio only. This processor never creates or opens a microphone.
class ReplyCapture extends AudioWorkletProcessor {
 constructor(){super();this.data=new Float32Array(2048);this.used=0;this.first=0;}
 process(inputs){
  const channels=inputs[0];if(!channels?.length)return true;
  const n=channels[0].length;
  for(let i=0;i<n;i++){
   if(!this.used)this.first=currentTime+i/sampleRate;
   let sample=0;for(const c of channels)sample+=c[i]||0;
   this.data[this.used++]=sample/channels.length;
   if(this.used===this.data.length){this.port.postMessage({at:this.first,pcm:this.data},[this.data.buffer]);this.data=new Float32Array(2048);this.used=0;}
  }
  return true; // Unwritten output remains silent.
 }
}
registerProcessor('reply-capture',ReplyCapture);

class ReplyPlayback extends AudioWorkletProcessor {
 constructor(){super();this.queue=[];this.offset=0;this.played=0;this.report=0;
  this.port.onmessage=e=>{if(e.data.pcm)this.queue.push(e.data.pcm);};
 }
 process(inputs,outputs){
  const out=outputs[0]?.[0];if(!out)return true;
  for(let i=0;i<out.length;i++){
   const chunk=this.queue[0];if(!chunk)break; // Underflow is silence, not lost samples.
   out[i]=chunk[this.offset++];this.played++;this.report++;
   if(this.offset===chunk.length){this.queue.shift();this.offset=0;}
  }
  if(this.report>=512){this.report=0;this.port.postMessage({played:this.played,at:currentTime+out.length/sampleRate});}
  return true;
 }
}
registerProcessor('reply-playback',ReplyPlayback);
