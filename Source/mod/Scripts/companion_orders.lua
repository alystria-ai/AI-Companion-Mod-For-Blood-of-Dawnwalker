-- Portable bounded graph executor. No UE calls, reflection, text evaluation, or timers.
-- Caller drives tick(monotonic milliseconds), supplies capabilities, and owns cleanup.
local M = {}
local terminals = {done=true, failed=true}
local values = {
    follow={player=true}, hold={position=true}, attack={current_target=true},
    role={frontline=true,rearguard=true,flank_left=true,flank_right=true,ranged=true},
    stance={passive=true,defensive=true,aggressive=true},
    priority={player_target=true,protect=true,nearest=true,weakest=true},
}
local function integer(n,lo,hi) return type(n)=='number' and n==math.floor(n) and n>=lo and n<=hi end
local function identifier(s) return type(s)=='string' and #s<=48 and s:match('^[A-Za-z][A-Za-z0-9_-]*$')~=nil end
local function validValue(op,value,timeout)
    if type(value)~='string' then return false end
    if values[op] then return values[op][value]==true end
    if op=='wait' then return value:match('^[1-9]%d*$')~=nil and #value<=6 and integer(tonumber(value),1,120000) and tonumber(value)<=timeout end
    if op=='condition' then
        if value=='combat' or value=='target_clear' then return true end
        local fraction=value:match('^health_below:(0%.%d+)$')
        return fraction~=nil and #fraction<=5 and tonumber(fraction)>0
    end
    return false
end
function M.validate(input)
    if type(input)~='table' or input.version~=1 or not identifier(input.id) or terminals[input.id] then return nil,'Invalid graph version or id' end
    if not integer(input.maxTransitions,1,96) then return nil,'Execution needs an explicit 1-96 transition bound' end
    if type(input.nodes)~='table' or #input.nodes<1 or #input.nodes>24 then return nil,'Provide 1-24 nodes' end
    local graph={version=1,id=input.id,start=input.start,maxTransitions=input.maxTransitions,nodes={},byId={}}
    local count=0
    for key in pairs(input.nodes) do
        if not integer(key,1,#input.nodes) then return nil,'Nodes must be a dense array' end
        count=count+1
    end
    if count~=#input.nodes then return nil,'Nodes must be a dense array' end
    for i,n in ipairs(input.nodes) do
        if type(n)~='table' or not identifier(n.id) or terminals[n.id] or graph.byId[n.id] then return nil,'Invalid or duplicate node id' end
        if not integer(n.timeoutMs,1,120000) or not validValue(n.op,n.value,n.timeoutMs) then return nil,'Unsupported operation/value or timeout at '..n.id end
        if type(n.success)~='string' or type(n.failure)~='string' then return nil,'Both edges are required at '..n.id end
        local copy={id=n.id,op=n.op,value=n.value,timeoutMs=n.timeoutMs,success=n.success,failure=n.failure}
        graph.nodes[i]=copy;graph.byId[n.id]=copy
    end
    if not graph.byId[graph.start] then return nil,'Missing start node' end
    for _,n in ipairs(graph.nodes) do
        if not terminals[n.success] and not graph.byId[n.success] then return nil,'Missing success edge at '..n.id end
        if not terminals[n.failure] and not graph.byId[n.failure] then return nil,'Missing failure edge at '..n.id end
    end
    local reachable={}
    local function visit(id)
        if terminals[id] or reachable[id] then return end
        reachable[id]=true;local n=graph.byId[id];visit(n.success);visit(n.failure)
    end
    visit(graph.start)
    local exits={done=true,failed=true}
    for _=1,#graph.nodes do for _,n in ipairs(graph.nodes) do if exits[n.success] or exits[n.failure] then exits[n.id]=true end end end
    for _,n in ipairs(graph.nodes) do
        if not reachable[n.id] then return nil,'Unreachable node '..n.id end
        if not exits[n.id] then return nil,'Closed loop at '..n.id end
    end
    return graph
end
local function split(line)
    local parts={};for value in (line..'\t'):gmatch('(.-)\t') do parts[#parts+1]=value end;return parts
end
function M.decode(text)
    if type(text)~='string' or #text>12288 or text:find('[^\9\10\13\32-\126]') then return nil,'Invalid or oversized wire data' end
    text=text:gsub('\r\n','\n'):gsub('\n$','')
    local lines={};for line in (text..'\n'):gmatch('(.-)\n') do lines[#lines+1]=line end
    local h=split(lines[1] or '')
    if #h~=5 or h[1]~='ORDER' or h[2]~='1' or not h[5]:match('^[1-9]%d?$') then return nil,'Invalid wire header' end
    local graph={version=1,id=h[3],start=h[4],maxTransitions=tonumber(h[5]),nodes={}}
    if #lines>25 then return nil,'Too many wire nodes' end
    for i=2,#lines do
        local p=split(lines[i])
        if #p~=7 or p[1]~='NODE' or not p[5]:match('^[1-9]%d*$') or #p[5]>6 then return nil,'Invalid wire node' end
        graph.nodes[#graph.nodes+1]={id=p[2],op=p[3],value=p[4],timeoutMs=tonumber(p[5]),success=p[6],failure=p[7]}
    end
    return M.validate(graph)
end

local Runner={};Runner.__index=Runner
function Runner:snapshot()
    return {id=self.graph.id,status=self.status,nodeId=self.nodeId,transitions=self.transitions,message=self.message,active=self.active~=nil}
end
function Runner:release(reason)
    if self.active and self.dispatched and type(self.adapter.cancel)=='function' then pcall(self.adapter.cancel,self.active.id,reason) end
    self.active=nil;self.dispatched=false
end
function Runner:cancel(reason)
    if self.status=='running' then self:release(reason or 'Cancelled');self.status='cancelled';self.message=reason or 'Cancelled' end
    return self:snapshot()
end
function Runner:transition(success,message)
    local edge=success and self.active.success or self.active.failure
    if not success then self:release(message or 'Action failed') else self.active=nil;self.dispatched=false end
    self.message=message or (success and 'Step completed' or 'Step failed')
    self.nodeId=edge
    if terminals[edge] then self.status=edge end
end
local function result(value)
    if value==true or value=='success' then return 'success' end
    if value==false or value=='failure' then return 'failure' end
    if value=='pending' then return 'pending' end
    return 'unsupported'
end
function Runner:tick(now)
    if self.status~='running' then return self:snapshot() end
    if type(now)~='number' or now~=now or now==math.huge or now<self.lastNow then
        self:release('Invalid clock');self.status='failed';self.message='Clock must be finite and monotonic';return self:snapshot()
    end
    self.lastNow=now
    if not self.active then
        if self.transitions>=self.graph.maxTransitions then self.status='failed';self.message='Transition budget exhausted';return self:snapshot() end
        self.transitions=self.transitions+1;self.active=self.graph.byId[self.nodeId];self.started=now;self.dispatched=false
    end
    local n=self.active;local elapsed=now-self.started
    if n.op=='wait' then
        if elapsed>=tonumber(n.value) then self:transition(true,'Wait completed') end
    elseif n.op=='condition' then
        local name,value=n.value:match('^([^:]+):(.+)$');name=name or n.value;value=value and tonumber(value) or nil
        if type(self.adapter.sense)~='function' then self:transition(false,'Condition sensing unavailable')
        else
            local ok,ready,why=pcall(self.adapter.sense,name,value)
            if not ok then self:transition(false,'Condition adapter failed')
            elseif ready==true then self:transition(true,'Condition met')
            elseif ready~=false then self:transition(false,why or 'Condition unsupported')
            elseif elapsed>=n.timeoutMs then self:transition(false,'Condition timed out') end
        end
    else
        local ok,value,why
        if not self.dispatched then
            self.dispatched=true
            if type(self.adapter.action)=='function' then ok,value,why=pcall(self.adapter.action,n.op,n.value,n.id)
            else ok=true;value=nil;why='Action adapter unavailable' end
        elseif elapsed>=n.timeoutMs then
            self:transition(false,'Action timed out');return self:snapshot()
        elseif type(self.adapter.poll)=='function' then ok,value,why=pcall(self.adapter.poll,n.id,n.op,n.value)
        else return self:snapshot() end
        local status=ok and result(value) or 'error'
        if status=='success' then self:transition(true,why or 'Action accepted')
        elseif status~='pending' then self:transition(false,why or (status=='error' and 'Action adapter failed' or 'Action unsupported or failed')) end
    end
    -- At most one node is entered per tick. A caller can tick slowly without busy loops.
    return self:snapshot()
end
function M.new(input,adapter,now)
    local graph,err=M.validate(input);if not graph then return nil,err end
    if type(adapter)~='table' then return nil,'Adapter is required' end
    now=now or 0
    if type(now)~='number' or now~=now or now==math.huge or now==-math.huge then return nil,'Clock must be finite' end
    return setmetatable({graph=graph,adapter=adapter,status='running',nodeId=graph.start,transitions=0,lastNow=now,message='Ready',dispatched=false},Runner)
end
return M
