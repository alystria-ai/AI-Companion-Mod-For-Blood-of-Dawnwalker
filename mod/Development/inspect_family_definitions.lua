-- Read-only NPC definition catalogue; no actors are spawned.
return function(root)
 local Native=assert(loadfile(root..'/../mod/Scripts/companion_native.lua'))();local pc=require('UEHelpers').GetPlayerController()
 local config=assert(loadfile(root..'/../mod/Scripts/companion_config.lua'))()
 local rows={}
 for _,c in ipairs(config.characters)do if c.protectIfNoncombatant then
  local class=Native.loadedClass(c.path)
  if not class then Native.requestClass(pc.Pawn,c.path);rows[#rows+1]=c.id..' loading'
  else local data,why=Native.inspect(class:GetCDO());rows[#rows+1]=c.id..' '..tostring(why)
   for key,value in pairs(data or {})do rows[#rows+1]=key..' '..tostring(value)end
  end
 end end
 return table.concat(rows,'\n')
end
