-- Observe inventory changes, including manual pickups. Never grant or remove items.
local AI=require('ai_state');local Policy=require('reaction_policy');local M={}
local pawn,previous,storage,world,lastGame,batch;local nextPoll=0;local metadata={};local owned={};local serial=0;local errorAt=0
local function snapshot(inventory)
 local counts,assets={},{};local items=inventory:GetCurrentItems()
 for i=1,#items do
  local item=items[i]:get();local a=item.ItemDataAsset
  if AI.valid(a)then local key=a:GetFullName();counts[key]=(counts[key]or 0)+item.Quantity;assets[key]=a end
 end
 return counts,assets
end
function M.reset()pawn=nil;previous=nil;storage=nil;world=nil;lastGame=nil;batch=nil;nextPoll=0;metadata={};owned={}end
local function observe(pc,enabled,busy,hasSpeaker)
 if not enabled then if previous then M.reset()end;return end
 if not hasSpeaker then if previous then M.reset()end;return end
 local now=os.time();if now<nextPoll then return end;nextPoll=now+1
 if not AI.playerReady(pc)then M.reset();return end
 local p=pc.Pawn;local w=p:GetWorld();local game=AI.find('/Script/Engine.Default__KismetSystemLibrary'):GetGameTimeInSeconds(pc)
 if not AI.sameInstance(pawn,p)or not AI.sameInstance(world,w)or lastGame and game<lastGame then M.reset();pawn=p;world=w;nextPoll=now+1 end
 lastGame=game
 local sub=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary'):GetGameInstanceSubsystem(pc,AI.find('/Script/DogwoodInventory.InventorySubsystem'))
 if not AI.valid(sub)then return end
 local inv,stash=sub:GetPlayerInventoryComponent(),sub:GetPlayerStorageComponent()
 -- Unknown storage means unknown provenance: rebaseline, never guess a discovery.
 if not AI.valid(inv)or not AI.valid(stash)or not AI.sameInstance(inv,p:GetInventoryComponent())then previous=nil;storage=nil;batch=nil;return end
 local current,assets=snapshot(inv);local stored=snapshot(stash)
 if not previous then previous=current;storage=stored;for k in pairs(current)do owned[k]=true end;for k in pairs(stored)do owned[k]=true end;return end
 local moved=false
 for key,quantity in pairs(current)do
  local increase=quantity-(previous[key]or 0)
  if increase>0 then
   moved=true
   local withdrawn=math.max(0,(storage[key]or 0)-(stored[key]or 0))
   local fresh=math.max(0,increase-withdrawn)
   if fresh>0 then
    local data=metadata[key]
    if not data then local a=assets[key];data={name=a:GetItemName():ToString(),top=a.ItemRarity==6 and(a.ItemType==6 or a.ItemType==7)};metadata[key]=data end
    batch=batch or {items={},count=0,started=now,last=now,top=false}
    if not batch.items[key]and batch.count<12 then batch.items[key]={name=data.name,quantity=0};batch.count=batch.count+1 end
    if batch.items[key]then batch.items[key].quantity=batch.items[key].quantity+fresh end
    batch.top=batch.top or(data.top and not owned[key]);owned[key]=true
   end
  end
 end
 -- Any inventory operation extends the quiet window, including storage sorting.
 for key,q in pairs(previous)do if q~=(current[key]or 0)then moved=true end end
 previous=current;storage=stored
 if batch and moved then batch.last=now end
 if not batch then return end
 if now-batch.last>90 then batch=nil;return end
 if now-batch.last<6 or busy or not hasSpeaker or p.bCinematicMode or AI.find('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc)then return end
 local board=AI.board(AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(p))
 if not board or board.bIsDead or board.Combat.bInCombat then return end
 local cinematic=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary'):GetWorldSubsystem(pc,AI.find('/Script/DialogueSystem.CinematicSubsystem'))
 if AI.valid(cinematic)then
  if AI.valid(cinematic:GetActiveDialogue())then return end
  for i=1,math.min(#cinematic.ActiveGameplayDialogues,12)do
   local dialogue=cinematic.ActiveGameplayDialogues[i]
   if AI.valid(dialogue)then local speaker=dialogue:GetSpeakingCharacter();if AI.valid(speaker)and cinematic:IsCurrentlySpeakingInGameplayDialogue(speaker)then return end end
  end
 end
 if not Policy.ready()then return end
 local done=batch;batch=nil;if not Policy.take('loot',done.top)then return end
 local rows={};for _,v in pairs(done.items)do rows[#rows+1]=v.name:gsub('[\r\n\t]',' ')..' x'..v.quantity end;table.sort(rows)
 local excerpt,total={},0;for _,row in ipairs(rows)do if total+#row<=720 then excerpt[#excerpt+1]=row;total=total+#row+2 end end
 if #excerpt==0 then return end
 serial=serial+1
 return {id='loot-'..now..'-'..serial,text='Coen finished acquiring a batch. Observed items include: '..table.concat(excerpt,', ')..'. '..(done.top and 'This includes newly acquired Unique-tier weapon or clothing equipment.'or '')..' Storage withdrawals have been excluded. The exact acquisition source is not established; do not invent a chest, theft, battle, purchase or discovery.'}
end
function M.tick(...)
 local ok,result=pcall(observe,...);if ok then return result end
 batch=nil;previous=nil;storage=nil
 if os.time()>=errorAt then errorAt=os.time()+60;print('[Dawnwalker loot reactions] Observation skipped: '..tostring(result)..'\n')end
end
return M
