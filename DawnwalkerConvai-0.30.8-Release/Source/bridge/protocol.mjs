export function encodeFrame(data, now = Date.now()) {
  if (!data || !Number.isSafeInteger(data.generation) || data.generation < 0) throw Error('Invalid generation');
  const entries = Object.entries(data.weights ?? {});
  if (entries.length > 300) throw Error('Too many weights');
  const weights = entries.map(([name, value]) => {
    if (!/^[A-Za-z0-9_]{1,100}$/.test(name) || typeof value !== 'number' || !Number.isFinite(value)) throw Error('Invalid weight');
    return `${name}\t${Math.max(0, Math.min(1, value)).toFixed(4)}`;
  });
  // Keep completion in the same generation-stamped frame as the final weights.
  // A hyphenated record name cannot be interpreted as a morph channel by Lua.
  const done=data.singleDone;
  if(done!==undefined&&done!==null&&(typeof done!=='string'||!/^[A-Za-z0-9-]{1,128}$/.test(done)))throw Error('Invalid reply completion');
  return `${data.generation}\t${Math.floor(now / 1000)}\n${weights.join('\n')}\n${done?`REPLY-END\t${done}\n`:''}`;
}
export function parseTarget(raw) {
  const [generation, active, actor = '', actorClass = '', status = '', mode = 'text', request = '1', name, definition='', bodyType='', voiceTag='',room='',turn=''] = raw.trimEnd().split(/\r?\n/);
  const n = Number(generation);
  if (!Number.isSafeInteger(n) || n < 0 || !['0','1'].includes(active)) throw Error('Invalid target');
  const requestId=Number(request);
  if(!Number.isSafeInteger(requestId)||requestId<0)throw Error('Invalid request ID');
  return {...(name===undefined?{}:{name,definition,bodyType,voiceTag}),generation: n, active: active === '1', actor, actorClass, status, mode:mode==='group'?'group':'single',room,turn,requestId};
}
export function parseSpatial(raw,target,now=Date.now()){
  if(!target.active||typeof raw!=='string'||raw.length>256)return null;
  const fields=raw.trim().split('\t');
  if(fields.length!==5||fields.some(v=>!v.trim()))return null;
  const [stamp,generation,...position]=fields.map(Number);
  if(!Number.isSafeInteger(stamp)||!Number.isSafeInteger(generation)||generation!==target.generation||Math.abs(now-stamp*1000)>2000||position.some(n=>!Number.isFinite(n)||Math.abs(n)>1000))return null;
  return {generation,at:stamp*1000,position};
}
