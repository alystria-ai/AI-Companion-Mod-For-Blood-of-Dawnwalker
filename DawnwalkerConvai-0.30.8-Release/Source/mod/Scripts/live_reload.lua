-- Stable callback router: swapping application code never registers duplicate keys/timers.
local M={}
M.modules={'app','config','targeting','engagement','face_inspector','jali_probe','jali_preview','face_graph','companion_config','companion_native','companions','ui_input','companion_combat','ai_state','companion_recovery','companion_damage','party_formation','formation_native','companion_settings','companion_tuning','companion_menu','companion_protection'}
function M.new(base,externalRequire,queue,report)
    local self={active=nil,last=nil,observed=nil,rejected=nil,pending=false}
    M.router=self -- Version migrations can hand off a cached module explicitly.
    function self:reload(files)
        local candidate={keys={},loops={},cache={}}
        local env=setmetatable({},{__index=base});env._G=env
        env.RegisterKeyBind=function(key,fn)candidate.keys[key]=fn end
        env.LoopAsync=function(ms,fn)table.insert(candidate.loops,{ms=ms,elapsed=0,fn=fn})end
        env.ExecuteInGameThread=function(fn)
            queue(function()if self.active==candidate then fn()end end)
        end
        env.RegisterModCleanup=function(fn)candidate.cleanup=fn end
        env.require=function(name)
            if not files[name]then return externalRequire(name)end
            if candidate.cache[name]~=nil then return candidate.cache[name]end
            local fn,err=load(files[name],'@live/'..name..'.lua','t',env)
            if not fn then error(err)end
            candidate.cache[name]=true
            local result=fn();if result~=nil then candidate.cache[name]=result end
            return candidate.cache[name]
        end
        -- Parse every watched module before executing anything or releasing the old state.
        for name,source in pairs(files)do
            local fn,err=load(source,'@live/'..name..'.lua','t',env)
            if not fn then report('Reload rejected: '..tostring(err));return false end
        end
        local ok,err=pcall(function()env.require('app')end)
        if not ok then report('Reload initialization failed; previous version retained: '..tostring(err));return false end
        local old=self.active
        if old and old.cleanup then
            ok,err=pcall(old.cleanup)
            if not ok then report('Reload cleanup failed; previous version retained: '..tostring(err));return false end
        end
        self.active=candidate
        report('Reload complete: previous NPC/test state released; new Lua code active.')
        return true
    end
    function self:key(key)
        local active=self.active
        if active and active.keys[key]then active.keys[key]()end
    end
    function self:tick(ms)
        local active=self.active;if not active then return end
        for _,loop in ipairs(active.loops)do
            if not loop.stopped then
                loop.elapsed=loop.elapsed+ms
                if loop.elapsed>=loop.ms then
                    loop.elapsed=loop.elapsed%loop.ms
                    local ok,result=pcall(loop.fn)
                    if not ok then report('Application timer error: '..tostring(result))end
                    loop.stopped=ok and result==true
                end
            end
        end
    end
    function self:poll(files,fingerprint)
        if self.pending or fingerprint==self.last or fingerprint==self.rejected then return end
        -- Two identical snapshots avoid reloading midway through a file save.
        if fingerprint~=self.observed then self.observed=fingerprint;return end
        self.pending=true
        local queued,queueError=pcall(queue,function()
            local ok,loaded=pcall(self.reload,self,files)
            self.pending=false
            if ok and loaded then self.last=fingerprint;self.rejected=nil else self.rejected=fingerprint end
            if not ok then report('Reload failed: '..tostring(loaded))end
        end)
        if not queued then self.pending=false;report('Reload queue rejected: '..tostring(queueError))end
    end
    return self
end
return M
