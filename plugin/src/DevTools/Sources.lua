--!strict
--[[
    Sources Handler - Script read/write operations

    Provides Chrome DevTools Sources panel functionality:
    - List scripts in the game
    - Read script content
    - Write script content
    - Create new scripts
]]

local ScriptEditorService = game:GetService("ScriptEditorService")

local Sources = {}

-- Containers to scan for scripts
local SCAN_CONTAINERS = {
    "Workspace",
    "ReplicatedStorage",
    "ReplicatedFirst",
    "ServerStorage",
    "ServerScriptService",
    "StarterGui",
    "StarterPlayer",
    "StarterPack",
    "Lighting",
    "SoundService",
    "Chat",
    "TestService"
}

-- Helper: Get instance by path
local function getInstanceByPath(pathStr: string): Instance?
    local parts = string.split(pathStr, "/")
    local current: Instance = game

    for _, part in ipairs(parts) do
        if part == "game" then
            current = game
        else
            local child = current:FindFirstChild(part)
            if not child then
                return nil
            end
            current = child
        end
    end

    return current
end

-- Helper: Get full path of an instance
local function getInstancePath(instance: Instance): string
    local parts = {}
    local current: Instance? = instance

    while current and current ~= game do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end

    return table.concat(parts, "/")
end

-- Helper: Check if instance is a script
local function isScript(instance: Instance): boolean
    return instance:IsA("LuaSourceContainer")
end

-- List all scripts
function Sources.listScripts(params: any): (boolean, any)
    local containers = params.containers or SCAN_CONTAINERS
    local scripts = {}

    local function scanContainer(container: Instance)
        for _, descendant in ipairs(container:GetDescendants()) do
            if isScript(descendant) then
                local scriptInfo = {
                    name = descendant.Name,
                    className = descendant.ClassName,
                    path = getInstancePath(descendant),
                    lineCount = 0
                }

                -- Try to get line count
                local success, source = pcall(function()
                    return (descendant :: LuaSourceContainer).Source
                end)
                if success and source then
                    local _, lines = string.gsub(source, "\n", "\n")
                    scriptInfo.lineCount = lines + 1
                end

                table.insert(scripts, scriptInfo)
            end
        end
    end

    for _, containerName in ipairs(containers) do
        local container = game:FindFirstChild(containerName)
        if container then
            -- Also include the container itself if it's a script
            if isScript(container) then
                table.insert(scripts, {
                    name = container.Name,
                    className = container.ClassName,
                    path = containerName,
                    lineCount = 0
                })
            end
            scanContainer(container)
        end
    end

    return true, {
        scripts = scripts,
        count = #scripts
    }
end

-- Read script content
function Sources.readScript(params: any): (boolean, any)
    local pathStr = params.path
    if not pathStr then
        return false, "Missing path parameter"
    end

    local instance = getInstanceByPath(pathStr)
    if not instance then
        return false, string.format("Script not found: %s", pathStr)
    end

    if not isScript(instance) then
        return false, string.format("Not a script: %s", pathStr)
    end

    local script = instance :: LuaSourceContainer

    -- Try to get source from editor first (unsaved changes)
    local source: string? = nil
    local fromEditor = false

    local success, editorSource = pcall(function()
        local docs = ScriptEditorService:GetScriptDocuments()
        for _, doc in ipairs(docs) do
            if doc:GetScript() == script then
                return doc:GetText()
            end
        end
        return nil
    end)

    if success and editorSource then
        source = editorSource
        fromEditor = true
    else
        -- Fall back to stored source
        local sourceSuccess, storedSource = pcall(function()
            return script.Source
        end)
        if sourceSuccess then
            source = storedSource
        end
    end

    if not source then
        return false, "Failed to read script source"
    end

    local _, lineCount = string.gsub(source, "\n", "\n")

    return true, {
        path = pathStr,
        className = script.ClassName,
        content = source,
        lineCount = lineCount + 1,
        fromEditor = fromEditor
    }
end

-- Write script content
function Sources.writeScript(params: any): (boolean, any)
    local pathStr = params.path
    local content = params.content

    if not pathStr then
        return false, "Missing path parameter"
    end
    if not content or type(content) ~= "string" then
        return false, "Missing or invalid content parameter"
    end

    local instance = getInstanceByPath(pathStr)
    if not instance then
        return false, string.format("Script not found: %s", pathStr)
    end

    if not isScript(instance) then
        return false, string.format("Not a script: %s", pathStr)
    end

    local script = instance :: LuaSourceContainer

    -- Use ScriptEditorService for better handling
    local success, err = pcall(function()
        ScriptEditorService:UpdateSourceAsync(script, function()
            return content
        end)
    end)

    if not success then
        -- Fall back to direct assignment
        success, err = pcall(function()
            script.Source = content
        end)
    end

    if not success then
        return false, string.format("Failed to write script: %s", tostring(err))
    end

    local _, lineCount = string.gsub(content, "\n", "\n")

    return true, {
        path = pathStr,
        lineCount = lineCount + 1,
        bytesWritten = #content
    }
end

-- Create new script
function Sources.createScript(params: any): (boolean, any)
    local parentPath = params.parent
    local name = params.name
    local className = params.className or "ModuleScript"
    local content = params.content or ""

    if not parentPath then
        return false, "Missing parent parameter"
    end
    if not name then
        return false, "Missing name parameter"
    end

    local parent = getInstanceByPath(parentPath)
    if not parent then
        return false, string.format("Parent not found: %s", parentPath)
    end

    -- Validate class name
    if className ~= "Script" and className ~= "LocalScript" and className ~= "ModuleScript" then
        return false, string.format("Invalid script class: %s", className)
    end

    local success, result = pcall(function()
        local script = Instance.new(className) :: LuaSourceContainer
        script.Name = name
        script.Source = content
        script.Parent = parent
        return script
    end)

    if not success then
        return false, string.format("Failed to create script: %s", tostring(result))
    end

    local script = result :: LuaSourceContainer

    return true, {
        path = getInstancePath(script),
        className = className,
        name = name
    }
end

return Sources
