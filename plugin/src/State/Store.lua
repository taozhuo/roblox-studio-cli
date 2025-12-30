--!strict
--[[
    Global State Store for DetAI Plugin
    Single source of truth for all plugin state
]]

local HttpService = game:GetService("HttpService")

export type SyncStatus = "disconnected" | "connecting" | "connected" | "syncing" | "error"

export type ScriptInfo = {
    detaiId: string,
    robloxPath: string,
    className: string,
    filePath: string?,
    hash: string?,
    text: string?
}

export type Change = {
    detaiId: string,
    filePath: string,
    hash: string,
    text: string,
    conflict: boolean?
}

export type ChatMessage = {
    id: string,
    type: "user" | "assistant" | "system" | "card",
    content: string,
    cardType: string?,
    cardData: any?,
    timestamp: number
}

export type StoreState = {
    -- Connection
    daemonUrl: string,
    daemonToken: string,
    syncStatus: SyncStatus,
    lastError: string?,

    -- Sync state
    lastRevision: number,
    scripts: {[string]: ScriptInfo},
    pendingChanges: {Change},
    conflicts: {Change},

    -- Selection context
    selection: {Instance},
    selectionContext: any?,

    -- Chat
    messages: {ChatMessage},

    -- UI state
    activeTab: string,
    isExporting: boolean,
    isImporting: boolean,
    showDiffPreview: boolean
}

local Store = {}
Store.__index = Store

-- Default state
local defaultState: StoreState = {
    daemonUrl = "http://127.0.0.1:4849",
    daemonToken = "",
    syncStatus = "disconnected",
    lastError = nil,

    lastRevision = 0,
    scripts = {},
    pendingChanges = {},
    conflicts = {},

    selection = {},
    selectionContext = nil,

    messages = {},

    activeTab = "sync",
    isExporting = false,
    isImporting = false,
    showDiffPreview = false
}

-- Listeners
local listeners: {(StoreState) -> ()} = {}
local state: StoreState = table.clone(defaultState)

function Store.getState(): StoreState
    return state
end

function Store.setState(partial: {[string]: any})
    for key, value in pairs(partial) do
        (state :: any)[key] = value
    end
    Store._notify()
end

function Store.subscribe(listener: (StoreState) -> ()): () -> ()
    table.insert(listeners, listener)
    return function()
        local idx = table.find(listeners, listener)
        if idx then
            table.remove(listeners, idx)
        end
    end
end

function Store._notify()
    for _, listener in ipairs(listeners) do
        task.spawn(listener, state)
    end
end

-- Actions
function Store.setDaemonConfig(url: string, token: string)
    Store.setState({
        daemonUrl = url,
        daemonToken = token
    })
end

function Store.setSyncStatus(status: SyncStatus, error: string?)
    Store.setState({
        syncStatus = status,
        lastError = error
    })
end

function Store.setSelection(selection: {Instance})
    Store.setState({ selection = selection })
end

function Store.addScript(info: ScriptInfo)
    local scripts = table.clone(state.scripts)
    scripts[info.detaiId] = info
    Store.setState({ scripts = scripts })
end

function Store.clearScripts()
    Store.setState({ scripts = {} })
end

function Store.setPendingChanges(changes: {Change})
    Store.setState({
        pendingChanges = changes,
        showDiffPreview = #changes > 0
    })
end

function Store.setConflicts(conflicts: {Change})
    Store.setState({ conflicts = conflicts })
end

function Store.setRevision(rev: number)
    Store.setState({ lastRevision = rev })
end

function Store.addMessage(msg: ChatMessage)
    local messages = table.clone(state.messages)
    if not msg.id then
        msg.id = HttpService:GenerateGUID(false)
    end
    if not msg.timestamp then
        msg.timestamp = os.time()
    end
    table.insert(messages, msg)
    Store.setState({ messages = messages })
end

function Store.clearMessages()
    Store.setState({ messages = {} })
end

function Store.setActiveTab(tab: string)
    Store.setState({ activeTab = tab })
end

function Store.setExporting(exporting: boolean)
    Store.setState({ isExporting = exporting })
end

function Store.setImporting(importing: boolean)
    Store.setState({ isImporting = importing })
end

-- Reset to default
function Store.reset()
    state = table.clone(defaultState)
    Store._notify()
end

return Store
