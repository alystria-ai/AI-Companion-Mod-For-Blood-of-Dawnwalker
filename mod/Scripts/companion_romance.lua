-- Relationship evidence belongs to the current game save, never a shared NPC asset.
local M={}
local AI=require('ai_state')
local Settings=require('companion_settings')
local facts={anca='q.s.721.fact.anca_romance',lacra='q.s.717.fact.lacra_romance'}
local system,instance,lastLookup=nil,nil,0
local function database(pc)
 if not AI.valid(pc)or not AI.valid(pc.Pawn)then return end
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
 if not db then Settings.setRomanceStory(false,false);return end
 local result={epoch=tostring(db:GetAddress()),characters={}}
 for key,tag in pairs(facts)do
  local story=db:FactGetInt({TagName=FName(tag)})==1
  local completed=math.max(0,math.min(100000,db:FactGetInt({TagName=FName(historyTag(key))})))
  result.characters[key]={story=story,completed=completed,unlocked=false}
 end
 Settings.setRomanceStory(result.characters.anca.story or result.characters.anca.completed>0,result.characters.lacra.story or result.characters.lacra.completed>0)
 for key,value in pairs(result.characters)do value.unlocked=Settings.effective(key=='anca'and 'AncaRomance'or 'LacraRomance')==1 end
 return result,db
end
function M.snapshot(pc)
 local state=M.read(pc)
 if not state then return 'RELATIONSHIPS\t3\t'..os.time()..'\tunavailable\n'end
 local rows={'RELATIONSHIPS\t3\t'..os.time()..'\t'..state.epoch}
 for _,key in ipairs({'anca','lacra'})do local value=state.characters[key]
  rows[#rows+1]=key..'\t'..(value.story and '1'or '0')..'\t'..value.completed..'\t'..(value.unlocked and '1'or '0')
 end
 return table.concat(rows,'\n')..'\n'
end
return M
