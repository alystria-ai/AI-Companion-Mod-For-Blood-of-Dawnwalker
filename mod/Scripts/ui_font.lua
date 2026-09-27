-- Private font copies let the mod select Chinese/Japanese without changing the
-- game's culture or mutating a shared font used by native menus.
local AI=require('ai_state');local M={};local cached={};local failed={}
local function text(v)return type(v)=='string'and v or v:ToString()end
function M.resolve(language,base)
 if language~='zh-CN'and language~='zh-TW'and language~='ja'then return base end
 local key=language=='ja'and 'Japanese'or 'Chinese'
 if AI.valid(cached[key])then return cached[key]end
 if failed[key]or not AI.valid(base)then return base end
 local ok,result=pcall(function()
  local path='/Engine/Transient.DawnwalkerCompanions_Font_'..key
  local font=StaticFindObject(path)
  if not AI.valid(font)then
   local outer=FindObject('Package','/Engine/Transient')
   assert(AI.valid(outer),'Transient font package unavailable')
   font=StaticConstructObject(AI.find('/Script/Engine.Font'),outer,FName('DawnwalkerCompanions_Font_'..key),EObjectFlags.RF_Transient,EInternalObjectFlags.RootSet)
   assert(AI.valid(font),'Private font construction failed')
  end
  -- UScriptStruct assignment copies the composite arrays. Never edit base.
  font.FontCacheType=base.FontCacheType
  font.CompositeFont=base.CompositeFont
  local found=false
  for i=1,#font.CompositeFont.SubTypefaces do
   local face=font.CompositeFont.SubTypefaces[i];local culture=text(face.Cultures)
   if culture=='ja'or culture=='zh-Hant'then
    local selected=key=='Japanese'and culture=='ja'or key=='Chinese'and culture=='zh-Hant'
    face.Cultures=selected and ''or 'x-dawnwalker-unused'
    found=found or selected
   end
  end
  assert(found,'Requested script subface unavailable')
  return font
 end)
 if ok then cached[key]=result;return result end
 failed[key]=tostring(result)
 return base
end
function M.failure(language)return failed[language=='ja'and 'Japanese'or 'Chinese']end
return M
