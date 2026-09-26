-- Cooldowns survive live reloads and save loads. Only ordinary loot rolls chance.
local root=require('runtime_path');local M={};local last={};local loaded=false
local function read()
 if loaded then return end;loaded=true
 local f=io.open(root..'/reaction-cooldowns.tsv','r');if not f then return end
 for k,v in f:read('*a'):gmatch('([%w_]+)\t(%d+)')do last[k]=tonumber(v)end;f:close()
end
function M.take(kind,exception)
 read();local now=os.time();local gap=kind=='loot'and 600 or 180
 if now-(last.any or 0)<30 then return false end
 if exception then if now-(last.rare or 0)<120 then return false end
 elseif now-(last[kind]or 0)<gap or (kind=='loot'and math.random()>.2)then return false end
 last[kind]=now;last.any=now;if exception then last.rare=now end
 local f=io.open(root..'/reaction-cooldowns.tsv','w');if f then for k,v in pairs(last)do f:write(k,'\t',v,'\n')end;f:close()end
 return true
end
function M.ready()
 local f=io.open(root..'/ambient-ready.tsv','r');if not f then return false end
 local stamp,value=f:read(100):match('^(%d+)\t([01])');f:close()
 return stamp and math.abs(os.time()-tonumber(stamp))<=2 and value=='1'
end
return M
