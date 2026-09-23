import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';

const source=await readFile('mod/Scripts/companion_appearance.lua','utf8');
function run(body){
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const setup=`
 package.preload.runtime_path=function()return 'test-runtime'end
 package.preload.ai_state=function()return {
  find=function(path)return path end,
  valid=function(o)return o~=nil end,
  same=function(a,b)return a~=nil and b~=nil and a:GetFullName()==b:GetFullName()end
 }end
 local saved=''
 io.open=function(_,mode)
  if mode=='rb' then return nil end
  return {write=function(_,content)saved=content end,close=function()end}
 end
 local M=(function() ${source} end)()
 `;
 try{
  const rc=lauxlib.luaL_dostring(L,to_luastring(setup+body));
  assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lua.lua_tostring(L,-1)));
 }finally{lua.lua_close(L);}
}

test('eye, hair and armour parameters are scoped to their correct mesh slots',()=>run(`
 local function info(names)local p={};for _,name in ipairs(names)do p[name]=name end;return p end
 assert(select(1,M.category('Face Mesh','MI_Anca_Eyeleft',info({'IrisColor1','IrisColor2'})))=='eyes')
 assert(M.category('Face Mesh','MI_Anca_Eyelashes',info({'IrisColor1'}))==nil)
 assert(select(1,M.category('Appearance.EAppearanceSlot::Headgear','MI_HFA_Anca_Hair',info({'RootColor','TipColor'})))=='hair')
 assert(M.category('Appearance.EAppearanceSlot::Headgear','MI_HairBands',info({'Color'}))==nil)
 assert(select(1,M.category('Appearance.EAppearanceSlot::Torso','/Humans/Garments/MI_Anca_Torso',info({'Color'})))==nil)
 assert(select(1,M.category('Appearance.EAppearanceSlot::Torso','MI_Ambrus_Chainmail',info({'Decal 1 Color 1'})))=='armor')
 assert(M.category('Weapon Mesh','MI_Ambrus_Chainmail',info({'Decal 1 Color 1'}))==nil)
`));

test('a changed colour reapplies immediately and reset restores the original material',()=>run(`
 local function object(name,fields)
  local o=fields or {};o.name=name
  function o:GetFullName()return self.name end
  return o
 end
 local info={Name={ToString=function()return 'IrisColor1'end}}
 local material=object('MI_Anca_Eyeleft',{VectorParameterValues={{ParameterInfo=info,ParameterValue={R=.1,G=.2,B=.3,A=1}}}})
 function material:IsA(class)return class=='/Script/Engine.MaterialInstance'end
 local mesh=object('Face Mesh /Anca',{current=material,writes=0,created=0})
 function mesh:GetNumMaterials()return 1 end
 function mesh:GetMaterial(slot)assert(slot==0);return self.current end
 function mesh:SetMaterial(slot,new)assert(slot==0);self.current=new;self.writes=self.writes+1 end
 function mesh:CreateAndSetMaterialInstanceDynamic(slot)
  assert(slot==0);self.created=self.created+1
  local mid=object('MID '..self.created,{colors={}})
  function mid:SetVectorParameterValueByInfo(parameter,color)
   assert(parameter==info);self.colors[parameter.Name:ToString()]=color
  end
  self.current=mid;return mid
 end
 local actor=object('Anca actor')
 function actor:K2_GetComponentsByClass(class)assert(class=='/Script/Engine.MeshComponent');return {mesh}end
 local member={actor=actor,characterId='anca'}
 M.set('anca','eyes','crimson');M.apply(member,1000)
 assert(mesh.current~=material and mesh.current.colors.IrisColor1.R==.55)
 M.set('anca','eyes','emerald');M.apply(member,1100)
 assert(mesh.created==2 and mesh.current.colors.IrisColor1.G==.34,'revision bypasses scan delay')
 M.reset('anca');M.apply(member,1200)
 assert(mesh.current==material and #member.appearanceLeases==0)
 assert(mesh.writes==2,'only owned material instances were restored')
`));
