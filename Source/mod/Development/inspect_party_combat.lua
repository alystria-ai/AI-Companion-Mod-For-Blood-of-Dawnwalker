-- Explicit paused-game audit. Only recorded party pawns and loaded definitions.
return function(root)
 local binding=io.open(root..'/formation-binding-probe.request','r')
 if binding then binding:close();os.remove(root..'/formation-binding-probe.request');return assert(loadfile(root..'/../mod/Development/probe_formation_binding.lua'))()(root)end
 local probe=io.open(root..'/formation-audit.request','r')
 if probe then probe:close();os.remove(root..'/formation-audit.request');return assert(loadfile(root..'/../mod/Development/inspect_party_formation.lua'))()(root)end
 local AI=require('ai_state');local Native=require('companion_native')
 local invoke=assert(package.loadlib(root..'/../bridge/native/companion_audit_v251.dll','companion_native_run'))
 local rows,seen,count={}, {},0
 local function export(o,kind)
  if not AI.valid(o)then return end
  local full=o:GetFullName();if seen[full]then return end;seen[full]=true
  count=count+1;local id='party251_'..count
  local f=assert(io.open(root..'/companion-native-request.txt','wb'));f:write(id..'\naudit\n'..full:match('^%S+ (.+)$')..'\n'..(kind or 'snapshot')..'\n');f:close();invoke()
  f=assert(io.open(root..'/companion-native-reply.txt','rb'));local text=f:read(4194304);f:close()
  assert(text:sub(1,#id)==id,'Stale read-only audit')
  f=assert(io.open(root..'/session-v0251/audit-'..count..'.txt','wb'));f:write(full..'\n'..text);f:close()
  rows[#rows+1]=count..' '..full
 end
 local function attempt(fn)local ok,e=pcall(fn);if not ok then rows[#rows+1]='UNAVAILABLE '..tostring(e)end end
 local function definition(c)
  if not AI.valid(c)then return end
  local d=c:GetCDO();export(d)
  attempt(function()export(d.EnemyConfig)end)
  attempt(function()d.CombatAnimationConfigs:ForEach(function(k,v)local cls=v:get();if AI.valid(cls)then export(cls:GetCDO())end end)end)
 end
 for _,c in ipairs(require('companion_config').characters)do definition(Native.loadedClass(c.path))end
 local f=assert(io.open(root..'/companions-state.tsv','rb'));local state=f:read(1048576);f:close()
 for line in state:gmatch('[^\r\n]+')do
  local full=line:match('^IDENTITY\t[^\t]+\t[^\t]+\t[^\t]+\t([^\t]+)')
  if full then attempt(function()
   local actor=StaticFindObject(full:match('^%S+ (.+)$')or full)
   if not AI.valid(actor)then return end
   local stub=StaticFindObject('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(actor)
   local board=AI.board(stub);if not board then return end
   export(board);export(actor:GetMovementComponent())
   local component=actor:GetComponentByClass(StaticFindObject('/Script/DogwoodCombat.CombatComponentBase'));export(component)
   local asc=stub:GetAbilitySystemComponent();export(asc)
   if AI.valid(asc)then for i=1,math.min(#asc.SpawnedAttributes,32)do export(asc.SpawnedAttributes[i])end end
   local def=stub:GetAIDefinition();export(def);export(def:GetAIConfig())
   for _,key in ipairs({'AssetTreeGeneric','LogicTreeGeneric','ServiceTree'})do attempt(function()export(def[key],'tree')end)end
  end)end
 end
 for _,path in ipairs({
 '/Game/_Dawnwalker/Combat/Enemies/Bosses/Ambrus/NewAI/AIDef_Ambrus.AIDef_Ambrus_C',
 '/Game/_Dawnwalker/Combat/Enemies/Bosses/Bakir/NewAI/AIDef_Bakir.AIDef_Bakir_C',
 })do attempt(function()
  local c=Native.loadedClass(path);if not AI.valid(c)then return end
  local d=c:GetCDO();export(d);export(d:GetAIConfig());export(d.AssetTreeGeneric,'tree');export(d.LogicTreeGeneric,'tree');export(d.ServiceTree,'tree')
 end)end
 for _,path in ipairs({
 '/Game/_Dawnwalker/AI/LogicTree/Trees/LogicTree_Follower_Phase.LogicTree_Follower_Phase',
 '/Game/_Dawnwalker/AI/LogicTree/Trees/LogicTree_Follower_Leader_Enter.LogicTree_Follower_Leader_Enter',
 '/Game/_Dawnwalker/AI/LogicTree/Trees/LogicTree_Followers_Triggers.LogicTree_Followers_Triggers',
 })do export(StaticFindObject(path),'tree')end
 return table.concat(rows,'\n')..'\n'
end
