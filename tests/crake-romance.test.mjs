import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {parseRelationships,relationshipKnowledge,relationshipProfiles,hasSharedRomance} from '../bridge/relationships.mjs';

const stamp=Math.floor(Date.now()/1000);
const snapshot=rows=>`RELATIONSHIPS\t3\t${stamp}\t123\n${rows.join('\n')}\n`;
const json=async file=>JSON.parse(await readFile(file,'utf8'));

test('relationship snapshots carry Crake, and older two-row snapshots still parse',()=>{
 const full=parseRelationships(snapshot(['anca\t0\t0\t0','lacra\t0\t0\t0','marat\t1\t0\t1']));
 assert.deepEqual(full.characters.marat,{story:true,completed:0,unlocked:true});
 assert.equal(Object.keys(parseRelationships(snapshot(['anca\t0\t0\t0','lacra\t1\t0\t1'])).characters).length,2);
 assert.throws(()=>parseRelationships(snapshot(['anca\t0\t0\t0','anca\t0\t0\t0'])),/Invalid/);
 assert.throws(()=>parseRelationships(snapshot(['anca\t0\t0\t0','ambrus\t0\t0\t0'])),/Invalid/);
 assert.throws(()=>parseRelationships(snapshot(['anca\t0\t0\t0'])),/Incomplete/);
});

test('a confirmed Crake romance reaches only Crake, and never creates the Anca/Lacra rivalry',()=>{
 const state=parseRelationships(snapshot(['anca\t0\t0\t0','lacra\t0\t0\t0','marat\t1\t0\t1']));
 const base={revision:'r',facts:[],ledger:[],text:''};
 const crake=relationshipKnowledge(base,state,'marat');
 assert(crake.facts.some(f=>f.id==='relationship:marat'&&/already become lovers/.test(f.text)));
 assert(crake.ledger.some(l=>l.id==='relationship:marat:story'));
 assert.equal(relationshipKnowledge(base,state,'anca').facts.some(f=>f.id==='relationship:anca'),false);
 assert.equal(hasSharedRomance({...state,updated:Date.now()}),false,'Crake does not satisfy the two-woman shared scene');
});

test('Crake maps to separate English and multilingual romance profiles',async()=>{
 const variants=await json('characters/romance-config.json');
 const ordinary=(await json('characters/release-config.json')).roster.find(p=>p.key==='marat');
 const multilingual=(await json('characters/multilingual-config.json')).roster.find(p=>p.key==='marat');
 for(const [variant,profile] of [['english',ordinary],['multilingual',multilingual]]){
  const entry=variants.profiles.find(p=>p.key==='marat'&&p.variant===variant);
  assert(entry,variant+' Crake romance profile is missing');
  assert.equal(entry.baseId,profile.id,variant+' romance profile was cloned from a different Crake');
  assert.notEqual(entry.id,entry.baseId);
  const mapped=relationshipProfiles({roster:[profile]},variants).roster[0];
  assert.equal(mapped.romanceId,entry.id);
 }
});

test('the Crake romance setting exists in the in-game schema, config and Mod Menu entry',async()=>{
 const [schema,config,menu]=await Promise.all(['mod/Scripts/companion_settings.lua','mod/config.ini','mod/mod_settings.ini'].map(f=>readFile(f,'utf8')));
 assert.match(schema,/id='CrakeRomance'.*romance=true/);
 assert.match(schema,/id=='CrakeRomance'/);
 assert.match(config,/^CrakeRomance = 0\r?$/m);
 assert.match(menu,/\[Setting\.CrakeRomance\][\s\S]*?ConfigKey = CrakeRomance/);
});

test('the save snapshot reports Crake and honours his On/Off preference while Auto has no story quest',async()=>{
 const {lua,lauxlib,lualib,to_luastring,to_jsstring}=await import('fengari');
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const code=await readFile('mod/Scripts/companion_romance.lua','utf8');
 const setup=`
local store={['q.s.717.fact.lacra_romance']=1}
package.preload.ai_state=function()
 local db={GetAddress=function()return 77 end,FactGetInt=function(self,a)return store[a.TagName] or 0 end}
 return {playerReady=function()return true end,valid=function()return true end,same=function()return true end,
  find=function(p)
   if p:find('GameplayStatics')then return {GetGameInstance=function()return {GetFullName=function()return 'X /Game/I'end} end}end
   return {GetFactsDB=function()return db end}
  end}
end
current={AncaRomance=0,LacraRomance=0,CrakeRomance=0}
package.preload.companion_settings=function()
 local story={}
 return {setRomanceStory=function(a,l,c)story={AncaRomance=a,LacraRomance=l,CrakeRomance=c}end,
  effective=function(id)return (current[id]==1 or current[id]==0 and story[id])and 1 or 0 end}
end
function FindAllOf()return {{GetFullName=function()return 'Q /Game/I.Q'end}}end
function FName(x)return x end
local M=(function()
${code}
end)()
local snap=M.snapshot({})
assert(snap:find('marat\t0\t0\t0'),'Crake is missing or unlocked by Auto without a story fact: '..snap)
assert(snap:find('lacra\t1\t0\t1'),'Lacra story romance was lost')
assert(snap:find('anca\t0\t0\t0'),'Anca changed')
current.CrakeRomance=1
assert(M.snapshot({}):find('marat\t0\t0\t1'),'Crake On did not enable his profile')
current.CrakeRomance=-1
assert(M.snapshot({}):find('marat\t0\t0\t0'),'Crake Off did not use the normal profile')`;
 const result=lauxlib.luaL_dostring(L,to_luastring(setup));
 assert.equal(result,lua.LUA_OK,result===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));
});

test('Crake is detected from the saved ending of A Closer Look, matched by quest GUID',async()=>{
 const {lua,lauxlib,lualib,to_luastring,to_jsstring}=await import('fengari');
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const code=await readFile('mod/Scripts/companion_romance.lua','utf8');
 const setup=`
local store={}
package.preload.ai_state=function()
 local db={GetAddress=function()return 77 end,FactGetInt=function(self,a)return store[a.TagName] or 0 end}
 return {playerReady=function()return true end,valid=function(o)return o~=nil end,same=function()return true end,
  find=function(p)
   if p:find('GameplayStatics')then return {GetGameInstance=function()return {GetFullName=function()return 'X /Game/I'end} end}end
   return {GetFactsDB=function()return db end}
  end}
end
package.preload.companion_settings=function()return {setRomanceStory=function()end,effective=function()return 0 end}end
local function quest(name,id,ending)return {GetFullName=function()return name end,ID=id,ChosenQuestEnding=ending}end
local asset=quest('Quest /Game/_Dawnwalker/Quest/_Side_Quests/sq713_rebel_traitor/Journal/sq713_After_Tantari.sq713_After_Tantari',{A=2080704471,B=1130753160,C=1120068286,D=1871392165},3)
local other=quest('Quest /Engine/Transient.Journal.Quest_1',{A=1,B=2,C=3,D=4},3)
local crake=quest('Quest /Engine/Transient.Journal.Quest_2',{A=2080704471,B=1130753160,C=1120068286,D=1871392165},0)
function FindAllOf(class)if class=='QuestSystemImpl'then return {{GetFullName=function()return 'Q /Game/I.Q'end}}end return {asset,other,crake}end
function FName(x)return x end
local M=(function()
${code}
end)()
local function marat(state)return state.characters.marat.story end
assert(not marat(M.read({})),'An unfinished quest, an asset copy and another quest at ending 3 must not unlock Crake')
crake.ChosenQuestEnding=1
assert(not marat(M.read({})),'Other endings must not unlock Crake')
crake.ChosenQuestEnding=3
assert(marat(M.read({})),'The intimate ending of A Closer Look must unlock Crake')
crake.ChosenQuestEnding=4
assert(not marat(M.read({})),'The cached quest must be re-read, not remembered')
store['q.m.302.fact.marat_romanced']=1
assert(marat(M.read({})),'The later-chapter romance fact must also unlock Crake')`;
 const result=lauxlib.luaL_dostring(L,to_luastring(setup));
 assert.equal(result,lua.LUA_OK,result===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));
});
