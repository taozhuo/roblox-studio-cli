--!strict
--[[
    Chat Widget UI
    Unified interface: Chat + Settings (Sync) + Speech
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
local pollConnection: thread? = nil
local wsUnsubscribers: {() -> ()} = {}

-- DevTools state
local isDrawingPath: boolean = false

-- Settings panel state
local settingsPanelVisible: boolean = false

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
    self.widget.Title = "DetAI"
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

    -- Status indicator (center of header)
    local statusLabel = Theme.createLabel({
        parent = header,
        text = "",
        position = UDim2.new(0, 60, 0, 0),
        size = UDim2.new(1, -120, 1, 0),
        textSize = Theme.Sizes.TextSmall,
        textColor = Theme.Colors.TextDim
    })
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    self.elements.statusLabel = statusLabel

    -- Settings button (gear icon) - right side
    local settingsBtn = Instance.new("TextButton")
    settingsBtn.Name = "SettingsBtn"
    settingsBtn.Text = "⚙"
    settingsBtn.Font = Enum.Font.GothamBold
    settingsBtn.TextSize = 18
    settingsBtn.TextColor3 = Theme.Colors.TextMuted
    settingsBtn.BackgroundTransparency = 1
    settingsBtn.Size = UDim2.new(0, 30, 0, 30)
    settingsBtn.Position = UDim2.new(1, -35, 0.5, -15)
    settingsBtn.Parent = header
    self.elements.settingsBtn = settingsBtn

    settingsBtn.MouseButton1Click:Connect(function()
        self:toggleSettingsPanel()
    end)

    -- Connection status dot (next to gear)
    local statusDot = Instance.new("Frame")
    statusDot.Name = "StatusDot"
    statusDot.BackgroundColor3 = Theme.Colors.Disconnected
    statusDot.Size = UDim2.new(0, 8, 0, 8)
    statusDot.Position = UDim2.new(1, -45, 0.5, -4)
    statusDot.Parent = header
    self.elements.statusDot = statusDot

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = statusDot

    -- Settings Panel (initially hidden)
    local settingsPanel = Instance.new("Frame")
    settingsPanel.Name = "SettingsPanel"
    settingsPanel.BackgroundColor3 = Theme.Colors.Surface
    settingsPanel.BorderSizePixel = 0
    settingsPanel.Size = UDim2.new(1, -16, 0, 180)
    settingsPanel.Position = UDim2.new(0, 8, 0, Theme.Sizes.HeaderHeight + 8)
    settingsPanel.Visible = false
    settingsPanel.ZIndex = 10
    settingsPanel.Parent = container
    self.elements.settingsPanel = settingsPanel

    local settingsCorner = Instance.new("UICorner")
    settingsCorner.CornerRadius = UDim.new(0, Theme.Sizes.BorderRadius)
    settingsCorner.Parent = settingsPanel

    local settingsPadding = Instance.new("UIPadding")
    settingsPadding.PaddingTop = UDim.new(0, 12)
    settingsPadding.PaddingBottom = UDim.new(0, 12)
    settingsPadding.PaddingLeft = UDim.new(0, 12)
    settingsPadding.PaddingRight = UDim.new(0, 12)
    settingsPadding.Parent = settingsPanel

    local settingsLayout = Instance.new("UIListLayout")
    settingsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    settingsLayout.Padding = UDim.new(0, 8)
    settingsLayout.Parent = settingsPanel

    -- Settings: Title
    local settingsTitle = Theme.createLabel({
        parent = settingsPanel,
        text = "Settings & Sync",
        font = Theme.Fonts.Bold,
        textSize = Theme.Sizes.TextNormal
    })
    settingsTitle.LayoutOrder = 0

    -- Settings: Connection status
    local connLabel = Theme.createLabel({
        parent = settingsPanel,
        text = "Disconnected",
        textSize = Theme.Sizes.TextSmall,
        textColor = Theme.Colors.TextMuted
    })
    connLabel.LayoutOrder = 1
    self.elements.connLabel = connLabel

    -- Settings: Sync buttons row
    local syncRow = Instance.new("Frame")
    syncRow.Name = "SyncRow"
    syncRow.BackgroundTransparency = 1
    syncRow.Size = UDim2.new(1, 0, 0, 28)
    syncRow.LayoutOrder = 2
    syncRow.Parent = settingsPanel

    local syncLayout = Instance.new("UIListLayout")
    syncLayout.FillDirection = Enum.FillDirection.Horizontal
    syncLayout.SortOrder = Enum.SortOrder.LayoutOrder
    syncLayout.Padding = UDim.new(0, 6)
    syncLayout.Parent = syncRow

    -- Export button
    local exportBtn = Theme.createButton({
        parent = syncRow,
        text = "Export",
        size = UDim2.new(0, 70, 1, 0),
        color = Theme.Colors.Success,
        onClick = function()
            task.spawn(function() Export.exportAll() end)
        end
    })
    exportBtn.LayoutOrder = 1

    -- Pull button
    local pullBtn = Theme.createButton({
        parent = syncRow,
        text = "Pull",
        size = UDim2.new(0, 60, 1, 0),
        onClick = function()
            task.spawn(function() Import.pullChanges() end)
        end
    })
    pullBtn.LayoutOrder = 2

    -- Apply button
    local applyBtn = Theme.createButton({
        parent = syncRow,
        text = "Apply",
        size = UDim2.new(0, 60, 1, 0),
        color = Theme.Colors.Primary,
        onClick = function()
            task.spawn(function() Import.applyChanges() end)
        end
    })
    applyBtn.LayoutOrder = 3

    -- Reconnect button
    local reconnectBtn = Theme.createButton({
        parent = syncRow,
        text = "Reconnect",
        size = UDim2.new(0, 80, 1, 0),
        onClick = function()
            task.spawn(function()
                DaemonClient.disconnectWebSocket()
                DaemonClient.connectFull()
            end)
        end
    })
    reconnectBtn.LayoutOrder = 4

    -- Settings: Token input
    local tokenLabel = Theme.createLabel({
        parent = settingsPanel,
        text = "Auth Token:",
        textSize = Theme.Sizes.TextSmall,
        textColor = Theme.Colors.TextMuted
    })
    tokenLabel.LayoutOrder = 3

    local tokenInput = Theme.createInput({
        parent = settingsPanel,
        text = self.plugin:GetSetting("DaemonToken") or "",
        placeholder = "Paste token from daemon console"
    })
    tokenInput.LayoutOrder = 4
    self.elements.tokenInput = tokenInput

    -- Save token on focus lost
    tokenInput.FocusLost:Connect(function()
        local token = tokenInput.Text
        if token ~= "" then
            self.plugin:SetSetting("DaemonToken", token)
            Store.setDaemonConfig(Store.getState().daemonUrl, token)
            task.spawn(function()
                DaemonClient.disconnectWebSocket()
                DaemonClient.connectFull()
            end)
        end
    end)

    -- Messages area
    local messagesFrame = Instance.new("Frame")
    messagesFrame.Name = "MessagesFrame"
    messagesFrame.BackgroundTransparency = 1
    messagesFrame.Size = UDim2.new(1, 0, 1, -Theme.Sizes.HeaderHeight - 100)
    messagesFrame.Position = UDim2.new(0, 0, 0, Theme.Sizes.HeaderHeight)
    messagesFrame.Parent = container

    local messagesScroll = Theme.createScrollFrame({
        parent = messagesFrame,
        size = UDim2.new(1, 0, 1, 0)
    })
    self.elements.messagesScroll = messagesScroll

    -- Composer area
    local composerFrame = Instance.new("Frame")
    composerFrame.Name = "ComposerFrame"
    composerFrame.BackgroundColor3 = Theme.Colors.BackgroundDark
    composerFrame.BorderSizePixel = 0
    composerFrame.Size = UDim2.new(1, 0, 0, 100)
    composerFrame.Position = UDim2.new(0, 0, 1, -100)
    composerFrame.Parent = container

    local composerPadding = Instance.new("UIPadding")
    composerPadding.PaddingTop = UDim.new(0, 8)
    composerPadding.PaddingBottom = UDim.new(0, 8)
    composerPadding.PaddingLeft = UDim.new(0, 8)
    composerPadding.PaddingRight = UDim.new(0, 8)
    composerPadding.Parent = composerFrame

    -- Input row (input + mic button)
    local inputRow = Instance.new("Frame")
    inputRow.Name = "InputRow"
    inputRow.BackgroundTransparency = 1
    inputRow.Size = UDim2.new(1, 0, 0, 36)
    inputRow.Parent = composerFrame

    -- Input box
    local inputBox = Instance.new("TextBox")
    inputBox.Name = "InputBox"
    inputBox.Text = ""
    inputBox.PlaceholderText = "Type a task for Claude..."
    inputBox.Font = Theme.Fonts.Default
    inputBox.TextSize = Theme.Sizes.TextNormal
    inputBox.TextColor3 = Theme.Colors.Text
    inputBox.PlaceholderColor3 = Theme.Colors.TextDim
    inputBox.BackgroundColor3 = Theme.Colors.BackgroundLight
    inputBox.BorderSizePixel = 0
    inputBox.Size = UDim2.new(1, -44, 1, 0)
    inputBox.Position = UDim2.new(0, 0, 0, 0)
    inputBox.TextXAlignment = Enum.TextXAlignment.Left
    inputBox.TextYAlignment = Enum.TextYAlignment.Center
    inputBox.ClearTextOnFocus = false
    inputBox.MultiLine = false
    inputBox.TextWrapped = false
    inputBox.Parent = inputRow
    self.elements.inputBox = inputBox

    local inputCorner = Instance.new("UICorner")
    inputCorner.CornerRadius = UDim.new(0, Theme.Sizes.BorderRadius)
    inputCorner.Parent = inputBox

    local inputPadding = Instance.new("UIPadding")
    inputPadding.PaddingLeft = UDim.new(0, 10)
    inputPadding.PaddingRight = UDim.new(0, 10)
    inputPadding.Parent = inputBox

    -- Mic button
    local micBtn = Instance.new("TextButton")
    micBtn.Name = "MicBtn"
    micBtn.Text = "🎤"
    micBtn.Font = Enum.Font.GothamBold
    micBtn.TextSize = 18
    micBtn.TextColor3 = Theme.Colors.TextMuted
    micBtn.BackgroundColor3 = Theme.Colors.BackgroundLight
    micBtn.BorderSizePixel = 0
    micBtn.Size = UDim2.new(0, 36, 0, 36)
    micBtn.Position = UDim2.new(1, -36, 0, 0)
    micBtn.Parent = inputRow
    self.elements.micBtn = micBtn

    local micCorner = Instance.new("UICorner")
    micCorner.CornerRadius = UDim.new(0, Theme.Sizes.BorderRadius)
    micCorner.Parent = micBtn

    micBtn.MouseButton1Click:Connect(function()
        self:toggleSpeech()
    end)

    -- DevTools row
    local devToolsFrame = Instance.new("Frame")
    devToolsFrame.Name = "DevToolsFrame"
    devToolsFrame.Size = UDim2.new(1, 0, 0, 24)
    devToolsFrame.Position = UDim2.new(0, 0, 0, 44)
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

    -- Draw Path button
    self.pathButton = self:createChip(devToolsFrame, "Draw Path", 2, function()
        self:togglePathDrawing()
    end, Color3.fromRGB(80, 160, 80))

    -- Clear button
    self:createChip(devToolsFrame, "Clear", 3, function()
        self:clearPath()
    end, Color3.fromRGB(160, 80, 80))

    -- Help chip
    self:createChip(devToolsFrame, "/help", 4, function()
        self:handleCommand("/help")
    end, Theme.Colors.TextMuted)

    -- Handle enter key
    inputBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            self:handleInput()
        end
    end)

    -- Subscribe to store
    self.connections.storeSubscription = Store.subscribe(function(state)
        self:updateMessages(state.messages)
        self:updateConnectionStatus(state)
    end)

    -- Initial update
    self:updateMessages(Store.getState().messages)
    self:updateConnectionStatus(Store.getState())

    -- Welcome message
    Store.addMessage({
        id = HttpService:GenerateGUID(false),
        type = "system",
        content = "Welcome to DetAI! Type a task for Claude, use /help for commands, or click ⚙ for settings.",
        timestamp = os.time()
    })

    -- Set up WebSocket listeners
    pcall(function()
        self:setupWebSocketListeners()
    end)

    -- Stream LogService output
    local logConnection = LogService.MessageOut:Connect(function(message, messageType)
        if message:match("^%[DetAI%]") or message:match("^%[Studio%]") then
            return
        end

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

-- Toggle settings panel visibility
function ChatWidget:toggleSettingsPanel()
    settingsPanelVisible = not settingsPanelVisible
    self.elements.settingsPanel.Visible = settingsPanelVisible

    -- Update gear color
    self.elements.settingsBtn.TextColor3 = settingsPanelVisible
        and Theme.Colors.Primary
        or Theme.Colors.TextMuted
end

-- Update connection status
function ChatWidget:updateConnectionStatus(state: Store.StoreState)
    local statusColor = Theme.Colors.Disconnected
    local statusText = "Disconnected"

    if state.syncStatus == "connected" then
        statusColor = Theme.Colors.Connected
        statusText = "Connected"
    elseif state.syncStatus == "connecting" then
        statusColor = Theme.Colors.Syncing
        statusText = "Connecting..."
    elseif state.syncStatus == "syncing" then
        statusColor = Theme.Colors.Syncing
        statusText = "Syncing..."
    elseif state.syncStatus == "error" then
        statusColor = Theme.Colors.Error
        statusText = "Error"
    end

    if self.elements.statusDot then
        self.elements.statusDot.BackgroundColor3 = statusColor
    end
    if self.elements.connLabel then
        self.elements.connLabel.Text = statusText
        self.elements.connLabel.TextColor3 = statusColor
    end
end

-- Toggle speech recognition
function ChatWidget:toggleSpeech()
    -- Call Tauri helper to start/stop speech
    task.spawn(function()
        local ok, result = pcall(function()
            return HttpService:GetAsync("http://127.0.0.1:4850/speech/status")
        end)

        if not ok then
            self:setStatus("Speech unavailable", Theme.Colors.Warning)
            task.delay(2, function() self:setStatus("") end)
            return
        end

        local status = HttpService:JSONDecode(result)

        if status.listening then
            -- Stop listening, get transcription
            pcall(function()
                HttpService:PostAsync("http://127.0.0.1:4850/speech/stop", "{}", Enum.HttpContentType.ApplicationJson)
            end)
            task.wait(0.3)

            local transcriptOk, transcriptResult = pcall(function()
                return HttpService:GetAsync("http://127.0.0.1:4850/speech/transcription")
            end)

            if transcriptOk then
                local transcript = HttpService:JSONDecode(transcriptResult)
                if transcript.text and transcript.text ~= "" then
                    self.elements.inputBox.Text = transcript.text
                    self:setStatus("", nil)
                end
            end

            self.elements.micBtn.TextColor3 = Theme.Colors.TextMuted
        else
            -- Start listening
            local startOk = pcall(function()
                HttpService:PostAsync("http://127.0.0.1:4850/speech/listen", "{}", Enum.HttpContentType.ApplicationJson)
            end)

            if startOk then
                self.elements.micBtn.TextColor3 = Theme.Colors.Error
                self:setStatus("Listening...", Theme.Colors.Primary, true)
            else
                self:setStatus("Mic failed", Theme.Colors.Error)
            end
        end
    end)
end

-- Set up WebSocket event listeners for live streaming
function ChatWidget:setupWebSocketListeners()
    for _, unsub in ipairs(wsUnsubscribers) do
        pcall(unsub)
    end
    wsUnsubscribers = {}

    -- Listen for agent log messages
    table.insert(wsUnsubscribers, DaemonClient.onEvent("run.log", function(data)
        if data.runId ~= activeRunId then return end
        local message = data.message or ""

        if message:match("^Claude:") then
            local claudeText = message:gsub("^Claude: ", "")
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "assistant",
                content = claudeText,
                timestamp = data.timestamp and math.floor(data.timestamp / 1000) or os.time()
            })
        elseif message:match("^Error:") and not message:match("^Completed:") then
            Store.addMessage({
                id = HttpService:GenerateGUID(false),
                type = "system",
                content = message,
                timestamp = data.timestamp and math.floor(data.timestamp / 1000) or os.time()
            })
        end
    end))

    -- Listen for agent progress
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
        self:setStatus("")

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

    -- Listen for repo changes
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
                content = "Repo updated: " .. #files .. " file(s) changed",
                timestamp = os.time()
            })
        end
    end))

    -- Helper functions
    local function sendLog(level, message)
        pcall(function()
            HttpService:PostAsync(
                "http://127.0.0.1:4849/log",
                HttpService:JSONEncode({ level = level, message = message }),
                Enum.HttpContentType.ApplicationJson
            )
        end)
    end

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

    -- Polling fallback for exec
    task.spawn(function()
        task.wait(2)
        if DaemonClient.isWebSocketConnected() then return end

        while true do
            task.wait(0.5)
            if DaemonClient.isWebSocketConnected() then break end

            local ok, result = DaemonClient.request("GET", "/exec/pending", nil)
            if ok and result and result.code and result.code ~= "" then
                local code = result.code
                self:setStatus("Executing", Theme.Colors.Primary, true)

                local execOk, execResult = pcall(function()
                    local fn, err = loadstring(code)
                    if not fn then error("Syntax error: " .. tostring(err)) end
                    return fn()
                end)

                if execOk then
                    postExecResult(true, tostring(execResult), nil, code)
                    self:setStatus("Done", Theme.Colors.Success)
                    task.delay(1, function() self:setStatus("") end)
                else
                    postExecResult(false, nil, tostring(execResult), code)
                    self:setStatus("Error", Theme.Colors.Error)
                end
            end
        end
    end)

    -- Listen for studio.exec commands
    table.insert(wsUnsubscribers, DaemonClient.onEvent("studio.exec", function(data)
        local code = data.code
        if not code or code == "" then return end

        self:setStatus("Executing", Theme.Colors.Primary, true)

        local ok, result = pcall(function()
            local fn, err = loadstring(code)
            if not fn then error("Syntax error: " .. tostring(err)) end
            return fn()
        end)

        if ok then
            postExecResult(true, tostring(result), nil, code)
            self:setStatus("Done", Theme.Colors.Success)
            task.delay(1, function()
                if self.elements.statusLabel and self.elements.statusLabel.Text == "Done" then
                    self:setStatus("")
                end
            end)
        else
            postExecResult(false, nil, tostring(result), code)
            self:setStatus("Error: " .. tostring(result):sub(1, 30), Theme.Colors.Error)
        end
    end))
end

-- Status animation
local statusAnimThread: thread? = nil

function ChatWidget:setStatus(text: string, color: Color3?, animate: boolean?)
    if not self.elements.statusLabel then return end

    if statusAnimThread then
        task.cancel(statusAnimThread)
        statusAnimThread = nil
    end

    self.elements.statusLabel.Text = text
    self.elements.statusLabel.TextColor3 = color or Theme.Colors.TextDim
    self.elements.statusLabel.TextTransparency = 0

    if animate and text ~= "" then
        statusAnimThread = task.spawn(function()
            local label = self.elements.statusLabel
            local dots = 0
            local baseText = text:gsub("%.+$", "")

            while label and label.Parent do
                for i = 0, 10 do
                    if not label or not label.Parent then break end
                    label.TextTransparency = 0.3 * math.sin(i * math.pi / 10)
                    task.wait(0.05)
                end
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

        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "user",
            content = text,
            timestamp = os.time()
        })

        if text:sub(1, 1) == "/" then
            self:handleCommand(text)
        else
            self:runAgentTask(text)
        end
    end)

    if not ok then
        warn("[DetAI] handleInput error:", tostring(err))
    end
end

function ChatWidget:handleCommand(cmd: string)
    local parts = cmd:split(" ")
    local command = parts[1]:lower()

    if command == "/export" then
        task.spawn(function() Export.exportAll() end)
    elseif command == "/pull" then
        task.spawn(function() Import.pullChanges() end)
    elseif command == "/apply" then
        task.spawn(function() Import.applyChanges() end)
    elseif command == "/cancel" then
        self:cancelAgentTask()
    elseif command == "/status" then
        self:checkAgentStatus()
    elseif command == "/help" then
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "system",
            content = [[Commands:
/export - Export scripts
/pull - Pull changes
/apply - Apply changes
/cancel - Cancel task
/status - Task status
/help - This help

Click ⚙ for sync settings
Type anything else to ask Claude!]],
            timestamp = os.time()
        })
    else
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "system",
            content = "Unknown: " .. command .. ". Type /help",
            timestamp = os.time()
        })
    end
end

-- Get selection context
function ChatWidget:getSelectionContext(): {string}
    local selected = Selection:Get()
    local paths = {}
    for _, inst in ipairs(selected) do
        table.insert(paths, inst:GetFullName())
    end
    return paths
end

-- Get class API
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

function ChatWidget:getRobloxAPIContext(): string
    local commonClasses = {"Part", "Model", "SpawnLocation", "Terrain", "BasePart", "MeshPart", "Script", "LocalScript", "ModuleScript"}
    local lines = {"=== Roblox API Reference ===\n"}

    for _, className in ipairs(commonClasses) do
        local api = self:getClassAPI(className)
        if api then
            table.insert(lines, api)
            table.insert(lines, "")
        end
    end

    return table.concat(lines, "\n")
end

function ChatWidget:getPathAndPointerContext(): {path: any?, pointer: any?}
    local context = { path = nil, pointer = nil }

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

function ChatWidget:runAgentTask(taskText: string)
    if activeRunId then
        self:setStatus("Task running", Theme.Colors.Warning)
        return
    end

    local selectionContext = self:getSelectionContext()
    local apiContext = self:getRobloxAPIContext()
    local pathPointerContext = self:getPathAndPointerContext()
    self:setStatus("Starting", Theme.Colors.Primary, true)

    local notes = "Roblox game project with Lua scripts."

    if pathPointerContext.path then
        local points = pathPointerContext.path.points or {}
        notes = notes .. "\n\nUSER DREW A PATH with " .. #points .. " points:\n"
        for i, pt in ipairs(points) do
            notes = notes .. string.format("  Point %d: (%.1f, %.1f, %.1f)\n", i, pt.position.x, pt.position.y, pt.position.z)
        end
    end

    if pathPointerContext.pointer then
        local pos = pathPointerContext.pointer.position
        notes = notes .. string.format("\n\nUSER MARKED POSITION at (%.1f, %.1f, %.1f)", pos.x, pos.y, pos.z)
        if pathPointerContext.pointer.instance then
            notes = notes .. " on " .. (pathPointerContext.pointer.instance.path or "unknown")
        end
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

            if not DaemonClient.isWebSocketConnected() then
                self:startStatusPolling(result.runId)
            end
        else
            self:setStatus("Failed", Theme.Colors.Error)
        end
    end)
end

function ChatWidget:startStatusPolling(runId: string)
    if pollConnection then task.cancel(pollConnection) end

    pollConnection = task.spawn(function()
        local lastLogCursor = "0"

        while activeRunId == runId do
            task.wait(2)

            local ok, status = DaemonClient.agentStatus(runId)
            if not ok or not status then break end

            local logOk, logs = DaemonClient.agentLogs(runId, lastLogCursor)
            if logOk and logs and logs.lines then
                for _, logEntry in ipairs(logs.lines) do
                    if logEntry.message and not logEntry.message:match("^Task:") then
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

            if status.state == "done" then
                activeRunId = nil
                self:setStatus("")
                Store.addMessage({
                    id = HttpService:GenerateGUID(false),
                    type = "assistant",
                    content = status.summary or "Task completed",
                    cardType = "ResultCard",
                    timestamp = os.time()
                })
                break
            elseif status.state == "error" or status.state == "cancelled" then
                activeRunId = nil
                Store.addMessage({
                    id = HttpService:GenerateGUID(false),
                    type = "system",
                    content = status.state == "error" and ("Error: " .. (status.error or "unknown")) or "Cancelled",
                    timestamp = os.time()
                })
                break
            end
        end
        pollConnection = nil
    end)
end

function ChatWidget:cancelAgentTask()
    if not activeRunId then
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "system",
            content = "No task running",
            timestamp = os.time()
        })
        return
    end

    task.spawn(function()
        local ok, _ = DaemonClient.agentCancel(activeRunId)
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "system",
            content = ok and "Cancel sent" or "Cancel failed",
            timestamp = os.time()
        })
    end)
end

function ChatWidget:checkAgentStatus()
    if not activeRunId then
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "system",
            content = "No task running",
            timestamp = os.time()
        })
        return
    end

    task.spawn(function()
        local ok, status = DaemonClient.agentStatus(activeRunId)
        Store.addMessage({
            id = HttpService:GenerateGUID(false),
            type = "system",
            content = ok and string.format("Task %s: %s", status.runId, status.state) or "Status failed",
            timestamp = os.time()
        })
    end)
end

function ChatWidget:updateMessages(messages: {Store.ChatMessage})
    local scroll = self.elements.messagesScroll

    for _, child in scroll:GetChildren() do
        if child:IsA("Frame") then child:Destroy() end
    end

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

        local timeLabel = Theme.createLabel({
            parent = msgFrame,
            text = os.date("%H:%M", msg.timestamp),
            textSize = Theme.Sizes.TextSmall,
            textColor = Theme.Colors.TextDim
        })
        timeLabel.Size = UDim2.new(1, 0, 0, 14)

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

    task.defer(function()
        scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
    end)
end

-- DevTools
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
                if pos then
                    local message = string.format("Marked: (%.1f, %.1f, %.1f)", pos.x, pos.y, pos.z)
                    if decoded.result.instance and decoded.result.instance.path then
                        message = message .. " on " .. decoded.result.instance.path
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
                    self:setStatus("No position", Theme.Colors.Warning)
                end
            end
        end
    end)
end

function ChatWidget:togglePathDrawing()
    task.spawn(function()
        if isDrawingPath then
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
                        content = "Click in viewport to add path points",
                        timestamp = os.time()
                    })
                    self:setStatus("Drawing path...", Theme.Colors.Primary, true)
                end
            end
        end
    end)
end

function ChatWidget:clearPath()
    task.spawn(function()
        pcall(function()
            HttpService:PostAsync(
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

        self:setStatus("Path cleared", Theme.Colors.TextDim)
        task.delay(1, function() self:setStatus("") end)
    end)
end

function ChatWidget:destroy()
    if pollConnection then
        task.cancel(pollConnection)
        pollConnection = nil
    end

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
