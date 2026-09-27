export type SpokenSegment={text:string;segmentId?:string|number;aggregatedBy?:string;spoken?:boolean;spokenStatus?:string};
type Phrase={text:string;weight:number};
type Segment={key:string;start:number;end?:number;phrases:Phrase[]};
// Speech events identify sentence boundaries. Inside a long sentence the SDK
// does not expose word timestamps, so advance short phrases at reading pace.
// Buffered replies use the captured audio clock, never the time of handoff.
export function captionPhrases(text:string):Phrase[]{
 const tokens=text.trim().match(/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]|[^\s\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]+\s*/gu)||[];
 const out:Phrase[]=[];let line='',width=0;
 const flush=()=>{if(line.trim())out.push({text:line.trim(),weight:Math.max(1,width)});line='';width=0;};
 for(const token of tokens){
  // Bound unbroken text too, without splitting UTF-16 surrogate pairs.
  const chars=Array.from(token);let part='';let size=0;
  for(const char of chars){const w=/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u.test(char)?2:1;if(size+w>68){if(line)flush();out.push({text:part.trim(),weight:size});part='';size=0;}part+=char;size+=w;}
  if(width+size>68)flush();line+=part;width+=size;
  if(/[.!?。！？;；]["'”’]?\s*$/.test(part)||width>=44&&/[,，:：]\s*$/.test(part))flush();
 }
 flush();return out;
}
export class SpokenCaptions {
 private segments:Segment[]=[];private byId=new Map<string,Segment>();private primary=false;
 private serial=0;private ended:number|undefined;private fallbackContent='';
 reset(){this.segments=[];this.byId.clear();this.primary=false;this.serial=0;this.ended=undefined;this.fallbackContent='';}
 receive(data:SpokenSegment,at:number,fallback=false){
  if(!data.text?.trim()||fallback&&this.primary)return;
  if(!fallback&&!(data.spoken||data.spokenStatus==='in-progress'||data.spokenStatus==='completed'))return;
  if(!fallback&&!this.primary){this.reset();this.primary=true;}
  this.ended=undefined;
  const last=this.segments[this.segments.length-1];
  const key=data.segmentId!==undefined?'id:'+data.segmentId:!fallback&&last?.key==='text:'+data.text?'text:'+data.text:fallback?'fallback:'+(++this.serial):'text:'+data.text;
  let segment=this.byId.get(key);
  if(!segment){
   if(last&&last.end===undefined)last.end=Math.max(last.start+.05,at);
   segment={key,start:at,phrases:captionPhrases(data.text)};this.segments.push(segment);this.byId.set(key,segment);
  }
  if(data.spokenStatus==='completed'&&segment.end===undefined&&at>segment.start+.05)segment.end=at;
 }
 // Some voice pipelines send audio and LLM text without spoken-text events.
 // Only current-turn text is eligible, and only after speech starts. Streamed
 // updates retain the initial clock rather than restarting the first caption.
 fallbackText(text:string,at:number,speaking:boolean,start=at){
  if(this.primary||this.segments.some(s=>s.key!=='transcript'))return;
  const existing=this.byId.get('transcript');
  if(!speaking){if(existing&&this.ended===undefined)this.finish(at);return;}
  if(!text.trim())return;
  this.ended=undefined;
  if(existing){if(text!==this.fallbackContent)existing.phrases=captionPhrases(text);existing.end=undefined;}
  else {const segment={key:'transcript',start,phrases:captionPhrases(text)};this.segments.push(segment);this.byId.set(segment.key,segment);}
  this.fallbackContent=text;
 }
 diagnostic(){return {source:this.primary?'speech-events':this.byId.has('transcript')?'current-reply':this.segments.length?'tts-events':'none',segments:this.segments.length};}
 finish(at:number){this.ended=at;const last=this.segments[this.segments.length-1];if(last&&last.end===undefined)last.end=Math.max(last.start+.05,at);}
 text(at:number){
  if(this.ended!==undefined&&at>this.ended+1.2)return '';
  let segment:Segment|undefined;for(const s of this.segments){if(s.start>at)break;segment=s;}
  if(!segment)return '';
  const total=segment.phrases.reduce((n,p)=>n+p.weight,0);
  const duration=segment.end!==undefined?Math.max(.05,segment.end-segment.start):Math.max(1,total/15);
  let offset=Math.min(total-.001,Math.max(0,(at-segment.start)/duration)*total);
  for(const phrase of segment.phrases){if(offset<phrase.weight)return phrase.text;offset-=phrase.weight;}
  return '';
 }
}
