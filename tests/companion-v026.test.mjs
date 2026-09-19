import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
async function check(module,body){
 const source=await readFile('mod/Scripts/'+module+'.lua','utf8');
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 try{const rc=lauxlib.luaL_dostring(L,to_luastring(`local M=(function() ${source} end)()\n${body}`));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}
}
test('names track live duplicates, recover plain names and leave shared character IDs intact',()=>check('companion_recovery',`
 local a={id='paaa',characterId='anca',baseName='Anca',ordinal=1}
 local b={id='pbbb',characterId='lacra',baseName='Lacra',ordinal=2}
 local c={id='pccc',characterId='anca',baseName='Anca',ordinal=3}
 local party={paaa=a,pbbb=b};M.layout(party)
 assert(a.label=='Anca'and b.label=='Lacra')
 party.pccc=c;M.layout(party);assert(a.label=='Anca #1'and c.label=='Anca #2'and b.label=='Lacra')
 party.paaa=nil;M.layout(party);assert(c.label=='Anca'and c.id=='pccc'and c.characterId=='anca')
 party.paaa={id='pddd',characterId='anca',baseName='Anca',ordinal=4};M.layout(party)
 assert(c.label=='Anca #1'and party.paaa.label=='Anca #2','A reused slot reversed summon order')
`));
test('latched retreat survives near-player combat and waits for a settled reunion',()=>check('companion_recovery',`
 local m={returning=true};local o={follow=true,now=0,gap=486,spacing=180,speed=500,awaySpeed=0,combat=true}
 for i=0,10 do o.now=i*250;assert(M.retreat(m,o),'Momentary reunion cancelled retreat')end
 o.speed=0;o.now=3000;assert(M.retreat(m,o),'Combat must finish before reunion')
 o.combat=false;o.now=3250;assert(M.retreat(m,o));o.now=4500;assert(M.retreat(m,o))
 o.now=4750;assert(not M.retreat(m,o));assert(m.noEngageUntil==nil,'Settled reunion left combat suppressed')
 m.returning=true;o.follow=false;assert(not M.retreat(m,o),'Stop failed to cancel returning mode')
`));

test('follow starts promptly and runs across a small gap with gait hysteresis',()=>check('companion_combat',`
 local p=M.followPace(210,0,false);assert(p.stop==180 and p.start==430 and not p.running)
 assert(M.followPace(230,300,false).running,'Follower waited while Coen jogged away')
 assert(M.followPace(310,0,false).running,'Follower walked across a large gap')
 assert(M.followPace(280,0,true).running);assert(not M.followPace(240,0,true).running)
 assert(not M.followPace(470,0,false,470).running)
 assert(M.followPace(520,350,false,470).running,'Later party members did not run promptly')
`));
test('native combat exit is acknowledged before following, retries are spaced and target churn cannot abort it',()=>check('companion_combat',`
 local starts,stops,following,busy=0,0,true,false
 local c=M.new({enter=function()following=false;return true end,target=function()return true end,start=function()starts=starts+1;return true end,
 inhibit=function()following=false end,stop=function()if busy then return false end;stops=stops+1;return true end,clear=function()end,travel=function(v)following=v end})
 c:tick({now=0,allowed=true,key='enemy',nativeCombat=false,follow=true})
 busy=true
 assert(c:tick({now=1000,allowed=false,nativeCombat=true,busy=true,follow=true})=='leaving');assert(stops==0 and not following)
 busy=false
 assert(c:tick({now=1250,allowed=false,nativeCombat=true,busy=false,follow=true})=='leaving');assert(stops==1 and not following)
 for n=1500,4000,250 do assert(c:tick({now=n,allowed=true,key='newEnemy',nativeCombat=true,busy=false,follow=true})=='leaving')end
 assert(stops==1 and starts==1,'Exit request spammed or new target aborted exit')
 c:tick({now=4250,allowed=false,nativeCombat=true,busy=false,follow=true});assert(stops==2)
 assert(c:tick({now=4500,allowed=false,nativeCombat=false,busy=false,follow=true})=='travel');assert(following)
 for n=4750,8000,250 do c:tick({now=n,allowed=false,nativeCombat=false,busy=false,follow=true})end
 assert(stops==2 and following,'Repeated retreat updates restarted or stopped the follower')
`));
test('perception gaps never stop an active native encounter or replay Lacra combat entry',()=>check('companion_combat',`
 local starts,stops,following=0,0,true
 local c=M.new({enter=function()following=false;return true end,target=function()return true end,start=function()starts=starts+1;return true end,
 stop=function()stops=stops+1;return true end,clear=function()end,travel=function(v)following=v end,maintain=function()following=false end})
 c:tick({now=0,allowed=true,key='enemy',nativeCombat=false,busy=false,follow=true})
 for n=250,60000,250 do
  c:tick({now=n,allowed=true,key=n%10000==0 and 'enemy'or nil,nativeCombat=true,busy=n%2000==0,follow=true})
  assert(not following)
 end
 assert(starts==1 and stops==0)
`));
test('ordinary unbreakable follower actions are not mistaken for combat needing cancellation',()=>check('companion_combat',`
 local follows=0
 local c=M.new({travel=function(v)assert(v);follows=follows+1 end,inhibit=function()error('Disabled normal follower')end,stop=function()error('Stopped normal follower')end})
 for n=0,10000,250 do assert(c:tick({now=n,allowed=true,nativeCombat=false,busy=true,follow=true})=='travel')end
 assert(follows==41)
`));
