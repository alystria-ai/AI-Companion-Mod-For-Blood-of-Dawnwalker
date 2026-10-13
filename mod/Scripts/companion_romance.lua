-- Relationship evidence belongs to the current game save, never a shared NPC asset.
local M={}
local AI=require('ai_state')
local Settings=require('companion_settings')
local facts={anca='q.s.721.fact.anca_romance',lacra='q.s.717.fact.lacra_romance'}
local order={'anca','lacra','marat'}
local settingIds={anca='AncaRomance',lacra='LacraRomance',marat='CrakeRomance'}
local system,instance,lastLookup=nil,nil,0
-- Crake's romance has no dedicated story fact. It is the third ending of the
-- quest "A Closer Look" (asset sq713_After_Tantari: "we spent some intimate time
-- together"), so it is read from that quest's saved ChosenQuestEnding. The quest is
-- matched by its asset GUID because its title is localized. Two later-chapter facts
-- that name the romance are accepted as well.
local crakeQuestId={2080704471,1130753160,1120068286,1871392165}
local crakeRomanceEnding=3
local crakeFacts={'q.m.302.fact.marat_romanced','q.m.401.fact.outcome.marat.romance'}
local crakeQuest,crakeEpoch,crakeScan=nil,nil,0
local function crakeEnding(epoch)
 if crakeEpoch~=epoch then crakeQuest,crakeEpoch,crakeScan=nil,epoch,0 end
 if not AI.valid(crakeQuest)then
  if os.time()-crakeScan<5 then return 0 end;crakeScan=os.time()
  for _,quest in ipairs(FindAllOf('Quest')or {})do
   if AI.valid(quest)and not quest:GetFullName():find('/Game/',1,true)then
    local ok,match=pcall(function()local id=quest.ID;return id.A==crakeQuestId[1]and id.B==crakeQuestId[2]and id.C==crakeQuestId[3]and id.D==crakeQuestId[4]end)
    if ok and match then crakeQuest=quest;break end
   end
  end
 end
 if not AI.valid(crakeQuest)then return 0 end
 local ok,ending=pcall(function()return crakeQuest.ChosenQuestEnding end)
 return ok and tonumber(ending)or 0
end
local function crakeStory(db,epoch)
 if crakeEnding(epoch)==crakeRomanceEnding then return true end
 for _,tag in ipairs(crakeFacts)do if db:FactGetInt({TagName=FName(tag)})==1 then return true end end
 return false
end
local function database(pc)
 if not AI.playerReady(pc)then return end
 local current=AI.find('/Script/Engine.Default__GameplayStatics'):GetGameInstance(pc)
 if not AI.valid(current)then return end
 if not AI.same(instance,current)then instance=current;system=nil;lastLookup=0 end
 if not AI.valid(system)then
  if os.time()-lastLookup<5 then return end;lastLookup=os.time()
  local instancePath=current:GetFullName():match('^%S+ (.+)$')
  local found
  for _,candidate in ipairs(FindAllOf('QuestSystemImpl')or {})do
   if AI.valid(candidate)and candidate:GetFullName():find(instancePath..'.',1,true)then
    if found then return end;found=candidate
   end
  end
  system=found
 end
 if not AI.valid(system)then return end
 -- The same quest system can replace FactsDB when a save is loaded.
 local db=AI.find('/Script/Quest.Default__QuestSystemBlueprintLibrary'):GetFactsDB(system)
 return AI.valid(db)and db or nil
end
local function historyTag(key)return 'mod.dawnwalkerconvai.relationship.'..key..'.completed'end
function M.read(pc)
 local db=database(pc)
 if not db then Settings.setRomanceStory(false,false,false);return end
 local result={epoch=tostring(db:GetAddress()),characters={}}
 for _,key in ipairs(order)do
  local tag=facts[key]
  local story
  if tag then story=db:FactGetInt({TagName=FName(tag)})==1 else story=crakeStory(db,result.epoch)end
  local completed=math.max(0,math.min(100000,db:FactGetInt({TagName=FName(historyTag(key))})))
  result.characters[key]={story=story,completed=completed,unlocked=false}
 end
 local c=result.characters
 Settings.setRomanceStory(c.anca.story or c.anca.completed>0,c.lacra.story or c.lacra.completed>0,c.marat.story or c.marat.completed>0)
 for key,value in pairs(c)do value.unlocked=Settings.effective(settingIds[key])==1 end
 return result,db
end
function M.snapshot(pc)
 local state=M.read(pc)
 if not state then return 'RELATIONSHIPS\t3\t'..os.time()..'\tunavailable\n'end
 local rows={'RELATIONSHIPS\t3\t'..os.time()..'\t'..state.epoch}
 for _,key in ipairs(order)do local value=state.characters[key]
  rows[#rows+1]=key..'\t'..(value.story and '1'or '0')..'\t'..value.completed..'\t'..(value.unlocked and '1'or '0')
 end
 return table.concat(rows,'\n')..'\n'
end
return M
