--!strict
--[[
    Script Import Module
    Pulls changes from daemon and applies them to Studio
]]

local HttpService = game:GetService("HttpService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Store = require(script.Parent.Parent.State.Store)
local DaemonClient = require(script.Parent.DaemonClient)

local Import = {}

-- Attribute names
local ID_ATTRIBUTE = "DetAI_Id"
local HASH_ATTRIBUTE = "DetAI_LastHash"

-- Containers to search for scripts
local SCAN_CONTAINERS = {
    "Workspace",
    "ReplicatedStorage",
    "ServerScriptService",
    "ServerStorage",
    "StarterGui",
    "StarterPack",
    "StarterPlayer"
}

-- Compute hash for conflict detection
local function computeHash(text: string): string
    local hash = 0
    for i = 1, #text do
        hash = (hash * 31 + string.byte(text, i)) % 2147483647
    end
    return string.format("%08x", hash)
end

-- Find script by DetAI_Id
local function findScriptById(detaiId: string): LuaSourceContainer?
    local function search(container: Instance): LuaSourceContainer?
        for _, child in container:GetDescendants() do
            if child:IsA("LuaSourceContainer") then
                local id = child:GetAttribute(ID_ATTRIBUTE)
                if id == detaiId then
                    return child :: LuaSourceContainer
                end
            end
        end
        return nil
    end

    for _, containerName in ipairs(SCAN_CONTAINERS) do
        local container = game:FindFirstChild(containerName)
        if container then
            local found = search(container)
            if found then
                return found
            end
        end
    end

    return nil
end

-- Check if script has local changes since last sync
local function hasLocalChanges(script: LuaSourceContainer): boolean
    local lastHash = script:GetAttribute(HASH_ATTRIBUTE)
    if not lastHash then
        return false
    end

    local ok, currentSource = pcall(function()
        return ScriptEditorService:GetEditorSource(script)
    end)

    if not ok then
        pcall(function()
            currentSource = (script :: any).Source
        end)
    end

    if currentSource then
        local currentHash = computeHash(currentSource)
        return currentHash ~= lastHash
    end

    return false
end

-- Pull changes from daemon
function Import.pullChanges(): (boolean, string)
    Store.setImporting(true)

    local state = Store.getState()
    local ok, result = DaemonClient.pullChanges(state.lastRevision)

    if not ok or not result then
        Store.setImporting(false)
        return false, "Failed to pull changes"
    end

    if #result.changes == 0 then
        Store.setImporting(false)
        Store.setRevision(result.revision)
        return true, "No changes"
    end

    -- Process changes and detect conflicts
    local changes: {Store.Change} = {}
    local conflicts: {Store.Change} = {}

    for _, change in ipairs(result.changes) do
        local script = findScriptById(change.detaiId)
        local hasConflict = false

        if script then
            -- Check for conflict
            local lastHash = script:GetAttribute(HASH_ATTRIBUTE)
            if lastHash and hasLocalChanges(script) then
                -- Both Studio and local changed since last sync
                hasConflict = true
            end
        end

        local changeEntry: Store.Change = {
            detaiId = change.detaiId,
            filePath = change.filePath,
            hash = change.hash,
            text = change.text,
            conflict = hasConflict
        }

        if hasConflict then
            table.insert(conflicts, changeEntry)
        else
            table.insert(changes, changeEntry)
        end
    end

    Store.setPendingChanges(changes)
    Store.setConflicts(conflicts)
    Store.setRevision(result.revision)
    Store.setImporting(false)

    local msg = string.format("Pulled %d changes", #changes)
    if #conflicts > 0 then
        msg = msg .. string.format(", %d conflicts", #conflicts)
    end

    Store.addMessage({
        id = HttpService:GenerateGUID(false),
        type = "system",
        content = msg,
        cardType = if #changes > 0 then "DiffCard" else nil,
        timestamp = os.time()
    })

    return true, msg
end

-- Apply changes to Studio (grouped undo)
function Import.applyChanges(changes: {Store.Change}?): (boolean, string)
    local toApply = changes or Store.getState().pendingChanges

    if #toApply == 0 then
        return true, "No changes to apply"
    end

    -- Start undo recording
    local recordId = ChangeHistoryService:TryBeginRecording("DetAI: Apply " .. #toApply .. " changes")

    local applied = 0
    local failed = 0

    for _, change in ipairs(toApply) do
        local script = findScriptById(change.detaiId)

        if script then
            local ok, err = pcall(function()
                ScriptEditorService:UpdateSourceAsync(script, function(_old)
                    return change.text
                end)
            end)

            if ok then
                -- Update hash
                script:SetAttribute(HASH_ATTRIBUTE, change.hash)
                applied = applied + 1
            else
                warn("[DetAI] Failed to apply change to", change.filePath, ":", err)
                failed = failed + 1
            end
        else
            warn("[DetAI] Script not found:", change.detaiId)
            failed = failed + 1
        end
    end

    -- Finish undo recording
    if recordId then
        if applied > 0 then
            ChangeHistoryService:FinishRecording(recordId, Enum.FinishRecordingOperation.Commit)
        else
            ChangeHistoryService:FinishRecording(recordId, Enum.FinishRecordingOperation.Cancel)
        end
    end

    -- Clear pending changes
    Store.setPendingChanges({})

    local msg = string.format("Applied %d changes", applied)
    if failed > 0 then
        msg = msg .. string.format(", %d failed", failed)
    end

    Store.addMessage({
        id = HttpService:GenerateGUID(false),
        type = "system",
        content = msg,
        timestamp = os.time()
    })

    return failed == 0, msg
end

-- Resolve conflict by choosing local or studio version
function Import.resolveConflict(detaiId: string, useLocal: boolean): boolean
    local state = Store.getState()
    local conflicts = state.conflicts

    local conflictIndex = nil
    for i, conflict in ipairs(conflicts) do
        if conflict.detaiId == detaiId then
            conflictIndex = i
            break
        end
    end

    if not conflictIndex then
        return false
    end

    local conflict = conflicts[conflictIndex]

    if useLocal then
        -- Apply the local (daemon) version
        Import.applyChanges({conflict})
    else
        -- Keep Studio version - just update the hash
        local script = findScriptById(detaiId)
        if script then
            local source = nil
            pcall(function()
                source = ScriptEditorService:GetEditorSource(script)
            end)
            if source then
                script:SetAttribute(HASH_ATTRIBUTE, computeHash(source))
            end
        end
    end

    -- Remove from conflicts
    local newConflicts = {}
    for i, c in ipairs(conflicts) do
        if i ~= conflictIndex then
            table.insert(newConflicts, c)
        end
    end
    Store.setConflicts(newConflicts)

    return true
end

-- Resolve all conflicts with same choice
function Import.resolveAllConflicts(useLocal: boolean)
    local state = Store.getState()

    if useLocal then
        Import.applyChanges(state.conflicts)
    else
        -- Keep all studio versions
        for _, conflict in ipairs(state.conflicts) do
            local script = findScriptById(conflict.detaiId)
            if script then
                local source = nil
                pcall(function()
                    source = ScriptEditorService:GetEditorSource(script)
                end)
                if source then
                    script:SetAttribute(HASH_ATTRIBUTE, computeHash(source))
                end
            end
        end
    end

    Store.setConflicts({})
end

return Import
