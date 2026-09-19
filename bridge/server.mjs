import {GroupChat} from './group-chat.mjs';
const group=new GroupChat();
import http from 'node:http';
import {readFile, writeFile, rename, mkdir} from 'node:fs/promises';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomBytes} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {encodeFrame, parseTarget, parseSpatial} from './protocol.mjs';
import {TextRequests} from './text-requests.mjs';
import {ActionQueue,parseQuests} from './game-context.mjs';
import {knowledge,recipient} from './quest-knowledge.mjs';
import {environmentContext} from './environment.mjs';
import {heartbeatMs} from './heartbeat.mjs';
import {Companions} from './companions.mjs';
let environmentRaw='',spatialRaw='',lastSpatialRead=0;
let microphone={enabled:false,id:'initial',generation:0};let lastMicFocus=0,lastVoiceDiagnostic='',lastVoiceStamp=0;
const actionQueue=new ActionQueue();let questMemory=null,lastQuestRead=0,lastMemoryReport='';
const textRequests=new TextRequests();
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const bundledConfig=JSON.parse(process.env.DAWNWALKER_DEFAULT_CONFIG||'{}');delete process.env.DAWNWALKER_DEFAULT_CONFIG;
const runtime = process.env.DAWNWALKER_RUNTIME || resolve(root, 'runtime');
await mkdir(runtime, {recursive:true});
const companions=new Companions(runtime,JSON.parse(await readFile(resolve(root,'characters/companion-config.json'),'utf8')));
await companions.init();setInterval(()=>companions.tick(),500);
const token = randomBytes(32).toString('hex');
const port = Number(process.env.DAWNWALKER_PORT || 32123), origin = `http://127.0.0.1:${port}`;
let target = {generation:0, active:false, actor:'', actorClass:'', status:'Waiting for the game'}, lastGame = 0;
let lastClient = 0, currentFrame = '', overlay = {text:'', status:'Open the Convai setup page', updated:Date.now()}, flushing = false;
let lastGroupDiagnostic='',replyDiagnostic=null,lastReplyDiagnostic=0;
// Single writer and atomic replacement: Lua never executes incoming data or reads half a frame.
async function atomic(name, text) {
  const path = resolve(runtime, name); await writeFile(path+'.tmp',text);
  for(let attempt=0;;attempt++){
    try{await rename(path+'.tmp',path);return;}catch(e){
      if(attempt>=4||!['EPERM','EBUSY','EACCES'].includes(e.code))throw e;
      await delay(4); // Windows readers can briefly hold a file across replacement.
    }
  }
}
setInterval(async () => {
  if (flushing) return; flushing = true;
  try {
    const raw = await readFile(resolve(runtime,'target.txt'),'utf8').catch(()=>null);
    if(raw) { const next=parseTarget(raw); target=next; }
    if(Date.now()-lastSpatialRead>=80){lastSpatialRead=Date.now();spatialRaw=await readFile(resolve(runtime,'spatial.txt'),'utf8').catch(()=>'');}
    if(Date.now()-lastQuestRead>1000){
      lastQuestRead=Date.now();
      environmentRaw=await readFile(resolve(runtime,'environment.txt'),'utf8').catch(()=>'');
      try{questMemory=parseQuests(await readFile(resolve(runtime,'quests.txt'),'utf8'));await atomic('quest-memory.json',JSON.stringify(questMemory));}catch{questMemory=null;}
    }
    actionQueue.ack(await readFile(resolve(runtime,'action-result.txt'),'utf8').catch(()=>''));
    const action=actionQueue.current(target);
    await atomic('actions.txt',action?`${action.generation}\t${Math.floor(Date.now()/1000)}\t${action.id}\t${action.name}\n`:'');
    lastGame=heartbeatMs(await readFile(resolve(runtime,'game-heartbeat.txt'),'utf8').catch(()=>''),lastGame);
    lastMicFocus=heartbeatMs(await readFile(resolve(runtime,'mic-focus.txt'),'utf8').catch(()=>''),lastMicFocus);
    const micStop=!target.active?'selection ended':microphone.generation!==target.generation?'selection changed':Date.now()-lastGame>3500?'game unavailable':Date.now()-lastMicFocus>1500?'game lost focus':Date.now()-lastClient>2500?'browser unavailable':'';
    if(micStop){if(microphone.enabled)console.error('Voice input stopped: '+micStop);microphone={enabled:false,id:microphone.id,generation:target.generation};}
    if(Date.now()-lastClient>2500) { currentFrame=encodeFrame({generation:target.generation}); overlay={text:'',status:'Convai browser disconnected / not armed',updated:Date.now()}; }
    group.tick(target,companions.state.members,Date.now()-lastGame<3500,Date.now(),await readFile(resolve(runtime,'group-ready.tsv'),'utf8').catch(()=>''));
    await atomic('group-control.tsv',group.command());
    const groupDiagnostic=JSON.stringify(group.diagnostic());
    if(groupDiagnostic!==lastGroupDiagnostic){await atomic('group-status.json',groupDiagnostic);lastGroupDiagnostic=groupDiagnostic;}
    if(replyDiagnostic&&Date.now()-lastReplyDiagnostic>=1000){await atomic('group-reply-status.json',JSON.stringify(replyDiagnostic));lastReplyDiagnostic=Date.now();}
    await atomic('frame.txt',currentFrame || encodeFrame({generation:target.generation}));
    await atomic('overlay.json',JSON.stringify({...overlay,active:target.active,generation:target.generation,actor:target.actor,name:target.name||'',mode:target.mode,room:target.room,microphoneRequested:microphone.enabled,gameAlive:Date.now()-lastGame<3500}));
  } catch(e) { console.error('Bridge file error:',e.message); } finally {flushing=false;}
},33);
const files = new Map([['/',['public/index.html','text/html']],['/client.js',['public/client.js','text/javascript']],['/reply-capture.js',['public/reply-capture.js','text/javascript']]]);
const server=http.createServer(async(req,res)=>{
  res.setHeader('Cache-Control','no-store'); res.setHeader('X-Content-Type-Options','nosniff');
  if(req.headers.host!==`127.0.0.1:${port}` || (req.headers.origin && req.headers.origin!==origin)) {res.writeHead(403).end();return;}
  const path=new URL(req.url,origin).pathname;
  try {
    if(req.method==='GET' && files.has(path)) {const [file,mime]=files.get(path);res.setHeader('Content-Type',mime);res.end(await readFile(resolve(root,'bridge',file)));return;}
    if(req.method==='GET' && path==='/session') {res.setHeader('Content-Type','application/json');res.end(JSON.stringify({token}));return;}
    if(req.headers['x-bridge-token']!==token) {res.writeHead(403).end();return;}
    if(req.method==='GET' && path==='/companions'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify(companions.view()));return;}
    if(req.method==='POST' && path==='/companions'){
      let body='';for await(const chunk of req){body+=chunk;if(body.length>16384){res.writeHead(413).end();return;}}
      try{const result=await companions.command(JSON.parse(body));res.setHeader('Content-Type','application/json');res.end(JSON.stringify(result));}
      catch(e){res.writeHead(409).end(e.message);}return;
    }
    if(req.method==='GET' && path==='/config') {
      const config={...bundledConfig,...JSON.parse(await readFile(resolve(runtime,'convai-config.json'),'utf8').catch(()=>'{}'))};
      res.setHeader('Content-Type','application/json');res.end(JSON.stringify(config));return;
    }
    if(req.method==='GET' && path==='/group-context') {
      const params=new URL(req.url,origin).searchParams,view=group.view(target),next=view?.upcoming?.find(s=>s.token===params.get('token'));
      if(!target.active||view?.stage!=='reply'||params.get('token')!==next?.token||params.get('room')!==target.room){res.writeHead(409).end('Group selection changed');return;}
      res.setHeader('Content-Type','application/json');res.end(JSON.stringify({token:next.token,questMemory:knowledge(questMemory,next.characterId),environment:environmentContext(environmentRaw,target)}));return;
    }
    if(req.method==='GET' && path==='/target') {res.setHeader('Content-Type','application/json');res.end(JSON.stringify({...target,spatial:parseSpatial(spatialRaw,target),partyCharacters:Date.now()-companions.state.updated<5000?companions.connectionCharacters():[],gameAlive:Date.now()-lastGame<3500,textRequests:target.mode==='group'?(group.view(target)?.request?[group.view(target).request]:[]):textRequests.forTarget(target),group:group.view(target),microphone,environment:environmentContext(environmentRaw,target),questMemory:knowledge(questMemory,target.active?recipient(target):(new URL(req.url,origin).searchParams.get('memoryRecipient')||'')),actionResult:actionQueue.result}));return;}
    if(req.method==='POST' && path==='/microphone'){
      let body='';for await(const chunk of req){body+=chunk;if(body.length>1024){res.writeHead(413).end();return;}}
      const value=JSON.parse(body);
      if(value.id!==undefined&&value.id!==microphone.id){res.writeHead(409).end('Microphone request changed');return;}
      if(typeof value.enabled!=='boolean'||value.generation!==target.generation||(value.enabled&&!target.active)){res.writeHead(409).end('Select a nearby character first');return;}
      if(value.enabled&&target.mode==='group')group.cancel('Listening for a new group message');
      microphone={enabled:value.enabled,generation:target.generation,id:randomBytes(12).toString('hex')};res.writeHead(204).end();return;
    }
    if(req.method==='POST' && path==='/text'){
      let body='';for await(const chunk of req){body+=chunk;if(body.length>8192){res.writeHead(413).end();return;}}
      try{const value=JSON.parse(body);if(target.mode==='group')group.start(value,target,companions.state.members);else textRequests.enqueue(value,target);res.writeHead(204).end();}catch(e){res.writeHead(409).end(e.message);}return;
    }
    if(req.method==='POST' && path==='/frame') {
      let body='';for await(const chunk of req) {body+=chunk;if(body.length>65536){res.writeHead(413).end();return;}}
      const data=JSON.parse(body);const encoded=encodeFrame(data);
      if(data.generation!==target.generation) {res.writeHead(409).end();return;}
      currentFrame=encoded;lastClient=Date.now();
      textRequests.acknowledge(data.generation,data.ackTextIds);
      actionQueue.add(target,data.actionRequests);
      if(data.groupVoice&&microphone.enabled&&target.mode==='group'){
        group.start({...data.groupVoice,generation:target.generation},target,companions.state.members,Date.now(),true);
        microphone={...microphone,enabled:false};
      }
      if(data.groupDone)group.complete(data.groupDone,target,companions.state.members);
      if(data.replyStatus&&JSON.stringify(data.replyStatus).length<2048)replyDiagnostic={updated:Date.now(),...data.replyStatus};
      if(data.memoryReport){const report=JSON.stringify(data.memoryReport);if(report.length<1500&&report!==lastMemoryReport){await atomic('quest-cloud-status.json',report);lastMemoryReport=report;}}
      const vd=data.voiceDiagnostic||{};
      const voice={device:String(vd.device||'').slice(0,140),level:Math.max(0,Math.min(1,Number(vd.level)||0)),trackState:String(vd.trackState||'off').slice(0,16),muted:vd.muted===true,meter:vd.meter===true,signalDetected:vd.signalDetected===true,silent:vd.silent===true};
      const voiceState=JSON.stringify({requested:microphone.enabled,on:data.microphoneOn===true,status:String(data.microphoneStatus||'').slice(0,200),...voice,transcribed:!!data.microphoneTranscript});
      if(voiceState!==lastVoiceDiagnostic&&Date.now()-lastVoiceStamp>500){lastVoiceStamp=Date.now();lastVoiceDiagnostic=voiceState;await atomic('microphone-status.json',JSON.stringify({updated:Date.now(),...JSON.parse(voiceState)}));}
      overlay={microphoneOn:data.microphoneOn===true,microphoneStatus:String(data.microphoneStatus||'Microphone off').slice(0,200),microphoneTranscript:String(data.microphoneTranscript||'').slice(-1200),microphoneDevice:voice.device,microphoneLevel:voice.level,microphoneSilent:voice.silent,text:String(data.subtitle??'').slice(-1200),status:String(data.status??'').slice(0,300),updated:Date.now()};
      res.writeHead(204).end();return;
    }
    res.writeHead(404).end();
  }catch(e){res.writeHead(400).end('Invalid request');}
});
export const ready=new Promise(resolve=>server.listen(port,'127.0.0.1',()=>{console.log(`Dawnwalker Convai: ${origin}`);resolve();}));
server.on('error',e=>{console.error(e.message);process.exit(1);});
