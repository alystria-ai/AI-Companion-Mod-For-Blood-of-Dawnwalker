-- Reuse bounded combat observations. No actor scans, damage hooks or combat
-- commands: this coordinator only schedules a short opening and closing reply.
local AI=require('ai_state');local Policy=require('reaction_policy')
local root=require('runtime_path')
local Battles=require('companion_combat').battles;local M={}
local pawn,world,lastGame,active;local seen={};local nextPoll=0;local serial=0;local errorAt=0
local statusKey,statusAt;local events={}
local function clip(v,limit)
 if #v<=limit then return v end
 local boundary=utf8.offset(v,0,limit+1);return v:sub(1,boundary-1)
end
local function field(v)return clip(tostring(v or''):gsub('[\r\n\t]',' '),480)end
local function status(stage,reason,record,event)
 local now=os.time();local key=table.concat({stage,record and record.key or'',reason or'',event and event.id or''},'|')
 local changed=key~=statusKey
 if not changed and now-(statusAt or 0)<5 then return end
 statusKey=key;statusAt=now
 local remaining,untilTime=Policy.battleCooldown()
 local rows={table.concat({'BATTLE-REACTIONS','1',now,stage},'\t'),
  'reason\t'..field(reason),'battle\t'..field(record and record.key),'battleState\t'..field(record and record.state),
  'cooldownRemaining\t'..remaining,'cooldownUntil\t'..untilTime,
  'openingGate\t'..field(active and active.openingGate),'event\t'..field(event and event.id),
  'eventPhase\t'..field(event and event.phase),'delivery\tScheduling only; client audio completion is reported separately'}
 local f=io.open(root..'/battle-comment-status.txt','w');if f then f:write(table.concat(rows,'\n'));f:close()end
 if changed then
  events[#events+1]=table.concat({now,stage,field(record and record.key),field(reason),remaining,field(event and event.id)},'\t')
  if #events>32 then table.remove(events,1)end
  local log=io.open(root..'/battle-reaction-events.tsv','w');if log then log:write(table.concat(events,'\n'));log:close()end
 end
end
local function close()
 if active then Policy.closeBattle(active.key)end;active=nil
end
function M.reset()
 close();pawn=nil;world=nil;lastGame=nil;seen={};nextPoll=0
end
function M.holdLoot()return active~=nil and active.eligible==true end
local function snapshot(r)
 local copy={key=r.key,kind=r.kind,state=r.state,quietAt=r.quietAt,kills=tonumber(r.kills)or 0,enemies={},witnesses={}}
 for k,v in pairs(r.enemies or {})do copy.enemies[k]=clip(tostring(v):gsub('[\r\n\t]',' '),180)end
 for k,v in pairs(r.witnesses or {})do if v then copy.witnesses[k]=true end end
 return copy
end
local function opponents(r)
 local counts,rows={},{}
 for _,name in pairs(r.enemies)do if name~=''then counts[name]=(counts[name]or 0)+1 end end
 for name,count in pairs(counts)do rows[#rows+1]=name..(count>1 and ' x'..count or '')end;table.sort(rows)
 local out,length={},0
 for _,row in ipairs(rows)do if length+#row<=260 then out[#out+1]=row;length=length+#row+2 end end
 return #out>0 and table.concat(out,', ')or 'identities not established'
end
local function message(r,phase,loot,observation)
 local ending=r.kind=='horde'and(r.state=='cleared'or r.state=='complete')
 local text=phase=='start'and 'Combat has begun.'or ending and 'The Horde wave has been cleared.'or 'Combat has ended; victory or retreat is not established.'
 text=text..' Observed opponents: '..opponents(r)..'.'
 if phase=='end'and ending then text=text..' Confirmed enemies defeated in this wave: '..r.kills..'.'end
 if observation then text=text..' After the fight, Coen observed: "'..clip(field(observation),300)..'".'end
 -- Keep the actual spoken observation before the optional inventory summary.
 -- The bridge accepts a maximum 1,200-byte context packet.
 if loot and loot~=''then text=text..' '..clip(loot,math.max(0,1190-#text))end
 serial=serial+1
 return {id='battle-'..os.time()..'-'..serial,phase=phase,text=text,witnesses=r.witnesses}
end
local function nativeSpeech(pc)
 local lib=AI.find('/Script/Engine.Default__SubsystemBlueprintLibrary')
 local cinematic=lib:GetWorldSubsystem(pc,AI.find('/Script/DialogueSystem.CinematicSubsystem'))
 if not AI.valid(cinematic)then return false end
 local dialogue=cinematic:GetActiveDialogue()
 if AI.valid(dialogue)then
  local detail='Active native dialogue'
  local ok,description=pcall(function()return dialogue:GetFullName()..'; playback='..tostring(dialogue.PlaybackMode)end)
  if ok then detail=detail..': '..description end
  return true,detail
 end
 for i=1,math.min(#cinematic.ActiveGameplayDialogues,12)do
  local d=cinematic.ActiveGameplayDialogues[i]
  if AI.valid(d)then
   local speaker=d:GetSpeakingCharacter()
   -- Combat cries should not starve the opening. Coen's speech and authored
   -- conversations still take priority over an automatic reply.
   if AI.same(speaker,pawn)and cinematic:IsCurrentlySpeakingInGameplayDialogue(speaker)then return true,'Coen is currently speaking'end
  end
 end
 return false
end
local function observe(pc,enabled,busy,hasSpeaker,loot,hasClosingSpeaker,ambient)
 if not enabled then if pawn or active then M.reset()end;status('disabled','React to battles is off');return end
 local now=os.time();if now<nextPoll then return end;nextPoll=now+1
 local p,w=AI.playerReady(pc);if not p then M.reset();status('player-unavailable','Waiting for a possessed player in a loaded world');return end
 local game=AI.find('/Script/Engine.Default__KismetSystemLibrary'):GetGameTimeInSeconds(pc)
 if not AI.sameInstance(pawn,p)or not AI.sameInstance(world,w)or lastGame and game<lastGame then
  M.reset();pawn=p;world=w;nextPoll=now+1
  -- A reload must not replay an already-running encounter or old completed
  -- records. New records after this baseline are eligible as usual.
  for _,r in ipairs(Battles.records)do seen[r.key]=true end
  status('baseline','Existing battle records are not replayed after a world or player reset')
 end
 lastGame=game
 if AI.find('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc)then status('paused','Game is paused',active and active.record);return end
 local current,match;local retained={}
 for _,r in ipairs(Battles.records)do
  retained[r.key]=true
  if r.state=='fighting'then current=r end
  if active and r.key==active.key then match=r end
 end
 for key in pairs(seen)do if not retained[key]then seen[key]=nil end end
 if active and not match then
  if active.eligible then Policy.endBattle(active.key)end
  close()
 end
 if current and(not active or current.key~=active.key)then
  -- A subsequent encounter invalidates any delayed farewell from the old
  -- fight. Finish its cooldown, then apply it to this new encounter.
  if active then if active.eligible then Policy.endBattle(active.key)end;close()end
  if not seen[current.key]then
   seen[current.key]=true
   local eligible,reason=Policy.beginBattle(current.key)
   active={key=current.key,started=game,eligible=eligible,eligibilityReason=reason,record=snapshot(current)}
   status(eligible and 'battle-observed'or 'cooldown',reason or 'Battle pair eligible; waiting for a stable opening',active.record)
   match=current
  end
 end
 if not active then return end
 if match then active.record=snapshot(match)end
 if not active.eligible then
  status('cooldown',active.eligibilityReason,active.record)
  if active.record.state~='fighting'then close()end
  return
 end
 if active.record.state~='fighting'and not active.ended then
  active.ended=now;active.endedGame=game;Policy.endBattle(active.key)
  status('battle-ended','Waiting for the closing window and any collected loot',active.record)
 end
 -- End messages have a bounded lifetime, even if a player starts manual chat
 -- or opens menus. Deferred comments never interrupt a later conversation.
 if active.ended and game-active.endedGame>40 then status('closing-expired','No closing slot became available within forty gameplay seconds',active.record);close();return end
 if not active.ended and not active.opening and game-active.started>12 and not active.openingExpired then
  active.openingExpired=true
  status('opening-expired',active.openingGate or 'No opening slot became available within twelve gameplay seconds',active.record)
 end
 local function wait(reason)
  if active.opening and not active.ended then return end
  if not active.ended and not active.opening and not active.openingExpired then active.openingGate=reason end
  if not active.openingExpired or active.ended then status(active.ended and 'closing-wait'or 'opening-wait',reason,active.record)end
 end
 local available=hasSpeaker
 if active.ended and hasClosingSpeaker~=nil then available=hasClosingSpeaker end
 if busy then wait('Menu, manual conversation or another reaction has priority');return end
 if not available then wait(active.ended and 'No idle companion available for the closing'or 'No nearby conversation-capable companion available');return end
 if pawn.bCinematicMode then wait('Coen is in cinematic mode');return end
 local bridgeReady,bridgeReason=Policy.ready()
 if not bridgeReady then wait(bridgeReason);return end
 local board=AI.board(AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(pawn))
 if not board or board.bIsDead then wait('Player combat board is unavailable or Coen is defeated');return end
 local speaking,speechReason=nativeSpeech(pc)
 if speaking then wait(speechReason);return end
 if not active.ended then
  if active.record.quietAt then wait('Combat is already settling');return end
  if active.opening then return end
  if game-active.started<2 then wait('Waiting two gameplay seconds for stable combat');return end
  if game-active.started>12 then return end
  if not Policy.takeBattle(active.key,'start')then wait('Another automatic reaction used the recent speaking slot');return end
  active.opening=true;local line=message(active.record,'start');status('opening-scheduled','Opening handed to conversation selection',active.record,line);return line
 end
 if board.Combat.bInCombat then wait('Native player combat has not cleared');return end
 local elapsed=now-active.ended
 local pending=loot and loot.pending()
 if elapsed<8 then wait('Waiting eight seconds after combat before closing');return end
 if elapsed<25 and pending and now-pending.last<6 then wait('Waiting for the current loot batch to settle');return end
 if ambient and ambient.waitingForBattle and ambient.waitingForBattle()then wait('Waiting for Coen\'s post-fight observation to finish');return end
 if not Policy.takeBattle(active.key,'finish')then wait('Another automatic reaction used the recent speaking slot');return end
 local text=loot and loot.consume()
 local observation,context
 if ambient then observation,context=ambient.consumeForBattle()end
 local line=message(active.record,'end',text,observation);line.context=context;status('closing-scheduled','Closing handed to conversation selection',active.record,line);close();return line
end
function M.tick(...)
 local ok,result=pcall(observe,...);if ok then return result end
 -- Missing native data must not leave all other reaction types held forever.
 if active and active.eligible then Policy.endBattle(active.key)end;close()
 status('observation-error',tostring(result))
 if os.time()>=errorAt then errorAt=os.time()+60;print('[Dawnwalker battle reactions] Observation skipped: '..tostring(result)..'\n')end
end
return M
