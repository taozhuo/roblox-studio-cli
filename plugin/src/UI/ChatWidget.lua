--!strict
--[[
    Chat Widget UI
    Slack-like chat interface for AI interactions with Claude Agent SDK
]]

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local LogService = game:GetService("LogService")
local ReflectionService = game:GetService("ReflectionService")

local Store = require(script.Parent.Parent.State.Store)
local Theme = require(script.Parent.Theme)
local DaemonClient = require(script.Parent.Parent.Sync.DaemonClient)
local Export = require(script.Parent.Parent.Sync.Export)
local Import = require(script.Parent.Parent.Sync.Import)

local ChatWidget = {}
ChatWidget.__index = ChatWidget

-- Active agent run tracking
local activeRunId: string? = nil
local pollConnection: thread? = nil -- Fallback polling if WebSocket unavailable
local wsUnsubscribers: {() -> ()} = {}

-- DevTools state
local isDrawingPath: boolean = false

function ChatWidget.new(plugin: Plugin): ChatWidget
    local self = setmetatable({}, ChatWidget)

    self.plugin = plugin
    self.widget = nil
    self.elements = {}
    self.connections = {}

    return self
end

function ChatWidget:create()
    -- Create dock widget
    local widgetInfo = DockWidgetPluginGuiInfo.new(
        Enum.InitialDockState.Right,
        true,
        false,
        350,
        500,
        250,
        300
    )

    self.widget = self.plugin:CreateDockWidgetPluginGui("DetAI_Chat", widgetInfo)
    self.widget.Title = "DetAI Chat"
    self.widget.Name = "DetAI_Chat"

    -- Main container
    local container = Instance.new("Frame")
    container.Name = "Container"
    container.BackgroundColor3 = Theme.Colors.Background
    container.BorderSizePixel = 0
    container.Size = UDim2.new(1, 0, 1, 0)
    container.Parent = self.widget

    -- Header
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.BackgroundColor3 = Theme.Colors.BackgroundDark
    header.BorderSizePixel = 0
    header.Size = UDim2.new(1, 0, 0, Theme.Sizes.HeaderHeight)
    header.Parent = container

    Theme.createLabel({
        parent = header,
        text = "DetAI",
        position = UDim2.new(0, Theme.Sizes.PaddingNormal, 0, 0),
        size = UDim2.new(0, 50, 1, 0),
        font = Theme.Fonts.Bold,
        textSize = Theme.Sizes.TextLarge
    })

    -- Status indicator (right side of header)
    local statusLabel = Theme.createLabel({
        parent = header,
        text = "",
        position = UDim2.new(0, 60, 0, 0),
        size = UDim2.new(1, -70, 1, 0),
        textSize = Theme.Sizes.TextSmall,
        textColor = Theme.Colors.TextDim
    })
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    self.elements.statusLabel = statusLabel

    -- Messages area
    local messagesFrame = Instance.new("Frame")
    messagesFrame.Name = "MessagesFrame"
    messagesFrame.BackgroundTransparency = 1
    messagesFrame.Size = UDim2.new(1, 0, 1, -Theme.Sizes.HeaderHeight - 110) -- Increased for DevTools row
    messagesFrame.Position = UDim2.new(0, 0, 0, Theme.Sizes.HeaderHeight)
    messagesFrame.Parent = container

    local messagesScroll = Theme.createScrollFrame({
        parent = messagesFrame,
        size = UDim2.new(1, 0, 1, 0)
    })
    self.elements.messagesScroll = messagesScroll

    -- Composer area (expanded for DevTools row)
    local composerFrame = Instance.new("Frame")
    composerFrame.Name = "ComposerFrame"
    composerFrame.BackgroundColor3 = Theme.Colors.BackgroundDark
    composerFrame.BorderSizePixel = 0
    composerFrame.Size = UDim2.new(1, 0, 0, 110)
    composerFrame.Position = UDim2.new(0, 0, 1, -110)
    composerFrame.Parent = container

    local composerPadding = Instance.new("UIPadding")
    composerPadding.PaddingTop = UDim.new(0, Theme.Sizes.PaddingNormal)
    composerPadding.PaddingBottom = UDim.new(0, Theme.Sizes.PaddingNormal)
    composerPadding.PaddingLeft = UDim.new(0, Theme.Sizes.PaddingNormal)
    composerPadding.PaddingRight = UDim.new(0, Theme.Sizes.PaddingNormal)
    composerPadding.Parent = composerFrame

    -- Input box
    local inputBox = Instance.new("TextBox")
    inputBox.Name = "InputBox"
    inputBox.Text = ""
    inputBox.PlaceholderText = "Type a task for Claude or /command..."
    inputBox.Font = Theme.Fonts.Default
    inputBox.TextSize = Theme.Sizes.TextNormal
    inputBox.TextColor3 = Theme.Colors.Text
    inputBox.PlaceholderColor3 = Theme.Colors.TextDim
    inputBox.BackgroundColor3 = Theme.Colors.BackgroundLight
    inputBox.BorderSizePixel = 0
    inputBox.Size = UDim2.new(1, 0, 0, 36)
    inputBox.Position = UDim2.new(0, 0, 0, 0)
    inputBox.TextXAlignment = Enum.TextXAlignment.Left
    inputBox.TextYAlignment = Enum.TextYAlignment.Center
    inputBox.ClearTextOnFocus = false
    inputBox.MultiLine = false  -- Single line so Enter submits
    inputBox.TextWrapped = false
    inputBox.Parent = composerFrame
    self.elements.inputBox = inputBox

    local inputCorner = Instance.new("UICorner")
    inputCorner.CornerRadius = UDim.new(0, Theme.Sizes.BorderRadius)
    inputCorner.Parent = inputBox

    local inputPadding = Instance.new("UIPadding")
    inputPadding.PaddingTop = UDim.new(0, 8)
    inputPadding.PaddingBottom = UDim.new(0, 8)
    inputPadding.PaddingLeft = UDim.new(0, 8)
    inputPadding.PaddingRight = UDim.new(0, 8)
    inputPadding.Parent = inputBox

    -- Quick actions
    local actionsFrame = Instance.new("Frame")
    actionsFrame.Name = "ActionsFrame"
    actionsFrame.BackgroundTransparency = 1
    actionsFrame.Size = UDim2.new(1, 0, 0, 24)
    actionsFrame.Position = UDim2.new(0, 0, 0, 40)
    actionsFrame.Parent = composerFrame

    local actionsLayout = Instance.new("UIListLayout")
    actionsLayout.FillDirection = Enum.FillDirection.Horizontal
    actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    actionsLayout.Padding = UDim.new(0, 4)
    actionsLayout.Parent = actionsFrame

    -- Quick action chips
    self:createChip(actionsFrame, "/export", 1, function()
        self:handleCommand("/export")
    end)

    self:createChip(actionsFrame, "/pull", 2, function()
        self:handleCommand("/pull")
    end)

    self:createChip(actionsFrame, "/apply", 3, function()
        self:handleCommand("/apply")
    end)

    self:createChip(actionsFrame, "/cancel", 4, function()
        self:handleCommand("/cancel")
    end)

    -- DevTools row (positioned below quick actions)
    local devToolsFrame = Instance.new("Frame")
    devToolsFrame.Name = "DevToolsFrame"
    devToolsFrame.Size = UDim2.new(1, 0, 0, 24)
    devToolsFrame.Position = UDim2.new(0, 0, 0, 66) -- Below actionsFrame (40 + 24 + 2 padding)
    devToolsFrame.BackgroundTransparency = 1
    devToolsFrame.Parent = composerFrame

    local devToolsLayout = Instance.new("UIListLayout")
    devToolsLayout.FillDirection = Enum.FillDirection.Horizontal
    devToolsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    devToolsLayout.Padding = UDim.new(0, 4)
    devToolsLayout.Parent = devToolsFrame

    -- Mark Here button
    self:createChip(devToolsFrame, "Mark Here", 1, function()
        self:capturePointer()
    end, Color3.fromRGB(80, 120, 200))

    -- Draw Path button (toggles)
    self.pathButton = self:createChip(devToolsFrame, "Draw Path", 2, function()
        self:togglePathDrawing()
    end, Color3.fromRGB(80, 160, 80))

    -- Clear Path button
    self:createChip(devToolsFrame, "Clear", 3, function()
        self:clearPath()
    end, Color3.fromRGB(160, 80, 80))

    -- Handle enter key
    inputBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            self:handleInput()
        end
    end)

    -- Subscribe to store
    self.connections.storeSubscription = Store.subscribe(function(state)
        self:updateMessages(state.messages)
    end)

    -- Initial update
    self:updateMessages(Store.getState().messages)

    -- Add welcome message
    Store.addMessage({
        id = HttpService:GenerateGUID(false),
        type = "system",
        content = "Welcome to DetAI! Type a task for Claude or use commands:\n/export - Export scripts\n/pull - Pull changes\n/apply - Apply changes\n/cancel - Cancel running task",
        timestamp = os.time()
    })

    -- Set up WebSocket event listeners for real-time updates (safe - won't crash if WS unavailable)
    pcall(function()
        self:setupWebSocketListeners()
    end)

    -- Stream LogService output to daemon
    local logConnection = LogService.MessageOut:Connect(function(message, messageType)
        -- Only send relevant logs (skip internal Roblox stuff)
        if message:match("^%[DetAI%]") or message:match("^%[Studio%]") then
            return -- Already sent via HTTP
        end

        -- Send print/warn/error to daemon
        local level = "print"
        if messageType == Enum.MessageType.MessageWarning then
            level = "warn"
        elseif messageType == Enum.MessageType.MessageError then
            level = "error"
        end

        pcall(function()
            HttpService:PostAsync(
                "http://127.0.0.1:4849/log",
                HttpService:JSONEncode({ level = "studio:" .. level, message = message }),
                Enum.HttpContentType.ApplicationJson
            )
        end)
    end)
    table.insert(self.connections, logConnection)
end

-- Set up WebSocket event listeners for live streaming
function ChatWidget:setupWebSocketListeners()
    -- Clean up any existing subscriptions
    for _, unsub in ipairs(wsUnsubscribers) do
        pcall(unsub)
    end
    wsUnsubscribers = {}

    -- Listen for agent log messages - show Claude responses and errors
    table.insert(wsUnsubscribers, DaemonClient.onEvent("run.log", function(data)
        if data.runId ~= activeRunId then return end
        local message = data.message or ""

        -- Show Claude's intermediate text (thinking before tool calls)
        if message:match("^Claude:") then
            local claudeText = message:gsub("^Claude: ", "")
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "assistant",
                content = claudeText,
                timestamp = data.timestamp and math.floor(data.timestamp / 1000) or os.time()
            })
        -- Show errors (but not Completed which is handled in run.done)
        elseif message:match("^Error:") and not message:match("^Completed:") then
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "system",
                content = message,
                timestamp = data.timestamp and math.floor(data.timestamp / 1000) or os.time()
            })
        end
    end))

    -- Listen for agent progress updates
    table.insert(wsUnsubscribers, DaemonClient.onEvent("run.progress", function(data)
        if data.runId ~= activeRunId then return end

        local filesChanged = data.filesChanged or {}
        if #filesChanged > 0 then
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "system",
                content = "Files modified: " .. table.concat(filesChanged, ", "),
                timestamp = os.time()
            })
        end
    end))

    -- Listen for agent completion
    table.insert(wsUnsubscribers, DaemonClient.onEvent("run.done", function(data)
        if data.runId ~= activeRunId then return end

        activeRunId = nil
        self:setStatus("")  -- Clear status

        local summary = data.summary or "Task completed"
        local success = data.success

        if success then
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "assistant",
                content = summary,
                cardType = "ResultCard",
                timestamp = os.time()
            })
        else
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "system",
                content = "Task failed: " .. summary,
                timestamp = os.time()
            })
        end
    end))

    -- Listen for repo changes (file watcher notifications)
    table.insert(wsUnsubscribers, DaemonClient.onEvent("repo.changed", function(data)
        local revision = data.revision
        local files = data.files or {}

        if revision then
            Store.setRevision(revision)
        end

        if #files > 0 then
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "system",
                content = "Repo updated: " .. #files .. " file(s) changed. Use /pull to sync.",
                timestamp = os.time()
            })
        end
    end))

    -- Helper to send logs to daemon
    local function sendLog(level, message)
        pcall(function()
            HttpService:PostAsync(
                "http://127.0.0.1:4849/log",
                HttpService:JSONEncode({ level = level, message = message }),
                Enum.HttpContentType.ApplicationJson
            )
        end)
    end

    sendLog("info", "ChatWidget WebSocket listeners setup")

    -- Helper to post execution results to daemon (so Claude can see them)
    local function postExecResult(success, result, error, code)
        pcall(function()
            HttpService:PostAsync(
                "http://127.0.0.1:4849/exec/result",
                HttpService:JSONEncode({
                    success = success,
                    result = result,
                    error = error,
                    code = code
                }),
                Enum.HttpContentType.ApplicationJson
            )
        end)
    end

    -- Start polling for exec commands (only if WS not working)
    task.spawn(function()
        task.wait(2) -- Give WS time to connect
        if DaemonClient.isWebSocketConnected() then
            sendLog("info", "WS connected, skipping HTTP polling")
            return
        end
        sendLog("info", "WS not connected, starting HTTP polling for exec")
        while true do
            task.wait(0.5)
            -- Stop polling if WS becomes connected
            if DaemonClient.isWebSocketConnected() then
                sendLog("info", "WS now connected, stopping polling")
                break
            end
            local ok, result = DaemonClient.request("GET", "/exec/pending", nil)
            if ok and result and result.code and result.code ~= "" then
                sendLog("info", "Got exec via polling")
                local code = result.code
                self:setStatus("Executing", Theme.Colors.Primary, true)

                local execOk, execResult = pcall(function()
                    local fn, err = loadstring(code)
                    if not fn then error("Syntax error: " .. tostring(err)) end
                    return fn()
                end)

                if execOk then
                    sendLog("info", "Polling exec success")
                    postExecResult(true, tostring(execResult), nil, code)
                    self:setStatus("Done", Theme.Colors.Success)
                    task.delay(1, function() self:setStatus("") end)
                else
                    sendLog("error", "Polling exec failed: " .. tostring(execResult))
                    postExecResult(false, nil, tostring(execResult), code)
                    self:setStatus("Error", Theme.Colors.Error)
                end
            end
        end
    end)

    -- Listen for studio.exec commands - execute Lua code directly
    table.insert(wsUnsubscribers, DaemonClient.onEvent("studio.exec", function(data)
        sendLog("info", "Received studio.exec event")

        local code = data.code
        if not code or code == "" then
            sendLog("warn", "No code in studio.exec event")
            return
        end

        sendLog("info", "Code to execute: " .. code:sub(1, 100))
        self:setStatus("Executing", Theme.Colors.Primary, true)

        -- Capture LogService errors during execution (catches async/deferred errors)
        local execErrors: {string} = {}
        local errorConnection = LogService.MessageOut:Connect(function(message, messageType)
            if messageType == Enum.MessageType.MessageError then
                table.insert(execErrors, message)
            end
        end)

        -- Execute the code in Studio
        local ok, result = pcall(function()
            local fn, err = loadstring(code)
            if not fn then
                error("Syntax error: " .. tostring(err))
            end
            return fn()
        end)

        -- Wait briefly for any deferred/async errors to come through
        task.wait(0.15)
        errorConnection:Disconnect()

        -- Check for LogService errors even if pcall succeeded
        local hasLogErrors = #execErrors > 0
        local logErrorStr = hasLogErrors and table.concat(execErrors, "\n") or nil

        if ok and not hasLogErrors then
            local resultStr = tostring(result)
            sendLog("info", "Execution success: " .. resultStr)
            postExecResult(true, resultStr, nil, code)
            self:setStatus("Done", Theme.Colors.Success)
            -- Clear status after brief delay
            task.delay(1, function()
                if self.elements.statusLabel and self.elements.statusLabel.Text == "Done" then
                    self:setStatus("")
                end
            end)
        else
            -- Combine pcall error with any LogService errors
            local errorStr = ""
            if not ok then
                errorStr = tostring(result)
            end
            if hasLogErrors then
                if errorStr ~= "" then
                    errorStr = errorStr .. "\n\nAdditional errors from LogService:\n" .. logErrorStr
                else
                    errorStr = "Errors from LogService:\n" .. logErrorStr
                end
            end
            sendLog("error", "Execution failed: " .. errorStr:sub(1, 200))
            postExecResult(false, nil, errorStr, code)
            self:setStatus("Error: " .. errorStr:sub(1, 30), Theme.Colors.Error)
        end
    end))
end

-- Status animation state
local statusAnimThread: thread? = nil

-- Update status indicator with optional animation
function ChatWidget:setStatus(text: string, color: Color3?, animate: boolean?)
    if not self.elements.statusLabel then return end

    -- Stop any existing animation
    if statusAnimThread then
        task.cancel(statusAnimThread)
        statusAnimThread = nil
    end

    self.elements.statusLabel.Text = text
    self.elements.statusLabel.TextColor3 = color or Theme.Colors.TextDim
    self.elements.statusLabel.TextTransparency = 0

    -- Animate if requested (pulse effect for running states)
    if animate and text ~= "" then
        statusAnimThread = task.spawn(function()
            local label = self.elements.statusLabel
            local dots = 0
            local baseText = text:gsub("%.+$", "") -- Remove trailing dots

            while label and label.Parent do
                -- Pulse transparency
                for i = 0, 10 do
                    if not label or not label.Parent then break end
                    label.TextTransparency = 0.3 * math.sin(i * math.pi / 10)
                    task.wait(0.05)
                end

                -- Animate dots
                dots = (dots % 3) + 1
                if label and label.Parent then
                    label.Text = baseText .. string.rep(".", dots)
                end
            end
        end)
    end
end

function ChatWidget:createChip(parent: GuiObject, text: string, order: number, onClick: () -> (), color: Color3?): TextButton
    local chipColor = color or Theme.Colors.Primary
    local chip = Instance.new("TextButton")
    chip.Name = text
    chip.Text = text
    chip.Font = Theme.Fonts.Default
    chip.TextSize = Theme.Sizes.TextSmall
    chip.TextColor3 = chipColor
    chip.BackgroundColor3 = Theme.Colors.Background
    chip.BorderSizePixel = 0
    chip.Size = UDim2.new(0, 0, 1, 0)
    chip.AutomaticSize = Enum.AutomaticSize.X
    chip.LayoutOrder = order
    chip.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = chip

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.Parent = chip

    local stroke = Instance.new("UIStroke")
    stroke.Color = chipColor
    stroke.Thickness = 1
    stroke.Parent = chip

    chip.MouseButton1Click:Connect(onClick)

    return chip
end

function ChatWidget:handleInput()
    local ok, err = pcall(function()
        local text = self.elements.inputBox.Text
        if text == "" then return end

        self.elements.inputBox.Text = ""

        -- Add user message
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "user",
            content = text,
            timestamp = os.time()
        })

        -- Handle commands vs agent tasks
        if text:sub(1, 1) == "/" then
            self:handleCommand(text)
        else
            -- Send to agent
            self:runAgentTask(text)
        end
    end)

    if not ok then
        warn("[DetAI] handleInput error:", tostring(err))
        -- Log to daemon
        pcall(function()
            HttpService:PostAsync(
                "http://127.0.0.1:4849/log/error",
                HttpService:JSONEncode({ source = "handleInput", error = tostring(err) }),
                Enum.HttpContentType.ApplicationJson
            )
        end)
    end
end

function ChatWidget:handleCommand(cmd: string)
    local parts = cmd:split(" ")
    local command = parts[1]:lower()

    if command == "/export" then
        task.spawn(function()
            Export.exportAll()
        end)
    elseif command == "/pull" then
        task.spawn(function()
            Import.pullChanges()
        end)
    elseif command == "/apply" then
        task.spawn(function()
            Import.applyChanges()
        end)
    elseif command == "/cancel" then
        self:cancelAgentTask()
    elseif command == "/status" then
        self:checkAgentStatus()
    elseif command == "/token" then
        local token = parts[2]
        if token and token ~= "" then
            Store.setDaemonConfig(Store.getState().daemonUrl, token)
            -- Save to plugin settings
            self.plugin:SetSetting("DaemonToken", token)

            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "system",
                content = "Token saved. Reconnecting...",
                timestamp = os.time()
            })

            -- Reconnect with new token
            task.spawn(function()
                DaemonClient.disconnectWebSocket()
                DaemonClient.connectFull()
            end)
        else
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "system",
                content = "Usage: /token <your-token>\nGet your token from the daemon console output.",
                timestamp = os.time()
            })
        end
    elseif command == "/connect" then
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "system",
            content = "Reconnecting to daemon...",
            timestamp = os.time()
        })
        task.spawn(function()
            DaemonClient.disconnectWebSocket()
            local ok = DaemonClient.connectFull()
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "system",
                content = ok and "Connected!" or "Connection failed",
                timestamp = os.time()
            })
        end)
    elseif command == "/preview" then
        task.spawn(function()
            local selected = Selection:Get()
            local scope = nil
            local scopeArg = parts[2] and parts[2]:lower()

            if scopeArg == "selection" then
                scope = "selection"
            elseif scopeArg == "descendants" then
                scope = "descendants"
            end

            local preview = Export.preview(scope, selected)
            local formatted = Export.formatPreview(preview)

            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "system",
                content = formatted,
                timestamp = os.time()
            })
        end)
    elseif command == "/help" then
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "system",
            content = [[Available commands:
/export - Export all scripts to local repo
/preview [selection|descendants] - Preview what will be exported
/pull - Pull changes from local repo
/apply - Apply pending changes
/cancel - Cancel running agent task
/status - Check agent task status
/token <token> - Set daemon auth token
/connect - Reconnect to daemon
/help - Show this help

Tags for filtering:
- DetAI_NoExport: Skip instance during export
- DetAI_NoModify: Export but prevent AI modifications
- DetAI_ContextOnly: Include in context but don't write to files

Or just type a task for Claude!]],
            timestamp = os.time()
        })
    else
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "system",
            content = "Unknown command: " .. command .. ". Type /help for available commands.",
            timestamp = os.time()
        })
    end
end

-- Get selected instances as context
function ChatWidget:getSelectionContext(): {string}
    local selected = Selection:Get()
    local paths = {}

    for _, inst in ipairs(selected) do
        local path = inst:GetFullName()
        table.insert(paths, path)
    end

    return paths
end

-- Get API info for a class using ReflectionService
function ChatWidget:getClassAPI(className: string): string?
    local ok, props = pcall(function()
        return ReflectionService:GetPropertiesOfClass(className)
    end)
    if not ok or not props then return nil end

    local lines = {className .. " properties:"}
    for _, prop in ipairs(props) do
        local access = ""
        if prop.Permits then
            if prop.Permits.Read and prop.Permits.Write then
                access = " (read/write)"
            elseif prop.Permits.Read then
                access = " (read-only)"
            end
        end
        table.insert(lines, "  " .. prop.Name .. ": " .. tostring(prop.ValueType) .. access)
    end
    return table.concat(lines, "\n")
end

-- Get common Roblox API context for Claude
function ChatWidget:getRobloxAPIContext(): string
    local commonClasses = {"Part", "Model", "SpawnLocation", "Terrain", "BasePart", "MeshPart", "Script", "LocalScript", "ModuleScript"}
    local lines = {"=== Roblox API Reference (from ReflectionService) ===\n"}

    for _, className in ipairs(commonClasses) do
        local api = self:getClassAPI(className)
        if api then
            table.insert(lines, api)
            table.insert(lines, "")
        end
    end

    return table.concat(lines, "\n")
end

-- Get path and pointer context from DevTools
function ChatWidget:getPathAndPointerContext(): {path: any?, pointer: any?}
    local context = { path = nil, pointer = nil }

    -- Get path data
    pcall(function()
        local response = HttpService:PostAsync(
            "http://127.0.0.1:4849/devtools/call",
            HttpService:JSONEncode({ tool = "studio.path.get", params = {} }),
            Enum.HttpContentType.ApplicationJson
        )
        local decoded = HttpService:JSONDecode(response)
        if decoded.success and decoded.result and decoded.result.pointCount > 0 then
            context.path = decoded.result
        end
    end)

    -- Get last pointer data
    pcall(function()
        local response = HttpService:PostAsync(
            "http://127.0.0.1:4849/devtools/call",
            HttpService:JSONEncode({ tool = "studio.pointer.getLast", params = {} }),
            Enum.HttpContentType.ApplicationJson
        )
        local decoded = HttpService:JSONDecode(response)
        if decoded.success and decoded.result and decoded.result.position then
            context.pointer = decoded.result
        end
    end)

    return context
end

-- Run agent task with progress tracking
function ChatWidget:runAgentTask(taskText: string)
    if activeRunId then
        self:setStatus("Task already running", Theme.Colors.Warning)
        return
    end

    local selectionContext = self:getSelectionContext()
    local apiContext = self:getRobloxAPIContext()
    local pathPointerContext = self:getPathAndPointerContext()
    self:setStatus("Starting", Theme.Colors.Primary, true)

    -- Build context notes
    local notes = "This is a Roblox game project with Lua scripts. Use the API Reference to know what properties exist."

    if pathPointerContext.path then
        local points = pathPointerContext.path.points or {}
        notes = notes .. "\n\nUSER DREW A PATH with " .. #points .. " points. The path coordinates are:\n"
        for i, pt in ipairs(points) do
            notes = notes .. string.format("  Point %d: (%.1f, %.1f, %.1f)\n", i, pt.position.x, pt.position.y, pt.position.z)
        end
        notes = notes .. "Use these coordinates to place objects along the path or within the area defined by the path."
    end

    if pathPointerContext.pointer then
        local pos = pathPointerContext.pointer.position
        notes = notes .. string.format("\n\nUSER MARKED A POSITION at (%.1f, %.1f, %.1f)", pos.x, pos.y, pos.z)
        if pathPointerContext.pointer.instance then
            notes = notes .. " on " .. (pathPointerContext.pointer.instance.path or pathPointerContext.pointer.instance.name or "unknown")
        end
        notes = notes .. ". Use this position when the user says 'here' or 'at this spot'."
    end

    task.spawn(function()
        local ok, result = DaemonClient.agentRun({
            task = taskText,
            context = {
                selection = selectionContext,
                apiReference = apiContext,
                path = pathPointerContext.path,
                pointer = pathPointerContext.pointer,
                notes = notes
            }
        })

        if ok and result and result.runId then
            activeRunId = result.runId
            self:setStatus("Running", Theme.Colors.Primary, true)

            -- Only use polling if WebSocket is not connected
            if not DaemonClient.isWebSocketConnected() then
                self:startStatusPolling(result.runId)
            end
        else
            self:setStatus("Failed to start", Theme.Colors.Error)
        end
    end)
end

-- Poll agent status
function ChatWidget:startStatusPolling(runId: string)
    if pollConnection then
        task.cancel(pollConnection)
    end

    pollConnection = task.spawn(function()
        local lastLogCursor = "0"

        while activeRunId == runId do
            task.wait(2) -- Poll every 2 seconds

            -- Get status
            local ok, status = DaemonClient.agentStatus(runId)

            if not ok or not status then
                break
            end

            -- Get new logs
            local logOk, logs = DaemonClient.agentLogs(runId, lastLogCursor)
            if logOk and logs and logs.lines then
                for _, logEntry in ipairs(logs.lines) do
                    if logEntry.message and not logEntry.message:match("^Task:") then
                        -- Only show interesting logs
                        if logEntry.message:match("^Writing:") or
                           logEntry.message:match("^Reading:") or
                           logEntry.message:match("^Bash:") or
                           logEntry.message:match("^Error:") or
                           logEntry.message:match("^Completed:") then
                            Store.addMessage({
                                id = HttpService:GenerateGUID(false),
                                type = "system",
                                content = logEntry.message,
                                timestamp = math.floor(logEntry.timestamp / 1000)
                            })
                        end
                    end
                end
                lastLogCursor = logs.nextCursor
            end

            -- Check if done
            if status.state == "done" then
                activeRunId = nil
                self:setStatus("")

                local summary = status.summary or "Task completed"

                Store.addMessage({
                    id = HttpService:GenerateGUID(false),
                    type = "assistant",
                    content = summary,
                    cardType = "ResultCard",
                    timestamp = os.time()
                })

                break

            elseif status.state == "error" then
                activeRunId = nil

                Store.addMessage({
                    id = HttpService:GenerateGUID(false),
                    type = "system",
                    content = "Agent error: " .. (status.error or "unknown"),
                    timestamp = os.time()
                })

                break

            elseif status.state == "cancelled" then
                activeRunId = nil

                Store.addMessage({
                    id = HttpService:GenerateGUID(false),
                    type = "system",
                    content = "Agent task was cancelled.",
                    timestamp = os.time()
                })

                break
            end
        end

        pollConnection = nil
    end)
end

-- Cancel running task
function ChatWidget:cancelAgentTask()
    if not activeRunId then
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "system",
            content = "No task is currently running.",
            timestamp = os.time()
        })
        return
    end

    task.spawn(function()
        local ok, _ = DaemonClient.agentCancel(activeRunId)

        if ok then
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "system",
                content = "Cancel request sent for " .. activeRunId,
                timestamp = os.time()
            })
        else
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "system",
                content = "Failed to cancel task",
                timestamp = os.time()
            })
        end
    end)
end

-- Check current status
function ChatWidget:checkAgentStatus()
    if not activeRunId then
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "system",
            content = "No task is currently running.",
            timestamp = os.time()
        })
        return
    end

    task.spawn(function()
        local ok, status = DaemonClient.agentStatus(activeRunId)

        if ok and status then
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "system",
                content = string.format("Task %s: %s", status.runId, status.state),
                timestamp = os.time()
            })
        else
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "system",
                content = "Failed to get status",
                timestamp = os.time()
            })
        end
    end)
end

function ChatWidget:updateMessages(messages: {Store.ChatMessage})
    local scroll = self.elements.messagesScroll

    -- Clear existing
    for _, child in scroll:GetChildren() do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    -- Add messages
    for i, msg in ipairs(messages) do
        local msgFrame = Instance.new("Frame")
        msgFrame.Name = "Message_" .. i
        msgFrame.BackgroundColor3 = if msg.type == "user" then Theme.Colors.Primary:Lerp(Theme.Colors.Background, 0.8)
            elseif msg.type == "assistant" then Theme.Colors.Success:Lerp(Theme.Colors.Background, 0.85)
            else Theme.Colors.Surface
        msgFrame.BorderSizePixel = 0
        msgFrame.Size = UDim2.new(1, -16, 0, 0)
        msgFrame.AutomaticSize = Enum.AutomaticSize.Y
        msgFrame.LayoutOrder = i
        msgFrame.Parent = scroll

        local msgCorner = Instance.new("UICorner")
        msgCorner.CornerRadius = UDim.new(0, Theme.Sizes.BorderRadius)
        msgCorner.Parent = msgFrame

        local msgPadding = Instance.new("UIPadding")
        msgPadding.PaddingTop = UDim.new(0, 8)
        msgPadding.PaddingBottom = UDim.new(0, 8)
        msgPadding.PaddingLeft = UDim.new(0, 8)
        msgPadding.PaddingRight = UDim.new(0, 8)
        msgPadding.Parent = msgFrame

        -- Time label
        local timeLabel = Theme.createLabel({
            parent = msgFrame,
            text = os.date("%H:%M", msg.timestamp),
            textSize = Theme.Sizes.TextSmall,
            textColor = Theme.Colors.TextDim
        })
        timeLabel.Size = UDim2.new(1, 0, 0, 14)

        -- Content label
        local contentLabel = Theme.createLabel({
            parent = msgFrame,
            text = msg.content,
            textSize = Theme.Sizes.TextNormal,
            textColor = Theme.Colors.Text
        })
        contentLabel.Position = UDim2.new(0, 0, 0, 16)
        contentLabel.Size = UDim2.new(1, 0, 0, 0)
        contentLabel.AutomaticSize = Enum.AutomaticSize.Y
        contentLabel.TextWrapped = true
    end

    -- Scroll to bottom
    task.defer(function()
        scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
    end)
end

-- DevTools: Capture current pointer position
function ChatWidget:capturePointer()
    task.spawn(function()
        local ok, result = pcall(function()
            return HttpService:PostAsync(
                "http://127.0.0.1:4849/devtools/call",
                HttpService:JSONEncode({ tool = "studio.pointer.capture", params = {} }),
                Enum.HttpContentType.ApplicationJson
            )
        end)

        if ok and result then
            local decoded = HttpService:JSONDecode(result)
            if decoded.success and decoded.result then
                local pos = decoded.result.position
                local instance = decoded.result.instance
                if not pos then
                    self:setStatus("No position", Theme.Colors.Warning)
                    return
                end
                local message = string.format("Marked: (%.1f, %.1f, %.1f)", pos.x, pos.y, pos.z)
                if instance and instance.path then
                    message = message .. " on " .. instance.path
                end
                Store.addMessage({
                    id = HttpService:GenerateGUID(false),
                    type = "system",
                    content = message,
                    timestamp = os.time()
                })
                self:setStatus("Position captured", Theme.Colors.Success)
                task.delay(1.5, function() self:setStatus("") end)
            else
                self:setStatus("Capture failed", Theme.Colors.Error)
            end
        else
            self:setStatus("Capture failed", Theme.Colors.Error)
        end
    end)
end

-- DevTools: Toggle path drawing mode
function ChatWidget:togglePathDrawing()
    task.spawn(function()
        if isDrawingPath then
            -- Stop drawing and get points
            local ok, result = pcall(function()
                return HttpService:PostAsync(
                    "http://127.0.0.1:4849/devtools/call",
                    HttpService:JSONEncode({ tool = "studio.path.stop", params = {} }),
                    Enum.HttpContentType.ApplicationJson
                )
            end)

            isDrawingPath = false
            if self.pathButton then
                self.pathButton.Text = "Draw Path"
                self.pathButton.TextColor3 = Color3.fromRGB(80, 160, 80)
                local stroke = self.pathButton:FindFirstChildOfClass("UIStroke")
                if stroke then stroke.Color = Color3.fromRGB(80, 160, 80) end
            end

            if ok and result then
                local decoded = HttpService:JSONDecode(result)
                if decoded.success and decoded.result then
                    local points = decoded.result.points or {}
                    Store.addMessage({
                        id = HttpService:GenerateGUID(false),
                        type = "system",
                        content = string.format("Path recorded: %d points", #points),
                        timestamp = os.time()
                    })
                    self:setStatus("Path saved", Theme.Colors.Success)
                    task.delay(1.5, function() self:setStatus("") end)
                end
            end
        else
            -- Start drawing
            local ok, result = pcall(function()
                return HttpService:PostAsync(
                    "http://127.0.0.1:4849/devtools/call",
                    HttpService:JSONEncode({ tool = "studio.path.start", params = {} }),
                    Enum.HttpContentType.ApplicationJson
                )
            end)

            if ok and result then
                local decoded = HttpService:JSONDecode(result)
                if decoded.success then
                    isDrawingPath = true
                    if self.pathButton then
                        self.pathButton.Text = "Stop Path"
                        self.pathButton.TextColor3 = Color3.fromRGB(200, 80, 80)
                        local stroke = self.pathButton:FindFirstChildOfClass("UIStroke")
                        if stroke then stroke.Color = Color3.fromRGB(200, 80, 80) end
                    end
                    Store.addMessage({
                        id = HttpService:GenerateGUID(false),
                        type = "system",
                        content = "Click in viewport to add path points. Click 'Stop Path' when done.",
                        timestamp = os.time()
                    })
                    self:setStatus("Drawing path...", Theme.Colors.Primary, true)
                end
            end
        end
    end)
end

-- DevTools: Clear path
function ChatWidget:clearPath()
    task.spawn(function()
        local ok, result = pcall(function()
            return HttpService:PostAsync(
                "http://127.0.0.1:4849/devtools/call",
                HttpService:JSONEncode({ tool = "studio.path.clear", params = {} }),
                Enum.HttpContentType.ApplicationJson
            )
        end)

        isDrawingPath = false
        if self.pathButton then
            self.pathButton.Text = "Draw Path"
            self.pathButton.TextColor3 = Color3.fromRGB(80, 160, 80)
            local stroke = self.pathButton:FindFirstChildOfClass("UIStroke")
            if stroke then stroke.Color = Color3.fromRGB(80, 160, 80) end
        end

        if ok and result then
            local decoded = HttpService:JSONDecode(result)
            if decoded.success then
                self:setStatus("Path cleared", Theme.Colors.TextDim)
                task.delay(1, function() self:setStatus("") end)
            end
        end
    end)
end

function ChatWidget:destroy()
    if pollConnection then
        task.cancel(pollConnection)
        pollConnection = nil
    end

    -- Clean up WebSocket event subscriptions
    for _, unsub in ipairs(wsUnsubscribers) do
        unsub()
    end
    wsUnsubscribers = {}

    for _, conn in pairs(self.connections) do
        if typeof(conn) == "function" then
            conn()
        elseif typeof(conn) == "RBXScriptConnection" then
            conn:Disconnect()
        end
    end

    if self.widget then
        self.widget:Destroy()
    end
end

export type ChatWidget = typeof(ChatWidget.new(nil :: any))

return ChatWidget
