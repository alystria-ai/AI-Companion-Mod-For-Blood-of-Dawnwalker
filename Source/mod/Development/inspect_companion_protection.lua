-- Explicit development smoke check. No damage effect, source marker, attribute
-- write or combat action is used. The empty-source filter is removed at once.
return function(root,player,Native,AI)
 local rows={}
 local function out(s)
  rows[#rows+1]=tostring(s);local f=assert(io.open(root..'/protection-check.txt','w'));f:write(table.concat(rows,'\n'));f:close()
 end
 local measured={run=function(op,args)
  local result,why=Native.run(op,args)
  if result then out(op..': nativeMs='..tostring(result.nativeMs)..'; lookupMs='..tostring(result.lookupMs)..'; lookups='..tostring(result.lookupCalls))end
  return result,why
 end}
 local env=setmetatable({require=function(name)if name=='ai_state'then return AI elseif name=='companion_native'then return measured else error('Unexpected dependency')end end},{__index=_G})
 local Protection=assert(loadfile(root..'/../mod/Scripts/companion_protection.lua','t',env))()
 local stub=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(player)
 local ok,why=pcall(function()
  out('Preparing native source query and private effect')
  assert(Protection.ensure(player,stub));out('Native query validated and exact active handle returned')
  assert(Protection.ensure(player,stub));out('Repeated ensure did not stack effects')
 end)
 local cleaned,cleanupError=pcall(Protection.cleanup)
 out('Cleanup '..tostring(cleaned)..' '..tostring(cleanupError))
 out('Result '..tostring(ok)..' '..tostring(why));return table.concat(rows,'\n')
end
