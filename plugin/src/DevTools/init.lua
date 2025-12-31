--!strict
--[[
    DevTools Module - Roblox Studio DevTools for MCP Integration

    This module handles DevTools calls from the daemon/MCP server,
    executing Roblox API operations and returning results.
]]

local HttpService = game:GetService("HttpService")

local DevTools = {}

-- Import tool handlers
local ToolHandler = require(script.ToolHandler)

-- Initialize DevTools
function DevTools.init()
    print("[DevTools] Initializing Roblox Studio DevTools")
    ToolHandler.init()
end

-- Handle a DevTools call from the daemon
function DevTools.handleCall(callId: string, tool: string, params: any): ()
    print(string.format("[DevTools] Handling call: %s (id: %s)", tool, callId))

    -- Execute the tool
    local success, result = ToolHandler.execute(tool, params)

    -- Send result back to daemon
    DevTools.sendResult(callId, success, result)
end

-- Send result back to daemon
function DevTools.sendResult(callId: string, success: boolean, result: any): ()
    local Store = require(script.Parent.State.Store)
    local state = Store.getState()
    local url = state.daemonUrl .. "/devtools/result"

    local body = HttpService:JSONEncode({
        callId = callId,
        success = success,
        result = success and result or nil,
        error = not success and tostring(result) or nil
    })

    local requestSuccess, response = pcall(function()
        return HttpService:RequestAsync({
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = body
        })
    end)

    if not requestSuccess then
        warn("[DevTools] Failed to send result:", response)
    end
end

return DevTools
