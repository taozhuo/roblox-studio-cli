--!strict
--[[
    Global State Store for Bakable Plugin
    Single source of truth for all plugin state
]]

local HttpService = game:GetService("HttpService")

export type SyncStatus = "disconnected" | "connecting" | "connected" | "error"

export type ScriptInfo = {
    bakableId: string,
    robloxPath: string,
    className: string,
    filePath: string?,
    hash: string?,
    text: string?
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
    connectionStatus: SyncStatus,
    lastError: string?,
    revision: number,

    -- Scripts
    scripts: {[string]: ScriptInfo},

    -- Selection context
    selection: {Instance},
    selectionContext: any?,

    -- Chat
    messages: {ChatMessage},
}

local Store = {}
Store.__index = Store

-- Default state
local defaultState: StoreState = {
    daemonUrl = "http://127.0.0.1:4849",
    daemonToken = "",
    connectionStatus = "disconnected",
    lastError = nil,
    revision = 0,

    scripts = {},

    selection = {},
    selectionContext = nil,

    messages = {},
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

function Store.setConnectionStatus(status: SyncStatus, error: string?)
    Store.setState({
        connectionStatus = status,
        lastError = error
    })
end

function Store.setRevision(revision: number)
    Store.setState({ revision = revision })
end

function Store.setSelection(selection: {Instance})
    Store.setState({ selection = selection })
end

function Store.addScript(info: ScriptInfo)
    local scripts = table.clone(state.scripts)
    scripts[info.bakableId] = info
    Store.setState({ scripts = scripts })
end

function Store.clearScripts()
    Store.setState({ scripts = {} })
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

-- Reset to default
function Store.reset()
    state = table.clone(defaultState)
    Store._notify()
end

return Store
