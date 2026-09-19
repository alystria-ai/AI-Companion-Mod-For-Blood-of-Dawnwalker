-- One-shot read-only probe: combat damage path metadata + live attribute values.
-- Never writes engine state. Reads class metadata, then attribute snapshots of the
-- player and registered companions to verify tuning/damage writes land.
return function(root, playerPawn)
 local AI=require('ai_state')
 local rows={}
 local function append(s)rows[#rows+1]=tostring(s)end
 local valid=AI.valid
 -- Class metadata: properties and functions (with parameters), walking supers.
 local function schema(path,depthLimit)
  local cls=StaticFindObject(path)
  if not valid(cls)then append('NOT LOADED '..path);return end
  for _=1,depthLimit or 2 do
   if not valid(cls)then return end
   local name=cls:GetFullName()
   append('CLASS '..name)
   local count=0
   cls:ForEachProperty(function(p)
    count=count+1;if count>256 then append('  PROPERTY LIMIT');return true end
    append('  PROPERTY '..p:GetFullName())
   end)
   count=0
   cls:ForEachFunction(function(fn)
    count=count+1;if count>160 then append('  FUNCTION LIMIT');return true end
    local fnName=fn:GetFullName()
    if not fnName:find('ExecuteUbergraph',1,true)then
     append('  FUNCTION '..fnName)
     local n=0
     fn:ForEachProperty(function(p)
      n=n+1;if n>20 then append('    PARAMETER LIMIT');return true end
      append('    '..p:GetFullName())
     end)
    end
   end)
   if name:find('/Script/Engine.',1,true)or name:find('/Script/CoreUObject.',1,true)then return end
   cls=cls:GetSuperStruct()
  end
 end
 schema('/Script/DogwoodStats.CharacterBaseAttributeSet',1)
 schema('/Script/DogwoodCombat.CombatComponentBase',3)
 schema('/Script/Dawnwalker.DawnwalkerCharacterBase',2)
 schema('/Script/RebelAI.RebelAIFactionsController',1)
 -- Live attribute snapshot for one pawn: every attribute name with base/current.
 local attrClass=StaticFindObject('/Script/DogwoodStats.CharacterBaseAttributeSet')
 local function snapshot(label,actor)
  if not valid(actor)then append('SNAPSHOT '..label..': actor invalid');return end
  local stub=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(actor)
  if not AI.board(stub)then append('SNAPSHOT '..label..': AI not ready');return end
  local asc=stub:GetAbilitySystemComponent()
  if not valid(asc)then append('SNAPSHOT '..label..': no ASC');return end
  local attrs=asc:GetAttributeSet(attrClass)
  if not valid(attrs)then append('SNAPSHOT '..label..': no base attribute set');return end
  append('SNAPSHOT '..label..' ('..actor:GetFullName()..')')
  if label~='player'then
   local ok,why=pcall(function()
    local gas=AI.find('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary')
    local effects=asc:GetActiveEffects({})
    append('ACTIVE EFFECTS '..#effects)
    for i=1,math.min(#effects,64)do
     local effect=gas:GetGameplayEffectFromActiveEffectHandle(effects[i]:get())
     if AI.valid(effect)then
      append(' EFFECT '..effect:GetFullName())
      for j=1,math.min(#effect.Modifiers,64)do
       local mod=effect.Modifiers[j]
       local n=mod.Attribute.AttributeName:ToString()
       if n=='Level'or n=='AttackSpeedMultiplierAdditive'then
        append('  MODIFIER '..n..' op='..mod.ModifierOp..' magnitude='..mod.ModifierMagnitude.MagnitudeCalculationType)
       end
      end
     end
    end
   end)
   if not ok then append('EFFECT INSPECTION '..tostring(why))end
  end

  local all={};asc:GetAllAttributes(all)
  if #all>512 then append('  attribute count >512, truncated');end
  for i=1,math.min(#all,512)do
   local a=all[i]:get();local name=a.AttributeName:ToString()
   local okB,base=pcall(function()return attrs[name].BaseValue end)
   local okC,cur=pcall(function()return attrs[name].CurrentValue end)
   local line='  '..name..' base='..(okB and tostring(base)or'?')..' current='..(okC and tostring(cur)or'?')
   -- Flag the attributes the mod tunes, and any base/current divergence that
   -- would make a tuning write invisible to the combat AI.
   if name=='AttackSpeedMultiplierAdditive'or name=='Level'or name=='BaseMeleeDamage'or name=='BaseUnarmedDamage'or name=='DamageAIvsAI'then
    line=line..'   <-- TUNED'
    if okB and okC and type(base)=='number'and type(cur)=='number'and math.abs(cur-base)>.001 then
     line=line..' (aggregated runtime differs from base)'
    end
   end
   append(line)
  end
 end
 if valid(playerPawn)then
  snapshot('player',playerPawn)
  -- Read the bounded identity snapshot. Friendship alone is not ownership.
  local f=io.open(root..'/companions-state.tsv','rb')
  local source=f and f:read(1048576)or '';if f then f:close()end
  local scanned=0
  for full in source:gmatch('IDENTITY\t[^\t]+\t[^\t]+\t[^\t]+\t([^\t]+)')do
   if scanned>=24 then break end
   local actor=StaticFindObject(full:match('^%S+ (.+)$')or full)
   if AI.valid(actor)then
    scanned=scanned+1;snapshot('owned companion '..scanned,actor)
   end
  end
 else append('Player pawn unavailable; static metadata captured only')end
 append('COMPLETE: metadata and attribute values read only; no engine state changed')
 return table.concat(rows,'\n')..'\n'
end
