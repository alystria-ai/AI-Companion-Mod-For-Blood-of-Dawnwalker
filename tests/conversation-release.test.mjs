import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
const app=await readFile(process.env.DAWNWALKER_APP||'mod/Scripts/app.lua','utf8');
const engagement=await readFile(process.env.DAWNWALKER_ENGAGEMENT||'mod/Scripts/engagement.lua','utf8');
function run(s){const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);try{const rc=lauxlib.luaL_dostring(L,to_luastring(s));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}}
test('single completion releases its body once, retains selection, respects composer/group/explicit Follow',()=>run(`
 local generation=5;local selected='Anca';local conversationMode='single';local composeController=nil
 local engagement={};local releases=0;local function releaseConversation()releases=releases+1;engagement=nil end;local function log()end
 ${app.slice(app.indexOf("local lastReplyRelease=''"),app.indexOf('-- Group membership'))}
 releaseCompletedReply('5\\t100\\nJawOpen\\t0\\n');assert(releases==0)
 local done='5\\t100\\nREPLY-END\\treply1\\n'
 composeController={};releaseCompletedReply(done);assert(releases==0)
 composeController=nil;releaseCompletedReply(done);releaseCompletedReply(done);assert(releases==1 and selected=='Anca')
 generation=6;conversationMode='group';releaseCompletedReply(done);assert(releases==1)
 conversationMode='single';engagement={following=true};releaseCompletedReply(done);assert(releases==1 and engagement.following)
 generation=7;engagement={};releaseCompletedReply(done);assert(releases==2)
`));
test('native attention leases focus/modes without rotating or locking movement; yields to travel and combat',()=>run(`
 local AI={valid=function(o)return o and not o.invalid end,same=function(a,b)return a and b and a==b end,board=function(s,b)return s and (not b or s.AIBoard==b)and s.AIBoard end}
 local board={Combat={},HasAnyUnbreakableActiveAction=function()return false end}
 local stub={AIBoard=board,IsInCombat=function()return board.Combat.bInCombat end,IsInCinematicMode=function()return false end}
 AI.find=function()return {GetAIStub=function()return stub end}end
 package.preload.ai_state=function()return AI end
 local M=(function()${engagement}end)()
 local player={K2_GetActorLocation=function()return {X=200,Y=0,Z=0}end}
 local old={};local controller={focus=old,GetFocusActor=function(self)return self.focus end,K2_SetFocus=function(self,p)self.focus=p end}
 local pushes,pops=0,0
 local movement={bOrientRotationToMovement=true,bUseControllerDesiredRotation=true,
  PushRotationMode=function(_,mode,priority)assert(mode==2 and priority==50);pushes=pushes+1;return 10 end,
  PushLookAtMode=function(_,mode,priority)assert(mode==4 and priority==50);pushes=pushes+1;return 11 end,
  PopRotationMode=function(_,h)assert(h==10);pops=pops+1 end,PopLookAtMode=function(_,h)assert(h==11);pops=pops+1 end}
 local speed=0;local actor={bUseControllerRotationYaw=true,GetFullName=function()return 'Anca'end,
  GetVelocity=function()return {X=speed,Y=0,Z=0}end,K2_GetActorLocation=function()return {X=0,Y=0,Z=0}end,
  GetController=function()return controller end,GetMovementComponent=function()return movement end,
  K2_SetActorRotation=function()error('Capsule rotation prohibited')end}
 local function log()end
 local attention=M.attend(nil,actor,player,log,false);assert(attention and pushes==2 and controller.focus==player)
 assert(not actor.bUseControllerRotationYaw and not movement.bUseControllerDesiredRotation)
 attention=M.attend(attention,actor,player,log,false);assert(attention and pushes==2,'Repeated tick stacked leases')
 speed=100;attention=M.attend(attention,actor,player,log,false)
 assert(not attention and pops==2 and controller.focus==old and actor.bUseControllerRotationYaw)
 speed=0;attention=M.attend(nil,actor,player,log,false);controller.focus=old
 M.releaseAttention(attention);M.releaseAttention(attention);assert(pops==4 and controller.focus==old,'Restore stomped native focus or popped twice')
 board.Combat.bInCombat=true;assert(not M.attend(nil,actor,player,log,false)and pushes==4)
 board.Combat.bInCombat=false;board.bMainBehaviorSuspended=true
 assert(not M.attend(nil,actor,player,log,false))
 attention=M.attend(nil,actor,player,log,true);assert(attention,'Owned conversation hold should allow animated attention')
 M.releaseAttention(attention)
 board.bMainBehaviorSuspended=false
 local point={X=10,Y=20,Z=30};local writes=0
 controller.focus=nil
 controller.GetFocalPoint=function()return point end
 controller.K2_SetFocalPoint=function(self,p)self.focus=nil;point=p;writes=writes+1 end
 attention=M.attend(nil,actor,player,log,false,{sideAngle=22,range=700})
 assert(attention and point.Y>50 and point.X<200,'General attention should look beside the player')
 attention=M.attend(attention,actor,player,log,false,{sideAngle=22,range=700})
 assert(attention and writes==1,'Settled attention should not rewrite focus every tick')
 speed=100;attention=M.attend(attention,actor,player,log,false,{sideAngle=22,range=700})
 assert(not attention and point.X==10 and point.Y==20,'Travel must restore the previous focal point')
 speed=0;attention=M.attend(nil,actor,player,log,false,{sideAngle=-22,range=700})
 point={X=900,Y=100,Z=50};M.releaseAttention(attention)
 assert(point.X==900,'Cleanup must preserve a newer native focal point')
`));
