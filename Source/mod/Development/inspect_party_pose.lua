-- Explicit paused, read-only diagnostic. No animation/state setters or asset loads.
return function(root)
 local AI=require('ai_state');local rows={os.date()}
 local function name(o)return AI.valid(o)and o:GetFullName()or 'None'end
 local function value(k,fn)local ok,v=pcall(fn);rows[#rows+1]=k..'='..tostring(v)end
 local lib=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary')
 local meshClass=AI.find('/Script/Engine.SkeletalMeshComponent')
 local f=assert(io.open(root..'/companions-state.tsv','rb'));local text=f:read(1048576);f:close()
 local count=0
 for id,full in text:gmatch('IDENTITY\t[^\t]+\t([^\t]+)\t[^\t]+\t([^\t]+)')do
  if id=='ambrus'then
   local actor=AI.find(full:match('^%S+ (.+)$')or full)
   if AI.valid(actor)then
    count=count+1;if count>4 then break end
    rows[#rows+1]='ACTOR '..full
    local stub=lib:GetAIStub(actor);local board=AI.board(stub)
    if board then
     value('state',function()return board.CurrentCharacterState.TagName:ToString()end)
     value('DefaultAnimLayer',function()return name(actor.DefaultAnimLayer)end)
     value('definition',function()return name(stub:GetAIDefinition())end)
     local meshes={actor.Mesh}
     for i=1,math.min(#meshes,12)do
      local mesh=meshes[i];rows[#rows+1]='MESH '..name(mesh)
      value('AnimationMode',function()return mesh:GetAnimationMode()end)
      value('bPauseAnims',function()return mesh.bPauseAnims end)
      value('bNoSkeletonUpdate',function()return mesh.bNoSkeletonUpdate end)
      value('asset',function()return name(mesh:GetSkeletalMeshAsset())end)
      local anim=mesh:GetAnimInstance();value('anim',function()return name(anim)end)
      if AI.valid(anim)and id=='ambrus'then
       for _,path in ipairs({
        '/Game/_Dawnwalker/Animation_MH/Humans/Ambrus/Animation/LinkedLayers/ABP_AmbrusLocomotionLayers.ABP_AmbrusLocomotionLayers_C',
        '/Game/_Dawnwalker/Animation_MH/Humans/LinkedLayers/ABP_NPC_HumanLocomotionDefaultLayers.ABP_NPC_HumanLocomotionDefaultLayers_C'
       })do local c=AI.find(path);rows[#rows+1]='CLASS '..name(c);if AI.valid(c)then
        local linked=anim:GetLinkedAnimLayerInstanceByClass(c,true);rows[#rows+1]='LINKED '..name(linked)
        for _,key in ipairs({'IdleAnimSet','CycleBlendSpaceSet','StartBlendSpaceSet','StopAnimSet','StopInPlaceAnimSet','TurnInPlaceBlendSpaceSet','PivotBlendSpaceSet','PivotAnimSet','FixedDirectionIdleAnimSet'})do
         value('CDO.'..key,function()return name(c:GetCDO()[key])end)
         if AI.valid(linked)then value('INSTANCE.'..key,function()return name(linked[key])end)end
        end
        value('idle assets',function()
         local assets=c:GetCDO().IdleAnimSet.Assets;local entries={}
         for j=1,math.min(#assets,16)do
          local a=assets[j];entries[#entries+1]=name(a.Animation)..'; states='..#a.StateConditions..'; flags='..#a.FlagConditions..'; tag='..name(a.TagCondition)
         end
         return table.concat(entries,'\n')
        end)
       end end
      end
     end
    end
   end
  end
 end
 local classes=FindAllOf('AnimBlueprintGeneratedClass')or {}
 for _,c in ipairs(classes)do local n=name(c);if n:find('LocomotionLayers',1,true)then rows[#rows+1]='AVAILABLE '..n end end
 return table.concat(rows,'\n')..'\n'
end
