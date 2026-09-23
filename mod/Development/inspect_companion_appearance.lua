-- Read-only inspection of owned party actors while the game is paused.
-- Material parameter names are discovered from live assets before any tint is applied.
return function(root)
 local AI={find=StaticFindObject,valid=function(o)return o and o:IsValid()end};local rows={os.date()}
 local function full(o)return AI.valid(o)and o:GetFullName()or 'None'end
 local function value(fn)local ok,result=pcall(fn);return ok and tostring(result)or 'unavailable'end
 local file=assert(io.open(root..'/companions-state.tsv','rb'))
 local state=file:read(1048576)or '';file:close()
 local meshClass=assert(AI.find('/Script/Engine.MeshComponent'),'MeshComponent unavailable')
 local materialClass=AI.find('/Script/Engine.MaterialInstance')
 local examined=0
 for line in state:gmatch('[^\r\n]+')do
  local _,identity,key,_,actorName=line:match('^(IDENTITY)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)')
  if identity and (key=='anca'or key=='brencis'or key=='ambrus')and examined<3 then
   local actor=AI.find(actorName:match('^%S+ (.+)$')or actorName)
   if AI.valid(actor)then
    examined=examined+1;rows[#rows+1]='ACTOR '..key..' '..full(actor)
    local meshes=actor:K2_GetComponentsByClass(meshClass)
    rows[#rows+1]='MESH COUNT '..tostring(#meshes)
    for i=1,math.min(#meshes,80)do
     local mesh=meshes[i]
     if AI.valid(mesh)then
      local count=tonumber(value(function()return mesh:GetNumMaterials()end))or 0
      rows[#rows+1]='MESH '..i..' '..full(mesh)..' materials='..count
      for slot=0,math.min(count,16)-1 do
       local material=mesh:GetMaterial(slot)
       rows[#rows+1]='  SLOT '..slot..' '..full(material)
       local seen={};local depth=0
       while AI.valid(material)and materialClass and material:IsA(materialClass)and depth<5 do
        local identity=full(material);if seen[identity]then break end;seen[identity]=true;depth=depth+1
        for _,entry in ipairs({{'VECTOR','VectorParameterValues'}, {'SCALAR','ScalarParameterValues'}})do
         local ok,parameters=pcall(function()return material[entry[2]]end)
         if ok and parameters then
          for n=1,math.min(#parameters,80)do
           local parameter=parameters[n]
           local name=value(function()return parameter.ParameterInfo.Name:ToString()end)
           if name=='unavailable'then name=value(function()return parameter.ParameterName:ToString()end)end
           local rgba=''
           if entry[1]=='VECTOR'then
            rgba=value(function()local c=parameter.ParameterValue;return string.format('%.3f,%.3f,%.3f,%.3f',c.R,c.G,c.B,c.A)end)
           else rgba=value(function()return parameter.ParameterValue end)end
           rows[#rows+1]='    '..entry[1]..' '..name..'='..rgba
          end
         end
        end
        material=material.Parent
        if AI.valid(material)then rows[#rows+1]='  PARENT '..full(material)end
       end
      end
     end
    end
   end
  end
 end
 return table.concat(rows,'\n')..'\n'
end
