--!strict
--[[
    DetAI Studio Plugin
    Main entry point - creates UI widgets and manages plugin lifecycle
]]

local SyncWidget = require(script.UI.SyncWidget)
local ChatWidget = require(script.UI.ChatWidget)
local Store = require(script.State.Store)
local DaemonClient = require(script.Sync.DaemonClient)
local Elements = require(script.DevTools.Elements)
local Studio = require(script.DevTools.Studio)

-- Plugin state
local syncWidget: SyncWidget.SyncWidget? = nil
local chatWidget: ChatWidget.ChatWidget? = nil

-- Toolbar setup
local toolbar = plugin:CreateToolbar("DetAI")

local syncButton = toolbar:CreateButton(
    "Sync",
    "Open DetAI Sync Panel",
    "rbxassetid://4458901886" -- sync icon
)

local chatButton = toolbar:CreateButton(
    "Chat",
    "Open DetAI Chat Panel",
    "rbxassetid://4458901886" -- chat icon
)

-- Toggle sync widget
syncButton.Click:Connect(function()
    if syncWidget then
        syncWidget.widget.Enabled = not syncWidget.widget.Enabled
    end
end)

-- Toggle chat widget
chatButton.Click:Connect(function()
    if chatWidget then
        chatWidget.widget.Enabled = not chatWidget.widget.Enabled
    end
end)

-- Initialize widgets
local function init()
    print("[DetAI] Initializing plugin...")

    -- Pass plugin reference to modules that need it
    Elements.setPlugin(plugin)
    Studio.setPlugin(plugin)

    -- Load saved token from plugin settings if available
    local savedToken = plugin:GetSetting("DaemonToken")
    if savedToken and savedToken ~= "" then
        Store.setDaemonConfig(Store.getState().daemonUrl, savedToken)
        print("[DetAI] Loaded saved daemon token")
    end

    -- Create widgets
    syncWidget = SyncWidget.new(plugin)
    syncWidget:create()

    chatWidget = ChatWidget.new(plugin)
    chatWidget:create()

    -- Try to auto-connect to daemon (HTTP + WebSocket)
    task.spawn(function()
        task.wait(1) -- Small delay for Studio to settle
        local connected = DaemonClient.connectFull()
        if connected then
            print("[DetAI] Connected to daemon with HTTP + WebSocket")
        else
            print("[DetAI] Failed to connect to daemon")
        end
    end)

    print("[DetAI] Plugin initialized")
end

-- Cleanup on unload
plugin.Unloading:Connect(function()
    print("[DetAI] Unloading plugin...")

    -- Disconnect WebSocket
    DaemonClient.disconnectWebSocket()

    if syncWidget then
        syncWidget:destroy()
    end

    if chatWidget then
        chatWidget:destroy()
    end

    Store.reset()
end)

-- Start
init()
