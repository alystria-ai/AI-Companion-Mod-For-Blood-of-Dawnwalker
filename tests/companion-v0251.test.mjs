import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
async function check(file,body){
 const source=await readFile((process.env.DAWNWALKER_LUA||'mod/Scripts')+'/'+file+'.lua','utf8');const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 try{const result=lauxlib.luaL_dostring(L,to_luastring(`local M=(function() ${source} end)()\n${body}`));assert.equal(result,lua.LUA_OK,result===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}finally{lua.lua_close(L);}
}
test('party destinations stay separate for duplicates, every heading, and large parties',()=>check('companion_recovery',`
 local player={X=100,Y=200,Z=300}
 for _,yaw in ipairs({-180,-45,0,32,90,179})do
  local points={}
  for slot=1,40 do
   local point,r=M.followPoint(player,yaw,slot)
   assert(r>=149.9 and point.Z==player.Z)
   local angle=math.rad(yaw)
   local dx,dy=point.X-player.X,point.Y-player.Y
   assert(dx*math.cos(angle)+dy*math.sin(angle)<0,'Follower slot is not behind Coen')
   local radius,angles,index=M.summonArc(slot)
   assert(r<=radius,'Arrival should be no farther away than its spawn arc')
   assert(math.abs(math.sqrt(dx*dx+dy*dy)-r)<0.01,'Rotating the formation changed its radius')
   assert(M.clearPoint(point,points,154.9),'Duplicate formation destinations')
   points[#points+1]=point
  end
 end
 local occupied={};local function project(p)return {X=p.X,Y=p.Y,Z=210}end
 for slot=1,4 do
  local point=M.catchupPoint(player,0,slot,occupied,project);assert(point)
  assert(M.behindCamera(point,player,0));assert(M.clearPoint(point,occupied,150))
  occupied[#occupied+1]=point
 end
 local calls=0;local blocked=occupied[1]
 assert(not M.catchupPoint(player,0,1,occupied,function()calls=calls+1;return blocked end))
 assert(calls==6,'Cramped navigation caused an unbounded catch-up search')
 assert(not M.behindCamera({X=110,Y=200,Z=300},player,0),'Visible point teleported')
 assert(not M.catchupPoint(player,0,1,{},function()return {X=500,Y=200,Z=1200}end),'Another floor accepted')
`));
test('accepted combat that stays idle is retried finitely without interrupting native attacks',()=>check('companion_combat',`
 local starts,stops,maintains,following=0,0,0,true
 local c=M.new({enter=function()following=false;return true end,target=function()return true end,
 start=function()starts=starts+1;return true end,stop=function()stops=stops+1;return true end,
 clear=function()end,travel=function(v)following=v end,maintain=function()maintains=maintains+1;following=false end})
 for i=0,120 do c:tick({now=i*750,key='same',allowed=true,nativeCombat=false,busy=false,follow=true})end
 assert(starts==3 and following,'A false-positive native start blocked follow forever or retried forever')
 assert(stops==3)
 c=M.new({enter=function()following=false;return true end,target=function()return true end,start=function()starts=starts+1;return true end,
 stop=function()error('Interrupted long attack')end,clear=function()end,travel=function()end,maintain=function()maintains=maintains+1;following=false end})
 starts=0
 for i=0,100 do following=true;c:tick({now=i*750,key='same',allowed=true,nativeCombat=i>0,busy=i>0,follow=true});assert(not following)end
 assert(starts==1 and maintains>=100)
`));
const mock=`
 EObjectFlags={RF_BeginDestroyed=0x8000,RF_FinishDestroyed=0x10000}
 FName=function(s)return {ToString=function()return s end}end
 local function obj(n)return {IsValid=function(self)return not self.invalid end,HasAnyFlags=function()return false end,GetFullName=function()return n end}end
`;
test('static libraries are reused, while invalidated objects are reacquired',()=>check('ai_state',mock+`
 local scans=0;local object=obj('Library /lib')
 StaticFindObject=function()scans=scans+1;return object end
 for i=1,500 do assert(M.find('/lib')==object)end
 assert(scans==1,'Party loop scans the object array repeatedly')
 object.invalid=true;local replacement=obj('Library /lib');object=replacement
 assert(M.find('/lib')==replacement and scans==2)
`));
test('owned damage branch clears helper scaling without enabling follower locomotion or touching other stubs',()=>check('ai_state',mock+`
 local s,b=obj('owned'),obj('board');s.AIBoard=b;s.IsInitializedAndHasPawn=function()return true end
 b.Follower={bFollowerModeEnabled=false};local tagged=true;local removes=0
 s.HasTag=function(_,t)assert(t.TagName:ToString()=='RebelAI.Flag.DealFollowerDamage');return tagged end
 s.RemoveTag=function()tagged=false;removes=removes+1 end
 assert(M.ownedDamageBranch(s,b));assert(not tagged and not b.Follower.bFollowerModeEnabled)
 assert(M.ownedDamageBranch(s,b)and removes==1)
 s.AIBoard=nil;assert(not M.ownedDamageBranch(s,b)and removes==1)
`));

test('sword setup restores existing inventory equipment without duplicate spawns or interrupting busy actors',()=>check('ai_state',mock+`
 local s,b,c=obj('owned'),obj('board'),obj('combat');s.AIBoard=b
 s.IsInitializedAndHasPawn=function()return true end;s.IsInCinematicMode=function()return false end
 local busy=false;b.HasAnyUnbreakableActiveAction=function()return busy end
 b.Weapon={TagName=FName('None')};local mode='None';local state='Neutral';local spawns,syncs=0,0
 b.Temp_BP_GetCombatMode=function(_,out)out.TagName=FName(mode)end
 b.Temp_BP_SetCombatMode=function(_,v)mode=v.TagName:ToString()end
 b.Temp_BP_SetWeapon=function(_,v)b.Weapon=v end
 s.BP_CharacterStateExist=function()return true end
 s.BP_SetCharacterState=function(_,v)state=v.TagName:ToString()end
 local weapon=nil;c.GetMainWeapon=function()return weapon end
 c.OnInventoryContentsChanged=function()syncs=syncs+1;c.EquippedWeapon=obj('native sword class')end
 c.SpawnEquippedWeapon=function(_,update)assert(update);spawns=spawns+1;weapon=obj('native sword');return true end
 local setup={};assert(M.swordCombat(s,b,c,setup))
 assert(mode=='RebelAI.CombatMode.Sword'and state=='RebelAI.CharacterState.Combat.Sword')
 assert(spawns==1 and syncs==1 and b.Weapon.TagName:ToString()=='RebelAI.Weapon.Sword')
 assert(M.swordCombat(s,b,c,setup)and spawns==1)
 busy=true;assert(not M.swordCombat(s,b,c,setup)and spawns==1)
 busy=false;s.AIBoard=nil;assert(not M.swordCombat(s,b,c,setup))
`));
