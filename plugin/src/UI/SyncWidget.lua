--!strict
--[[
    Sync Widget UI
    Main dock widget for DetAI sync functionality
]]

local Store = require(script.Parent.Parent.State.Store)
local Theme = require(script.Parent.Theme)
local DaemonClient = require(script.Parent.Parent.Sync.DaemonClient)
local Export = require(script.Parent.Parent.Sync.Export)
local Import = require(script.Parent.Parent.Sync.Import)

local SyncWidget = {}
SyncWidget.__index = SyncWidget

function SyncWidget.new(plugin: Plugin): SyncWidget
    local self = setmetatable({}, SyncWidget)

    self.plugin = plugin
    self.widget = nil
    self.elements = {}
    self.connections = {}

    return self
end

function SyncWidget:create()
    -- Create dock widget
    local widgetInfo = DockWidgetPluginGuiInfo.new(
        Enum.InitialDockState.Right,
        true, -- enabled
        false, -- override
        300, -- width
        400, -- height
        200, -- min width
        200  -- min height
    )

    self.widget = self.plugin:CreateDockWidgetPluginGui("DetAI_Sync", widgetInfo)
    self.widget.Title = "DetAI Sync"
    self.widget.Name = "DetAI_Sync"

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
        text = "DetAI Sync",
        position = UDim2.new(0, Theme.Sizes.PaddingNormal, 0, 0),
        size = UDim2.new(1, -16, 1, 0),
        font = Theme.Fonts.Bold,
        textSize = Theme.Sizes.TextLarge
    })

    -- Status indicator
    local statusDot = Instance.new("Frame")
    statusDot.Name = "StatusDot"
    statusDot.BackgroundColor3 = Theme.Colors.Disconnected
    statusDot.Size = UDim2.new(0, 10, 0, 10)
    statusDot.Position = UDim2.new(1, -20, 0.5, -5)
    statusDot.Parent = header
    self.elements.statusDot = statusDot

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = statusDot

    -- Content area
    local content = Instance.new("Frame")
    content.Name = "Content"
    content.BackgroundTransparency = 1
    content.Size = UDim2.new(1, 0, 1, -Theme.Sizes.HeaderHeight)
    content.Position = UDim2.new(0, 0, 0, Theme.Sizes.HeaderHeight)
    content.Parent = container

    local contentPadding = Instance.new("UIPadding")
    contentPadding.PaddingTop = UDim.new(0, Theme.Sizes.PaddingNormal)
    contentPadding.PaddingBottom = UDim.new(0, Theme.Sizes.PaddingNormal)
    contentPadding.PaddingLeft = UDim.new(0, Theme.Sizes.PaddingNormal)
    contentPadding.PaddingRight = UDim.new(0, Theme.Sizes.PaddingNormal)
    contentPadding.Parent = content

    local contentLayout = Instance.new("UIListLayout")
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Padding = UDim.new(0, Theme.Sizes.PaddingNormal)
    contentLayout.Parent = content

    -- Connection section
    local connSection = self:createSection(content, "Connection", 1)

    local urlLabel = Theme.createLabel({
        parent = connSection,
        text = "Daemon URL",
        textColor = Theme.Colors.TextMuted,
        textSize = Theme.Sizes.TextSmall
    })
    urlLabel.LayoutOrder = 1

    local urlInput = Theme.createInput({
        parent = connSection,
        text = Store.getState().daemonUrl,
        placeholder = "http://127.0.0.1:4849"
    })
    urlInput.LayoutOrder = 2
    self.elements.urlInput = urlInput

    local connectBtn = Theme.createButton({
        parent = connSection,
        text = "Connect",
        size = UDim2.new(1, 0, 0, Theme.Sizes.ButtonHeight),
        onClick = function()
            self:onConnect()
        end
    })
    connectBtn.LayoutOrder = 3
    self.elements.connectBtn = connectBtn

    -- Status label
    local statusLabel = Theme.createLabel({
        parent = connSection,
        text = "Disconnected",
        textColor = Theme.Colors.TextMuted
    })
    statusLabel.LayoutOrder = 4
    self.elements.statusLabel = statusLabel

    -- Sync section
    local syncSection = self:createSection(content, "Sync", 2)

    local scriptCountLabel = Theme.createLabel({
        parent = syncSection,
        text = "Scripts: --",
        textColor = Theme.Colors.TextMuted
    })
    scriptCountLabel.LayoutOrder = 1
    self.elements.scriptCountLabel = scriptCountLabel

    local exportBtn = Theme.createButton({
        parent = syncSection,
        text = "Export Scripts",
        size = UDim2.new(1, 0, 0, Theme.Sizes.ButtonHeight),
        color = Theme.Colors.Success,
        onClick = function()
            self:onExport()
        end
    })
    exportBtn.LayoutOrder = 2
    self.elements.exportBtn = exportBtn

    local pullBtn = Theme.createButton({
        parent = syncSection,
        text = "Pull Changes",
        size = UDim2.new(1, 0, 0, Theme.Sizes.ButtonHeight),
        onClick = function()
            self:onPull()
        end
    })
    pullBtn.LayoutOrder = 3
    self.elements.pullBtn = pullBtn

    -- Changes section (hidden by default)
    local changesSection = self:createSection(content, "Pending Changes", 3)
    changesSection.Visible = false
    self.elements.changesSection = changesSection

    local changesLabel = Theme.createLabel({
        parent = changesSection,
        text = "0 files changed",
        textColor = Theme.Colors.TextMuted
    })
    changesLabel.LayoutOrder = 1
    self.elements.changesLabel = changesLabel

    local applyBtn = Theme.createButton({
        parent = changesSection,
        text = "Apply Changes",
        size = UDim2.new(1, 0, 0, Theme.Sizes.ButtonHeight),
        color = Theme.Colors.Success,
        onClick = function()
            self:onApply()
        end
    })
    applyBtn.LayoutOrder = 2
    self.elements.applyBtn = applyBtn

    local cancelBtn = Theme.createButton({
        parent = changesSection,
        text = "Cancel",
        size = UDim2.new(1, 0, 0, Theme.Sizes.ButtonHeight),
        color = Theme.Colors.BackgroundLight,
        onClick = function()
            self:onCancelChanges()
        end
    })
    cancelBtn.LayoutOrder = 3
    self.elements.cancelBtn = cancelBtn

    -- Messages section
    local messagesSection = self:createSection(content, "Activity", 4)

    local messagesScroll = Theme.createScrollFrame({
        parent = messagesSection,
        size = UDim2.new(1, 0, 0, 120)
    })
    messagesScroll.LayoutOrder = 1
    self.elements.messagesScroll = messagesScroll

    -- Subscribe to store changes
    self.connections.storeSubscription = Store.subscribe(function(state)
        self:updateUI(state)
    end)

    -- Initial UI update
    self:updateUI(Store.getState())
    self:updateScriptCount()
end

function SyncWidget:createSection(parent: GuiObject, title: string, order: number): Frame
    local section = Instance.new("Frame")
    section.Name = title:gsub("%s+", "")
    section.BackgroundColor3 = Theme.Colors.Surface
    section.BorderSizePixel = 0
    section.Size = UDim2.new(1, 0, 0, 0)
    section.AutomaticSize = Enum.AutomaticSize.Y
    section.LayoutOrder = order
    section.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.Sizes.BorderRadius)
    corner.Parent = section

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, Theme.Sizes.PaddingNormal)
    padding.PaddingBottom = UDim.new(0, Theme.Sizes.PaddingNormal)
    padding.PaddingLeft = UDim.new(0, Theme.Sizes.PaddingNormal)
    padding.PaddingRight = UDim.new(0, Theme.Sizes.PaddingNormal)
    padding.Parent = section

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
    layout.Parent = section

    -- Section title
    local titleLabel = Theme.createLabel({
        parent = section,
        text = title,
        font = Theme.Fonts.Bold,
        textSize = Theme.Sizes.TextSmall,
        textColor = Theme.Colors.TextMuted
    })
    titleLabel.LayoutOrder = 0

    return section
end

function SyncWidget:updateUI(state: Store.StoreState)
    -- Update status indicator
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
        statusText = "Error: " .. (state.lastError or "Unknown")
    end

    self.elements.statusDot.BackgroundColor3 = statusColor
    self.elements.statusLabel.Text = statusText

    -- Update connect button
    if state.syncStatus == "connected" then
        self.elements.connectBtn.Text = "Disconnect"
    else
        self.elements.connectBtn.Text = "Connect"
    end

    -- Update buttons state
    local canSync = state.syncStatus == "connected"
    self.elements.exportBtn.BackgroundTransparency = canSync and 0 or 0.5
    self.elements.pullBtn.BackgroundTransparency = canSync and 0 or 0.5

    -- Update pending changes section
    local hasPending = #state.pendingChanges > 0
    self.elements.changesSection.Visible = hasPending

    if hasPending then
        self.elements.changesLabel.Text = string.format("%d file(s) changed", #state.pendingChanges)
    end

    -- Update messages
    self:updateMessages(state.messages)
end

function SyncWidget:updateMessages(messages: {Store.ChatMessage})
    local scroll = self.elements.messagesScroll

    -- Clear existing messages
    for _, child in scroll:GetChildren() do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    -- Add messages (show last 10)
    local startIdx = math.max(1, #messages - 9)
    for i = startIdx, #messages do
        local msg = messages[i]
        local label = Theme.createLabel({
            parent = scroll,
            text = os.date("%H:%M", msg.timestamp) .. " " .. msg.content,
            textSize = Theme.Sizes.TextSmall,
            textColor = Theme.Colors.TextMuted
        })
        label.TextWrapped = true
        label.AutomaticSize = Enum.AutomaticSize.Y
        label.LayoutOrder = i
    end
end

function SyncWidget:updateScriptCount()
    local count = Export.getScriptCount()
    self.elements.scriptCountLabel.Text = string.format("Scripts: %d", count)
end

function SyncWidget:onConnect()
    local state = Store.getState()

    if state.syncStatus == "connected" then
        DaemonClient.disconnect()
    else
        local url = self.elements.urlInput.Text
        Store.setDaemonConfig(url, "")
        DaemonClient.connect()
    end
end

function SyncWidget:onExport()
    local state = Store.getState()
    if state.syncStatus ~= "connected" then
        return
    end

    task.spawn(function()
        local ok, msg = Export.exportAll()
        if ok then
            print("[DetAI]", msg)
        else
            warn("[DetAI] Export failed:", msg)
        end
    end)
end

function SyncWidget:onPull()
    local state = Store.getState()
    if state.syncStatus ~= "connected" then
        return
    end

    task.spawn(function()
        local ok, msg = Import.pullChanges()
        if ok then
            print("[DetAI]", msg)
        else
            warn("[DetAI] Pull failed:", msg)
        end
    end)
end

function SyncWidget:onApply()
    task.spawn(function()
        local ok, msg = Import.applyChanges()
        if ok then
            print("[DetAI]", msg)
        else
            warn("[DetAI] Apply failed:", msg)
        end
    end)
end

function SyncWidget:onCancelChanges()
    Store.setPendingChanges({})
end

function SyncWidget:destroy()
    for _, conn in pairs(self.connections) do
        if typeof(conn) == "function" then
            conn() -- unsubscribe
        elseif typeof(conn) == "RBXScriptConnection" then
            conn:Disconnect()
        end
    end

    if self.widget then
        self.widget:Destroy()
    end
end

export type SyncWidget = typeof(SyncWidget.new(nil :: any))

return SyncWidget
