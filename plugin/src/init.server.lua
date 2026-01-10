--!strict
--[[
    Bakable Studio Plugin - Minimal test version
]]

print("[Bakable] === PLUGIN STARTING ===")

-- Test 1: Basic print
print("[Bakable] Test 1: Basic print works")

-- Test 2: Load Store
local ok1, Store = pcall(function()
    return require(script.State.Store)
end)
print("[Bakable] Test 2: Store loaded:", ok1)

-- Test 3: Load DaemonClient
local ok2, DaemonClient = pcall(function()
    return require(script.Sync.DaemonClient)
end)
print("[Bakable] Test 3: DaemonClient loaded:", ok2)

-- Test 4: Load Elements
local ok3, Elements = pcall(function()
    return require(script.DevTools.Elements)
end)
print("[Bakable] Test 4: Elements loaded:", ok3)

-- Test 5: Load Studio
local ok4, Studio = pcall(function()
    return require(script.DevTools.Studio)
end)
print("[Bakable] Test 5: Studio loaded:", ok4)

if not (ok1 and ok2 and ok3 and ok4) then
    warn("[Bakable] Module load failed - check errors above")
    return
end

print("[Bakable] All modules loaded OK")

-- Test 6: Create widget
local ok5, widgetErr = pcall(function()
    local widgetInfo = DockWidgetPluginGuiInfo.new(
        Enum.InitialDockState.Float,
        true,
        false,
        180, 120,
        180, 120
    )
    local widget = plugin:CreateDockWidgetPluginGui("Bakable_Tools", widgetInfo)
    widget.Title = "Bakable"

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    frame.Parent = widget

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = "Bakable OK"
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Parent = frame
end)
print("[Bakable] Test 6: Widget created:", ok5)
if not ok5 then warn("[Bakable] Widget error:", widgetErr) end

-- Test 7: Connect to daemon
task.spawn(function()
    print("[Bakable] Test 7: Connecting to daemon...")
    local connected = DaemonClient.connectFull()
    print("[Bakable] Test 7: Daemon connected:", connected)
end)

print("[Bakable] === PLUGIN READY ===")
