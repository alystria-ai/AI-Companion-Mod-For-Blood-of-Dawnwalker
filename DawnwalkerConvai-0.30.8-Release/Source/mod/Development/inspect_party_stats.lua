return function(root)
 local AI=require('ai_state');local rows={os.date()}
 local lib=StaticFindObject('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary')
 local attributesClass=StaticFindObject('/Script/DogwoodStats.CharacterBaseAttributeSet')
 local f=assert(io.open(root..'/companions-state.tsv','rb'));local text=f:read(1048576);f:close()
 for full in text:gmatch('IDENTITY\t[^\t]+\t[^\t]+\t[^\t]+\t([^\t]+)')do
  local a=StaticFindObject(full:match('^%S+ (.+)$')or full)
  if AI.valid(a)then
   local s=lib:GetAIStub(a)
   if AI.board(s)then
    rows[#rows+1]=full
    local asc=s:GetAbilitySystemComponent();local attrs=asc:GetAttributeSet(attributesClass)
    for _,key in ipairs({'DamageAIvsAI','WeaponDamageMin','WeaponDamageMax','ClawsDamageMultiplier','MeleeDamageMultiplier','Level','Health','MaxHealth'})do
     local ok,v=pcall(function()return attrs[key].CurrentValue end);rows[#rows+1]=key..'='..tostring(v)
    end
    local all={};asc:GetAllAttributes(all);rows[#rows+1]='attributes='..#all
    for i=1,math.min(#all,256)do
     local attr=all[i]:get();local name=lib:GetGameplayAttributeName(attr):ToString()
     if name:find('DamageAIvsAI',1,true)then rows[#rows+1]='setter descriptor='..name end
    end
   end
  end
 end
 return table.concat(rows,'\n')..'\n'
end
