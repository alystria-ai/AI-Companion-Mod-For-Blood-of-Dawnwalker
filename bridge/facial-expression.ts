export type EmotionSignal={emotion:string;scale?:number}|null;
type Weights=Record<string,number>;
// Eye direction and head pose remain native. Upper-face expression uses the
// owned Lua face layer's curve map, alongside its unchanged fixed mouth inputs.
export function supportedFaceCurve(name:string){
 return /^CTRL_expressions_(mouth|jaw|tongue)/.test(name)||/^CTRL_expressions_(eyeBlink|eyeWiden|eyeSquintInner|eyeCheekRaise|browDown|browLateral|browRaiseIn|browRaiseOuter|noseWrinkle)[LR]$/.test(name);
}
const poses:Record<string,Weights>={
 joy:{mouthCornerPull:.30,mouthCornerUp:.12,mouthDimple:.07,eyeCheekRaise:.18},
 trust:{mouthCornerPull:.20,mouthCornerUp:.07,eyeCheekRaise:.09},
 sadness:{mouthCornerDepress:.17,mouthCornerDown:.06,jawChinRaiseU:.08,browRaiseIn:.22,browDown:.08},
 anger:{mouthLipsTightenU:.16,mouthLipsTightenD:.13,mouthCornerDepress:.065,browDown:.23,eyeSquintInner:.12},
 fear:{mouthStretch:.15,mouthCornerDepress:.055,browRaiseIn:.20,eyeWiden:.13},
 surprise:{mouthFunnelU:.08,mouthFunnelD:.07,browRaiseIn:.22,browRaiseOuter:.25,eyeWiden:.18},
 disgust:{mouthUpperLipRaise:.14,mouthCornerDepress:.08,noseWrinkle:.20,browDown:.13},
 anticipation:{mouthDimple:.08,mouthCornerPull:.065,browRaiseOuter:.13},
 neutral:{},
};
const aliases:Record<string,string>={
 joy:'joy',happy:'joy',happiness:'joy',serenity:'joy',ecstasy:'joy',amusement:'joy',optimism:'joy',
 trust:'trust',acceptance:'trust',admiration:'trust',love:'trust',affection:'trust',gratitude:'trust',
 sadness:'sadness',sad:'sadness',pensiveness:'sadness',grief:'sadness',remorse:'sadness',disappointment:'sadness',
 anger:'anger',angry:'anger',annoyance:'anger',rage:'anger',frustration:'anger',aggressiveness:'anger',
 fear:'fear',afraid:'fear',apprehension:'fear',terror:'fear',anxiety:'fear',submission:'fear',
 surprise:'surprise',surprised:'surprise',distraction:'surprise',amazement:'surprise',awe:'surprise',
 disgust:'disgust',disgusted:'disgust',boredom:'disgust',loathing:'disgust',contempt:'disgust',disapproval:'sadness',
 anticipation:'anticipation',interest:'anticipation',vigilance:'anticipation',curiosity:'anticipation',neutral:'neutral',
};
const clamp=(v:number)=>Number.isFinite(v)?Math.max(0,Math.min(1,v)):0;
function expand(pose:Weights,scale=1):Weights{
 const result:Weights={};
 for(const [name,value]of Object.entries(pose))for(const side of ['L','R'])result['CTRL_expressions_'+name+side]=value*scale;
 return result;
}
export class FacialExpression {
 private mood='';private intensity=1;private changedAt=0;private lastAt=0;private lastSpeakingAt=0;private current:Weights={};
 reset(){this.mood='';this.intensity=1;this.changedAt=0;this.lastAt=0;this.lastSpeakingAt=0;this.current={};}
 receive(signal:EmotionSignal,now=performance.now()){
  if(signal===null){this.reset();return;}
  if(typeof signal?.emotion!=='string')return;
  this.mood=aliases[signal.emotion.trim().toLowerCase()]||'neutral';
  this.intensity=[.55,.8,1][Math.max(0,Math.min(2,Math.round(Number(signal.scale)||1)-1))];
  this.changedAt=now;
 }
 diagnostic(){return {mood:this.mood||'gentle greeting',intensity:this.intensity,source:this.mood?'convai':'default'};}
 mix(speech:Weights,speaking:boolean,thinking=false,now=performance.now()):Weights{
  const delta=this.lastAt?Math.max(0,Math.min(.1,(now-this.lastAt)/1000)):1/60;this.lastAt=now;
  // Keep the detected reaction through speech, hold for two seconds afterward,
  // then crossfade back to the listening smile over three seconds. A neutral
  // label must not permanently replace the resting expression with zeroes.
  if(speaking)this.lastSpeakingAt=now;
  const age=(now-Math.max(this.changedAt,this.lastSpeakingAt))/1000;
  const fade=this.mood&&this.mood!=='neutral'?Math.max(0,Math.min(1,(5-age)/3)):0;
  if(fade===0)this.mood='';
  const pose=expand({mouthCornerPull:.21,mouthCornerUp:.075,mouthDimple:.04,eyeCheekRaise:.10},(thinking?0:speaking?.35:1)*(1-fade));
  if(this.mood)for(const [name,value]of Object.entries(expand(poses[this.mood],this.intensity*fade)))pose[name]=(pose[name]||0)+value;
  const out={...speech};
  const articulation=Math.max(...['mouthFunnelUL','mouthFunnelUR','mouthLipsPurseUL','mouthLipsPurseUR','mouthLipsTogetherUL','mouthLipsTogetherUR'].map(k=>clamp(speech['CTRL_expressions_'+k]||0)));
  const speechScale=speaking?.45*(1-.8*articulation):1;
  for(const name of new Set([...Object.keys(this.current),...Object.keys(pose)])){
   // Brows and cheeks can express emotion without suppressing lip closures.
   const upper=/^CTRL_expressions_(eye|brow|nose)/.test(name);
   const target=(pose[name]||0)*(upper?1:speechScale);
   const previous=this.current[name]||0;
   const value=previous+(target-previous)*(1-Math.exp(-delta/(target>previous?.4:.7)));
   if(value<.0001&&target===0){delete this.current[name];continue;}
   this.current[name]=value;
   // Do not add expression strength on top of an already expressive speech curve.
   out[name]=Math.max(clamp(out[name]||0),clamp(value));
  }
  // Opens the verified numeric curve path for a quiet listening expression too.
  out.CTRL_expressions_jawOpen=clamp(speech.CTRL_expressions_jawOpen||0);
  return out;
 }
}
