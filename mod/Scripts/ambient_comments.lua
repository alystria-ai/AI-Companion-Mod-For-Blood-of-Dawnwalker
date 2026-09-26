-- Observe only live Coen gameplay speech. No audio capture, hooks, global actor
-- scans or synthetic place names. Nothing queues while a menu or fight is active.
local AI=require('ai_state');local Settings=require('companion_settings')
local Policy=require('reaction_policy')
local root=require('runtime_path');local M={};local world,pawn,pending,lastTime,lastVoice,lastReply
local seen={};local soloGraphs={};local graphReasons={};local serial=0;local nextError=0;local lastStatus
local function status(message)
 if message==lastStatus then return end;lastStatus=message
 local f=io.open(root..'/ambient-status.txt','w');if f then f:write(message);f:close()end
end
-- Inspect authored speakers, not translated words. A Coen line inside an NPC
-- exchange is still a conversation even while only Coen is currently speaking.
local function soloObservation(dialogue)
 -- Tower observations are authored as CinematicGameplay (2), not Gameplay (1).
 if dialogue.PlaybackMode~=1 and dialogue.PlaybackMode~=2 then return false,'Cinematic conversation or cutscene'end
 local template=dialogue.TemplateAsset
 local graph=AI.valid(template)and template or dialogue
 local key=graph:GetFullName()
 -- Coen's generic voiceset also contains conversation-resumption and thirst
 -- barks. It is not an exploration observation, despite having only one speaker.
 if key:lower():find('/voicesets/',1,true)then return false,'General voiceset, not an exploration observation'end
 if soloGraphs[key]~=nil then return soloGraphs[key],graphReasons[key]end
 local ok,result=pcall(function()
  local count,lines=0,0
  local response=AI.find('/Script/DialogueSystem.CinematicNode_Response')
  graph.Nodes:ForEach(function(_,value)
   -- The shared NanoPOI graph has 187 nodes and 94 solo Coen lines, including
   -- climbing observations. Inspect it once, with a bounded cache thereafter.
   count=count+1;if count>512 then error('Observation graph exceeds 512-node inspection bound')end
   local node=value:get();if not AI.valid(node)then error('Unresolved dialogue node')end
   if node:IsA(response)then
    if #node.Responses>128 then error('Observation lines exceed inspection bound')end
    for i=1,#node.Responses do
     local line=node.Responses[i]
     if line.SpeakerTag.TagName:ToString()~='Character.Main.Coen'then error('Another or unknown speaker')end
     lines=lines+1
    end
   else
    local class=node:GetClass():GetFullName():lower()
    -- Nested dialogue/graphs may contain a reply that this graph cannot prove absent.
    local factNode=class:match('/script/dialoguesystem%.flownode_([%w]+)$')
    local factOnly=factNode and ({conditionfact=true,conditionfactint=true,doesfactexist=true,factbranch=true,factbranchint=true,setfactint=true,removefact=true})[factNode]
    if not factOnly and(class:find('cinematic',1,true)or class:find('dialogue',1,true)or class:find('subgraph',1,true))then error('Interactive or nested dialogue')end
   end
  end)
  return lines>0
 end)
 soloGraphs[key]=ok and result==true
 graphReasons[key]=not ok and tostring(result)or not result and 'No authored response lines'or nil
 return soloGraphs[key],graphReasons[key]
end
local function file(name)
 local f=io.open(root..'/'..name,'r');if not f then return ''end;local text=f:read(8192)or '';f:close();return text
end
function M.reset()world=nil;pawn=nil;pending=nil;lastTime=nil;lastVoice=nil;lastReply=nil;seen={};soloGraphs={};graphReasons={}end
local function observe(pc,busy,speakerAvailable)
 if busy then pending=nil;return end
 if Settings.values.AmbientComments~=1 or not AI.playerReady(pc)then pending=nil;return end
 local currentWorld=pc.Pawn:GetWorld()
 local now=AI.find('/Script/Engine.Default__KismetSystemLibrary'):GetGameTimeInSeconds(pc)
 if not AI.sameInstance(world,currentWorld)or not AI.sameInstance(pawn,pc.Pawn)or lastTime and now<lastTime then M.reset();world=currentWorld;pawn=pc.Pawn end
 lastTime=now
 if AI.find('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc)then pending=nil;return end
 local stub=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(pawn)
 local board=AI.board(stub)
 if not board or board.bIsDead or board.Combat.bInCombat then pending=nil;return end
 local lib=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary')
 local system=lib:GetWorldSubsystem(pc,AI.find('/Script/DialogueSystem.CinematicSubsystem'))
 if not AI.valid(system)then pending=nil;return end
 local active=system:GetActiveDialogue()
 if AI.valid(active)and not soloObservation(active)then pending=nil;return end
 local speaking=system:IsCurrentlySpeakingInGameplayDialogue(pawn)
 local dialogueBlocked=false
 local count=math.min(#system.ActiveGameplayDialogues,12)
 for i=0,count do
  local dialogue=i==0 and active or system.ActiveGameplayDialogues[i]
  if AI.valid(dialogue)then
   local speaker=dialogue:GetSpeakingCharacter()
   local nativeSpeaking=AI.valid(speaker)and(i==0 or system:IsCurrentlySpeakingInGameplayDialogue(speaker))
   -- Other gameplay dialogues can be unrelated ambient cries or village barks.
   -- They must not erase Coen's solo line. His own multi-speaker graph and the
   -- active cinematic conversation still block reactions independently.
   if nativeSpeaking and AI.same(speaker,pawn)then
    local solo,reason=soloObservation(dialogue)
    if not solo then dialogueBlocked=reason or 'Not a solo exploration graph'else
    local node=dialogue:GetActiveResponseNode()
    if AI.valid(node)then
     local text=node.ActiveResponseText:ToString():gsub('[\r\n\t]',' '):match('^%s*(.-)%s*$')
     if #text>=8 and #text<=1000 and text:find('%s')then
      if not pending or pending.text~=text then pending={text=text,at=now};status('Observation captured; waiting for Coen to finish')end
      lastVoice=now
     end
    end
    end
   end
  end
 end
 if dialogueBlocked then pending=nil;status('Skipped Coen dialogue: '..tostring(dialogueBlocked));return end
 if not pending or speaking or AI.valid(active)or pawn.bCinematicMode or now-(lastVoice or now)<2 then return end
 if now-(lastVoice or pending.at)>20 then pending=nil;status('Observation expired before a reply was available');return end
 if lastReply and now-lastReply<180 then pending=nil;status('Observation skipped: three-minute cooldown');return end
 if seen[pending.text]and now-seen[pending.text]<300 then pending=nil;status('Repeated observation skipped');return end
 -- A follower can be briefly unavailable during the native line. Capture first
 -- and wait for a speaker, rather than discarding the line before it is heard.
 if speakerAvailable==false then status('Observation waiting for a nearby available companion');return end
 local stamp,ready=file('ambient-ready.tsv'):match('^(%d+)\t([01])')
 if not stamp or math.abs(os.time()-tonumber(stamp))>2 or ready~='1'then status('Observation waiting for conversation runtime');return end
 local line=pending.text;pending=nil;seen[line]=now
 if not Policy.take('ambient',false)then status('Observation skipped: reaction cooldown');return end
 status('Observation sent to companion')
 lastReply=now
 for text,t in pairs(seen)do if now-t>300 then seen[text]=nil end end
 serial=serial+1
 return {text=line,id='ambient-'..os.time()..'-'..serial}
end
function M.tick(pc,busy,speakerAvailable)
 local ok,result=pcall(observe,pc,busy,speakerAvailable)
 if ok then return result end
 pending=nil
 if os.time()>=nextError then nextError=os.time()+30;local f=io.open(root..'/ambient-status.txt','w');if f then f:write('Native observation unavailable: '..tostring(result));f:close()end end
end
return M
