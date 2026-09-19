return function(root)
 local AI=require('ai_state');local rows={}
 local function str(x)return type(x)=='string'and x or x:ToString()end
 local function field(k,fn)local ok,v=pcall(fn);rows[#rows+1]=k..'='..tostring(v)end
 local filter=StaticFindObject('/Game/_Dawnwalker/AI/AssetTree/Filters/BP_AssetNode_Filter_AttackerIsPlayerFollower.Default__BP_AssetNode_Filter_AttackerIsPlayerFollower_C')
 if AI.valid(filter)then field('FollowerDamageTag',function()local tags=filter.FollowerDamageTag.GameplayTags;local out={};for i=1,#tags do out[#out+1]=str(tags[i].TagName)end;return table.concat(out,',')end)end
 for _,name in ipairs({'GE_Combat_Health_DamageAIvsAI','GE_Combat_Follower_Health_Damage'})do
  local d=StaticFindObject('/Game/_Dawnwalker/Combat/Effects/'..name..'.Default__'..name..'_C')
  if AI.valid(d)then
   rows[#rows+1]=name
   for i=1,math.min(#d.Modifiers,16)do
    local a=d.Modifiers[i];local mag=a.ModifierMagnitude;local b=mag.AttributeBasedMagnitude
    field('attribute',function()return str(a.Attribute.AttributeName)end)
    field('operation',function()return a.ModifierOp end)
    field('magnitudeType',function()return mag.MagnitudeCalculationType end)
    field('scalable',function()return mag.ScalableFloatMagnitude.Value end)
    field('capture',function()return str(b.BackingAttribute.AttributeToCapture.AttributeName)end)
    field('captureSource',function()return b.BackingAttribute.AttributeSource end)
    field('coefficient',function()return b.Coefficient.Value end)
    field('custom',function()return mag.CustomMagnitude.CalculationClassMagnitude:GetFullName()end)
   end
   field('executions',function()return #d.Executions end)
   for i=1,math.min(#d.Executions,8)do field('execution',function()return d.Executions[i].CalculationClass:GetFullName()end)end
  end
 end
 return table.concat(rows,'\n')..'\n'
end
