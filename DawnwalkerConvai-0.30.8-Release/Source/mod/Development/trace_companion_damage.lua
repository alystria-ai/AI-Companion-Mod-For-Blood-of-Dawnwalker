-- Development-only, bounded observation. No parameter/return/health changes.
-- Install only through the explicit damage-trace command; never at startup.
return function(root,player,party,AI)
 local M={};local hooks,rows={},{};local expires=os.time()+300;local stopped=false
 local library=AI.find('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary')
 local function name(o)return AI.valid(o)and o:GetFullName()or 'None'end
 local function actor(o)
  if not AI.valid(o)then return nil end
  if o:IsA(AI.find('/Script/Engine.Actor'))then return o end
  if o:IsA(AI.find('/Script/Engine.ActorComponent'))then return o:GetOwner()end
 end
 local function record(path,source,target,detail)
  source=actor(source);target=actor(target)
  local owned=AI.valid(source)and party.identity(source)
  if not owned and not AI.same(target,player)then return end
  rows[#rows+1]=os.time()..'\t'..path..'\tsource='..name(source)..'\towned='..tostring(owned and owned.characterId or false)..'\ttarget='..name(target)..'\t'..(detail or '')
 end
 local function specSource(param)
  local context=library:GetEffectContext(param:get())
  return library:EffectContextGetInstigatorActor(context)
 end
 local function hook(path,fn)
  local ok,pre,post=pcall(RegisterHook,path,function(...)
   if stopped or #rows>=200 or os.time()>=expires then return end
   local pass,why=pcall(fn,...)
   if not pass then rows[#rows+1]='READ ERROR '..path..': '..tostring(why)end
   -- Intentionally no return override.
  end)
  if ok then hooks[#hooks+1]={path,pre,post};rows[#rows+1]='HOOK '..path
  else rows[#rows+1]='UNAVAILABLE '..path..': '..tostring(pre)end
 end
 function M.stop()
  if stopped then return end;stopped=true
  for _,h in ipairs(hooks)do pcall(UnregisterHook,h[1],h[2],h[3])end
  rows[#rows+1]='STOPPED: observation only; no combat values modified'
  local f=io.open(root..'/companion-damage-trace.txt','w');if f then f:write(table.concat(rows,'\n'));f:close()end
 end
 function M.tick()
  if stopped then return end
  if os.time()>=expires or #rows>=200 or not AI.valid(player)then M.stop();return end
  if M.written~=#rows then
   local f=io.open(root..'/companion-damage-trace.txt','w');if f then f:write(table.concat(rows,'\n'));f:close()end
   M.written=#rows
  end
 end
 hook('/Script/GameplayAbilities.AbilitySystemComponent:BP_ApplyGameplayEffectSpecToSelf',function(ctx,spec)
  record('ASC self effect',specSource(spec),ctx:get(),'')
 end)
 hook('/Script/GameplayAbilities.AbilitySystemComponent:BP_ApplyGameplayEffectSpecToTarget',function(ctx,spec,target)
  record('ASC target effect',specSource(spec),target:get(),'')
 end)
 hook('/Script/GameplayAbilities.GameplayAbility:K2_ApplyGameplayEffectSpecToTarget',function(ctx,spec,targets)
  local source=specSource(spec);local found={};local data=targets:get()
  -- Keep the original target data intact. Read a bounded number of entries.
  for i=0,7 do
   local actors=library:GetActorsFromTargetData(data,i)
   for _,a in ipairs(actors)do local key=name(a);if not found[key]then found[key]=true;record('Ability target effect',source,a,name(ctx:get()))end end
  end
 end)
 hook('/Script/DogwoodCombat.CombatComponentBase:BP_ApplyAttackDamage',function(ctx)
  record('Combat attack',ctx:get(),nil,'Target resolved inside native combat')
 end)
 hook('/Script/Engine.GameplayStatics:ApplyDamage',function(ctx,target,amount,instigator,source)
  record('ApplyDamage',source:get(),target:get(),'amount='..tostring(amount:get()))
 end)
 hook('/Script/Engine.Actor:ReceiveAnyDamage',function(ctx,amount,kind,instigator,source)
  record('ReceiveAnyDamage',source:get(),ctx:get(),'amount='..tostring(amount:get()))
 end)
 M.tick();return M
end
