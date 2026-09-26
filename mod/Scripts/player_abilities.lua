-- Allow both learned active-ability families without transforming the player,
-- changing the clock, granting skills or touching any enemy ability system.
local AI=require('ai_state');local Native=require('companion_native')
local M={};local lease;local nextCheck=0;local root=require('runtime_path');local lastStatus
local function status(text)
 if text==lastStatus then return end;lastStatus=text
 local f=io.open(root..'/ability-override-status.txt','w');if f then f:write(text);f:close()end
end
function M.cleanup()
 if not lease then return end
 local ok,why=Native.run('protectabilitiesoff',{});assert(ok,why);lease=nil;nextCheck=0;status('Off. Native ability restrictions restored.')
end
function M.tick(pc,enabled)
 if not enabled then if lease then M.cleanup()end;return end
 if os.time()<nextCheck then return end;nextCheck=os.time()+1
 if not AI.playerReady(pc)then M.cleanup();return end
 local pawn=pc.Pawn;local path=pawn:GetFullName():match('^%S+ (.+)$')
 local now=AI.find('/Script/Engine.Default__KismetSystemLibrary'):GetGameTimeInSeconds(pc)
 local asc=AI.playerAbilitySystem(pc)
 if not AI.valid(asc)then M.cleanup();return end
 if lease and (not AI.same(lease.asc,asc)or lease.path~=path or now<lease.time)then M.cleanup()end
 if lease then lease.time=now;return end
 local result,why=Native.run('protectabilitieson',{path})
 if result then lease={asc=asc,path=path,time=now};status('On. Learned human and vampire active abilities allowed at either time of day.')
 else nextCheck=os.time()+5;status('Waiting for native ability effects: '..tostring(why))end
end
return M
