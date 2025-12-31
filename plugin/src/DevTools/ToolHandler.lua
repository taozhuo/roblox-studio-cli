--!strict
--[[
    ToolHandler - Dispatches DevTools calls to appropriate handlers

    Each tool category has its own handler module:
    - Elements: Selection and instance tree operations
    - Console: Logs and code evaluation
    - Sources: Script read/write operations
    - History: Undo/redo operations
    - Network: HTTP capture (placeholder)
    - Performance: Perf spans (placeholder)
    - Memory: Memory sampling
]]

local ToolHandler = {}

-- Tool handlers will be registered here
local handlers: {[string]: (params: any) -> (boolean, any)} = {}

-- Import handler modules (will be implemented in later phases)
local Elements: any = nil
local Console: any = nil
local Sources: any = nil
local History: any = nil
local Studio: any = nil
local Network: any = nil
local Performance: any = nil
local Memory: any = nil

-- Initialize all handlers
function ToolHandler.init()
    -- Load handler modules
    local success, err = pcall(function()
        Elements = require(script.Parent.Elements)
        Console = require(script.Parent.Console)
        Sources = require(script.Parent.Sources)
        History = require(script.Parent.History)
        Studio = require(script.Parent.Studio)
        -- These are placeholders for now
        -- Network = require(script.Parent.Network)
        -- Performance = require(script.Parent.Performance)
        -- Memory = require(script.Parent.Memory)
    end)

    if not success then
        warn("[DevTools] Some handlers failed to load:", err)
    end

    -- Register all tool handlers
    ToolHandler.registerHandlers()
end

-- Register all tool handlers
function ToolHandler.registerHandlers()
    -- Elements Panel (Phase 2)
    if Elements then
        handlers["studio.selection.get"] = Elements.getSelection
        handlers["studio.selection.set"] = Elements.setSelection
        handlers["studio.instances.tree"] = Elements.getInstanceTree
        handlers["studio.instances.getProps"] = Elements.getInstanceProps
        handlers["studio.instances.setProps"] = Elements.setInstanceProps
        handlers["studio.instances.create"] = Elements.createInstance
        handlers["studio.instances.delete"] = Elements.deleteInstance
        -- Mouse pointer tools
        handlers["studio.pointer.get"] = Elements.getMousePointer
        handlers["studio.pointer.capture"] = Elements.capturePointer
        handlers["studio.pointer.getLast"] = Elements.getLastPointer
        -- Path drawing tools
        handlers["studio.path.start"] = Elements.startPath
        handlers["studio.path.stop"] = Elements.stopPath
        handlers["studio.path.get"] = Elements.getPath
        handlers["studio.path.clear"] = Elements.clearPath
        handlers["studio.path.addPoint"] = Elements.addPathPoint
    end

    -- Console Panel (Phase 3)
    if Console then
        handlers["studio.logs.getHistory"] = Console.getLogHistory
        handlers["studio.logs.clear"] = Console.clearLogs
        handlers["studio.eval"] = Console.eval
    end

    -- Sources Panel (Phase 4)
    if Sources then
        handlers["studio.scripts.list"] = Sources.listScripts
        handlers["studio.scripts.read"] = Sources.readScript
        handlers["studio.scripts.write"] = Sources.writeScript
        handlers["studio.scripts.create"] = Sources.createScript
    end

    -- History Panel (Phase 5)
    if History then
        handlers["studio.history.begin"] = History.beginRecording
        handlers["studio.history.end"] = History.endRecording
        handlers["studio.history.undo"] = History.undo
        handlers["studio.history.redo"] = History.redo
    end

    -- Studio Tools (Plugin-level features)
    if Studio then
        handlers["studio.getActiveScript"] = Studio.getActiveScript
        handlers["studio.getActiveScriptSource"] = Studio.getActiveScriptSource
        handlers["studio.getStudioInfo"] = Studio.getStudioInfo
        handlers["studio.openScript"] = Studio.openScript
        handlers["studio.getOpenDocuments"] = Studio.getOpenDocuments
        -- Debugger tools
        handlers["studio.debug.getBreakpoints"] = Studio.getBreakpoints
        handlers["studio.debug.addBreakpoint"] = Studio.addBreakpoint
        handlers["studio.debug.removeBreakpoint"] = Studio.removeBreakpoint
        handlers["studio.debug.clearAllBreakpoints"] = Studio.clearAllBreakpoints
    end

    -- Runtime Tools (Phase 6) - placeholders
    handlers["runtime.http.captureStart"] = function() return true, { message = "Not implemented yet" } end
    handlers["runtime.http.captureStop"] = function() return true, { message = "Not implemented yet" } end
    handlers["runtime.http.getRecent"] = function() return true, { requests = {} } end

    handlers["runtime.perf.span"] = function() return true, { message = "Not implemented yet" } end
    handlers["runtime.perf.dumpWindow"] = function() return true, { spans = {} } end
    handlers["runtime.perf.getStats"] = function()
        local Stats = game:GetService("Stats")
        return true, {
            fps = Stats.HeartbeatTimeMs > 0 and (1000 / Stats.HeartbeatTimeMs) or 60,
            heartbeatTimeMs = Stats.HeartbeatTimeMs
        }
    end

    handlers["runtime.memory.sample"] = function(params)
        local Stats = game:GetService("Stats")
        return true, {
            totalMemoryMb = Stats:GetTotalMemoryUsageMb(),
            timestamp = os.time()
        }
    end
    handlers["runtime.memory.getStats"] = function()
        local Stats = game:GetService("Stats")
        return true, {
            totalMemoryMb = Stats:GetTotalMemoryUsageMb()
        }
    end
    handlers["runtime.memory.instanceCount"] = function()
        -- Count all instances
        local count = 0
        local function countDescendants(instance: Instance)
            count = count + 1
            for _, child in ipairs(instance:GetChildren()) do
                countDescendants(child)
            end
        end
        countDescendants(game)
        return true, { count = count }
    end

    -- Cloud Tools (Phase 7) - handled by daemon, not plugin
    handlers["cloud.datastore.read"] = function() return false, "Cloud tools are handled by daemon" end
    handlers["cloud.datastore.write"] = function() return false, "Cloud tools are handled by daemon" end
    handlers["cloud.datastore.list"] = function() return false, "Cloud tools are handled by daemon" end
    handlers["cloud.place.publish"] = function() return false, "Cloud tools are handled by daemon" end
    handlers["cloud.place.getInfo"] = function() return false, "Cloud tools are handled by daemon" end
    handlers["cloud.universe.getInfo"] = function() return false, "Cloud tools are handled by daemon" end

    print(string.format("[DevTools] Registered %d tool handlers", ToolHandler.countHandlers()))
end

-- Count registered handlers
function ToolHandler.countHandlers(): number
    local count = 0
    for _ in pairs(handlers) do
        count = count + 1
    end
    return count
end

-- Execute a tool
function ToolHandler.execute(tool: string, params: any): (boolean, any)
    local handler = handlers[tool]

    if not handler then
        return false, string.format("Unknown tool: %s", tool)
    end

    local success, handlerSuccess, handlerResult = pcall(handler, params or {})

    if not success then
        return false, string.format("Tool execution failed: %s", tostring(handlerSuccess))
    end

    -- Handler returns (success, result)
    return handlerSuccess, handlerResult
end

-- Auto-initialize on require
ToolHandler.init()

return ToolHandler
