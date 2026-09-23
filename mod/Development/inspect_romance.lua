-- Read-only asset and saved-fact discovery. Never starts a scene or changes a fact.
return function(root)
 local rows={os.date()}
 local function read(label,fn)local ok,value=pcall(fn);rows[#rows+1]=label..'\t'..tostring(value)end
 local function valid(o)return o and o:IsValid()and not o:HasAnyFlags(EObjectFlags.RF_BeginDestroyed|EObjectFlags.RF_FinishDestroyed)end
 local helpers=assert(StaticFindObject('/Script/AssetRegistry.Default__AssetRegistryHelpers'))
 local registry=helpers:GetAssetRegistry()
 for _,path in ipairs({'/Game/_Dawnwalker/Cutscenes','/Game/_Dawnwalker/Quest'})do
  local assets={};registry:GetAssetsByPath(FName(path),assets,true,true)
  rows[#rows+1]='CATALOG '..path..' '..#assets
  for i=1,math.min(#assets,150000)do
   local a=assets[i]:get();local name=a.AssetName:ToString();local package=a.PackageName:ToString();local lower=package:lower()
   if lower:find('romanc',1,true)or lower:find('kiss',1,true)or lower:find('sq717',1,true)or lower:find('sq721',1,true)then
    rows[#rows+1]='ASSET\t'..package..'.'..name
   end
  end
 end
 for _,asset in ipairs(FindAllOf('LevelSequence')or {})do
  if valid(asset)then local full=asset:GetFullName();local lower=full:lower()
   if lower:find('romanc',1,true)or lower:find('sq717',1,true)or lower:find('sq721',1,true)then rows[#rows+1]='LOADED\t'..full end
  end
 end
 local dbs={}
 for _,db in ipairs(FindAllOf('FactsDB')or {})do
  if valid(db)and db:GetFullName():find('/Engine/Transient.',1,true)then dbs[#dbs+1]=db;rows[#rows+1]='DB\t'..db:GetFullName()end
 end
 local tags={['q.s.721.fact.anca_romance']=true}
 for _,list in ipairs(FindAllOf('GameplayTagsList')or {})do
  if valid(list)then read('TAGLIST '..list:GetFullName(),function()
   local entries=list.GameplayTagList
   for i=1,math.min(#entries,100000)do
    local name=entries[i].Tag:ToString();local lower=name:lower()
    if lower:find('romanc',1,true)or lower:find('kiss',1,true)then tags[name]=true end
   end
   return #entries
  end)end
 end
 for tag in pairs(tags)do
  rows[#rows+1]='TAG\t'..tag
  if #dbs==1 then read('FACT '..tag,function()return dbs[1]:FactGetInt({TagName=FName(tag)})end)end
 end
 for _,time in ipairs(FindAllOf('TimeSystemImpl')or {})do
  if valid(time)and not time:GetFullName():find('Default__',1,true)then read('TIME '..time:GetFullName(),function()return time:GetCurrentDay()end)end
 end
 return table.concat(rows,'\n')..'\n'
end
