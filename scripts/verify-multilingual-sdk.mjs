// Exercise the actual Web SDK conversation path for profiles whose Core API
// response did not reflect the dashboard language setting.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';

const run=promisify(execFile),root=resolve('runtime/multilingual-sdk-verification');
const state=JSON.parse(await readFile('runtime/multilingual-characters.json','utf8'));
const keys=['ambrus','male-2','male-3','male-5','female-1','female-2','female-3','female-4','vicho'];
const reportPath=resolve(root,'report.json');
await mkdir(root,{recursive:true});
let report={};try{report=JSON.parse(await readFile(reportPath,'utf8'));}catch{}
for(const key of keys){
 if(report[key]?.result==='Russian')continue;
 const directory=resolve(root,key);await mkdir(directory,{recursive:true});
 let execution='';try{
  const result=await run(process.execPath,['scripts/benchmark-convai.mjs',directory,'prepared',key,state[key].id,
   'Привет! Что ты думаешь о нашей долине?'],{timeout:90000,maxBuffer:1048576,windowsHide:true});
  execution=result.stdout;
 }catch(error){execution=error.stdout||error.message;}
 let response={};try{response=JSON.parse(await readFile(resolve(directory,'result.json'),'utf8'));}catch{}
 const text=response.reply||'',letters=(text.match(/\p{L}/gu)||[]).length;
 const cyrillic=(text.match(/[\u0400-\u04ff]/gu)||[]).length;
 const result=response.done&&letters&&cyrillic/letters>=0.5?'Russian':'Other';
 report[key]={result,reply:text.slice(0,250),error:response.error||'',audioReady:!!response.firstPcmMs};
 await writeFile(reportPath,JSON.stringify(report,null,2));
 process.stdout.write(key+': '+result+(response.error?' (SDK error)':'')+'\n');
}
const failed=keys.filter(key=>report[key]?.result!=='Russian'||!report[key]?.audioReady);
process.stdout.write('Russian SDK replies with audio: '+(keys.length-failed.length)+'/'+keys.length+'\n');
if(failed.length){process.stdout.write('Needs review: '+failed.join(', ')+'\n');process.exitCode=1;}
