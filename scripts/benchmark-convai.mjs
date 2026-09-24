// Real Convai test in an isolated, muted browser. No microphone or game inputs.
import {build} from 'esbuild';import http from 'node:http';import {spawn} from 'node:child_process';import {readFile,writeFile,mkdir} from 'node:fs/promises';import {resolve} from 'node:path';
const output=resolve(process.argv[2]),mode=process.argv[3]||'prepared';await mkdir(output,{recursive:true});
const config=JSON.parse((await readFile('runtime/convai-config.json','utf8')).replace(/^\uFEFF/,''));const profile=config.roster.find(p=>p.key===(process.argv[4]||'anca'));
const characterId=process.argv[5]||profile.id;
const question=process.argv[6]||('Hello '+profile.name+'. How do you feel about travelling with me? Please answer in one short sentence.');
const context=process.argv[7]?await readFile(resolve(process.argv[7]),'utf8'):'';
const source=`import {ConvaiClient,AudioRenderer} from '@convai/web-sdk/vanilla';import {PreparedReply} from './bridge/prepared-reply';
const cfg=await(await fetch('/config')).json(),events=[],metrics=[];let sent=0,firstText=0,finalText=0,firstSpeech=0,firstPcm=0,c,p,renderer,timer;
const start=performance.now(),mark=(name,data)=>events.push({name,ms:Math.round(performance.now()-(sent||start)),data});
try{
 c=new ConvaiClient({apiKey:cfg.apiKey,characterId:cfg.id,endUserId:crypto.randomUUID(),startWithAudioOn:false,transport:'livekit',enableLipsync:true,enableVideo:false,blendshapeConfig:{format:'mha',output_fps:60},logRtviMessages:false});
 c.on('error',e=>mark('error',String(e).slice(0,250)));c.on('metrics',data=>metrics.push(data));
 c.on('messagesChange',messages=>{const rows=messages.filter(m=>['bot-llm-text','convai'].includes(m.type)&&m.content?.trim());if(rows.length&&!firstText){firstText=performance.now();mark('first-text');}if(rows.length&&rows.every(m=>m.isStreaming!==true)&&!finalText){finalText=performance.now();mark('final-text');}});
 c.on('stateChange',()=>{if(c.state.isSpeaking&&!firstSpeech){firstSpeech=performance.now();mark('first-speech');}});
 c.on('botTtsStarted',()=>mark('tts-start'));c.on('botTtsStopped',()=>mark('tts-stop'));c.room.on('trackSubscribed',track=>mark('track',{kind:track.kind,muted:track.mediaStreamTrack.muted,enabled:track.mediaStreamTrack.enabled}));
 await c.connect();for(let i=0;i<300&&!c.isBotReady;i++)await new Promise(r=>setTimeout(r,50));if(!c.isBotReady)throw Error('Bot-ready timeout');const connectMs=Math.round(performance.now()-start);
 p=new PreparedReply(c,'benchmark','bench-token','benchmark');
 if(cfg.mode==='attached'){renderer=new AudioRenderer(c.room);await c.room.startAudio();}
 if(cfg.mode==='primed'){
  const attach=track=>{if(track.kind!=='audio')return;const el=document.createElement('audio');el.autoplay=true;el.muted=true;track.attach(el);document.body.appendChild(el);void el.play().catch(()=>{});};
  c.room.on('trackSubscribed',attach);c.room.remoteParticipants.forEach(p=>p.audioTrackPublications.forEach(pub=>{if(pub.track)attach(pub.track);}));await c.room.startAudio();
 }
 sent=performance.now();await p.start(cfg.question, cfg.context||('You are '+cfg.name+' in Vale Sangora, talking to Coen. This is a short conversation, not a quest update. Answer naturally in one short sentence, without stage directions. Do not invent completed quests.'));
 timer=setInterval(()=>{p.tick();if(p.audio.hasAudio&&!firstPcm){firstPcm=performance.now();mark('first-pcm');}if(performance.now()-sent>=5000)p.activated=true;},16);
 for(let i=0;i<900;i++){await new Promise(r=>setTimeout(r,50));if(p.error||p.view().done)break;}
 const report={mode:cfg.mode,connectMs,firstTextMs:firstText?Math.round(firstText-sent):null,finalTextMs:finalText?Math.round(finalText-sent):null,firstSpeechMs:firstSpeech?Math.round(firstSpeech-sent):null,firstPcmMs:firstPcm?Math.round(firstPcm-sent):null,capturedMs:p.audio.capturedMs,done:p.view().done,error:p.error,reply:p.reply.text,metrics,events,audio:{state:p.audio.context?.state,clock:p.audio.clock,source:!!p.audio.source,origin:p.audio.origin,finished:p.audio.finished}};
 await fetch('/result',{method:'POST',body:JSON.stringify(report)});
}catch(e){await fetch('/result',{method:'POST',body:JSON.stringify({error:String(e),events,metrics})});}finally{clearInterval(timer);p?.stop(true);renderer?.destroy();await c?.disconnect();}`;
const b=await build({stdin:{contents:source,resolveDir:process.cwd()},bundle:true,write:false,format:'esm'});
let done;const result=new Promise(r=>done=r);
const server=http.createServer(async(req,res)=>{
 if(req.headers.origin&&req.headers.origin!==`http://127.0.0.1:${server.address().port}`){res.writeHead(403).end();return;}
 if(req.url==='/result'){let body='';for await(const part of req)body+=part;res.end('ok');done(JSON.parse(body));return;}
 res.setHeader('Cache-Control','no-store');res.setHeader('Content-Type',req.url==='/'?'text/html':req.url==='/config'?'application/json':'text/javascript');
 res.end(req.url==='/'?'<script type="module" src="/bench.js"></script>':req.url==='/config'?JSON.stringify({apiKey:config.apiKey,id:characterId,name:profile.name,mode,question,context}):req.url==='/bench.js'?b.outputFiles[0].text:await readFile('bridge/public/reply-capture.js'));
});await new Promise(r=>server.listen(0,'127.0.0.1',r));
const child=spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless=new','--disable-gpu','--mute-audio','--autoplay-policy=no-user-gesture-required','--disable-background-timer-throttling','--no-first-run','--remote-debugging-port=0','--user-data-dir='+resolve(output,'edge-profile'),`http://127.0.0.1:${server.address().port}/`],{windowsHide:true,stdio:'ignore'});
let timer;try{
 const report=await Promise.race([result,new Promise(r=>timer=setTimeout(()=>r({error:'Browser test timeout'}),65000))]);
 await writeFile(resolve(output,'result.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({...report,metrics:report.metrics?.length,events:report.events?.filter(e=>e.name!=='track')}));
 if(report.error||!report.done||!report.firstPcmMs)process.exitCode=1;
}finally{
 clearTimeout(timer);try{const [port,path]=(await readFile(resolve(output,'edge-profile/DevToolsActivePort'),'utf8')).trim().split('\n');const ws=new WebSocket('ws://127.0.0.1:'+port+path.trim());await new Promise((resolve,reject)=>{ws.onopen=()=>{ws.send(JSON.stringify({id:1,method:'Browser.close'}));resolve();};ws.onerror=reject;setTimeout(reject,1000);});ws.close();}catch{child.kill();}
 server.closeAllConnections();server.close();
}
