-- Offline interface language. Conversation language and character IDs stay separate.
local data=require('ui_translations');local rows=data.rows
local root=require('runtime_path')
local AI=require('ai_state')
local M={revision=0,index=1,code='en'}
M.languages={'en','zh-CN','zh-TW','es','pt-BR','fr','de','ru','ja','ko'}
M.names={'English','简体中文','繁體中文','Español','Português (Brasil)','Français','Deutsch','Русский','日本語','한국어'}
local selected,lastPoll,published=0,0,nil
local aliases={APPEARANCE='Appearance',WAVES='Waves',['STARTING WAVE']='Starting wave',['CURRENT RUN']='Current run',INTERFACE='Interface',PLAYER='Player',FOLLOWING='Following',COMPANIONS='Companions',CONVERSATIONS='Conversations',CAMERA='Camera',HORDE='Horde'}
function M.normalize(value)
 value=tostring(value or ''):lower():gsub('_','-')
 if value:match('^zh')then return (value:find('tw',1,true)or value:find('hk',1,true)or value:find('hant',1,true))and 'zh-TW'or 'zh-CN'end
 if value:match('^pt')then return 'pt-BR'end
 for _,code in ipairs(M.languages)do if value==code:lower()or value:sub(1,#code+1)==code:lower()..'-'then return code end end
 return nil
end
local function autoLanguage()
 -- Static engine library call only. No actor/widget scans or language mutation.
 local ok,value=pcall(function()
  local library=AI.find('/Script/Engine.Default__KismetInternationalizationLibrary')
  return library and library:IsValid()and library:GetCurrentLanguage()or nil
 end)
 local language=ok and M.normalize(value)or nil
 if language then return language end
 local f=io.open(root..'/os-language.txt','r')
 if f then language=M.normalize(f:read(32));f:close()end
 return language or M.normalize(os.getenv('LANG'))or 'en'
end
function M.poll(value,force)
 value=math.max(0,math.min(#M.languages,math.floor(tonumber(value)or 0)))
 if not force and value==selected and os.time()==lastPoll then return end
 selected=value;lastPoll=os.time()
 local code=value==0 and autoLanguage()or M.languages[value]
 if code~=M.code then M.code=code;M.revision=M.revision+1 end
 for i,item in ipairs(M.languages)do if item==code then M.index=i;break end end
 if published~=code then
  local f=io.open(root..'/ui-language.txt','w');if f then f:write(code);f:close();published=code end
 end
end
function M.text(value)
 value=tostring(value or '')
 local row=rows[value]or rows[aliases[value]]
 return M.index>1 and row and row[M.index-1]or value
end
function M.format(value,...)
 local args={...}
 local result=M.text(value):gsub('{(%d+)}',function(n)return tostring(args[tonumber(n)+1]or '')end)
 return result
end
function M.choice(value)
 return value==0 and M.text('Auto')or M.names[value]or 'English'
end
function M.help(setting)return M.text(data.help[setting.id]or (setting.romance and data.help.Romance)or setting.help or '')end
function M.cjk()return M.index==2 or M.index==3 or M.index==9 or M.index==10 end
-- The native Afacad composite used by the menu theme has Japanese, Chinese
-- and Korean subfaces. Do not replace it with Engine Roboto (no CJK subfaces).
return M
