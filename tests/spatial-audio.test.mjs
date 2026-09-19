import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {parseSpatial} from '../bridge/protocol.mjs';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
import vm from 'node:vm';import {build} from 'esbuild';

test('spatial transport rejects stale, cross-speaker, inactive, partial and nonfinite coordinates',()=>{
 const t={active:true,generation:7};assert.deepEqual(parseSpatial('100\t7\t2\t0\t-3\n',t,100500),{generation:7,at:100000,position:[2,0,-3]});
 for(const raw of ['100\t8\t2\t0\t-3','97\t7\t2\t0\t-3','100\t7\tNaN\t0\t-3','100\t7\t1001\t0\t0','100\t7\t\t0\t0','100\t7\t1\t2'])assert.equal(parseSpatial(raw,t,100500),null);
 assert.equal(parseSpatial('100\t7\t1\t2\t3',{...t,active:false},100500),null);
});

test('Lua source-to-camera transform preserves right/left, camera rotation, height, roll and centimetre scale',async()=>{
 const source=await readFile(process.env.DAWNWALKER_TARGETING||'mod/Scripts/targeting.lua','utf8');
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const code=`local M=(function() ${source} end)()
 local function check(source,rotation,x,y,z)
  local row=M.spatial({X=0,Y=0,Z=160},rotation,source,7,100)
  local vals={};for v in row:gmatch('[^\\t\\n]+')do vals[#vals+1]=tonumber(v)end
  assert(vals[1]==100 and vals[2]==7)
  assert(math.abs(vals[3]-x)<.001 and math.abs(vals[4]-y)<.001 and math.abs(vals[5]-z)<.001,row)
 end
 check({X=300,Y=200,Z=100},{Yaw=0,Pitch=0,Roll=0},2,0,-3)
 check({X=300,Y=200,Z=100},{Yaw=0,pitch=0,Roll=0},2,0,-3)
 check({X=300,Y=-200,Z=100},{Yaw=0,Pitch=0,Roll=0},-2,0,-3)
 check({X=300,Y=0,Z=100},{Yaw=90,Pitch=0,Roll=0},-3,0,0)
 check({X=0,Y=0,Z=260},{Yaw=0,Pitch=90,Roll=0},0,0,-1.6)
 check({X=0,Y=100,Z=100},{Yaw=0,Pitch=0,Roll=90},0,1,0)
 check({X=-300,Y=0,Z=100},{Yaw=0,Pitch=0,Roll=0},0,0,3)
 local good,why=pcall(M.spatial,{X=0,Y=0,Z=0},{Yaw=0,Roll=0},{X=1,Y=2,Z=3},7,100)
 assert(not good and tostring(why):find('field 7',1,true),'Missing pitch was silently skipped')
 `;
 try{const rc=lauxlib.luaL_dostring(L,to_luastring(code));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}
});

test('uncoloured spatial output smooths movement and resets stale ownership',async()=>{
 const b=await build({entryPoints:['bridge/spatial-output.ts'],bundle:true,write:false,format:'iife',globalName:'M'});
 const ctx={};vm.runInNewContext(b.outputFiles[0].text,ctx);
 const events=[],p=()=>({value:0,cancelScheduledValues(){},setTargetAtTime(v,t,tau){events.push([v,t,tau]);}});
 const node={positionX:p(),positionY:p(),positionZ:p(),connect(){},disconnect(){}};
 const out=new ctx.M.SpatialOutput({createPanner:()=>node,currentTime:1,destination:{}});
 assert.equal(node.panningModel,'equalpower');assert.equal(node.distanceModel,'inverse');assert.equal(node.refDistance,2);
 out.setPosition([2,0,-3]);assert.deepEqual(events.map(e=>e[0]),[2,0,-3]);assert.ok(events.every(e=>e[2]===.045));
 out.setPosition([2,0,-3]);assert.equal(events.length,3,'Unchanged polling queued extra ramps');
 out.setPosition(null);assert.deepEqual(events.slice(-3).map(e=>e[0]),[0,0,-2]);
 assert.equal(ctx.M.voicePosition({generation:8,at:10000,position:[1,2,3]},7,10001),null);
 assert.equal(ctx.M.voicePosition({generation:7,at:10000,position:[1,2,3]},7,12500),null);
});
