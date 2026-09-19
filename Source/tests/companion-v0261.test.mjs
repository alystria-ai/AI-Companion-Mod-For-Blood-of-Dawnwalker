import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
import {Companions} from '../bridge/companions.mjs';
async function check(module,body){
 const source=await readFile((process.env.DAWNWALKER_LUA||'mod/Scripts')+'/'+module+'.lua','utf8');
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 try{const rc=lauxlib.luaL_dostring(L,to_luastring(`local M=(function() ${source} end)()\n${body}`));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}
}
const retreat=`local m={};local o={follow=true,encounter=true,now=0,gap=2400,spacing=180,speed=600,awaySpeed=600,combat=true,threatDistance=2000,x=2000,y=0}
 local function step(t,x,d,away) o.now=t;o.x=x;o.threatDistance=d;o.awaySpeed=away or 600;return M.retreat(m,o)end
`;
test('short dodges and sprints do not dismiss the fight',()=>check('companion_recovery',retreat+`
 assert(not step(0,2000,2000));assert(not step(1250,2750,2750))
 o.speed=0;assert(not step(1500,2750,2750,0));assert(not m.departure)
 o.speed=600;assert(not step(1750,2750,2750));assert(not step(3000,3500,3500))
`));
test('circling, nearby flanking and moving toward the fight stay in combat',()=>check('companion_recovery',retreat+`
 for t=0,6000,250 do assert(not step(t,2000,2000,100))end
 for t=7000,14000,250 do assert(not step(t,2000+t,900,600),'Nearby enemy means repositioning')end
 assert(not step(15000,2000,2000,-600))
`));
test('sustained retreat requires net travel and increasing enemy separation',()=>check('companion_recovery',retreat+`
 assert(not step(0,2000,2000));assert(not step(2000,3200,3200));assert(step(2500,3500,3500))
 m={};assert(not step(0,2000,2000));assert(not step(3000,4000,2000),'Enemy keeps up: separation did not grow')
 m={};assert(not step(0,2000,2000));assert(not step(3000,2100,3000),'Enemy moving away is not player retreat')
`));
test('a newly nearby enemy resets pending retreat',()=>check('companion_recovery',retreat+`
 assert(not step(0,2000,2000));assert(not step(2000,3200,3200));assert(not step(2250,3350,1000))
 assert(not m.departure);assert(not step(3000,3800,2100));assert(not step(4000,4400,2700))
`));
test('ordinary travel never latches retreat and a far stranded fighter regroups after a grace',()=>check('companion_recovery',retreat+`
 o.encounter=false;for t=0,12000,250 do assert(not step(t,2000+t,2000+t))end
 o.encounter=true;o.speed=0;o.gap=5000
 assert(not step(13000,5000,5000,0));assert(not step(14750,5000,5000,0));assert(step(15000,5000,5000,0))
`));
const aiMock=`
 EObjectFlags={RF_BeginDestroyed=1,RF_FinishDestroyed=2}
 local function obj(name)return {IsValid=function()return true end,HasAnyFlags=function()return false end,GetFullName=function()return name end}end
 local s,b=obj('owned'),obj('board');s.AIBoard=b;s.IsInitializedAndHasPawn=function()return true end
 local busy=false;local reaction='RebelAI.Situation.HostileDetected';local stopped=0
 b.Follower={bFollowerModeEnabled=false};b.HasAnyUnbreakableActiveAction=function()return busy end
 b.HasReaction=function()return reaction~=nil end
 b.GetReactionSituationTag=function()local tag=reaction;return {TagName={ToString=function()return tag end}}end
 b.StopReaction=function()stopped=stopped+1;reaction=nil end
`;
test('retreat sensing restores once, cancels detection reactions and leaves native actions alone',()=>check('ai_state',aiMock+`
 local changes,resets={},0;s.SetPerceptionEnabled=function(_,v)changes[#changes+1]=v end;s.ResetPerception=function()resets=resets+1 end
 local state={};assert(M.retreatSensing(s,b,state,true));assert(stopped==1 and changes[1]==false and resets==1)
 for i=1,10 do M.retreatSensing(s,b,state,true)end;assert(#changes==1 and resets==1)
 reaction='StoryScene';M.retreatSensing(s,b,state,true);assert(stopped==1)
 reaction='RebelAI.Situation.FightIsNearby';busy=true;M.retreatSensing(s,b,state,true);assert(stopped==1)
 busy=false;M.retreatSensing(s,b,state,true);assert(stopped==2)
 assert(M.retreatSensing(s,b,state,false));M.retreatSensing(s,b,state,false);assert(#changes==2 and changes[2]==true)
 s.AIBoard=nil;assert(not M.retreatSensing(s,b,state,true)and #changes==2)
`));
test('combat exit arms follower before native idle transition and honors unbreakable actions',()=>check('ai_state',aiMock+`
 local calls=0;local lib={StopCombatBehaviors=function(_,stub,a,c)assert(stub==s and a and not c and b.Follower.bFollowerModeEnabled);calls=calls+1 end}
 busy=true;assert(not M.stopCombatForTravel(lib,s,b,true)and calls==0)
 busy=false;assert(M.stopCombatForTravel(lib,s,b,true)and calls==1 and stopped==1)
 s.AIBoard=nil;assert(M.stopCombatForTravel(lib,s,b,true)and calls==1)
`));
test('native-initiated combat without a mod target prepares once without replaying start',()=>check('companion_combat',`
 local enters,maintains=0,0
 local c=M.new({enter=function(native)assert(native);enters=enters+1;return true end,maintain=function()maintains=maintains+1 end,
 start=function()error('Native intro replayed')end,travel=function()error('Follow interfered with combat')end})
 for n=0,20000,250 do assert(c:tick({now=n,allowed=true,nativeCombat=true,busy=false,follow=true})=='combat')end
 assert(enters==1 and maintains==81)
`));
test('loading allows additional queued summons through brief stalls, with epoch and lifetime bounds',async()=>{
 const c=new Companions('',{limit:0,characters:[{id:'anca'}]});c.state={epoch:'123',members:[],summons:[],updated:Date.now()};
 const one=await c.command({op:'spawn',member:'anca',epoch:'123'});c.state.updated=Date.now()-10000;
 assert.equal(c.view().gameAlive,false);assert.equal(c.view().canSummon,true);
 const two=await c.command({op:'spawn',member:'anca',epoch:'123'});assert.notEqual(one.id,two.id);
 await assert.rejects(c.command({op:'spawn',member:'anca',epoch:'124'}));
 await assert.rejects(c.command({op:'dismiss_all',epoch:'123'}));
 c.queue=[];c.state.summons=[{phase:'body'}];assert.equal(c.canSummon(),true);
 c.state.updated=Date.now()-60001;await assert.rejects(c.command({op:'spawn',member:'anca',epoch:'123'}));
 c.state.updated=Date.now()-10000;c.state.summons=[{phase:'ready'}];assert.equal(c.canSummon(),false);
});
