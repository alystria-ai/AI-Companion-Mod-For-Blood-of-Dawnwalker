-- Player-owned colour presets for summoned companions. The game-facing tint
-- adapter only receives actors owned by the companion manager.
local M={}
local root=require('runtime_path')
local AI=require('ai_state')
local filename=root..'/companion-appearance.tsv'
M.channels={
 {id='eyes',label='Eye colour'},
 {id='hair',label='Hair colour'},
 {id='armor',label='Armour colour'}
}
M.palette={
 {id='default',label='Original',r=0,g=0,b=0},
 {id='onyx',label='Onyx',r=.035,g=.039,b=.045},
 {id='chestnut',label='Chestnut',r=.28,g=.12,b=.07},
 {id='copper',label='Copper',r=.62,g=.22,b=.10},
 {id='gold',label='Gold',r=.78,g=.54,b=.18},
 {id='ivory',label='Ivory',r=.88,g=.81,b=.67},
 {id='silver',label='Silver',r=.59,g=.65,b=.71},
 {id='crimson',label='Crimson',r=.55,g=.045,b=.065},
 {id='emerald',label='Emerald',r=.055,g=.34,b=.16},
 {id='sapphire',label='Sapphire',r=.055,g=.17,b=.50},
 {id='violet',label='Violet',r=.31,g=.13,b=.48},
 {id='scarlet',label='Scarlet',r=1,g=.025,b=.015},
 {id='hot_pink',label='Hot pink',r=1,g=.025,b=.38},
 {id='magenta',label='Magenta',r=.90,g=.015,b=.85},
 {id='electric_blue',label='Electric blue',r=.015,g=.18,b=1},
 {id='neon_lime',label='Neon lime',r=.48,g=1,b=.015},
 {id='auburn',label='Auburn',r=.36,g=.09,b=.045},
 {id='ginger',label='Ginger',r=.78,g=.27,b=.055},
 {id='tangerine',label='Tangerine',r=1,g=.24,b=.015},
 {id='burgundy',label='Burgundy',r=.29,g=.025,b=.09},
 {id='ash_blonde',label='Ash blonde',r=.54,g=.46,b=.32},
 {id='honey_blonde',label='Honey blonde',r=.82,g=.57,b=.25},
 {id='platinum',label='Platinum',r=.83,g=.81,b=.72},
 {id='pearl_white',label='Pearl white',r=.96,g=.93,b=.90},
 {id='lemon',label='Lemon',r=1,g=.92,b=.015},
 {id='rose_pink',label='Rose pink',r=.78,g=.20,b=.36},
 {id='lavender',label='Lavender',r=.57,g=.37,b=.78},
 {id='pastel_blue',label='Pastel blue',r=.30,g=.53,b=.85},
 {id='cyan',label='Cyan',r=.045,g=.67,b=.80},
 {id='teal',label='Teal',r=.025,g=.35,b=.33},
 {id='acid_green',label='Acid green',r=.015,g=.95,b=.065},
 {id='ultraviolet',label='Ultraviolet',r=.48,g=.015,b=1},
 {id='turquoise',label='Turquoise',r=.015,g=.95,b=.68},
 {id='coral',label='Coral',r=1,g=.18,b=.14}
}
-- Retired near-duplicate shades migrate to the remaining natural options.
local aliases={jet_black='onyx',espresso='chestnut',chocolate='chestnut',walnut='chestnut',ash_brown='chestnut',mahogany='auburn',charcoal='onyx',forest_green='emerald'}
local choices,values,revisions,loaded={},{},{},false
for i,color in ipairs(M.palette)do choices[color.id]=i end
local channels={};for _,channel in ipairs(M.channels)do channels[channel.id]=true end
local function validId(value)return type(value)=='string'and value:match('^[%w_%-]+$')and #value<=64 end
function M.load()
 if loaded then return end;loaded=true
 local f=io.open(filename,'rb');if not f then return end
 for line in f:lines()do
  local id,channel,color=line:match('^([%w_%-]+)\t([%w_%-]+)\t([%w_%-]+)$')
  color=aliases[color]or color
  if validId(id)and channels[channel]and choices[color]and color~='default'then
   values[id]=values[id]or {};values[id][channel]=color
  end
 end
 f:close()
end
local function save()
 local rows={'# Companion colour presets. Remove a row to restore its original colour.'}
 local ids={};for id in pairs(values)do ids[#ids+1]=id end;table.sort(ids)
 for _,id in ipairs(ids)do
  for _,channel in ipairs(M.channels)do
   local color=values[id][channel.id]
   if color then rows[#rows+1]=id..'\t'..channel.id..'\t'..color end
  end
 end
 local f=assert(io.open(filename,'wb'));f:write(table.concat(rows,'\n')..'\n');f:close()
end
function M.get(id,channel)
 M.load();local color=values[id]and values[id][channel]or 'default'
 return M.palette[choices[color]or 1]
end
function M.revision(id)M.load();return revisions[id]or 0 end
function M.set(id,channel,color)
 M.load();assert(validId(id)and channels[channel]and choices[color],'Invalid companion colour')
 local old=M.get(id,channel).id;if old==color then return false end
 values[id]=values[id]or {};values[id][channel]=color~='default'and color or nil
 if not next(values[id])then values[id]=nil end
 save();revisions[id]=(revisions[id]or 0)+1;return true
end
function M.cycle(id,channel,direction)
 local index=choices[M.get(id,channel).id]
 local nextIndex=((index-1+(direction or 1))%#M.palette)+1
 M.set(id,channel,M.palette[nextIndex].id)
 return M.palette[nextIndex]
end
function M.reset(id)
 M.load();assert(validId(id),'Invalid companion')
 if not values[id]then return false end
 values[id]=nil;save();revisions[id]=(revisions[id]or 0)+1;return true
end
function M.selected(id)
 M.load();return values[id]~=nil
end
-- Freeze the menu selection when Summon is queued, including an empty original
-- preset. Each member keeps its own copy through loading, recovery and travel.
function M.capture(id,preset)
 M.load();local source=preset or values[id]or {};local copy={}
 for _,channel in ipairs(M.channels)do
  local color=aliases[source[channel.id]]or source[channel.id]
  if choices[color]and color~='default'then copy[channel.id]=color end
 end
 return copy
end
function M.hasPreset(member)
 if not member.appearancePreset then member.appearancePreset=M.capture(member.characterId)end
 return next(member.appearancePreset)~=nil
end

-- Inspect parameter overrides on the material and its parents. A slot is
-- touched only when its existing material actually exposes the named colour.
-- This avoids applying an invented parameter to skin, weapons or unrelated NPCs.
local materialClass
local meshClass
local function vectorParameters(material)
 materialClass=materialClass or AI.find('/Script/Engine.MaterialInstance')
 local found,seen,colors,ancestry={},{},{},{}
 for _=1,6 do
  if not AI.valid(material)or not materialClass or not material:IsA(materialClass)then break end
  local identity=material:GetFullName();if seen[identity]then break end;seen[identity]=true;ancestry[#ancestry+1]=identity
  local ok,entries=pcall(function()return material.VectorParameterValues end)
  if ok and entries then
   for i=1,math.min(#entries,512)do
    local entry=entries[i]
    local passed,name=pcall(function()return entry.ParameterInfo.Name:ToString()end)
    if passed and not found[name]then
     found[name]=entry.ParameterInfo
     local c=entry.ParameterValue;colors[name]={R=c.R,G=c.G,B=c.B,A=c.A}
    end
   end
  end
  material=material.Parent
 end
 return found,colors,table.concat(ancestry,' ')
end
local function category(meshName,materialName,parameters)
 meshName=meshName:lower();materialName=materialName:lower()
 if meshName:find('face mesh',1,true)and materialName:find('eye',1,true)
    and not materialName:find('eyelash',1,true)and not materialName:find('occlusion',1,true)
    and not materialName:find('lacrimal',1,true)then
  if parameters.IrisColor1 or parameters.IrisColor2 or parameters.Leukocoria_Color then return 'eyes',{'IrisColor1','IrisColor2','Leukocoria_Color'}end
 end
 if (meshName:find('headgear',1,true)or meshName:find('hair mesh',1,true)or meshName:find('eyebrows',1,true))
    and (materialName:find('hair',1,true)or materialName:find('eyebrow',1,true))
    and (parameters.RootColor or parameters.TipColor)then return 'hair',{'RootColor','TipColor'}end
 if meshName:find('appearance.eappearanceslot::',1,true)and not meshName:find('headgear',1,true)then
  if materialName:find('armor',1,true)or materialName:find('armour',1,true)
     or materialName:find('chainmail',1,true)or materialName:find('plate',1,true)then
   if parameters.Color or parameters['Decal 1 Color 1']or parameters['Decal 1 Color 2']then
    return 'armor',{'Color','Decal 1 Color 1','Decal 1 Color 2'}
   end
  end
 end
end
M.category=category -- Pure slot selector; also used by offline checks.
local function rgba(color)return {R=color.r,G=color.g,B=color.b,A=1}end
local function restore(member)
 for _,lease in ipairs(member.appearanceLeases or {})do
  pcall(function()
   if AI.valid(lease.mesh)and AI.valid(lease.original)and AI.valid(lease.dynamic)
     and AI.same(lease.mesh:GetMaterial(lease.slot),lease.dynamic)then
    lease.mesh:SetMaterial(lease.slot,lease.original)
   end
  end)
 end
 member.appearanceLeases={}
end
function M.release(member)
 if member then
  restore(member);member.appearanceRevision=nil;member.appearanceActor=nil
  member.appearanceFirstAt=nil;member.appearanceChecked=nil
 end
end
function M.apply(member,now)
 if not member or not AI.valid(member.actor)then return end
 local selected=M.hasPreset(member);local preset=member.appearancePreset
 if not selected and not member.appearanceLeases then return end
 if member.appearanceActor and not AI.same(member.appearanceActor,member.actor)then
  member.appearanceLeases={};member.appearanceFirstAt=nil;member.appearanceChecked=nil
 end
 if member.appearanceRevision~=preset then
  restore(member);member.appearanceRevision=preset;member.appearanceChecked=nil
 end
 member.appearanceActor=member.actor
 if not selected then member.appearanceRevision=nil;return end
 -- The appearance component can replace garment meshes after the pawn arrives.
 -- Recheck briefly during construction, then at a low rate during travel.
 local delay=member.appearanceFirstAt and now-member.appearanceFirstAt<12000 and 1500 or 30000
 if member.appearanceChecked and now-member.appearanceChecked<delay then return end
 member.appearanceFirstAt=member.appearanceFirstAt or now;member.appearanceChecked=now
 meshClass=meshClass or AI.find('/Script/Engine.MeshComponent')
 if not meshClass then return end
 local meshes=member.actor:K2_GetComponentsByClass(meshClass)
 local owned,leases={},{}
 for _,lease in ipairs(member.appearanceLeases or {})do
  local ok,current=pcall(function()return AI.valid(lease.mesh)and lease.mesh:GetMaterial(lease.slot)end)
  if ok and AI.same(current,lease.dynamic)then
   owned[lease.mesh:GetFullName()..':'..lease.slot]=lease;leases[#leases+1]=lease
  end
 end
 member.appearanceLeases=leases
 local applied=0
 for i=1,math.min(#meshes,80)do
  local mesh=meshes[i]
  if AI.valid(mesh)then
   local meshName=mesh:GetFullName()
   local lower=meshName:lower()
   local relevant=lower:find('face mesh',1,true)or lower:find('eyebrows',1,true)
     or lower:find('headgear',1,true)or lower:find('hair mesh',1,true)
     or lower:find('appearance.eappearanceslot::',1,true)
   local count=relevant and math.min(mesh:GetNumMaterials(),32)or 0
   for slot=0,count-1 do
    local material=mesh:GetMaterial(slot)
    if AI.valid(material)then
     local key=meshName..':'..slot;local lease=owned[key]
     if not lease or not AI.same(material,lease.dynamic)then
      owned[key]=nil
      local parameters,_,materialNames=vectorParameters(material)
      local channel,names=category(meshName,materialNames,parameters)
      local color=M.palette[choices[channel and preset[channel]]or 1]
      if color.id~='default'then
       local ok,dynamic=pcall(function()return mesh:CreateAndSetMaterialInstanceDynamic(slot)end)
       if ok and AI.valid(dynamic)then
        lease={mesh=mesh,slot=slot,original=material,dynamic=dynamic}
        member.appearanceLeases[#member.appearanceLeases+1]=lease;owned[key]=lease
        local changed=0
        for _,name in ipairs(names)do if parameters[name]then
         local tint=rgba(color)
         local appliedOk=pcall(function()dynamic:SetVectorParameterValueByInfo(parameters[name],tint)end)
         if not appliedOk then appliedOk=pcall(function()dynamic:SetVectorParameterValue(FName(name),tint)end)end
         if appliedOk then applied=applied+1;changed=changed+1 end
        end end
        if changed==0 then
         pcall(function()if AI.same(mesh:GetMaterial(slot),dynamic)then mesh:SetMaterial(slot,material)end end)
         member.appearanceLeases[#member.appearanceLeases]=nil;owned[key]=nil
        end
       end
      end
     end
    end
   end
  end
 end
 member.appearanceApplied=(member.appearanceApplied or 0)+applied
end
return M
