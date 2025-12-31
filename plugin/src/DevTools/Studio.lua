--!strict
--[[
    Studio Handler - Plugin-level Studio features

    Provides access to Studio-only APIs:
    - StudioService (active script, theme)
    - Plugin:OpenScript (jump to line)
    - ScriptEditorService (open documents)
    - DebuggerManager (breakpoints)
]]

local StudioService = game:GetService("StudioService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local DebuggerManager = game:GetService("DebuggerManager")

local Studio = {}

-- Plugin reference (set from init)
local pluginRef: Plugin? = nil

function Studio.setPlugin(plugin: Plugin)
    pluginRef = plugin
end

-- Get the currently active/focused script in the editor
function Studio.getActiveScript(params: any): (boolean, any)
    local activeScript = StudioService.ActiveScript

    if activeScript then
        return true, {
            name = activeScript.Name,
            className = activeScript.ClassName,
            path = activeScript:GetFullName(),
            lineCount = #activeScript.Source:split("\n")
        }
    else
        return true, {
            activeScript = nil,
            message = "No script is currently active in the editor"
        }
    end
end

-- Get Studio theme and settings info
function Studio.getStudioInfo(params: any): (boolean, any)
    local theme = settings().Studio.Theme

    return true, {
        theme = theme and theme.Name or "Unknown",
        studioLocaleId = StudioService.StudioLocaleId,
        -- Add more settings as needed
    }
end

-- Open a script at a specific line number
function Studio.openScript(params: any): (boolean, any)
    if not pluginRef then
        return false, "Plugin reference not set"
    end

    local scriptPath = params.path
    local lineNumber = params.line or 1

    if not scriptPath then
        return false, "Script path required"
    end

    -- Find the script by path
    local parts = string.split(scriptPath, "/")
    local current: Instance = game

    for _, part in ipairs(parts) do
        if part == "game" then
            current = game
        else
            local child = current:FindFirstChild(part)
            if not child then
                return false, "Script not found: " .. scriptPath
            end
            current = child
        end
    end

    if not current:IsA("LuaSourceContainer") then
        return false, "Path does not point to a script: " .. scriptPath
    end

    -- Open the script at the specified line
    pluginRef:OpenScript(current, lineNumber)

    return true, {
        opened = true,
        script = current:GetFullName(),
        line = lineNumber
    }
end

-- Get all currently open script documents
function Studio.getOpenDocuments(params: any): (boolean, any)
    local documents = ScriptEditorService:GetScriptDocuments()
    local result = {}

    for _, doc in ipairs(documents) do
        -- ScriptDocument has limited API, get what we can
        local script = doc:GetScript()
        if script then
            table.insert(result, {
                name = script.Name,
                className = script.ClassName,
                path = script:GetFullName(),
                isCommandBar = doc:IsCommandBar()
            })
        end
    end

    return true, {
        count = #result,
        documents = result
    }
end

-- Get the source of the currently active script
function Studio.getActiveScriptSource(params: any): (boolean, any)
    local activeScript = StudioService.ActiveScript

    if not activeScript then
        return false, "No script is currently active"
    end

    local source = activeScript.Source
    local lines = source:split("\n")

    -- Optionally limit to a range
    local startLine = params.startLine or 1
    local endLine = params.endLine or #lines

    local selectedLines = {}
    for i = startLine, math.min(endLine, #lines) do
        table.insert(selectedLines, {
            lineNumber = i,
            content = lines[i]
        })
    end

    return true, {
        script = activeScript:GetFullName(),
        totalLines = #lines,
        startLine = startLine,
        endLine = math.min(endLine, #lines),
        lines = selectedLines
    }
end

-- ============ Debugger Tools ============

-- Get all breakpoints
function Studio.getBreakpoints(params: any): (boolean, any)
    local breakpoints = DebuggerManager:GetBreakpoints()
    local result = {}

    for _, bp in ipairs(breakpoints) do
        local script = bp.Script
        table.insert(result, {
            id = bp:GetDebugId(),
            enabled = bp.Enabled,
            line = bp.Line,
            script = script and script:GetFullName() or nil,
            condition = bp.Condition,
            isLogpoint = bp.IsLogpoint,
            logMessage = bp.LogMessage
        })
    end

    return true, {
        count = #result,
        breakpoints = result
    }
end

-- Add a breakpoint to a script
function Studio.addBreakpoint(params: any): (boolean, any)
    local scriptPath = params.path
    local lineNumber = params.line
    local condition = params.condition
    local isLogpoint = params.isLogpoint or false
    local logMessage = params.logMessage

    if not scriptPath or not lineNumber then
        return false, "Script path and line number required"
    end

    -- Find the script
    local parts = string.split(scriptPath, "/")
    local current: Instance = game

    for _, part in ipairs(parts) do
        if part == "game" then
            current = game
        else
            local child = current:FindFirstChild(part)
            if not child then
                return false, "Script not found: " .. scriptPath
            end
            current = child
        end
    end

    if not current:IsA("LuaSourceContainer") then
        return false, "Path does not point to a script"
    end

    -- Add breakpoint
    local bp = DebuggerManager:AddBreakpoint(current, lineNumber)

    if condition then
        bp.Condition = condition
    end

    if isLogpoint then
        bp.IsLogpoint = true
        bp.LogMessage = logMessage or ""
    end

    return true, {
        added = true,
        id = bp:GetDebugId(),
        script = current:GetFullName(),
        line = lineNumber
    }
end

-- Remove a breakpoint
function Studio.removeBreakpoint(params: any): (boolean, any)
    local scriptPath = params.path
    local lineNumber = params.line

    if not scriptPath or not lineNumber then
        return false, "Script path and line number required"
    end

    local breakpoints = DebuggerManager:GetBreakpoints()

    for _, bp in ipairs(breakpoints) do
        local script = bp.Script
        if script and script:GetFullName() == scriptPath and bp.Line == lineNumber then
            bp:Destroy()
            return true, {
                removed = true,
                script = scriptPath,
                line = lineNumber
            }
        end
    end

    return false, "Breakpoint not found at " .. scriptPath .. ":" .. tostring(lineNumber)
end

-- Clear all breakpoints
function Studio.clearAllBreakpoints(params: any): (boolean, any)
    local breakpoints = DebuggerManager:GetBreakpoints()
    local count = #breakpoints

    for _, bp in ipairs(breakpoints) do
        bp:Destroy()
    end

    return true, {
        cleared = count,
        message = "Cleared " .. count .. " breakpoints"
    }
end

return Studio
