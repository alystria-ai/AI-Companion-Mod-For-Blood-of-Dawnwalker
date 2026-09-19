import {createHash} from 'node:crypto';
export function environmentContext(raw,target,now=Date.now()){
  const unavailable={revision:'unavailable',text:'Current surroundings are unavailable. Do not infer location or weather from earlier observations.'};
  if(!target.active)return unavailable;
  const [stamp,gen,region,hour,minute,rain,snow]=String(raw||'').trimEnd().split('\t');
  if(!Number.isFinite(Number(stamp))||Math.abs(now-Number(stamp)*1000)>12000||Number(gen)!==target.generation)return unavailable;
  const facts=[];
  if(region&&region.length<=180&&!/[\r\n]/.test(region))facts.push('Current region: '+region+'. This identifies a region, not a specific building or room.');
  const h=Number(hour),m=Number(minute);
  if(hour!==''&&minute!==''&&Number.isInteger(h)&&h>=0&&h<24&&Number.isInteger(m)&&m>=0&&m<60)facts.push('Current game time: '+String(h).padStart(2,'0')+':'+String(m).padStart(2,'0')+'. Refer to the time naturally rather than reciting a clock reading unless asked.');
  const r=Number(rain),s=Number(snow);
  if(rain!==''&&snow!==''&&Number.isFinite(r)&&Number.isFinite(s)&&r>=0&&s>=0){
    facts.push('Current regional precipitation: '+(r>0.01?'rain is active':s>0.01?'snow is active':'no rain or snow is active')+'. Indoor/outdoor exposure, temperature, cloud cover and visibility have not been established; do not claim you are getting wet or can see the sky.');
  }
  if(!facts.length)return unavailable;
  const text='Temporary observations near the current conversation. Use only when relevant; these replace old surroundings and are not permanent quest memories.\n'+facts.join('\n');
  return {revision:createHash('sha256').update(text).digest('hex'),text};
}
