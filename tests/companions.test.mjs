import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {compileOrder,encodeGraph,decodeGraph,validateGraph} from '../bridge/companion-orders.mjs';
import {Companions,parseParty} from '../bridge/companions.mjs';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';

test('complex order preserves condition subject and rejects unsupported promises',()=>{
 const graph=compileOrder('protect me then when your health is below 30 percent, regroup then prefer ranged then attack my target');
 assert.deepEqual(decodeGraph(encodeGraph(graph)),graph);
 assert.deepEqual(graph.nodes.map(n=>n.op),['priority','condition','follow','role','attack']);
 assert.throws(()=>compileOrder('use counterspell'));
 assert.throws(()=>validateGraph({...graph,nodes:graph.nodes.map(n=>n.op==='attack'?{...n,op:'power',value:'counterspell'}:n)}));
 assert.throws(()=>compileOrder('ranged only'));
 assert.throws(()=>compileOrder('when my health is below 30 percent, regroup'));
 assert.throws(()=>compileOrder('spawn a dragon'));
 assert.throws(()=>compileOrder('wait 121 seconds'));
 assert.throws(()=>validateGraph({...graph,nodes:graph.nodes.map(n=>({...n,success:'n1',failure:'n1'}))}));
});
test('Lua graph waits on game time and takes a declared failure edge',async()=>{
 const source=await readFile('mod/Scripts/companion_orders.lua','utf8');
 const wire=encodeGraph(compileOrder('when your health is below 30 percent, regroup then attack my target'));
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const code=`local M=(function() ${source} end)()
 local g=assert(M.decode([=[${wire}]=]));local health=0.8;local calls={}
 local r=assert(M.new(g,{sense=function()return health<0.3 end,action=function(op,value) calls[#calls+1]=op;return op~='attack' end},100))
 r:tick(100);r:tick(100);assert(#calls==0 and r:snapshot().status=='running')
 health=0.2;r:tick(200);assert(#calls==0);r:tick(300);assert(calls[1]=='follow')
 r:tick(400);assert(r:snapshot().status=='failed' and calls[2]=='attack')
 r:tick(500);assert(#calls==2)
 local slow=assert(M.new(g,{sense=function()return false end},0));slow:tick(0);slow:tick(60001);assert(slow:snapshot().status=='failed')
 local legacy=[=[${wire.replace('attack\tcurrent_target','power\tcounterspell')}]=]
 assert(M.decode(legacy)==nil,'Legacy power nodes must not reach the action adapter')
 `;
 const result=lauxlib.luaL_dostring(L,to_luastring(code));const message=result===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1));lua.lua_close(L);assert.equal(result,lua.LUA_OK,message);
});
test('party protocol retains instance targeting and rejects removed tactics, plans and powers',async()=>{
 const folder=await mkdtemp(join(tmpdir(),'dawnwalker-companions-'));
 try{
  const config=JSON.parse(await readFile('characters/companion-config.json','utf8'));assert.equal(config.characters.filter(c=>c.category==='story').length,15);assert(config.characters.some(c=>c.category==='combat'&&c.chat===false));
 const c=new Companions(folder,config);await c.init();
  const observed=parseParty('PARTY\t1\t123\t1\t3\nMEMBER\tanca\tAnca\tFollowing\tfollow\tfrontline\tdefensive\tprotect\t20\t0.25\t0.15\tcounterspell\t1\t1\t\t1\t0\t\nPOWERINFO\tanca\tready\t12\nEND\t123\n');
  assert.equal(observed.members[0].health,1);assert.equal(observed.members[0].stamina,1);assert.equal(observed.members[0].canFight,true);
  for(const field of ['powers','powerState','grantCount','autoPower'])assert.equal(Object.hasOwn(observed.members[0],field),false);
  assert.ok(config.characters.every(c=>!Object.hasOwn(c,'powers')));
  const progress=parseParty('PARTY\t1\t123\t1\t3\nSUMMON\tpabc\tambrus\tbody\tLoading model\nSUMMON\tpdef\tanca\tready\tJoined\nEND\t123\n');
  assert.deepEqual(progress.summons,[{id:'pabc',member:'ambrus',phase:'body',message:'Loading model'},{id:'pdef',member:'anca',phase:'ready',message:'Joined'}]);
  c.state=parseParty(`PARTY\t1\t123\t${Math.floor(Date.now()/1000)}\t3\nACK\t\t\t\nNOTE\tReady\nEND\t123\n`);
  c.state.members=observed.members;
  assert.throws(()=>parseParty('PARTY\t1\t123\t1\t3\nACK\t\t\t\n'));
  await assert.rejects(()=>c.command({epoch:'122',op:'spawn',member:'anca'}));
  await assert.rejects(()=>c.command({epoch:'123',op:'spawn',member:'unknown'}));
  for(const member of ['pieter','vladimir'])await assert.rejects(()=>c.command({epoch:'123',op:'spawn',member}));
  await assert.rejects(()=>c.command({epoch:'123',op:'power',member:'anca',value:'teleport_to_arena'}));
  await assert.rejects(()=>c.command({epoch:'123',op:'power',member:'anca',value:'counterspell'}),/native combat/);
  assert.equal(c.queue.length,0);
  for(const op of ['configure','plan','preview','save_plan','cancel_plan','hold','attack'])
   await assert.rejects(()=>c.command({epoch:'123',op,member:'anca',text:'protect me'}),/removed/);
  await c.command({epoch:'123',op:'follow',member:'anca'});
  const request=c.queue[0];assert.ok(request.wire.includes('follow\tanca\t'));assert.ok(request.wire.startsWith('CMD\t123\t'));
  const {writeFile}=await import('node:fs/promises');
  await writeFile(join(folder,'companions-state.tsv'),`PARTY\t1\t123\t${Math.floor(Date.now()/1000)}\t3\nACK\t${request.id}\tok\tFollowing player\nEND\t123\n`);
  await c.tick();assert.equal(c.queue.length,0);assert.equal(c.result.message,'Following player');
  await c.command({epoch:'123',op:'spawn',member:'anca'});
  const firstClone=c.queue.at(-1).id;
  await c.command({epoch:'123',op:'spawn',member:'anca'});
  assert.notEqual(c.queue.at(-1).id,firstClone,'Every copy needs its own game instance');
  c.state.members=[{id:firstClone,characterId:'anca'}];
  await assert.rejects(()=>c.command({epoch:'123',op:'dismiss',member:'anca'}));
  await c.command({epoch:'123',op:'dismiss',member:firstClone});
  assert.match(c.queue.at(-1).wire,new RegExp('dismiss\\t'+firstClone+'\\t'));
  await writeFile(join(folder,'companions-state.tsv'),`PARTY\t1\t124\t${Math.floor(Date.now()/1000)}\t3\nEND\t124\n`);
  await c.tick();assert.equal(c.queue.length,0);assert.match(c.result.message,/reset/);
  const legacy=compileOrder('protect me then flank left');
  await writeFile(join(folder,'companion-plans.json'),JSON.stringify({'Old plan':legacy}));
  const restored=new Companions(folder,config);await restored.init();
  assert.equal(Object.hasOwn(restored.view(),'presets'),false);
  assert.equal(Object.hasOwn(restored.view(),'grammar'),false);
  assert.equal(restored.queue.length,0);
  assert.ok((await readFile(join(folder,'companion-plans.json'),'utf8')).includes('Old plan'),'Old user data was deleted');
 }finally{await rm(folder,{recursive:true,force:true});}
});
