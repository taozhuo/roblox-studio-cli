--!strict
--[[
    Bakable Studio Plugin
    Thin API bridge - exposes Roblox Studio APIs to the daemon
    UI is handled by the Bakable Desktop app (Tauri)
]]

local Store = require(script.State.Store)
local DaemonClient = require(script.Sync.DaemonClient)
local DevTools = require(script.DevTools)
local Elements = require(script.DevTools.Elements)
local Studio = require(script.DevTools.Studio)

-- Minimal status widget
local statusWidget: DockWidgetPluginGui? = nil
local statusLabel: TextLabel? = nil

-- Create minimal status indicator
local function createStatusWidget()
    local widgetInfo = DockWidgetPluginGuiInfo.new(
        Enum.InitialDockState.Float,
        false, -- disabled by default
        false,
        120, 32,
        120, 32
    )

    statusWidget = plugin:CreateDockWidgetPluginGui("Bakable_Status", widgetInfo)
    statusWidget.Title = "Bakable"
    statusWidget.Name = "Bakable_Status"

    -- Simple status display
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    frame.BorderSizePixel = 0
    frame.Parent = statusWidget

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(160, 160, 170)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 12
    label.Text = "Connecting..."
    label.Parent = frame

    statusLabel = label

    return statusWidget
end

-- Update status display
local function updateStatus(connected: boolean, message: string?)
    if statusLabel then
        if connected then
            statusLabel.TextColor3 = Color3.fromRGB(74, 222, 128)
            statusLabel.Text = message or "Connected"
        else
            statusLabel.TextColor3 = Color3.fromRGB(248, 113, 113)
            statusLabel.Text = message or "Disconnected"
        end
    end
end

-- Toolbar setup
local toolbar = plugin:CreateToolbar("Bakable")

local statusButton = toolbar:CreateButton(
    "Status",
    "Show Bakable connection status",
    "rbxassetid://4458901886"
)

statusButton.Click:Connect(function()
    if statusWidget then
        statusWidget.Enabled = not statusWidget.Enabled
    end
end)

-- Initialize
local function init()
    print("[Bakable] Initializing plugin (thin bridge mode)...")

    -- Pass plugin reference to DevTools modules
    Elements.setPlugin(plugin)
    Studio.setPlugin(plugin)

    -- Create minimal status widget
    createStatusWidget()

    -- Load saved token
    local savedToken = plugin:GetSetting("DaemonToken")
    if savedToken and savedToken ~= "" then
        Store.setDaemonConfig(Store.getState().daemonUrl, savedToken)
        print("[Bakable] Loaded saved daemon token")
    end

    -- Auto-connect to daemon
    task.spawn(function()
        task.wait(1)

        local connected = DaemonClient.connectFull()
        if connected then
            updateStatus(true, "Connected")
            print("[Bakable] Connected to daemon")
            -- Send session info to daemon
            DevTools.sendSessionInfo()
        else
            updateStatus(false, "No daemon")
            print("[Bakable] Daemon not available")
        end

        -- Periodic reconnection check
        while true do
            task.wait(10)
            local state = Store.getState()
            if state.connectionStatus == "connected" then
                updateStatus(true, "Connected")
            elseif state.connectionStatus == "connecting" then
                updateStatus(false, "Connecting...")
            else
                updateStatus(false, "Disconnected")
                -- Try to reconnect
                DaemonClient.connectFull()
            end
        end
    end)

    print("[Bakable] Plugin ready (UI in Bakable Desktop app)")
end

-- Cleanup
plugin.Unloading:Connect(function()
    print("[Bakable] Unloading plugin...")
    DaemonClient.disconnectWebSocket()

    if statusWidget then
        statusWidget:Destroy()
    end

    Store.reset()
end)

-- Start
init()
