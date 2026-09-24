import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';

const app=await readFile(process.env.DAWNWALKER_APP||'mod/Scripts/app.lua','utf8');
const targeting=await readFile('mod/Scripts/targeting.lua','utf8');
const trace=app.slice(app.indexOf('local function trace('),app.indexOf('local channels='));
const commands=app.slice(app.indexOf('local function uiCommand()'),app.indexOf('if config.AutoStartConvai then'));
function execute(code){
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 try{const rc=lauxlib.luaL_dostring(L,to_luastring(code));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));}
 finally{lua.lua_close(L);}
}
const setup=`
 local Targeting=(function() ${targeting} end)()
 local config={MaxDistance=450,FacingHalfAngle=80,UseFaceLayer=true}
 local function valid(a)return a and not a.invalid end
 local function log()end;local function write()end
 local world={GetFullName=function()return 'world' end}
 local function actor(name,x,y,owned,blocked)
  return {owned=owned,blocked=blocked,point={X=x,Y=y,Z=0},
   GetFullName=function()return name end,GetWorld=function(self)return self.world or world end,
   IsPlayerControlled=function(self)return self.player end,
   K2_GetActorLocation=function(self)return self.point end}
 end
 local player=actor('player',0,0);player.player=true
 local forward={X=1,Y=0,Z=0}
 local pc={Pawn=player,PlayerCameraManager={GetCameraLocation=function()return player.point end,GetCameraRotation=function()return {}end},
  LineOfSightTo=function(_,a)return not a.blocked end}
 local function playerController()return pc end
 local UE={GetKismetMathLibrary=function()return {GetForwardVector=function()return forward end}end}
 local NativeMenu={close=function()end}
 local Companions={identity=function(a)if a.owned then return {definition='NPCDef_'..a:GetFullName()}end end}
 Targeting.identify=function(a)return {definition=a.definition or 'NPCDef_'..a:GetFullName()}end
 local candidates={};FindAllOf=function()return candidates end
 ${trace}
`;

test('repeated single/group text and voice selection works after camera rotation, using nearest companion',()=>execute(`${setup}
 local anca=actor('Anca',256,0,true);local crake=actor('Crake',-180,0,true)
 candidates={player,anca,crake}
 assert(trace(false)==anca,'Initially aimed character')
 forward={X=0,Y=1,Z=0}
 for _,group in ipairs({false,true,false,true})do
  assert(trace(group)==crake,'Must choose nearest, not previous conversation')
 end
 forward={X=1,Y=0,Z=0};assert(trace(false)==anca,'Aimed character takes priority again')
`));

test('companion fallback has no distance, facing or visibility requirement; rejects invalid/world/player actors',()=>execute(`${setup}
 local far=actor('Far',-5000,0,true,true)
 local invalid=actor('Invalid',-10,0,true);invalid.invalid=true
 local other=actor('OtherWorld',-10,0,true);other.world={GetFullName=function()return 'other' end}
 local controlled=actor('Controlled',-10,0,true);controlled.player=true
 candidates={invalid,other,controlled,far}
 assert(trace(false)==far);assert(trace(true)==far)
 assert(trace()==nil,'Debug targeting must stay aimed and in range')
 local aimed=actor('Aimed',6000,0,true);candidates[#candidates+1]=aimed
 assert(trace(false)==aimed,'Visible companion has priority over behind-camera companion')
`));

test('campaign NPC proximity and visibility limits remain in place',()=>execute(`${setup}
 local npc=actor('NPC',-700,0,false)
 candidates={npc};assert(trace(false)==nil);assert(trace(true)==npc)
 npc.blocked=true;assert(trace(true)==nil)
 npc.blocked=false;npc.point.X=-200;assert(trace(false)==npc)
 npc.definition='/Animals/NPCDef_Wolf';assert(trace(false)==nil)
 candidates={};assert(trace(false)==nil)
`));

test('all four chat commands reselect on every press and failed lookup preserves current chat',()=>execute(`
 local config={UseFaceLayer=true};local root='test';local lastUiCommand='';local composeController=nil
 local selected='old';local status='busy';local activeController={};local stopped=0;local restored=0;local acquired=0
 local writes={};local command='';local desired='new';local expectedGroup=false
 local function valid(a)return a~=nil end
 local function write(name,value)writes[name]=value end
 io.open=function()return {read=function()return command end,close=function()end}end
 local function trace(group)assert(group==expectedGroup);return desired,'No target' end
 local function stop()selected=nil;stopped=stopped+1 end
 local NativeMenu={close=function()end}
 local function restoreFocusPause()restored=restored+1 end
 local function toggle(mode,a)assert(mode=='compose');selected=a end
 local function reuseConversation()return false end
 local function acquireUiInput()acquired=acquired+1;return true end
 ${commands}
 for _,kind in ipairs({'compose-single','select-single','compose-group','select-group'})do
  expectedGroup=kind:find('group')~=nil
  for i=1,2 do
   command=kind..':'..i;uiCommand()
   assert(selected=='new');assert(writes['ui-ready.txt']==command..'\\nready')
  end
 end
 assert(stopped==8 and acquired==4)
 desired=nil;command='compose-group:failed';uiCommand()
 assert(selected=='new' and stopped==8,'Failed selection destroyed working chat')
 assert(writes['ui-ready.txt']==command..'\\nNo target')
`));
