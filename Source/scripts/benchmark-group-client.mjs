// Run the actual browser bridge and group coordinator against real Convai,
// simulating only Lua actor selection. It never sends input/files to the game.
import {build} from 'esbuild';import http from 'node:http';import {spawn} from 'node:child_process';import {readFile,writeFile,mkdir} from 'node:fs/promises';import {resolve} from 'node:path';import {randomUUID} from 'node:crypto';import {GroupChat} from '../bridge/group-chat.mjs';
const output=resolve(process.argv[2]);await mkdir(output,{recursive:true});const config=JSON.parse((await readFile('runtime/convai-config.json','utf8')).replace(/^\uFEFF/,''));
const roster=['anca','lacra','pieter'].map(key=>config.roster.find(p=>p.key===key));if(roster.some(p=>!p))throw Error('Benchmark roster unavailable');
const group=new GroupChat(),members=roster.slice(1).map(p=>({id:p.key,actor:p.key,characterId:p.key,name:p.name,distance:400,available:true}));
const spatialTest=process.argv.includes('--spatial');
// Test-only analyser taps prove decoded sound reaches each production panner.
const spatialProbe=`<script>
const probes=[],create=AudioContext.prototype.createPanner;
AudioContext.prototype.createPanner=function(){const p=create.call(this),a=this.createAnalyser();a.fftSize=1024;p.connect(a);probes.push({a,peak:0,data:new Float32Array(1024)});return p;};
setInterval(()=>{for(const p of probes){p.a.getFloatTimeDomainData(p.data);p.peak=Math.max(p.peak,...p.data.map(Math.abs));}},20);
const originalFetch=window.fetch;window.fetch=(url,options)=>{if(url==='/frame'&&options?.body){const body=JSON.parse(options.body);body.spatialProbe=probes.map(p=>p.peak);options={...options,body:JSON.stringify(body)};}return originalFetch(url,options);};
</script>`;
let target={generation:1,active:false,actor:'anca',actorClass:'NPC',name:'Anca',mode:'group',room:'benchmark',turn:'',gameAlive:true,requestId:0};
const at=Date.now(),turns=[],failures=[];let started=false,done;const result=new Promise(r=>done=r);let lastFrame;
const b=await build({entryPoints:['bridge/client.ts'],bundle:true,write:false,format:'esm'});
const server=http.createServer(async(req,res)=>{
 const url=new URL(req.url,'http://localhost');if(req.headers.origin&&req.headers.origin!==`http://127.0.0.1:${server.address().port}`){res.writeHead(403).end();return;}
 res.setHeader('Cache-Control','no-store');res.setHeader('Content-Type','application/json');
 if(url.pathname==='/'){res.setHeader('Content-Type','text/html');res.end((spatialTest?spatialProbe:'')+'<input id="key"><input id="character"><input id="mapping" value="{}"><button id="arm"></button><button id="stop"></button><div id="status"></div><div id="subtitle"></div><div id="detail"></div><script type="module" src="/client.js"></script>');return;}
 if(url.pathname==='/client.js'||url.pathname==='/reply-capture.js'){res.setHeader('Content-Type','text/javascript');res.end(url.pathname==='/client.js'?b.outputFiles[0].text:await readFile('bridge/public/reply-capture.js'));return;}
 if(url.pathname==='/session'){res.end(JSON.stringify({token:'isolated-benchmark'}));return;}
 if(url.pathname==='/config'){res.end(JSON.stringify({apiKey:config.apiKey,characterId:roster[0].id,roster}));return;}
 const g=group.view(target);
 const quest=p=>({recipient:p.key,revision:'unavailable',text:'No current quest completion or relationship changes have been verified. Stay in your configured character.',facts:[],ledger:[]});
 if(url.pathname==='/target'){const p=roster.find(p=>p.name===target.name)||roster[0];res.end(JSON.stringify({...target,spatial:spatialTest?{generation:target.generation,at:Date.now(),position:[[-2,0,-3],[2,0,-3],[0,0,5]][group.round?.index||0]}:null,status:'Isolated real API benchmark',partyCharacters:roster.map(p=>p.key),group:g,textRequests:g?.request?[g.request]:[],questMemory:quest(p),environment:{revision:'benchmark',text:'Coen and his companions are together in Vale Sangora.'}}));return;}
 if(url.pathname==='/group-context'){const next=g?.upcoming?.find(s=>s.token===url.searchParams.get('token'));if(!next){res.writeHead(409).end();return;}res.end(JSON.stringify({token:next.token,questMemory:quest(roster.find(p=>p.key===next.characterId)),environment:{text:'Coen and his companions are together in Vale Sangora.'}}));return;}
 if(url.pathname==='/frame'){
  let body='';for await(const part of req)body+=part;const f=JSON.parse(body);lastFrame=f.replyStatus;
  if(f.status?.includes('unavailable')||f.replyStatus?.lastPreparationFailure)failures.push({at:Date.now()-at,status:f.status,error:f.replyStatus?.lastPreparationFailure});
  if(!started&&f.replyStatus?.ready&&f.replyStatus?.connections?.ready>=2){started=true;target={...target,active:true,generation:2};group.start({generation:2,id:'send1',text:'How do you feel about travelling together? Each of you, answer in one short sentence.'},target,members);turns.push({name:'Anca',selected:Date.now()-at});}
  else if(group.round?.stage==='reply'){
   const turn=turns.at(-1),playing=group.round.index===0?f.replyStatus?.speaking:f.replyStatus?.prepared?.playing;
   if(playing&&!turn.audioStarted){turn.audioStarted=Date.now()-at;turn.waitMs=turn.audioStarted-turn.selected;}
   if(f.subtitle)turn.lastSubtitle=f.subtitle;
   if(f.groupDone&&group.complete(f.groupDone,target,members)){
    turn.completed=Date.now()-at;turn.reply=f.groupDone.text;
    // A direct renderer may be restored after buffered playback completes;
    // its idle panner is permitted, but exactly three outputs must carry speech.
    if(group.round.stage==='done'){done({passed:turns.length===3&&turns.every(t=>t.audioStarted&&t.reply)&&(!spatialTest||f.spatialProbe?.filter(n=>n>0.001).length===3),turns,spatialPeaks:f.spatialProbe,failures:failures.slice(-8),lastFrame});}
    else {const next=group.round.speakers[group.round.index];target={...target,generation:target.generation+2,actor:next.actor,name:next.name,turn:group.round.token};group.tick(target,members,true);turns.push({name:next.name,selected:Date.now()-at});}
   }
  }
  res.writeHead(204).end();return;
 }
 res.writeHead(204).end();
});await new Promise(r=>server.listen(0,'127.0.0.1',r));
const child=spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless=new','--disable-gpu','--mute-audio','--autoplay-policy=no-user-gesture-required','--disable-background-timer-throttling','--no-first-run','--remote-debugging-port=0','--user-data-dir='+resolve(output,'edge-profile'),`http://127.0.0.1:${server.address().port}/?auto=1`],{windowsHide:true,stdio:'ignore'});
let timer;try{const report=await Promise.race([result,new Promise(r=>timer=setTimeout(()=>r({passed:false,error:'Group benchmark timeout',turns,lastFrame}),110000))]);await writeFile(resolve(output,'result.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));if(!report.passed)process.exitCode=1;}
finally{clearTimeout(timer);try{const [port,path]=(await readFile(resolve(output,'edge-profile/DevToolsActivePort'),'utf8')).trim().split('\n');const ws=new WebSocket('ws://127.0.0.1:'+port+path.trim());await new Promise((resolve,reject)=>{ws.onopen=()=>{ws.send(JSON.stringify({id:1,method:'Browser.close'}));resolve();};ws.onerror=reject;setTimeout(reject,1000);});ws.close();}catch{child.kill();}server.closeAllConnections();server.close();}
