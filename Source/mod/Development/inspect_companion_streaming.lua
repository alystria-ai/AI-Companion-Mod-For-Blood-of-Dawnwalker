-- Explicit read-only probe: recorded owners, loaded profiles, enums and settings.
return function(root)
 local AI=require('ai_state');local Native=require('companion_native');local rows={}
 local function read(label,fn)local ok,v=pcall(fn);rows[#rows+1]=label..'='..(ok and tostring(v)or 'UNAVAILABLE '..tostring(v))end
 local function file(path)local f=io.open(root..'/'..path,'rb');if not f then return ''end;local v=f:read(1048576);f:close();return v end
 for _,path in ipairs({'/Script/RebelAI.ERebelAIFollowerSpeed','/Script/Population.ECommunityActivatorMode'})do
  read(path,function()local t={};AI.find(path):ForEachName(function(n,v)t[#t+1]=n:ToString()..':'..tostring(v)end);return table.concat(t,',')end)
 end
 local settings=AI.find('/Script/Population.Default__PopulationSettings')
 for _,key in ipairs({'SpawnRangeNear','SpawnRangeFar'})do read(key,function()return settings[key]end)end
 for path in file('session-v0262/movement-profile-paths.txt'):gmatch('[^\r\n]+')do
  local p=AI.find(path);if AI.valid(p)then read('profile '..path,function()return p.MovementConfig.MaxSpeed end)end
 end
 local state=file('companions-state.tsv')
 for id in state:gmatch('\nIDENTITY\t(p%x+)\t')do
  local action=file('companion-recovery-'..id..'.txt'):match('\nowner=([^\r\n]+)')
  if action then read('owner '..id,function()
   local result,why=Native.poll(action);if not result then return why end
   rows[#rows+1]='pawns '..id..'='..tostring(result.pawns)
   local owner=AI.find(result.spawner);if not AI.valid(owner)then return 'Owner unloaded'end
   local p=owner:K2_GetActorLocation();rows[#rows+1]='ownerPosition='..p.X..','..p.Y..','..p.Z
   for _,key in ipairs({'SpawnActivator','DespawnActivator'})do read(key,function()local a=owner[key];return a:GetFullName()..' mode='..tostring(a.Mode)end)end
   local points=owner.DynamicSpawnPoints
   for i=1,math.min(#points,4)do read('spawnpoint '..i,function()local a=points[i];local p=a:K2_GetActorLocation();return a:GetFullName()..' '..p.X..','..p.Y..','..p.Z end)end
   return result.spawner
  end)end
 end
 return table.concat(rows,'\n')..'\n'
end
