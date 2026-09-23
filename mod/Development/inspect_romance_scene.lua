-- Loads only the reviewed cinematic definitions; never starts playback.
return function(root)
 local native=assert(loadfile(root..'/../mod/Scripts/companion_native.lua'))()
 local pc=require('UEHelpers').GetPlayerController()
 assert(pc and pc:IsValid()and pc.Pawn:IsValid(),'Load a save first')
 local rows={}
 local invoke=assert(package.loadlib(root..'/../bridge/native/companion_audit_v040b.dll','companion_native_run'))
 local serial=0
 local function audit(object)
  serial=serial+1;local id='romance-'..os.time()..'-'..serial
  local f=assert(io.open(root..'/companion-native-request.txt','wb'))
  f:write(id..'\naudit\n'..object:GetFullName():match('^%S+ (.+)$')..'\ncinematic\n');f:close();invoke()
  f=assert(io.open(root..'/companion-native-reply.txt','rb'));local data=f:read(500000);f:close()
  assert(data:sub(1,#id)==id,'Stale scene metadata');rows[#rows+1]=data
 end
 local paths={
  '/Game/_Dawnwalker/Cutscenes/Scenes/SQ717/cs_sq717_85_lacra_romance/cs_sq717_85_lacra_romance.cs_sq717_85_lacra_romance',
  '/Game/_Dawnwalker/Quest/_Side_Quests/sq717_wisps/Dialogues/Cutscenes/cs_sq717_85_lacra_romance/Seq/en/Seq-975A4495473059E012DA7EBA1731DD80.Seq-975A4495473059E012DA7EBA1731DD80',
  '/Game/_Dawnwalker/Quest/_Side_Quests/sq717_wisps/Dialogues/Cutscenes/cs_sq717_85_lacra_romance.cs_sq717_85_lacra_romance',
  '/Game/_Dawnwalker/Quest/_Side_Quests/sq721_anca/Dialogues/Cutscenes/cs_sq721_130_RomanceScene.cs_sq721_130_RomanceScene',
  '/Game/_Dawnwalker/Cutscenes/Scenes/SQ721/cs_sq721_130_RomanceScene/cs_sq721_130_RomanceScene.cs_sq721_130_RomanceScene'
 }
 for _,path in ipairs(paths)do
  local object=native.loadedAsset(path)
  if not object then
   local ok,why=native.requestAsset(pc.Pawn,path);rows[#rows+1]='LOAD\t'..path..'\t'..tostring(ok)..' '..tostring(why)
  else
   rows[#rows+1]='OBJECT\t'..object:GetFullName()
   audit(object)
   local cls=object:GetClass()
   for depth=1,4 do
    if not cls or not cls:IsValid()then break end
    rows[#rows+1]='CLASS\t'..cls:GetFullName()
    cls:ForEachProperty(function(p)rows[#rows+1]=p:GetFullName()end)
    cls=cls:GetSuperStruct()
   end
   if object:IsA(StaticFindObject('/Script/Flow.FlowAsset'))then
    local count=0
    object.Nodes:ForEach(function(_,value)
     count=count+1;if count>20 then return end
     local node=value:get();rows[#rows+1]='NODE\t'..node:GetFullName();audit(node)
    end)
   end
   if object:IsA(StaticFindObject('/Script/LevelSequence.LevelSequence'))then
    local scene=object.MovieScene
    rows[#rows+1]='SCENE\t'..scene:GetFullName()
    audit(scene)
    local camera=scene.CameraCutTrack
    if camera and camera:IsValid()then camera.Sections:ForEach(function(_,r)audit(r:get())end)end
    scene.Tracks:ForEach(function(_,value)
     local track=value:get()
     rows[#rows+1]='MASTERTRACK\t'..track:GetFullName()
     if track:IsA(StaticFindObject('/Script/MovieScene.MovieSceneSubTrack'))then
      track.Sections:ForEach(function(_,raw)
       local section=raw:get();local sequence=section:GetSequence()
       if sequence and sequence:IsValid()then rows[#rows+1]='SUBSEQUENCE\t'..sequence:GetFullName()end
      end)
     end
    end)
    scene.ObjectBindings:ForEach(function(_,value)
     local b=value:get();rows[#rows+1]='BINDING\t'..b.BindingName:ToString()
     b.Tracks:ForEach(function(_,track)
      local t=track:get();rows[#rows+1]='TRACK\t'..t:GetFullName()
     end)
    end)
   end
  end
 end
 return table.concat(rows,'\n')
end
