-- Cooldowns survive code reloads, but start fresh when a saved game is loaded.
-- Only ordinary loot rolls chance.
local root=require('runtime_path');local M={};local last={};local loaded=false;local battle
local function read()
 if loaded then return end;loaded=true
 local f=io.open(root..'/reaction-cooldowns.tsv','r');if not f then return end
 for k,v in f:read('*a'):gmatch('([%w_]+)\t(%d+)')do last[k]=tonumber(v)end;f:close()
end
local function save()
 local f=io.open(root..'/reaction-cooldowns.tsv','w');if f then for k,v in pairs(last)do f:write(k,'\t',v,'\n')end;f:close()end
end
function M.resetForSaveLoad()
 last={};battle=nil;loaded=true;save()
end
function M.take(kind,exception)
 read();local now=os.time();local gap=kind=='loot'and 600 or 180
 if battle then return false end
 if now-(last.any or 0)<30 then return false end
 if exception then if now-(last.rare or 0)<120 then return false end
 elseif now-(last[kind]or 0)<gap or (kind=='loot'and math.random()>.2)then return false end
 last[kind]=now;last.any=now;if exception then last.rare=now end
 save()
 return true
end
-- A battle is one pair, not two independent cooldown rolls. Eligibility is
-- decided once at entry. Its ten-minute cooldown starts at the confirmed end.
function M.beginBattle(key)
 read();if battle then return false,'Another battle reaction pair is active'end
 if os.time()-(last.battle or 0)<600 then return false,'Ten-minute cooldown after the previous battle'end
 battle={key=key};return true
end
function M.battleCooldown()
 read();local untilTime=(last.battle or 0)+600
 return math.max(0,untilTime-os.time()),untilTime
end
function M.endBattle(key)
 if not battle or battle.key~=key or battle.ended then return false end
 battle.ended=true;last.battle=os.time();save();return true
end
function M.takeBattle(key,phase)
 if not battle or battle.key~=key or battle[phase]then return false end
 local now=os.time()
 if phase=='start'then
  if battle.ended or now-(last.any or 0)<30 then return false end
 elseif phase=='finish'then
  if not battle.ended then return false end
  -- The paired ending may follow a short fight. An unrelated automatic
  -- reaction still gets breathing room, but the battle's own opening does not
  -- consume its closing line.
  if now-(last.any or 0)<30 and last.any~=battle.spokenAt then return false end
 else return false end
 battle[phase]=true;battle.spokenAt=now;last.any=now
 if phase=='finish'then
  -- A completed encounter and its loot are a single beat. Suppress a delayed
  -- standalone batch, including a rare-item exception immediately afterward.
  last.loot=now;last.rare=now
 end
 save();return true
end
function M.closeBattle(key)if not key or battle and battle.key==key then battle=nil end end
function M.mergedAmbient()
 read();last.ambient=os.time();save()
end
function M.ready()
 local f=io.open(root..'/ambient-ready.tsv','r');if not f then return false,'Conversation runtime readiness is missing'end
 local stamp,value=f:read(100):match('^(%d+)\t([01])');f:close()
 if not stamp or math.abs(os.time()-tonumber(stamp))>2 then return false,'Conversation runtime readiness is stale'end
 if value~='1'then return false,'Conversation runtime is busy'end
 return true
end
return M
