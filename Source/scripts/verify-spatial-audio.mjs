// Render the production spatial graph in isolated, muted Edge. No game or microphone.
import {build} from 'esbuild';import http from 'node:http';import {spawn} from 'node:child_process';
import {readFile,writeFile,mkdir} from 'node:fs/promises';import {resolve} from 'node:path';
const output=resolve(process.argv[2]||'runtime/spatial-verification');await mkdir(output,{recursive:true});
const b=await build({entryPoints:['bridge/spatial-output.ts'],bundle:true,write:false,format:'iife',globalName:'Spatial'});
const page=`<script src='/test.js'></script><script>
(async()=>{try{
 async function render(position){
  const c=new OfflineAudioContext(2,48000,48000),out=new Spatial.SpatialOutput(c),osc=c.createOscillator();
  osc.type='sawtooth';osc.frequency.value=220;osc.connect(out.input);out.setPosition(position);osc.start();
  const buffer=await c.startRendering();return [0,1].map(ch=>{const a=buffer.getChannelData(ch).slice(12000);return Math.sqrt(a.reduce((sum,x)=>sum+x*x,0)/a.length);});
 }
 const left=await render([-3,0,-1]),right=await render([3,0,-1]),near=await render([0,0,-2]),far=await render([0,0,-10]);
 if(!(left[0]>left[1]*1.2&&right[1]>right[0]*1.2))throw Error('Stereo directions reversed or missing');
 if(!(far[0]<near[0]*.5&&far[1]<near[1]*.5))throw Error('Distance attenuation missing');
 if(Math.abs(near[0]-near[1])>near[0]*.1)throw Error('Centred voice is not balanced');
 // A centred multitone spanning speech frequencies must be an unchanged,
 // constant-gain copy in both ears, rather than a filtered/phase-shifted signal.
 const c=new OfflineAudioContext(2,48000,48000),out=new Spatial.SpatialOutput(c),buffer=c.createBuffer(1,48000,48000);
 const source=buffer.getChannelData(0);
 for(let i=0;i<source.length;i++)source[i]=[180,650,1900,4200,7800].reduce((sum,f)=>sum+.07*Math.sin(2*Math.PI*f*i/48000),0);
 const node=c.createBufferSource();node.buffer=buffer;node.connect(out.input);out.setPosition([0,0,-2]);node.start();
 const rendered=await c.startRendering();let signal=0,error=0;
 for(let ch=0;ch<2;ch++)for(let i=12000;i<48000;i++){
  const expected=source[i]*Math.SQRT1_2;signal+=expected*expected;error+=(rendered.getChannelData(ch)[i]-expected)**2;
 }
 const fidelityDb=10*Math.log10(signal/Math.max(error,1e-30));
 if(fidelityDb<100)throw Error('Spatial graph coloured or distorted speech: '+fidelityDb+' dB');
 await fetch('/result',{method:'POST',body:JSON.stringify({passed:true,left,right,near,far,fidelityDb,spatialMode:'equalpower'})});
 }catch(e){await fetch('/result',{method:'POST',body:JSON.stringify({passed:false,error:String(e)})});}})();
</script>`;
let done;const result=new Promise(r=>done=r);const server=http.createServer(async(req,res)=>{
 if(req.url==='/result'){let body='';for await(const c of req)body+=c;res.end('ok');done(JSON.parse(body));return;}
 res.setHeader('Content-Type',req.url==='/'?'text/html':'text/javascript');res.end(req.url==='/'?page:b.outputFiles[0].text);
});await new Promise(r=>server.listen(0,'127.0.0.1',r));
const child=spawn('C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',['--headless=new','--disable-gpu','--mute-audio','--autoplay-policy=no-user-gesture-required','--no-first-run','--remote-debugging-port=0','--user-data-dir='+resolve(output,'edge-profile'),`http://127.0.0.1:${server.address().port}/`],{windowsHide:true,stdio:'ignore'});
let timer;try{const status=await Promise.race([result,new Promise(r=>timer=setTimeout(()=>r({passed:false,error:'Browser timeout'}),25000))]);await writeFile(resolve(output,'result.json'),JSON.stringify(status,null,2));console.log(JSON.stringify(status));if(!status.passed)process.exitCode=1;}
finally{clearTimeout(timer);try{const [port,path]=(await readFile(resolve(output,'edge-profile/DevToolsActivePort'),'utf8')).trim().split('\n');const ws=new WebSocket('ws://127.0.0.1:'+port+path.trim());await new Promise((resolve,reject)=>{ws.onopen=()=>{ws.send(JSON.stringify({id:1,method:'Browser.close'}));resolve();};ws.onerror=reject;setTimeout(reject,1000);});ws.close();}catch{child.kill();}server.closeAllConnections();server.close();}
