-- Explicit development check: applies test colours and restores them in the same tick.
return function(root)
 local AI=assert(loadfile(root..'/../mod/Scripts/ai_state.lua'))()
 local env=setmetatable({require=function(name)
  if name=='runtime_path'then return root..'/appearance-check'end
  if name=='ai_state'then return AI end
  error('Unexpected dependency')
 end},{__index=_G})
 local adapter=assert(loadfile(root..'/../mod/Scripts/companion_appearance.lua','t',env))()
 local f=assert(io.open(root..'/companions-state.tsv','rb'));local state=f:read('*a');f:close()
 local rows={};local count=0
 for line in state:gmatch('[^\r\n]+')do
  local key,full=line:match('^IDENTITY\t[^\t]+\t([^\t]+)\t[^\t]+\t([^\t]+)')
  if key=='anca'or key=='ambrus'then
   local actor=StaticFindObject(full:match('^%S+ (.+)$')or full)
   if AI.valid(actor)then
    count=count+1;local member={actor=actor,characterId=key}
    local ok,why=pcall(function()
     for _,c in ipairs(adapter.channels)do adapter.set(key,c.id,'emerald')end
     adapter.apply(member,1000)
     rows[#rows+1]=key..' applied='..tostring(member.appearanceApplied or 0)..' slots='..#(member.appearanceLeases or {})
     for _,lease in ipairs(member.appearanceLeases or {})do
      rows[#rows+1]=lease.mesh:GetFullName()..' slot='..lease.slot
      local values=lease.dynamic.VectorParameterValues
      for n=1,math.min(#values,12)do local v=values[n];local color=v.ParameterValue
       rows[#rows+1]=v.ParameterInfo.Name:ToString()..'='..color.R..','..color.G..','..color.B
      end
     end
    end)
    adapter.release(member)
    rows[#rows+1]=key..' restored; ok='..tostring(ok)..' '..tostring(why)
   end
  end
 end
 assert(count>0,'No Anca or Ambrus companion found')
 return table.concat(rows,'\n')
end
