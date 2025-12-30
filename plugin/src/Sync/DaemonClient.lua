--!strict
--[[
    HTTP + WebSocket Client for Local Daemon Communication
    Handles all sync and agent API calls to the local daemon
    Uses WebSocket for real-time updates (logs, progress, repo changes)
]]

local HttpService = game:GetService("HttpService")
local Store = require(script.Parent.Parent.State.Store)

local DaemonClient = {}

-- WebSocket client state (typed as any since WebStreamClient may not exist)
local wsClient: any = nil
local wsConnected: boolean = false
local wsEventListeners: {[string]: {(data: any) -> ()}} = {}
local wsSupported: boolean? = nil -- nil = unknown, true/false = tested

-- JSON helpers
local function jsonEncode(data: any): string?
    local ok, result = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    return ok and result or nil
end

local function jsonDecode(str: string): any?
    local ok, result = pcall(function()
        return HttpService:JSONDecode(str)
    end)
    return ok and result or nil
end

-- Make HTTP request to daemon
function DaemonClient.request(method: string, endpoint: string, body: any?): (boolean, any)
    local state = Store.getState()
    local url = state.daemonUrl .. endpoint

    local headers = {
        ["Content-Type"] = "application/json"
    }

    if state.daemonToken and state.daemonToken ~= "" then
        headers["Authorization"] = "Bearer " .. state.daemonToken
    end

    local requestBody = nil
    if body then
        requestBody = jsonEncode(body)
    end

    local ok, response = pcall(function()
        return HttpService:RequestAsync({
            Url = url,
            Method = method,
            Headers = headers,
            Body = requestBody
        })
    end)

    if not ok then
        return false, { error = tostring(response) }
    end

    if response.Success then
        local data = jsonDecode(response.Body)
        return true, data
    else
        local errorData = jsonDecode(response.Body)
        return false, errorData or { error = "HTTP " .. response.StatusCode }
    end
end

-- ============ Health & Connection ============

function DaemonClient.health(): (boolean, any)
    return DaemonClient.request("GET", "/health", nil)
end

function DaemonClient.connect(): boolean
    Store.setSyncStatus("connecting")

    local ok, result = DaemonClient.health()

    if ok and result and result.ok then
        Store.setSyncStatus("connected")
        local version = result.version or "unknown"
        local agentEnabled = result.agentSdkEnabled and " (Agent SDK enabled)" or ""
        print("[DetAI] Connected to daemon:", version .. agentEnabled)
        return true
    else
        Store.setSyncStatus("error", "Failed to connect to daemon")
        warn("[DetAI] Daemon connection failed:", result and result.error or "unknown error")
        return false
    end
end

function DaemonClient.disconnect()
    Store.setSyncStatus("disconnected")
end

-- ============ Sync Endpoints ============

export type PushSnapshotPayload = {
    projectId: string?,
    scripts: {{
        detaiId: string,
        robloxPath: string,
        className: string,
        filePath: string?,
        hash: string,
        text: string
    }}
}

function DaemonClient.pushSnapshot(payload: PushSnapshotPayload): (boolean, any)
    Store.setSyncStatus("syncing")
    local ok, result = DaemonClient.request("POST", "/sync/pushSnapshot", payload)

    if ok then
        Store.setSyncStatus("connected")
        if result and result.revision then
            Store.setRevision(result.revision)
        end
    else
        Store.setSyncStatus("error", result and result.error or "Push failed")
    end

    return ok, result
end

export type PullChangesResult = {
    revision: number,
    changes: {{
        detaiId: string,
        filePath: string,
        hash: string,
        text: string
    }}
}

function DaemonClient.pullChanges(sinceRevision: number): (boolean, PullChangesResult?)
    local ok, result = DaemonClient.request("POST", "/sync/pullChanges", {
        sinceRevision = sinceRevision
    })

    if ok and result then
        return true, result :: PullChangesResult
    end

    return false, nil
end

-- ============ Agent Endpoints ============

export type AgentRunPayload = {
    task: string,
    scope: {
        includePaths: {string}?,
        focusFiles: {string}?
    }?,
    context: {
        selection: {string}?,
        notes: string?
    }?,
    repoRoot: string?
}

export type AgentRunResult = {
    ok: boolean,
    runId: string?,
    startedAt: number?,
    error: string?
}

function DaemonClient.agentRun(payload: AgentRunPayload): (boolean, AgentRunResult?)
    local ok, result = DaemonClient.request("POST", "/agent/run", payload)
    return ok, result :: AgentRunResult?
end

export type AgentStatusResult = {
    runId: string,
    state: string, -- "running" | "done" | "error" | "cancelled"
    startedAt: number,
    filesChanged: {string}?,
    summary: string?,
    error: string?
}

function DaemonClient.agentStatus(runId: string): (boolean, AgentStatusResult?)
    local ok, result = DaemonClient.request("GET", "/agent/status?runId=" .. runId, nil)
    return ok, result :: AgentStatusResult?
end

export type AgentLogsResult = {
    runId: string,
    lines: {{timestamp: number, message: string}},
    nextCursor: string,
    state: string
}

function DaemonClient.agentLogs(runId: string, cursor: string?): (boolean, AgentLogsResult?)
    local endpoint = "/agent/logs?runId=" .. runId
    if cursor then
        endpoint = endpoint .. "&cursor=" .. cursor
    end
    local ok, result = DaemonClient.request("GET", endpoint, nil)
    return ok, result :: AgentLogsResult?
end

function DaemonClient.agentCancel(runId: string): (boolean, any)
    return DaemonClient.request("POST", "/agent/cancel", { runId = runId })
end

-- ============ Legacy Exec Endpoint ============

export type RunCommandPayload = {
    cwd: string?,
    cmd: string,
    args: {string}?
}

export type RunCommandResult = {
    ok: boolean,
    runId: string?,
    error: string?
}

function DaemonClient.runCommand(payload: RunCommandPayload): (boolean, RunCommandResult?)
    local ok, result = DaemonClient.request("POST", "/exec/run", payload)
    return ok, result :: RunCommandResult?
end

function DaemonClient.getLogs(runId: string): (boolean, any)
    return DaemonClient.request("GET", "/exec/logs?runId=" .. runId, nil)
end

-- ============ WebSocket Client ============

-- Event types from daemon:
-- run.log: { runId, timestamp, message }
-- run.progress: { runId, state, filesChanged }
-- run.done: { runId, success, summary, filesChanged, costUsd }
-- repo.changed: { revision, files }

function DaemonClient.onEvent(eventType: string, callback: (data: any) -> ()): () -> ()
    if not wsEventListeners[eventType] then
        wsEventListeners[eventType] = {}
    end
    table.insert(wsEventListeners[eventType], callback)

    -- Return unsubscribe function
    return function()
        local listeners = wsEventListeners[eventType]
        if listeners then
            local idx = table.find(listeners, callback)
            if idx then
                table.remove(listeners, idx)
            end
        end
    end
end

local function dispatchEvent(eventType: string, data: any)
    local listeners = wsEventListeners[eventType]
    if listeners then
        for _, callback in ipairs(listeners) do
            task.spawn(callback, data)
        end
    end
end

local function handleWsMessage(message: string)
    local data = jsonDecode(message)
    if not data or not data.type then
        return
    end

    local eventType = data.type

    if eventType == "welcome" then
        wsConnected = true
        print("[DetAI] WebSocket connected, daemon version:", data.version)
        Store.setSyncStatus("connected")
        if data.revision then
            Store.setRevision(data.revision)
        end
    elseif eventType == "error" then
        warn("[DetAI] WebSocket error:", data.error)
        wsConnected = false
    else
        -- Dispatch to listeners: run.log, run.progress, run.done, repo.changed
        dispatchEvent(eventType, data)
    end
end

function DaemonClient.connectWebSocket(): boolean
    if wsClient and wsConnected then
        return true -- Already connected
    end

    -- Check if WebSocket API is supported (only check once)
    if wsSupported == false then
        return false
    end

    if wsSupported == nil then
        -- Test if the API exists
        local testOk = pcall(function()
            local _ = Enum.WebStreamClientType.WebSocket
        end)
        if not testOk then
            warn("[DetAI] WebSocket not supported in this Studio version - using HTTP polling")
            wsSupported = false
            return false
        end
        wsSupported = true
    end

    local state = Store.getState()
    -- Convert HTTP URL to WS URL
    local wsUrl = state.daemonUrl:gsub("^http://", "ws://"):gsub("^https://", "wss://") .. "/ws"

    print("[DetAI] Connecting WebSocket to:", wsUrl)

    local ok, client = pcall(function()
        return HttpService:CreateWebStreamClient(Enum.WebStreamClientType.WebSocket, {
            Url = wsUrl
        })
    end)

    if not ok or not client then
        warn("[DetAI] Failed to create WebSocket client:", tostring(client))
        wsSupported = false -- Mark as not supported
        return false
    end

    wsClient = client

    -- Set up event handlers
    local msgOk = pcall(function()
        client.MessageReceived:Connect(function(message: string)
            handleWsMessage(message)
        end)
    end)

    local discOk = pcall(function()
        client.Disconnected:Connect(function(reason: string)
            print("[DetAI] WebSocket disconnected:", reason)
            wsConnected = false
            wsClient = nil
        end)
    end)

    if not msgOk or not discOk then
        warn("[DetAI] Failed to set up WebSocket handlers")
        wsClient = nil
        wsSupported = false
        return false
    end

    -- Connect
    local connectOk, connectErr = pcall(function()
        client:Connect()
    end)

    if not connectOk then
        warn("[DetAI] WebSocket connect failed:", tostring(connectErr))
        wsClient = nil
        return false
    end

    -- Send auth message
    local token = state.daemonToken
    if token and token ~= "" then
        local authOk = pcall(function()
            client:Send(jsonEncode({ type = "auth", token = token }) or "")
        end)
        if not authOk then
            warn("[DetAI] Failed to send auth message")
        end
    else
        print("[DetAI] No daemon token configured - use /token command to set it")
    end

    return true
end

function DaemonClient.disconnectWebSocket()
    if wsClient then
        pcall(function()
            wsClient:Close()
        end)
        wsClient = nil
    end
    wsConnected = false
end

function DaemonClient.isWebSocketConnected(): boolean
    return wsConnected
end

-- Combined connect: HTTP health check + WebSocket
function DaemonClient.connectFull(): boolean
    -- First do HTTP health check
    local httpOk = DaemonClient.connect()
    if not httpOk then
        return false
    end

    -- Then connect WebSocket for live updates
    local wsOk = DaemonClient.connectWebSocket()
    if not wsOk then
        warn("[DetAI] WebSocket failed but HTTP is working - falling back to polling")
    end

    return true
end

return DaemonClient
