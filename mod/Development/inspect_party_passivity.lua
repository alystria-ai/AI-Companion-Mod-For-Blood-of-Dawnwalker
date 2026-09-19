-- Read-only paused diagnostic: no attacks, cooldown resets or state changes.
return function(root)
 local AI=require('ai_state');local rows={os.date()}
 local Engagement=assert(loadfile(root..'/../mod/Scripts/engagement.lua'))()
 local lib=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary')
 local boardLib=AI.find('/Script/RebelAI.Default__RebelAIBoardBlueprintFunctionLibrary')
 local function name(o)return AI.valid(o)and o:GetFullName()or 'None'end
 local function read(k,f)local ok,v=pcall(f);rows[#rows+1]=k..'='..tostring(v)end
 local f=assert(io.open(root..'/companions-state.tsv','rb'));local state=f:read(1048576);f:close()
 for full in state:gmatch('IDENTITY\t[^\t]+\t[^\t]+\t[^\t]+\t([^\t]+)')do
  local actor=AI.find(full:match('^%S+ (.+)$')or full)
  if AI.valid(actor)then
   local s=lib:GetAIStub(actor);local b=AI.board(s)
   if b then
    rows[#rows+1]='ACTOR '..full
    read('campaignFollower',function()return boardLib:IsLeaderOrFollowerOfPlayer(s)end)
    read('insideCombatGuardArea',function()return b:IsInsideCombatGuardArea()end)
    read('behavior',function()return b.CurrentBehaviorName:ToString()end)
    if Engagement.combatActivity then read('activity',function()return Engagement.combatActivity(s,b)end)end
    read('ownGuardArea',function()local p=b:GetGuardAreaLocation();return p.X..','..p.Y..','..p.Z end)
    read('guardConfig',function()local c=s:GetAIDefinition():GetAIConfig();return tostring(c.bIgnoreGuardAreas)..','..c.FallbackCombatGuardAreaRadius end)
    read('abilityCounts',function()
     local a=s:GetAbilitySystemComponent();local items=a.ActivatableAbilities.Items;assert(#items<=256)
     local list={};for i=1,#items do local v=items[i];list[#list+1]=name(v.Ability)..' active='..tostring(v.ActiveCount)end
     return table.concat(list,'\n')
    end)
    read('movementStack',function()
     local stack=actor:GetMovementComponent().MovementProfileStack;assert(#stack<=64)
     local list={};for i=1,#stack do local v=stack[i];list[#list+1]=tostring(i)..' '..name(v.MovementProfile)..' handle='..tostring(v.MovementProfileHandle)end
     return table.concat(list,'\n')
    end)
   end
  end
 end
 return table.concat(rows,'\n')..'\n'
end
