// Isolated headless Edge check using a synthetic remote tone, never a microphone
// or the running game's browser profile. All output is muted at the browser.
import {build} from 'esbuild';import http from 'node:http';import {spawn} from 'node:child_process';
import {readFile,writeFile,mkdir} from 'node:fs/promises';import {resolve} from 'node:path';
const output=resolve(process.argv[2]||'runtime/audio-verification');await mkdir(output,{recursive:true});
const b=await build({stdin:{contents:`import {ReplyAudio} from './bridge/reply-audio';globalThis.ReplyAudio=ReplyAudio;`,resolveDir:process.cwd()},bundle:true,write:false,format:'iife'});
let done;const result=new Promise(r=>done=r);
const page=`<script src='/audio.js'></script><script>
(async()=>{let audio,source;try{
 source=new AudioContext();await source.resume();const tone=source.createOscillator(),gain=source.createGain(),stream=source.createMediaStreamDestination();
 gain.gain.value=0;tone.connect(gain);gain.connect(stream);tone.start();
 const track={kind:'audio',mediaStreamTrack:stream.stream.getAudioTracks()[0],attach(el){el.srcObject=new MediaStream([this.mediaStreamTrack]);return el;},detach(el){el.srcObject=null;}};
 const room={on(){},off(){},async startAudio(){},remoteParticipants:new Map([['bot',{audioTrackPublications:new Map([['track',{track}]])}]])};
 audio=new ReplyAudio(room);await audio.init();audio.begin();gain.gain.setValueAtTime(0.2,source.currentTime);
 await new Promise(r=>setTimeout(r,1700));if(!audio.ready)throw Error('Remote track produced no captured PCM '+JSON.stringify({sourceState:source.state,sourceTime:source.currentTime,clock:audio.clock,state:audio.context?.state,origin:audio.origin,track:track.mediaStreamTrack.readyState,connected:!!audio.source}));
 const before=audio.capturedMs;if(audio.playStart||!audio.prime?.muted||audio.prime?.volume!==0)throw Error('Preparation started playback prematurely');
 audio.play();const pump=setInterval(()=>audio.pump(),16);
 await new Promise(r=>setTimeout(r,700));gain.gain.setValueAtTime(0,source.currentTime);
 await new Promise(r=>setTimeout(r,200));audio.finish();
 for(let i=0;i<150&&!audio.done;i++)await new Promise(r=>setTimeout(r,20));clearInterval(pump);
 if(!audio.done||audio.error)throw Error(audio.error||'Playback did not drain');
 await fetch('/result',{method:'POST',body:JSON.stringify({passed:true,preparedMs:before,totalMs:audio.capturedMs,playedMs:Math.round((audio.position-audio.origin)*1000),microphoneUsed:false})});
 }catch(e){await fetch('/result',{method:'POST',body:JSON.stringify({passed:false,error:String(e)})});}finally{audio?.stop();await source?.close();}})();
</script>`;
const server=http.createServer(async(req,res)=>{
 if(req.url==='/result'){let body='';for await(const part of req)body+=part;res.end('ok');done(JSON.parse(body));return;}
 res.setHeader('Content-Type',req.url==='/'?'text/html':'text/javascript');
 res.end(req.url==='/'?page:req.url==='/audio.js'?b.outputFiles[0].text:await readFile('bridge/public/reply-capture.js'));
});await new Promise(r=>server.listen(0,'127.0.0.1',r));
const child=spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless=new','--disable-gpu','--mute-audio','--autoplay-policy=no-user-gesture-required','--no-first-run','--remote-debugging-port=0','--user-data-dir='+resolve(output,'edge-profile'),`http://127.0.0.1:${server.address().port}/`],{windowsHide:true,stdio:'ignore'});
let timer;try{
 const status=await Promise.race([result,new Promise(r=>timer=setTimeout(()=>r({passed:false,error:'Browser test timed out'}),20000))]);
 await writeFile(resolve(output,'audio-verification.json'),JSON.stringify(status,null,2));console.log(JSON.stringify(status));if(!status.passed)process.exitCode=1;
}finally{
 clearTimeout(timer);
 try{const [port,path]=(await readFile(resolve(output,'edge-profile/DevToolsActivePort'),'utf8')).trim().split('\n');const ws=new WebSocket('ws://127.0.0.1:'+port+path.trim());await new Promise((resolve,reject)=>{ws.onopen=()=>{ws.send(JSON.stringify({id:1,method:'Browser.close'}));resolve();};ws.onerror=reject;setTimeout(reject,1000);});ws.close();}catch{child.kill();}
 server.closeAllConnections();server.close();
}
