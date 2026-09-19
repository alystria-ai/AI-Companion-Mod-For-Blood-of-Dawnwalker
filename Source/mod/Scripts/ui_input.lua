-- One balanced input lease per native overlay. Do not reapply input modes on
-- heartbeat refreshes: that can recapture/recenter the gameplay cursor.
local M={}
function M.release(lease)
    if not lease or lease.released then return end
    lease.released=true
    local pc=lease.pc
    if not pc or not pc:IsValid()then return end
    local errors={}
    local function attempt(f)local ok,err=pcall(f);if not ok then errors[#errors+1]=tostring(err)end end
    if lease.move then attempt(function()pc:SetIgnoreMoveInput(false)end)end
    if lease.look then attempt(function()pc:SetIgnoreLookInput(false)end)end
    attempt(function()pc.bShowMouseCursor=lease.cursor end)
    -- Preserve the native pause menu's UI routing. During ordinary gameplay,
    -- restore capture once. Never change the game's paused state.
    if lease.mode then attempt(function()
        if not lease.gameplay:IsGamePaused(pc) then lease.library:SetInputMode_GameOnly(pc,true)end
    end)end
    if #errors>0 then return table.concat(errors,'; ')end
end
function M.acquire(pc,library,gameplay,focus)
    local lease={pc=pc,library=library,gameplay=gameplay,cursor=pc.bShowMouseCursor}
    local ok,err=pcall(function()
        -- Verified in the game's reflected UMG signature: DoNotLock=0,
        -- visible during capture, flush stale gameplay input.
        library:SetInputMode_GameAndUIEx(pc,focus,0,false,true);lease.mode=true
        pc:SetIgnoreMoveInput(true);lease.move=true
        pc:SetIgnoreLookInput(true);lease.look=true
        pc.bShowMouseCursor=true
    end)
    if not ok then M.release(lease);return nil,err end
    return lease
end
return M
