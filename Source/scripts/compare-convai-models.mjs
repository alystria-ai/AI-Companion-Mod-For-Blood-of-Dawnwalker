import {readFile,writeFile,mkdir} from 'node:fs/promises';import {resolve} from 'node:path';import {spawn} from 'node:child_process';import {setTimeout as delay} from 'node:timers/promises';
const root=resolve('runtime/session-v0277'),cfg=JSON.parse((await readFile('runtime/convai-config.json','utf8')).replace(/^\uFEFF/,'')),profile=cfg.roster.find(p=>p.key==='anca');
const catalog=JSON.parse((await readFile(resolve(root,'models-live.json'),'utf8')));const models=JSON.parse(catalog.STATUS);const original=models.find(m=>m.is_active).model_group_name;
const candidates=process.argv.slice(2);if(candidates.some(id=>!models.some(m=>m.model_group_name===id&&!m.is_deprecated)))throw Error('Unsupported model candidate');
async function api(path,body){await delay(3000);const res=await fetch('https://api.convai.com'+path,{method:'POST',headers:{'CONVAI-API-KEY':cfg.apiKey,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});if(!res.ok)throw Error('Core API '+res.status);const d=await res.json();if(d.API_ERROR||d.ERROR)throw Error('Core API rejected model operation');return d;}
async function select(model){await api('/character/update',{charID:profile.id,model_group_name:model});const selected=JSON.parse((await api('/character/getSupportedModel',{charID:profile.id})).STATUS);if(!selected.some(m=>m.model_group_name===model&&m.is_active))throw Error('Model readback mismatch');}
const results=[];try{
 for(const model of candidates){
  await select(model);console.log('Testing '+model);
  for(let run=1;run<=2;run++){
   const dir=resolve(root,model+'-'+run);await mkdir(dir,{recursive:true});
   await new Promise((resolve,reject)=>{const child=spawn(process.execPath,['scripts/benchmark-convai.mjs',dir,'prepared'],{windowsHide:true,stdio:'ignore'});child.on('error',reject);child.on('exit',code=>code===0?resolve():reject(Error('Benchmark failed')));});
   const r=JSON.parse(await readFile(resolve(dir,'result.json'),'utf8'));results.push({model,run,...r});
   await writeFile(resolve(root,'model-comparison.json'),JSON.stringify(results,null,2));console.log(JSON.stringify({model,run,firstTextMs:r.firstTextMs,firstSpeechMs:r.firstSpeechMs,firstPcmMs:r.firstPcmMs,error:r.error,reply:r.reply}));
  }
 }
}finally{await select(original);console.log('Restored original model: '+original);}
