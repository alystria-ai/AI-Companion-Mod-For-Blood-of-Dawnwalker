-- One explicit paused-game read. Resolve only the recorded party and loaded
-- logic trees; no class loading, behavior mutation or ability activation.
return function(root)
 local AI=require('ai_state')
 local invoke=assert(package.loadlib(root..'/../bridge/native/companion_audit_v251.dll','companion_native_run'))
 local rows,queue,seen={}, {},{};local count=0
 local treeClass=AI.find('/Script/RebelGenericTreeModule.RebelGenericTree')
 local function add(o)
  if not AI.valid(o)or not o:IsA(treeClass)then return end
  local path=o:GetFullName():match('^%S+ (.+)$')
  if not seen[path]then seen[path]=true;queue[#queue+1]=o end
 end
 local function export(o,kind)
  if not AI.valid(o)then return ''end
  count=count+1;local id='ambrus261_'..count
  local f=assert(io.open(root..'/companion-native-request.txt','wb'));f:write(id..'\naudit\n'..o:GetFullName():match('^%S+ (.+)$')..'\n'..kind..'\n');f:close();invoke()
  f=assert(io.open(root..'/companion-native-reply.txt','rb'));local s=f:read(4194304);f:close();assert(s:sub(1,#id)==id,'Stale audit reply')
  f=assert(io.open(root..'/session-v0261/audit-'..count..'.txt','wb'));f:write(o:GetFullName()..'\n'..s);f:close()
  rows[#rows+1]=count..' '..o:GetFullName();return s
 end
 local f=assert(io.open(root..'/companions-state.tsv','rb'));local text=f:read(1048576);f:close()
 for line in text:gmatch('[^\r\n]+')do
  local full=line:match('^IDENTITY\t[^\t]+\tambrus\t[^\t]+\t([^\t]+)')
  if full then
   local actor=AI.find(full:match('^%S+ (.+)$'))
   if AI.valid(actor)then
    local stub=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(actor);local b=AI.board(stub)
    if b then
     export(b,'snapshot')
     rows[#rows+1]='liveCombat='..tostring(stub:IsInCombat())..' flag='..tostring(b.Combat.bInCombat)..' phase='..b.CurrentPhaseName:ToString()..' behavior='..b.CurrentBehaviorName:ToString()
     local def=stub:GetAIDefinition();add(def.LogicTreeGeneric)
    end
   end
  end
 end
 for _,path in ipairs({
 '/Game/_Dawnwalker/Combat/Enemies/_AIDefault/LogicTree_DefaultEnemy_Main.LogicTree_DefaultEnemy_Main',
 '/Game/_Dawnwalker/AI/LogicTree/Trees/LogicTree_Follower_Phase.LogicTree_Follower_Phase',
 '/Game/_Dawnwalker/AI/LogicTree/Trees/LogicTree_Follower_Leader_Enter.LogicTree_Follower_Leader_Enter',
 '/Game/_Dawnwalker/AI/LogicTree/Trees/LogicTree_Followers_Triggers.LogicTree_Followers_Triggers',
 })do add(AI.find(path))end
 local i=1
 while i<=#queue and i<=24 do
  local result=export(queue[i],'tree');i=i+1
  for path in result:gmatch("RebelGenericTree'(/Game/[^']+)'")do if not seen[path]then add(AI.find(path))end end
 end
 rows[#rows+1]='loaded trees seen='..#queue..' exported='..(i-1)
 return table.concat(rows,'\n')..'\n'
end
