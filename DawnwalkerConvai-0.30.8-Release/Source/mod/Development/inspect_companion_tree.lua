-- Explicit read-only development probe. No gameplay action is requested.
return function(root)
 local AI=require('ai_state');local Native=require('companion_native')
 local invoke=assert(package.loadlib(root..'/../bridge/native/companion_audit.dll','companion_native_run'))
 local rows,queue,seen={},{},{};local count=0
 local function path(o)return o:GetFullName():match('^%S+ (.+)$')end
 local function export(o,kind)
  count=count+1;local id='tree_'..os.time()..'_'..count
  local f=assert(io.open(root..'/companion-native-request.txt','wb'));f:write(id..'\naudit\n'..path(o)..'\n'..kind..'\n');f:close()
  invoke()
  f=assert(io.open(root..'/companion-native-reply.txt','rb'));local result=f:read(4194304);f:close()
  assert(result:sub(1,#id)==id,'Stale audit reply')
  f=assert(io.open(root..'/session-v0243/tree-'..count..'.txt','wb'));f:write(path(o)..'\n'..result);f:close()
  rows[#rows+1]=count..' '..path(o)..' '..(result:find('\nOK\t',1,true)and 'OK'or 'FAILED')
  return result
 end
 local treeClass=StaticFindObject('/Script/RebelGenericTreeModule.RebelGenericTree')
 local function add(o)
  if AI.valid(o)and o:IsA(treeClass)and not seen[path(o)]then seen[path(o)]=true;queue[#queue+1]=o end
 end
 local c=assert(Native.loadedClass('/Game/_Dawnwalker/Combat/Enemies/Bosses/Lacra/AI/AIDef_Lacra.AIDef_Lacra_C'),'Lacra AI class is not loaded')
 local def=c:GetCDO();export(def,'def')
 rows[#rows+1]='tickets: user='..tostring(def.bUseTicketUser)..' board='..tostring(def.bUseTicketBoard)
 local config=def:GetAIConfig()
 for _,key in ipairs({'bAlwaysKeepStandardTicket','bCanGetTicketWithoutPath','ChanceToPassStandardTicketToHelper','MinHelperTicketCooldown','MaxHelperTicketCooldown'})do
  local ok,value=pcall(function()return config[key]end);rows[#rows+1]=key..'='..tostring(value)
 end
 add(def.AssetTreeGeneric);add(def.LogicTreeGeneric);add(def.ServiceTree)
 local attacks=StaticFindObject('/Game/_Dawnwalker/Combat/Enemies/Bosses/Lacra/DA_NPCA_Lacra.DA_NPCA_Lacra')
 if AI.valid(attacks)then export(attacks,'attacks')end
 local i=1
 while i<=#queue and i<=64 do
  local result=export(queue[i],'tree');i=i+1
  -- Resolve only referenced trees, not every montage/ability path in a tree.
  for objectPath in result:gmatch("RebelGenericTree'(/Game/[^']+)'")do
   if not seen[objectPath]then add(StaticFindObject(objectPath))end
  end
 end
 rows[#rows+1]='trees='..#queue..' read='..(i-1)
 return table.concat(rows,'\n')..'\n'
end
