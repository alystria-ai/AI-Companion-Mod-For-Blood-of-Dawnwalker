-- Explicit paused read-only audit of current party definitions and movement.
return function(root)
 local AI=require('ai_state')
 local invoke=assert(package.loadlib(root..'/../bridge/native/companion_audit_v251.dll','companion_native_run'))
 local rows,seen,count={os.date()},{},0
 local function name(o)return AI.valid(o)and o:GetFullName()or 'None'end
 local function read(k,fn)local ok,v=pcall(fn);rows[#rows+1]=k..'='..tostring(v)end
 local function export(o,kind)
  if not AI.valid(o)or seen[name(o)]then return end;seen[name(o)]=true;count=count+1
  local id='combat269_'..count
  local f=assert(io.open(root..'/companion-native-request.txt','wb'));f:write(id..'\naudit\n'..name(o):match('^%S+ (.+)$')..'\n'..(kind or 'snapshot')..'\n');f:close();invoke()
  f=assert(io.open(root..'/companion-native-reply.txt','rb'));local text=f:read(4194304);f:close();assert(text:sub(1,#id)==id,'Stale audit reply')
  f=assert(io.open(root..'/session-v0269/audit-'..count..'.txt','wb'));f:write(name(o)..'\n'..text);f:close()
  rows[#rows+1]='AUDIT '..count..' '..name(o)
 end
 local settings=AI.find('/Script/RebelAI.Default__RebelAISettings')
 read('useAggressionController',function()return settings.Aggression.bUseAggressionController end)
 local f=assert(io.open(root..'/companions-state.tsv','rb'));local state=f:read(1048576);f:close()
 local lib=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary')
 for full in state:gmatch('IDENTITY\t[^\t]+\t[^\t]+\t[^\t]+\t([^\t]+)')do
  local actor=AI.find(full:match('^%S+ (.+)$')or full)
  if AI.valid(actor)then
   local stub=lib:GetAIStub(actor);local board=AI.board(stub)
   if board then
    rows[#rows+1]='ACTOR '..full
    export(board)
    local move=actor:GetMovementComponent();export(move)
    for _,k in ipairs({'MaxWalkSpeed','DesiredMovementSpeedMultiplier'})do read(k,function()return move[k]end)end
    read('movementProfile',function()return name(move:GetCurrentMovementProfile())end)
    read('profileSpeed',function()return move:GetCurrentMovementProfile().MovementConfig.MaxSpeed end)
    local def=stub:GetAIDefinition();export(def);export(def:GetAIConfig())
    for _,k in ipairs({'LogicTreeGeneric','AssetTreeGeneric','ServiceTree'})do read(k,function()export(def[k],'tree');return name(def[k])end)end
    local component=actor:GetComponentByClass(AI.find('/Script/DogwoodCombat.CombatComponentBase'));export(component)
    if AI.valid(component)then read('attacks',function()export(component.NPCAttacks,'attacks');return name(component.NPCAttacks)end)end
   end
  end
 end
 return table.concat(rows,'\n')..'\n'
end
