import {ambientContext,parseAmbientMessage,parseObservationContext,ambientReady} from './ambient-comments.mjs';
import {ReactionDelivery} from './reaction-delivery.mjs';
import {AddonRegistry} from './addon-registry.mjs';
import {localAddonAction} from './local-addon-actions.mjs';
import {GroupChat,chooseSpeakers} from './group-chat.mjs';
import {parseFollowUpQuestions,conversationContext} from './conversation-context.mjs';
const group=new GroupChat();
import http from 'node:http';
import {readFile, writeFile, rename, mkdir} from 'node:fs/promises';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomBytes} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {encodeFrame, parseTarget, parseSpatial} from './protocol.mjs';
import {TextRequests} from './text-requests.mjs';
import {ActionQueue,parseQuests,activeQuestContext} from './game-context.mjs';
import {knowledge as questKnowledge,recipient} from './quest-knowledge.mjs';
import {parseRelationships,relationshipKnowledge,relationshipProfiles,hasSharedRomance,groupRomanceContext} from './relationships.mjs';
import {battleContext} from './battle-context.mjs';
let relationships=null;
const knowledge=(snapshot,npc)=>{
 const base=relationshipKnowledge(questKnowledge(snapshot,npc),relationships,npc);
 const audience=target.active&&target.mode==='group'&&Date.now()-companions.state.updated<5000
  ?group.audience(target,companions.state.members):[];
 const banter=groupRomanceContext(relationships,npc,audience);
 // Both /target and /group-context use this, so prepared replies receive the
 // same relationship context as the speaker currently playing aloud.
 const battle=battleContext(battleRaw,npc);
 return {...base,revision:base.revision+(banter?':shared-romance-group-v2':'')+':'+battle.revision,
  text:[banter,battle.text,base.text].filter(Boolean).join('\n\n')};
};
import {environmentContext} from './environment.mjs';
function conversationEnvironment(target){const result=environmentContext(environmentRaw,target),quest=target.active?activeQuestContext(questMemory):'';return {...result,revision:result.revision+quest,text:result.text+quest};}
import {heartbeatMs} from './heartbeat.mjs';
import {Companions} from './companions.mjs';
let environmentRaw='',battleRaw='',spatialRaw='',lastSpatialRead=0,hordeText='';
let microphone={enabled:false,id:'initial',generation:0};let lastMicFocus=0,lastVoiceDiagnostic='',lastVoiceStamp=0;
const actionQueue=new ActionQueue();let questMemory=null,lastQuestRead=0,lastMemoryReport='';
const textRequests=new TextRequests();
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const romanceVariants=JSON.parse(await readFile(resolve(root,'characters/romance-config.json'),'utf8').catch(()=>'{}'));
const bundledConfig=JSON.parse(process.env.DAWNWALKER_DEFAULT_CONFIG||'{}');delete process.env.DAWNWALKER_DEFAULT_CONFIG;
const runtime = process.env.DAWNWALKER_RUNTIME || resolve(root, 'runtime');
const addons=new AddonRegistry(runtime);
let followUpQuestions=true,ambientEnabled=true,lootCommentsEnabled=true,battleCommentsEnabled=true,lastManual=Date.now(),lastAmbient='',lastAmbientPoll=0,lootObservation=null,observationDetails=null;
async function readConversationSettings(){
 try{
  const directory=(await readFile(resolve(runtime,'mod-directory.txt'),'utf8').catch(()=>resolve(root,'mod'))).trim();
  const source=await readFile(resolve(directory,'config.ini'),'utf8');
  followUpQuestions=parseFollowUpQuestions(source);
  const ambient=source.match(/^AmbientComments\s*=\s*([01](?:\.0+)?)\s*$/m);ambientEnabled=!ambient||Number(ambient[1])===1;
  const loot=source.match(/^LootComments\s*=\s*([01](?:\.0+)?)\s*$/m);lootCommentsEnabled=!loot||Number(loot[1])===1;
  const battle=source.match(/^BattleComments\s*=\s*([01](?:\.0+)?)\s*$/m);battleCommentsEnabled=!battle||Number(battle[1])===1;
 }catch{/* Keep the last setting if an editor temporarily holds the file. */}
}
await readConversationSettings();
function conversationFor(view,index){
 if(/^(ambient|loot|battle)-/.test(target.room||''))return ambientContext(target.room,lootObservation?.room===target.room?lootObservation.text:'',observationDetails?.room===target.room&&observationDetails.generation===target.generation?observationDetails.text:'');
 const active=view&&view.stage!=='done';
 // Voice starts generating before its transcript creates the group round.
 // Predict the number of distinct eligible speakers so that first reply does
 // not ask Coen a question ahead of the remaining companions.
 const count=active?view.count:target.mode==='group'
  ?chooseSpeakers(target,Date.now()-companions.state.updated<5000?companions.state.members:[],'',hasSharedRomance(relationships)).length:1;
 const result=conversationContext(followUpQuestions,target.mode,index??(active?view.index:0),count);
 const external=addons.profile(target);
 if(!external)return result;
 const mode=external.silentReplies
  ?'Command-only mode. Interpret Coen\'s order and request an available structured action. Do not generate spoken or written dialogue, narration, or a follow-up question. Do not invent unsupported tricks or claim an action has completed.'
  :result.text;
 return {...result,followUpQuestions:!external.silentReplies&&result.followUpQuestions,revision:result.revision+':addon:'+external.key+':'+external.silentReplies+':'+external.actions.join(',')+':'+external.context,text:mode+'\n\nContext from the character owning mod: '+external.context};
}
await mkdir(runtime, {recursive:true});
const companions=new Companions(runtime,JSON.parse(await readFile(resolve(root,'characters/companion-config.json'),'utf8')));
await companions.init();setInterval(()=>companions.tick(),500);
const token = randomBytes(32).toString('hex');
const port = Number(process.env.DAWNWALKER_PORT || 32123), origin = `http://127.0.0.1:${port}`;
let target = {generation:0, active:false, actor:'', actorClass:'', status:'Waiting for the game'}, lastGame = 0;
let lastClient = 0, currentFrame = '', overlay = {text:'', status:'Open the Convai setup page', updated:Date.now()}, flushing = false;
let lastGroupDiagnostic='',replyDiagnostic=null,lastReplyDiagnostic=0;
const reactionDelivery=new ReactionDelivery();let lastReactionDelivery='';
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
    if(raw) {
      const next=parseTarget(raw);
      if(next.generation!==target.generation||next.room!==target.room){
        if(next.active&&!/^(ambient|loot|battle)-/.test(next.room||''))lastManual=Date.now();
        // Never relabel the preceding character's subtitle/microphone frame as
        // the new conversation while the browser is acknowledging selection.
        overlay={text:'',microphoneOn:false,microphoneTranscript:'',status:'',updated:Date.now()};
        currentFrame=encodeFrame({generation:next.generation});
      }
      target=next;
    }
    if(Date.now()-lastSpatialRead>=80){lastSpatialRead=Date.now();spatialRaw=await readFile(resolve(runtime,'spatial.txt'),'utf8').catch(()=>'');}
    if(Date.now()-lastQuestRead>1000){
      lastQuestRead=Date.now();
      await readConversationSettings();
      const registry=await addons.tick();if(registry!==null)await atomic('addon-registry.tsv',registry);
      const horde=(await readFile(resolve(runtime,'horde-state.tsv'),'utf8').catch(()=>'')).trim().split('\t');
      const fresh=horde[0]==='HORDE'&&horde[1]==='1'&&Math.abs(Date.now()/1000-Number(horde[2]))<4;
      const remaining=Number(horde[7]),level=Number(horde[5])+1,levels=Number(horde[6]);
      hordeText=fresh&&horde[3]==='1'&&horde[4]==='rest'&&Number.isFinite(remaining)&&remaining>0&&level<=levels
        ?`Level ${level} / ${levels} begins in ${Math.ceil(remaining)} s`:'';
      environmentRaw=await readFile(resolve(runtime,'environment.txt'),'utf8').catch(()=>'');
      battleRaw=await readFile(resolve(runtime,'battle-context.tsv'),'utf8').catch(()=>'');
      try{relationships=parseRelationships(await readFile(resolve(runtime,'relationships.tsv'),'utf8'));}catch{}
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
    if(Date.now()-lastAmbientPoll>=250){
      lastAmbientPoll=Date.now();
      const raw=await readFile(resolve(runtime,'ambient-message.tsv'),'utf8').catch(()=>'');
      const message=parseAmbientMessage(raw,target);
      if(message&&message.id!==lastAmbient){
        const enabled=message.id.startsWith('battle-')?battleCommentsEnabled:message.id.startsWith('loot-')?lootCommentsEnabled:ambientEnabled;
        reactionDelivery.observe(message,target,!enabled?'disabled':microphone.enabled?'waiting-for-microphone':Date.now()-lastManual<5000?'waiting-after-manual-input':'ready');
        if(!enabled)lastAmbient=message.id;
        else if(!microphone.enabled&&Date.now()-lastManual>=5000){
          observationDetails={room:target.room,generation:target.generation,text:parseObservationContext(await readFile(resolve(runtime,'observation-context.tsv'),'utf8').catch(()=>''),target)};
          if(/^(loot|battle)-/.test(message.id)){lootObservation={room:message.id,text:message.text};message.text=message.id.startsWith('battle-')?'React briefly to the observed battle event described in the current context.':'React briefly to the completed item collection described in the current context.';}
          textRequests.enqueue(message,target);lastAmbient=message.id;reactionDelivery.observe(message,target,'queued');
        }
        // Connecting the chosen speaker may briefly close an old microphone.
        // Keep a fresh, matching event until queued; do not consume it on wait.
      }
      const quiet=ambientReady({enabled:ambientEnabled||lootCommentsEnabled||battleCommentsEnabled,now:Date.now(),lastGame,lastClient,lastManual,microphone:microphone.enabled||overlay.microphoneOn,reply:replyDiagnostic,pending:textRequests.forTarget(target).length>0,group:group.view(target),subtitle:overlay.text});
      await atomic('ambient-ready.tsv',`${Math.floor(Date.now()/1000)}\t${quiet?1:0}`);
      const delivery=reactionDelivery.snapshot(target);if(delivery!==lastReactionDelivery){await atomic('reaction-delivery.json',delivery);lastReactionDelivery=delivery;}
    }
    await atomic('frame.txt',currentFrame || encodeFrame({generation:target.generation}));
    await atomic('overlay.json',JSON.stringify({...overlay,hordeText,active:target.active,generation:target.generation,actor:target.actor,name:target.name||'',mode:target.mode,room:target.room,microphoneRequested:microphone.enabled,gameAlive:Date.now()-lastGame<3500}));
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
      res.setHeader('Content-Type','application/json');res.end(JSON.stringify(relationshipProfiles(config,romanceVariants)));return;
    }
    if(req.method==='GET' && path==='/group-context') {
      const params=new URL(req.url,origin).searchParams,view=group.view(target),next=view?.upcoming?.find(s=>s.token===params.get('token'));
      if(!target.active||view?.stage!=='reply'||params.get('token')!==next?.token||params.get('room')!==target.room){res.writeHead(409).end('Group selection changed');return;}
      res.setHeader('Content-Type','application/json');res.end(JSON.stringify({token:next.token,conversation:conversationFor(view,view.index+1+view.upcoming.indexOf(next)),questMemory:knowledge(questMemory,next.characterId),environment:conversationEnvironment(target)}));return;
    }
    if(req.method==='GET' && path==='/target') {const external=addons.profile(target);if(external?.localActionsOnly)textRequests.acknowledge(target.generation,textRequests.forTarget(target).map(item=>item.id));res.setHeader('Content-Type','application/json');res.end(JSON.stringify({...target,externalProfile:external,conversation:conversationFor(group.view(target)),relationships:relationships&&Date.now()-relationships.updated<=10000?relationships.characters:{},spatial:parseSpatial(spatialRaw,target),partyCharacters:Date.now()-companions.state.updated<5000?companions.connectionCharacters():[],gameAlive:Date.now()-lastGame<3500,textRequests:target.mode==='group'?(group.view(target)?.request?[group.view(target).request]:[]):textRequests.forTarget(target),group:group.view(target),microphone,environment:conversationEnvironment(target),questMemory:knowledge(questMemory,target.active?(external?.key||recipient(target)):(new URL(req.url,origin).searchParams.get('memoryRecipient')||'')),actionResult:actionQueue.result}));return;}
    if(req.method==='POST' && path==='/microphone'){
      let body='';for await(const chunk of req){body+=chunk;if(body.length>1024){res.writeHead(413).end();return;}}
      const value=JSON.parse(body);
      if(value.id!==undefined&&value.id!==microphone.id){res.writeHead(409).end('Microphone request changed');return;}
      if(typeof value.enabled!=='boolean'||value.generation!==target.generation||(value.enabled&&!target.active)){res.writeHead(409).end('Select a nearby character first');return;}
      if(value.enabled&&addons.profile(target)?.localActionsOnly){res.writeHead(409).end('Spoken replies are Off. Use text commands for this creature.');return;}
      if(value.enabled!==microphone.enabled)lastManual=Date.now();
      else {res.writeHead(204).end();return;}
      if(value.enabled&&target.mode==='group')group.cancel('Listening for a new group message');
      microphone={enabled:value.enabled,generation:target.generation,id:randomBytes(12).toString('hex')};res.writeHead(204).end();return;
    }
    if(req.method==='POST' && path==='/text'){
      let body='';for await(const chunk of req){body+=chunk;if(body.length>8192){res.writeHead(413).end();return;}}
      try{const value=JSON.parse(body);const external=addons.profile(target);
      if(external?.localActionsOnly){const command=localAddonAction(value,target,external);actionQueue.current(target);if(actionQueue.pending.length>=8)throw Error('Wait for the previous commands to finish.');actionQueue.add({...target,externalProfile:external},[command]);}
      else if(target.addon&&!external)throw Error('Creature registration expired. Select it again.');
      else if(target.mode==='group')group.start(value,target,companions.state.members,Date.now(),false,hasSharedRomance(relationships));else textRequests.enqueue(value,target);lastManual=Date.now();res.writeHead(204).end();}catch(e){res.writeHead(409).end(e.message);}return;
    }
    if(req.method==='POST' && path==='/frame') {
      let body='';for await(const chunk of req) {body+=chunk;if(body.length>65536){res.writeHead(413).end();return;}}
      const data=JSON.parse(body);const external=addons.profile(target);
      if(data.generation!==target.generation) {res.writeHead(409).end();return;}
      if(target.addon&&(!external||external.silentReplies)){data.subtitle='';data.weights={};}
      const encoded=encodeFrame(data);
      currentFrame=encoded;lastClient=Date.now();
      textRequests.acknowledge(data.generation,data.ackTextIds);
      if(!/^(ambient|loot|battle)-/.test(target.room||''))if(!external?.localActionsOnly)actionQueue.add({...target,externalProfile:external},data.actionRequests);
      if(data.groupVoice&&microphone.enabled&&target.mode==='group'){
        group.start({...data.groupVoice,generation:target.generation},target,companions.state.members,Date.now(),true,hasSharedRomance(relationships));
        microphone={...microphone,enabled:false};
      }
      if(data.groupDone)group.complete(data.groupDone,target,companions.state.members);
      if(data.replyStatus&&JSON.stringify(data.replyStatus).length<2048)replyDiagnostic={updated:Date.now(),...data.replyStatus};
      reactionDelivery.frame(target,data);
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
