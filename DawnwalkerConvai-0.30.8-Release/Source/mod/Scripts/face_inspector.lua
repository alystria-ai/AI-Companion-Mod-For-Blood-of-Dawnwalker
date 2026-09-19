-- Metadata-only inspector. Disabled in-game after the v0.5 native crash.
-- Never read arbitrary instance properties or invoke getters on global instances.
local M={}
local function valid(object) return object and object:IsValid() end
function M.object(object,report,label,checkpoint)
    checkpoint=checkpoint or function()end
    checkpoint(label..': validate object')
    if not valid(object) then return end
    checkpoint(label..': object name')
    table.insert(report,'\n'..label..': '..tostring(object:GetFullName()))
    checkpoint(label..': GetClass')
    local cls=object:GetClass()
    for depth=1,8 do
        checkpoint(label..': validate class '..depth)
        if not valid(cls) then break end
        checkpoint(label..': class name '..depth)
        table.insert(report,'CLASS '..tostring(cls:GetFullName()))
        local count=0
        local ok,err=pcall(function()
            checkpoint(label..': ForEachProperty depth '..depth)
            cls:ForEachProperty(function(property)
                count=count+1;if count>600 then return true end
                checkpoint(label..': property metadata '..depth..'/'..count)
                table.insert(report,'  '..tostring(property:GetFullName()))
            end)
            checkpoint(label..': ForEachFunction depth '..depth)
            cls:ForEachFunction(function(fn)
                count=count+1;if count>1000 then return true end
                checkpoint(label..': function metadata '..depth..'/'..count)
                table.insert(report,'  FUNCTION '..tostring(fn:GetFullName()))
                if depth<=3 then
                    local parameters=0
                    checkpoint(label..': function parameters '..depth..'/'..count)
                    fn:ForEachProperty(function(p)
                        parameters=parameters+1;if parameters>100 then return true end
                        checkpoint(label..': parameter metadata '..depth..'/'..count..'/'..parameters)
                        table.insert(report,'    '..tostring(p:GetFullName()))
                    end)
                end
            end)
        end)
        if not ok then table.insert(report,'Metadata unavailable: '..tostring(err):match('^[^\n]*')) end
        checkpoint(label..': GetSuperStruct '..depth)
        cls=cls:GetSuperStruct()
    end
end
function M.layers(mesh,report,checkpoint)
    checkpoint=checkpoint or function()end
    -- Only the known face instance; global linked-layer traversal is quarantined.
    checkpoint('Face: GetAnimInstance')
    local ok,instance=pcall(function()return mesh:GetAnimInstance()end)
    if ok then M.object(instance,report,'Main face animation metadata',checkpoint) end
    table.insert(report,'Linked-instance runtime traversal disabled after v0.5 crash')
end
return M
