--!strict
--[[
    History Handler - Undo/redo operations

    Provides Chrome DevTools Changes panel functionality:
    - Begin/end change recordings (waypoints)
    - Undo/redo operations
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local History = {}

-- Active recording state
local activeRecording: string? = nil
local activeRecordingLabel: string? = nil

-- Begin a change recording
function History.beginRecording(params: any): (boolean, any)
    local label = params.label or "DevTools Change"

    if activeRecording then
        return false, string.format("Recording already in progress: %s", activeRecordingLabel or "unknown")
    end

    local success, recordingId = pcall(function()
        return ChangeHistoryService:TryBeginRecording(label)
    end)

    if not success or not recordingId then
        return false, "Failed to begin recording"
    end

    activeRecording = recordingId
    activeRecordingLabel = label

    return true, {
        recordingId = recordingId,
        label = label
    }
end

-- End a change recording
function History.endRecording(params: any): (boolean, any)
    local commit = params.commit
    if commit == nil then
        commit = true
    end

    if not activeRecording then
        return false, "No active recording"
    end

    local recordingId = activeRecording
    local label = activeRecordingLabel

    activeRecording = nil
    activeRecordingLabel = nil

    local success, err = pcall(function()
        if commit then
            ChangeHistoryService:FinishRecording(recordingId, Enum.FinishRecordingOperation.Commit)
        else
            ChangeHistoryService:FinishRecording(recordingId, Enum.FinishRecordingOperation.Cancel)
        end
    end)

    if not success then
        return false, string.format("Failed to end recording: %s", tostring(err))
    end

    return true, {
        recordingId = recordingId,
        label = label,
        committed = commit
    }
end

-- Undo
function History.undo(params: any): (boolean, any)
    local success, err = pcall(function()
        ChangeHistoryService:Undo()
    end)

    if not success then
        return false, string.format("Undo failed: %s", tostring(err))
    end

    return true, { undone = true }
end

-- Redo
function History.redo(params: any): (boolean, any)
    local success, err = pcall(function()
        ChangeHistoryService:Redo()
    end)

    if not success then
        return false, string.format("Redo failed: %s", tostring(err))
    end

    return true, { redone = true }
end

-- Get recording state
function History.getState(params: any): (boolean, any)
    return true, {
        hasActiveRecording = activeRecording ~= nil,
        activeLabel = activeRecordingLabel
    }
end

return History
