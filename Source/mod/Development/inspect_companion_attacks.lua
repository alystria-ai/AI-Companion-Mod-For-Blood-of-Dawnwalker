-- Read-only diagnostic, called on the game thread before reload releases a
-- recorded companion. The report supplies a path, never executable text.
return function(root)
 local AI=require('ai_state');local Native=require('companion_native')
 local rows={os.date()};local seen={}
 local function name(o)return AI.valid(o)and o:GetFullName()or 'None'end
 local function read(key,fn)local ok,value=pcall(fn);rows[#rows+1]=key..'='..tostring(value)end
 local function config(o)
  if not AI.valid(o)or seen[name(o)]then return end;seen[name(o)]=true
  rows[#rows+1]='CONFIG '..name(o)
  for _,key in ipairs({'AttackAbilities','NPCAttacks','AttackAnimations','AnimLayers'})do
   read(key,function()
    if key~='AttackAbilities'then return name(o[key])end
    local a=o[key];assert(#a<=256);local names={}
    for i=1,#a do names[#names+1]=name(a[i])end
    return #a..' '..table.concat(names,';')
   end)
  end
 end
 local function configs(map)
  assert(#map<=16);map:ForEach(function(k,v)
   local c=v:get();rows[#rows+1]='animationType='..tostring(k:get())..' class='..name(c)
   if AI.valid(c)then config(c:IsA(StaticFindObject('/Script/CoreUObject.Class'))and c:GetCDO()or c)end
  end)
 end
 local f=io.open(root..'/companion-combat-lacra.txt','r')
 if f then
  f:read('*l');local line=f:read('*l')or '';f:close()
  local path=line:match('^%S+ (/Game/.+NPCDef_Lacra_Base_C_%d+)$')
  local actor=path and StaticFindObject(path)
  if AI.valid(actor)and actor:IsA(StaticFindObject('/Script/Engine.Pawn'))then
   rows[#rows+1]='PAWN '..name(actor)
   local component=actor:GetComponentByClass(StaticFindObject('/Script/DogwoodCombat.CombatComponentBase'))
   if AI.valid(component)and AI.board(component.AIStub)then
    for _,key in ipairs({'EnemyConfig','Config','AttackAction','OffenseController','DefenseController','ParentAbilitySystemComponent'})do read(key,function()return name(component[key])end)end
    read('mainWeapon',function()return name(component:GetMainWeapon())end)
    read('weaponAnimationType',function()return component:GetCurrentWeaponAnimationType()end)
    read('spawnedWeaponCount',function()return #component.SpawnedWeapons end)
    read('currentAnimations',function()local c=component:GetCurrentCombatAnimations();config(c);return name(c)end)
    read('componentConfigs',function()configs(component.CombatAnimationConfigs);return 'read'end)
   end
  else rows[#rows+1]='Recorded pawn unavailable'end
 end
 for _,path in ipairs({
  '/Game/_Dawnwalker/Combat/Enemies/Bosses/Lacra/NPCDef_Lacra_Base.NPCDef_Lacra_Base_C',
  '/Game/_Dawnwalker/Combat/Enemies/Bosses/Ambrus/NPCDef_Ambrus_Base.NPCDef_Ambrus_Base_C',
 })do
  local c=Native.loadedClass(path)
  if AI.valid(c)then rows[#rows+1]='DEFINITION '..path;read('definitionConfigs',function()configs(c:GetCDO().CombatAnimationConfigs);return 'read'end)end
 end
 return table.concat(rows,'\n')..'\n'
end
