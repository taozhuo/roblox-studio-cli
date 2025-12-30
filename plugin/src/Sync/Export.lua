--!strict
--[[
    Script Export Module
    Enumerates scripts and exports them to local daemon
]]

local HttpService = game:GetService("HttpService")
local ScriptEditorService = game:GetService("ScriptEditorService")

local Store = require(script.Parent.Parent.State.Store)
local DaemonClient = require(script.Parent.DaemonClient)

local Export = {}

-- Containers to scan for scripts
local SCAN_CONTAINERS = {
    "Workspace",
    "ReplicatedStorage",
    "ServerScriptService",
    "ServerStorage",
    "StarterGui",
    "StarterPack",
    "StarterPlayer"
}

-- Attribute name for stable ID
local ID_ATTRIBUTE = "DetAI_Id"
local HASH_ATTRIBUTE = "DetAI_LastHash"

-- Tag names for filtering
local TAG_NO_EXPORT = "DetAI_NoExport"   -- Skip this instance during export
local TAG_NO_MODIFY = "DetAI_NoModify"   -- Allow export but prevent AI modifications
local TAG_CONTEXT_ONLY = "DetAI_ContextOnly"  -- Include in context but don't export to files

-- SHA1 hash (simplified - just use string hash for now)
local function computeHash(text: string): string
    -- Simple hash for now (in production, use proper SHA1)
    local hash = 0
    for i = 1, #text do
        hash = (hash * 31 + string.byte(text, i)) % 2147483647
    end
    return string.format("%08x", hash)
end

-- Get or create stable ID for script
local function getOrCreateId(script: LuaSourceContainer): string
    local existingId = script:GetAttribute(ID_ATTRIBUTE)
    if existingId and type(existingId) == "string" then
        return existingId
    end

    local newId = HttpService:GenerateGUID(false)
    script:SetAttribute(ID_ATTRIBUTE, newId)
    return newId
end

-- Get full path of instance
local function getFullPath(instance: Instance): string
    local parts = {}
    local current = instance

    while current and current ~= game do
        table.insert(parts, 1, current.Name)
        current = current.Parent :: Instance
    end

    return table.concat(parts, "/")
end

-- Get file path from roblox path
local function getFilePath(robloxPath: string, className: string): string
    local extension = ".lua"
    if className == "Script" then
        extension = ".server.lua"
    elseif className == "LocalScript" then
        extension = ".client.lua"
    end

    return "src/" .. robloxPath:gsub("/", "/") .. extension
end

-- Get script source (prefer open editor buffer)
local function getScriptSource(script: LuaSourceContainer): string
    -- Try to get from editor if open
    local ok, source = pcall(function()
        return ScriptEditorService:GetEditorSource(script)
    end)

    if ok and source then
        return source
    end

    -- Fallback to Source property
    local ok2, source2 = pcall(function()
        return (script :: any).Source
    end)

    if ok2 and source2 then
        return source2
    end

    return ""
end

-- Check if instance is a script type
local function isScript(instance: Instance): boolean
    return instance:IsA("LuaSourceContainer")
end

-- Check if instance or any ancestor has a tag
local function hasTagOrAncestorHasTag(instance: Instance, tagName: string): boolean
    local CollectionService = game:GetService("CollectionService")
    local current = instance
    while current and current ~= game do
        if CollectionService:HasTag(current, tagName) then
            return true
        end
        current = current.Parent :: Instance
    end
    return false
end

-- Check if instance should be exported (not tagged with NoExport)
local function shouldExport(instance: Instance): boolean
    return not hasTagOrAncestorHasTag(instance, TAG_NO_EXPORT)
end

-- Check if instance is read-only (tagged with NoModify)
local function isReadOnly(instance: Instance): boolean
    return hasTagOrAncestorHasTag(instance, TAG_NO_MODIFY)
end

-- Check if instance is context-only (not written to files, just shown to AI)
local function isContextOnly(instance: Instance): boolean
    return hasTagOrAncestorHasTag(instance, TAG_CONTEXT_ONLY)
end

-- Export scope options
export type ExportScope = "all" | "selection" | "descendants"

-- Enumerate all scripts in DataModel
function Export.enumerateScripts(): {Store.ScriptInfo}
    local scripts: {Store.ScriptInfo} = {}

    local function scan(container: Instance)
        for _, child in container:GetDescendants() do
            if isScript(child) then
                local script = child :: LuaSourceContainer
                local detaiId = getOrCreateId(script)
                local robloxPath = getFullPath(script)
                local className = script.ClassName
                local text = getScriptSource(script)
                local hash = computeHash(text)
                local filePath = getFilePath(robloxPath, className)

                table.insert(scripts, {
                    detaiId = detaiId,
                    robloxPath = robloxPath,
                    className = className,
                    filePath = filePath,
                    hash = hash,
                    text = text
                })

                -- Store hash for conflict detection
                script:SetAttribute(HASH_ATTRIBUTE, hash)
            end
        end
    end

    for _, containerName in ipairs(SCAN_CONTAINERS) do
        local container = game:FindFirstChild(containerName)
        if container then
            scan(container)
        end
    end

    return scripts
end

-- Export all scripts to daemon
function Export.exportAll(): (boolean, string)
    Store.setExporting(true)
    Store.clearScripts()

    local scripts = Export.enumerateScripts()

    if #scripts == 0 then
        Store.setExporting(false)
        return false, "No scripts found"
    end

    -- Store script info locally
    for _, scriptInfo in ipairs(scripts) do
        Store.addScript(scriptInfo)
    end

    -- Push to daemon
    local ok, result = DaemonClient.pushSnapshot({
        projectId = game.Name,
        scripts = scripts
    })

    Store.setExporting(false)

    if ok then
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "system",
            content = string.format("Exported %d scripts to local repo", #scripts),
            timestamp = os.time()
        })
        return true, string.format("Exported %d scripts", #scripts)
    else
        local errorMsg = result and result.error or "Export failed"
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "system",
            content = "Export failed: " .. errorMsg,
            timestamp = os.time()
        })
        return false, errorMsg
    end
end

-- Get script count without exporting
function Export.getScriptCount(): number
    local count = 0

    local function countScripts(container: Instance)
        for _, child in container:GetDescendants() do
            if isScript(child) and shouldExport(child) then
                count = count + 1
            end
        end
    end

    for _, containerName in ipairs(SCAN_CONTAINERS) do
        local container = game:FindFirstChild(containerName)
        if container then
            countScripts(container)
        end
    end

    return count
end

-- Preview what will be exported (without actually exporting)
export type PreviewInfo = {
    totalScripts: number,
    totalSize: number,
    byContainer: {[string]: number},
    byType: {[string]: number},
    excluded: number,
    readOnly: number,
    contextOnly: number,
    scripts: {{path: string, className: string, size: number, flags: {string}}}
}

function Export.preview(scope: ExportScope?, rootInstances: {Instance}?): PreviewInfo
    local preview: PreviewInfo = {
        totalScripts = 0,
        totalSize = 0,
        byContainer = {},
        byType = {},
        excluded = 0,
        readOnly = 0,
        contextOnly = 0,
        scripts = {}
    }

    local function processScript(script: LuaSourceContainer)
        local robloxPath = getFullPath(script)
        local className = script.ClassName
        local text = getScriptSource(script)
        local size = #text

        -- Check tags
        if not shouldExport(script) then
            preview.excluded = preview.excluded + 1
            return
        end

        local flags = {}
        if isReadOnly(script) then
            preview.readOnly = preview.readOnly + 1
            table.insert(flags, "read-only")
        end
        if isContextOnly(script) then
            preview.contextOnly = preview.contextOnly + 1
            table.insert(flags, "context-only")
        end

        preview.totalScripts = preview.totalScripts + 1
        preview.totalSize = preview.totalSize + size

        -- Count by container
        local container = robloxPath:match("^([^/]+)")
        preview.byContainer[container] = (preview.byContainer[container] or 0) + 1

        -- Count by type
        preview.byType[className] = (preview.byType[className] or 0) + 1

        table.insert(preview.scripts, {
            path = robloxPath,
            className = className,
            size = size,
            flags = flags
        })
    end

    local function scanContainer(container: Instance)
        for _, child in container:GetDescendants() do
            if isScript(child) then
                processScript(child :: LuaSourceContainer)
            end
        end
    end

    -- Determine what to scan based on scope
    if scope == "selection" and rootInstances and #rootInstances > 0 then
        -- Only scan selected instances (not their descendants)
        for _, inst in ipairs(rootInstances) do
            if isScript(inst) then
                processScript(inst :: LuaSourceContainer)
            end
        end
    elseif scope == "descendants" and rootInstances and #rootInstances > 0 then
        -- Scan selected instances and all their descendants
        for _, inst in ipairs(rootInstances) do
            if isScript(inst) then
                processScript(inst :: LuaSourceContainer)
            end
            for _, child in inst:GetDescendants() do
                if isScript(child) then
                    processScript(child :: LuaSourceContainer)
                end
            end
        end
    else
        -- Default: scan all containers
        for _, containerName in ipairs(SCAN_CONTAINERS) do
            local container = game:FindFirstChild(containerName)
            if container then
                scanContainer(container)
            end
        end
    end

    return preview
end

-- Format preview as readable string
function Export.formatPreview(preview: PreviewInfo): string
    local lines = {}

    table.insert(lines, "=== Export Preview ===")
    table.insert(lines, string.format("Scripts: %d", preview.totalScripts))
    table.insert(lines, string.format("Total size: %s", Export.formatBytes(preview.totalSize)))

    if preview.excluded > 0 then
        table.insert(lines, string.format("Excluded (DetAI_NoExport): %d", preview.excluded))
    end
    if preview.readOnly > 0 then
        table.insert(lines, string.format("Read-only (DetAI_NoModify): %d", preview.readOnly))
    end
    if preview.contextOnly > 0 then
        table.insert(lines, string.format("Context-only: %d", preview.contextOnly))
    end

    table.insert(lines, "")
    table.insert(lines, "By container:")
    for container, count in pairs(preview.byContainer) do
        table.insert(lines, string.format("  %s: %d", container, count))
    end

    table.insert(lines, "")
    table.insert(lines, "By type:")
    for className, count in pairs(preview.byType) do
        table.insert(lines, string.format("  %s: %d", className, count))
    end

    return table.concat(lines, "\n")
end

-- Format bytes to human readable
function Export.formatBytes(bytes: number): string
    if bytes < 1024 then
        return string.format("%d B", bytes)
    elseif bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    else
        return string.format("%.1f MB", bytes / (1024 * 1024))
    end
end

return Export
