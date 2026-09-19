-- Native GAS source filtering. Only owned companion ASCs receive the marker;
-- the private immunity effect belongs to the current player ASC, never a CDO.
local AI=require('ai_state');local Native=require('companion_native')
local M={};local state
local function path(o)return assert(o:GetFullName():match('^%S+ (.+)$'))end
local function request(op,args)
 local result,why=Native.run(op,args);assert(result,why);return result
end
local function import(o,name,text)
 local p=o:Reflection():GetProperty(name)
 p:ImportText(text,p:ContainerPtrToValuePtr(o,0),0,o)
end
function M.cleanup()
 if not state then return end
 if state.handle then
  request('protectremove',{state.ascPath,tostring(state.handle),state.effectPath})
  state.handle=nil
 end
 request('protectrelease',{state.effectPath});state=nil
end
function M.ensure(player,stub)
 assert(AI.valid(player)and AI.board(stub),'Player not ready for companion protection')
 local asc=stub:GetAbilitySystemComponent();assert(AI.valid(asc),'Player ability system unavailable')
 if state and state.handle and AI.same(state.asc,asc)and AI.valid(state.effect)then return true end
 M.cleanup()
 local effect=StaticConstructObject(AI.find('/Script/GameplayAbilities.GameplayEffect'),player)
 assert(AI.valid(effect),'Companion protection effect unavailable');effect.DurationPolicy=1
 local part=StaticConstructObject(AI.find('/Script/GameplayAbilities.ImmunityGameplayEffectComponent'),effect)
 assert(AI.valid(part),'Companion protection component unavailable')
 -- UE4SS Lua table-to-array assignment is not supported for these structs.
 -- Native text import allocates them; the helper copies the native query.
 import(part,'ImmunityQueries','(())')
 import(effect,'GEComponents',"(ImmunityGameplayEffectComponent'"..path(part).."')")
 local effectPath=path(effect)
 request('protectprepare',{effectPath,path(part)})
 state={effect=effect,effectPath=effectPath,asc=asc,ascPath=path(asc),player=player}
 local result=request('protectapply',{state.ascPath,effectPath,path(player)})
 local handle=assert(tonumber(result.handle),'Native protection handle missing')
 assert(handle>=0 and handle%1==0,'Native protection application rejected');state.handle=handle
 return true
end
function M.mark(m,playerStub)
 assert(AI.board(m.stub,m.board)and AI.valid(m.actor),'Companion not ready for source marking')
 local asc=m.stub:GetAbilitySystemComponent()
 assert(AI.valid(asc)and not AI.same(asc,playerStub:GetAbilitySystemComponent()),'Refusing to mark player as a companion')
 if m.protection and AI.same(m.protection.actor,m.actor)and AI.same(m.protection.asc,asc)then return end
 M.unmark(m)
 request('protecttag',{path(m.actor),path(asc),'1'})
 m.protection={actor=m.actor,asc=asc,actorPath=path(m.actor),ascPath=path(asc)}
end
function M.unmark(m)
 if not m.protection then return end
 request('protecttag',{m.protection.actorPath,m.protection.ascPath,'0'});m.protection=nil
end
return M
