# Testable UI Architecture

Guide for writing UI code that can be tested without Roblox GUI, simulating client behavior in Lune or Studio command bar.

## Quick Start Example

**1. Create ReplicatedStorage/shared/ShopLogic.lua:**

```lua
local ShopLogic = {}

function ShopLogic.createState(gold, inventory)
    return {
        gold = gold or 100,
        inventory = inventory or {},
        maxSlots = 10
    }
end

function ShopLogic.canBuy(state, price)
    if state.gold < price then
        return false, "NOT_ENOUGH_GOLD"
    end
    if #state.inventory >= state.maxSlots then
        return false, "INVENTORY_FULL"
    end
    return true
end

function ShopLogic.buy(state, itemId, price)
    local ok, err = ShopLogic.canBuy(state, price)
    if not ok then return false, err end

    state.gold = state.gold - price
    table.insert(state.inventory, itemId)
    return true
end

function ShopLogic.sell(state, slotIndex, sellPrice)
    if not state.inventory[slotIndex] then
        return false, "INVALID_SLOT"
    end

    state.gold = state.gold + sellPrice
    table.remove(state.inventory, slotIndex)
    return true
end

return ShopLogic
```

**2. Test from Command Bar (paste and run):**

```lua
local Shop = require(game.ReplicatedStorage.shared.ShopLogic)

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed += 1 print("✅", name)
    else failed += 1 warn("❌", name, "-", err) end
end

test("buy success", function()
    local s = Shop.createState(100, {})
    local ok = Shop.buy(s, "sword", 50)
    assert(ok == true)
    assert(s.gold == 50)
    assert(s.inventory[1] == "sword")
end)

test("buy insufficient gold", function()
    local s = Shop.createState(10, {})
    local ok, err = Shop.buy(s, "sword", 50)
    assert(ok == false)
    assert(err == "NOT_ENOUGH_GOLD")
end)

test("buy inventory full", function()
    local s = Shop.createState(1000, {})
    s.maxSlots = 2
    Shop.buy(s, "a", 10)
    Shop.buy(s, "b", 10)
    local ok, err = Shop.buy(s, "c", 10)
    assert(err == "INVENTORY_FULL")
end)

test("sell success", function()
    local s = Shop.createState(100, {"sword"})
    Shop.sell(s, 1, 25)
    assert(s.gold == 125)
    assert(#s.inventory == 0)
end)

print(string.format("\n=== %d passed, %d failed ===", passed, failed))
```

**3. Use in Client (StarterPlayerScripts):**

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shop = require(ReplicatedStorage.shared.ShopLogic)

local state = Shop.createState(100, {})
local gui = script.Parent:WaitForChild("ShopGui")

gui.BuyButton.MouseButton1Click:Connect(function()
    local ok, err = Shop.buy(state, "potion", 25)
    if ok then
        gui.GoldLabel.Text = tostring(state.gold)
    else
        gui.ErrorLabel.Text = err
    end
end)
```

Zero Roblox dependencies in the logic = testable anywhere.

---

## Core Principle: State-Driven Architecture

Separate UI into three layers:
1. **State** - Pure data, no Roblox dependencies
2. **Actions** - Business logic with injectable dependencies
3. **View** - Roblox GUI rendering (thin layer)

```
┌─────────────────────────────────────────────────┐
│                    Tests                        │
│  (Lune or Studio - no GUI needed)               │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│              Actions (Logic)                    │
│  - Business rules, validation                   │
│  - Injectable services (network, audio, etc)    │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│              State (Data)                       │
│  - Observable state with subscriptions          │
│  - No Roblox dependencies                       │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────┐
│              View (Roblox GUI)                  │
│  - Renders state to GuiObjects                  │
│  - Binds input events to actions                │
│  - Only layer that needs real GUI               │
└─────────────────────────────────────────────────┘
```

## 1. State Module

Observable state container with change notifications:

```lua
-- shared/UIState.lua
local UIState = {}
UIState.__index = UIState

function UIState.new(initialState)
    local self = setmetatable({
        _listeners = {},
        _state = initialState or {}
    }, UIState)

    -- Copy initial state to top level for easy access
    for k, v in pairs(self._state) do
        self[k] = v
    end

    return self
end

function UIState:get(key)
    return self._state[key]
end

function UIState:set(key, value)
    local oldValue = self._state[key]
    if oldValue == value then return end

    self._state[key] = value
    self[key] = value
    self:_notify(key, value, oldValue)
end

function UIState:update(updates)
    for key, value in pairs(updates) do
        self:set(key, value)
    end
end

function UIState:subscribe(listener)
    table.insert(self._listeners, listener)
    return function()
        local idx = table.find(self._listeners, listener)
        if idx then table.remove(self._listeners, idx) end
    end
end

function UIState:_notify(key, newValue, oldValue)
    for _, listener in ipairs(self._listeners) do
        listener(key, newValue, oldValue)
    end
end

-- Snapshot for debugging/testing
function UIState:snapshot()
    local copy = {}
    for k, v in pairs(self._state) do
        copy[k] = v
    end
    return copy
end

return UIState
```

## 2. Actions Module

Business logic with dependency injection:

```lua
-- shared/InventoryActions.lua
local InventoryActions = {}
InventoryActions.__index = InventoryActions

-- Services are injected, not imported
function InventoryActions.new(state, services)
    return setmetatable({
        state = state,
        network = services.network,
        audio = services.audio,
        dataStore = services.dataStore
    }, InventoryActions)
end

function InventoryActions:buyItem(itemId, price)
    -- Validation
    if self.state.gold < price then
        return false, "INSUFFICIENT_GOLD"
    end

    if #self.state.inventory >= self.state.maxSlots then
        return false, "INVENTORY_FULL"
    end

    -- Update state
    self.state:set("gold", self.state.gold - price)

    local inventory = table.clone(self.state.inventory)
    table.insert(inventory, itemId)
    self.state:set("inventory", inventory)

    -- Side effects (mockable)
    self.audio:play("Coins")
    self.network:fireServer("BuyItem", itemId)

    return true
end

function InventoryActions:sellItem(slotIndex)
    local inventory = self.state.inventory
    local item = inventory[slotIndex]

    if not item then
        return false, "INVALID_SLOT"
    end

    -- Get item value (would come from item database)
    local value = self:getItemValue(item)

    -- Update state
    self.state:set("gold", self.state.gold + value)

    local newInventory = table.clone(inventory)
    table.remove(newInventory, slotIndex)
    self.state:set("inventory", newInventory)

    self.audio:play("Sell")
    self.network:fireServer("SellItem", slotIndex)

    return true
end

function InventoryActions:selectSlot(index)
    if index == self.state.selectedSlot then
        self.state:set("selectedSlot", nil) -- Deselect
    else
        self.state:set("selectedSlot", index)
    end
end

function InventoryActions:useItem(slotIndex)
    local item = self.state.inventory[slotIndex]
    if not item then return false, "INVALID_SLOT" end

    -- Item-specific logic
    if item.type == "consumable" then
        local newInventory = table.clone(self.state.inventory)
        table.remove(newInventory, slotIndex)
        self.state:set("inventory", newInventory)
        self.network:fireServer("UseItem", slotIndex)
    end

    return true
end

function InventoryActions:getItemValue(item)
    -- Would normally look up in item database
    return item.value or 10
end

return InventoryActions
```

## 3. Mock Services for Testing

```lua
-- test/MockServices.lua
local MockServices = {}

function MockServices.new()
    return {
        network = MockServices.createNetwork(),
        audio = MockServices.createAudio(),
        dataStore = MockServices.createDataStore()
    }
end

function MockServices.createNetwork()
    return {
        _sent = {},
        _received = {},

        fireServer = function(self, event, ...)
            table.insert(self._sent, {event = event, args = {...}})
        end,

        -- Simulate server response
        simulateResponse = function(self, event, ...)
            table.insert(self._received, {event = event, args = {...}})
        end,

        -- Assert helpers
        assertSent = function(self, event)
            for _, msg in ipairs(self._sent) do
                if msg.event == event then return true end
            end
            error("Expected network event: " .. event)
        end,

        clear = function(self)
            self._sent = {}
            self._received = {}
        end
    }
end

function MockServices.createAudio()
    return {
        _played = {},

        play = function(self, soundName)
            table.insert(self._played, soundName)
        end,

        assertPlayed = function(self, soundName)
            if not table.find(self._played, soundName) then
                error("Expected sound: " .. soundName)
            end
        end,

        clear = function(self)
            self._played = {}
        end
    }
end

function MockServices.createDataStore()
    return {
        _data = {},

        get = function(self, key)
            return self._data[key]
        end,

        set = function(self, key, value)
            self._data[key] = value
        end,

        clear = function(self)
            self._data = {}
        end
    }
end

return MockServices
```

## 4. View Layer (Roblox-Specific)

The view is thin - it just renders state and binds events:

```lua
-- client/InventoryView.lua
local InventoryView = {}
InventoryView.__index = InventoryView

function InventoryView.new(gui: ScreenGui, state, actions)
    local self = setmetatable({
        gui = gui,
        state = state,
        actions = actions,
        slotFrames = {}
    }, InventoryView)

    self:_setupSlots()
    self:_bindState()

    return self
end

function InventoryView:_setupSlots()
    local container = self.gui.InventoryFrame.Slots

    for i, slot in ipairs(container:GetChildren()) do
        if slot:IsA("GuiButton") then
            self.slotFrames[i] = slot

            -- Bind click to action
            slot.MouseButton1Click:Connect(function()
                self.actions:selectSlot(i)
            end)

            slot.MouseButton2Click:Connect(function()
                self.actions:useItem(i)
            end)
        end
    end
end

function InventoryView:_bindState()
    self.state:subscribe(function(key, value)
        if key == "inventory" then
            self:_renderInventory(value)
        elseif key == "selectedSlot" then
            self:_renderSelection(value)
        elseif key == "gold" then
            self:_renderGold(value)
        end
    end)

    -- Initial render
    self:_renderInventory(self.state.inventory)
    self:_renderGold(self.state.gold)
end

function InventoryView:_renderInventory(items)
    for i, slot in ipairs(self.slotFrames) do
        local item = items[i]
        if item then
            slot.ItemIcon.Image = item.icon
            slot.ItemIcon.Visible = true
            slot.CountLabel.Text = item.count and tostring(item.count) or ""
        else
            slot.ItemIcon.Visible = false
            slot.CountLabel.Text = ""
        end
    end
end

function InventoryView:_renderSelection(selectedIndex)
    for i, slot in ipairs(self.slotFrames) do
        slot.SelectionBorder.Visible = (i == selectedIndex)
    end
end

function InventoryView:_renderGold(amount)
    self.gui.GoldLabel.Text = tostring(amount)
end

return InventoryView
```

## 5. Writing Tests

Tests run without any GUI:

```lua
-- test/InventoryTests.lua
local UIState = require("shared.UIState")
local InventoryActions = require("shared.InventoryActions")
local MockServices = require("test.MockServices")

local function createTestContext()
    local state = UIState.new({
        gold = 100,
        inventory = {},
        maxSlots = 10,
        selectedSlot = nil
    })
    local mocks = MockServices.new()
    local actions = InventoryActions.new(state, mocks)

    return state, actions, mocks
end

-- Test: Buying an item
local function test_buyItem_success()
    local state, actions, mocks = createTestContext()

    local success = actions:buyItem("sword", 50)

    assert(success == true, "Buy should succeed")
    assert(state.gold == 50, "Gold should decrease")
    assert(#state.inventory == 1, "Inventory should have 1 item")
    mocks.audio:assertPlayed("Coins")
    mocks.network:assertSent("BuyItem")

    print("✅ test_buyItem_success")
end

-- Test: Insufficient gold
local function test_buyItem_insufficient_gold()
    local state, actions, mocks = createTestContext()
    state:set("gold", 10)

    local success, err = actions:buyItem("sword", 50)

    assert(success == false, "Buy should fail")
    assert(err == "INSUFFICIENT_GOLD", "Should return error code")
    assert(state.gold == 10, "Gold should be unchanged")
    assert(#state.inventory == 0, "Inventory should be empty")
    assert(#mocks.network._sent == 0, "No network call")

    print("✅ test_buyItem_insufficient_gold")
end

-- Test: Inventory full
local function test_buyItem_inventory_full()
    local state, actions, mocks = createTestContext()
    state:set("maxSlots", 2)
    state:set("inventory", {"item1", "item2"})

    local success, err = actions:buyItem("sword", 10)

    assert(success == false)
    assert(err == "INVENTORY_FULL")

    print("✅ test_buyItem_inventory_full")
end

-- Test: Select/deselect slot
local function test_selectSlot_toggle()
    local state, actions = createTestContext()

    actions:selectSlot(1)
    assert(state.selectedSlot == 1)

    actions:selectSlot(1) -- Same slot = deselect
    assert(state.selectedSlot == nil)

    actions:selectSlot(2)
    assert(state.selectedSlot == 2)

    print("✅ test_selectSlot_toggle")
end

-- Run all tests
local function runTests()
    print("=== Inventory Tests ===")
    test_buyItem_success()
    test_buyItem_insufficient_gold()
    test_buyItem_inventory_full()
    test_selectSlot_toggle()
    print("=== All tests passed ===")
end

return runTests
```

## 6. Simulating User Flows

Test complete user journeys:

```lua
-- test/UserFlowTests.lua
local function test_shopping_session()
    local state, actions, mocks = createTestContext()
    state:set("gold", 500)

    -- User browses and buys multiple items
    assert(actions:buyItem("potion", 25))
    assert(actions:buyItem("potion", 25))
    assert(actions:buyItem("sword", 200))

    -- User tries to buy expensive item
    local ok, err = actions:buyItem("legendary_armor", 300)
    assert(not ok and err == "INSUFFICIENT_GOLD")

    -- User sells an item to afford armor
    state.inventory[1] = {id = "potion", value = 50}
    assert(actions:sellItem(1))

    -- Now can afford armor
    assert(actions:buyItem("armor", 250))

    -- Final state
    assert(state.gold == 50)
    assert(#state.inventory == 3)

    print("✅ Shopping session flow")
end

local function test_inventory_management()
    local state, actions = createTestContext()
    state:set("inventory", {
        {id = "sword", type = "equipment"},
        {id = "potion", type = "consumable"},
        {id = "shield", type = "equipment"}
    })

    -- Select item
    actions:selectSlot(2)
    assert(state.selectedSlot == 2)

    -- Use consumable (removes it)
    actions:useItem(2)
    assert(#state.inventory == 2)
    assert(state.inventory[2].id == "shield") -- Shield shifted up

    print("✅ Inventory management flow")
end
```

## 7. Testing State Subscriptions

Verify UI would update correctly:

```lua
local function test_state_notifications()
    local state = UIState.new({ gold = 100 })
    local notifications = {}

    state:subscribe(function(key, newVal, oldVal)
        table.insert(notifications, {
            key = key,
            new = newVal,
            old = oldVal
        })
    end)

    state:set("gold", 150)
    state:set("gold", 150) -- Same value, should not notify
    state:set("gold", 200)

    assert(#notifications == 2, "Should have 2 notifications")
    assert(notifications[1].old == 100)
    assert(notifications[1].new == 150)
    assert(notifications[2].old == 150)
    assert(notifications[2].new == 200)

    print("✅ State notifications work correctly")
end
```

## 8. GUI Validation Tests

Test GUI layout issues (requires runtime):

```lua
-- Run in Studio during playtest
local function validateGUI(screenGui: ScreenGui)
    local issues = {}

    -- Check for overlapping buttons
    local buttons = {}
    for _, desc in screenGui:GetDescendants() do
        if desc:IsA("GuiButton") and desc.Visible then
            table.insert(buttons, desc)
        end
    end

    for i = 1, #buttons do
        for j = i + 1, #buttons do
            local a, b = buttons[i], buttons[j]
            if not a:IsDescendantOf(b) and not b:IsDescendantOf(a) then
                if guiOverlaps(a, b) then
                    table.insert(issues, {
                        type = "OVERLAP",
                        a = a:GetFullName(),
                        b = b:GetFullName()
                    })
                end
            end
        end
    end

    -- Check for buttons too small to click
    for _, btn in buttons do
        local size = btn.AbsoluteSize
        if size.X < 44 or size.Y < 44 then
            table.insert(issues, {
                type = "TOO_SMALL",
                element = btn:GetFullName(),
                size = {size.X, size.Y}
            })
        end
    end

    -- Check for elements outside parent bounds
    for _, el in screenGui:GetDescendants() do
        if el:IsA("GuiObject") and el.Visible then
            local parent = el.Parent
            if parent:IsA("GuiObject") and not parent.ClipsDescendants then
                local pPos, pSize = parent.AbsolutePosition, parent.AbsoluteSize
                local ePos, eSize = el.AbsolutePosition, el.AbsoluteSize

                if ePos.X < pPos.X or ePos.Y < pPos.Y
                   or ePos.X + eSize.X > pPos.X + pSize.X
                   or ePos.Y + eSize.Y > pPos.Y + pSize.Y then
                    table.insert(issues, {
                        type = "OUT_OF_BOUNDS",
                        element = el:GetFullName()
                    })
                end
            end
        end
    end

    return issues
end

local function guiOverlaps(a: GuiObject, b: GuiObject): boolean
    local aPos, aSize = a.AbsolutePosition, a.AbsoluteSize
    local bPos, bSize = b.AbsolutePosition, b.AbsoluteSize

    return aPos.X < bPos.X + bSize.X
       and aPos.X + aSize.X > bPos.X
       and aPos.Y < bPos.Y + bSize.Y
       and aPos.Y + aSize.Y > bPos.Y
end
```

## Code Organization: Shared vs Client

### Roblox Execution Contexts

```
┌─────────────────────────────────────────────────────────┐
│                      SERVER ONLY                        │
│  ServerScriptService/  - Scripts run here               │
│  ServerStorage/        - Server-only assets/data        │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                   REPLICATED (SHARED)                   │
│  ReplicatedStorage/    - Both server & client can see   │
│  ReplicatedFirst/      - Client loads this first        │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                      CLIENT ONLY                        │
│  StarterPlayerScripts/ - LocalScripts run here          │
│  StarterGui/           - Player GUI                     │
│  StarterPack/          - Tools                          │
└─────────────────────────────────────────────────────────┘
```

### What "Shared" Means

"Shared" = ModuleScripts in `ReplicatedStorage` with **no server or client specific APIs**.

They can be `require()`d by both:
- Server Scripts (in ServerScriptService)
- Client LocalScripts (in StarterPlayerScripts)

### What Goes Where

| ReplicatedStorage/shared/ | StarterPlayerScripts/client/ |
|---------------------------|------------------------------|
| State management | GUI element references |
| Business rules/validation | Button click connections |
| Data transformations | Rendering/updating visuals |
| Error codes/messages | Tweens, animations |
| Item databases | Sound effects |
| Math/utility functions | Camera controls |

### What CAN'T Be Shared

```lua
-- SERVER ONLY APIs - can't use in shared code
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- CLIENT ONLY APIs - can't use in shared code
local UserInputService = game:GetService("UserInputService")
local Players.LocalPlayer  -- nil on server
local PlayerGui            -- doesn't exist on server
local StarterGui           -- not the live GUI
```

### File Structure in Roblox

```
game
├── ReplicatedStorage/
│   └── shared/                    # TESTABLE - no Roblox dependencies
│       ├── UIState.lua            # State container
│       ├── InventoryActions.lua   # Buy/sell/use logic
│       ├── ShopActions.lua        # Shop logic
│       ├── ValidationRules.lua    # Input validation
│       └── ItemDatabase.lua       # Item definitions
│
├── ServerScriptService/
│   └── server/                    # SERVER ONLY
│       ├── DataManager.lua        # DataStoreService
│       ├── GameLoop.lua           # Game state
│       └── PurchaseHandler.lua    # Validate purchases
│
├── StarterPlayerScripts/
│   └── client/                    # CLIENT ONLY - thin layer
│       ├── InventoryView.lua      # Binds GUI to state
│       ├── ShopView.lua           # Binds GUI to state
│       └── InputHandler.lua       # UserInputService
│
└── StarterGui/
    └── ScreenGuis...              # GUI assets
```

### The 80/20 Rule

Aim for:
- **80-90%** of UI code in `ReplicatedStorage/shared/` (testable)
- **10-20%** in `StarterPlayerScripts/client/` (just wiring)

### Example: Shared Logic

```lua
-- ReplicatedStorage/shared/ShopActions.lua
-- No Roblox-specific APIs - pure logic
local ShopActions = {}

function ShopActions.canBuy(state, itemId, price)
    if state.gold < price then
        return false, "NOT_ENOUGH_GOLD"
    end
    if #state.inventory >= state.maxSlots then
        return false, "INVENTORY_FULL"
    end
    return true
end

function ShopActions.buy(state, itemId, price)
    local canBuy, err = ShopActions.canBuy(state, itemId, price)
    if not canBuy then return false, err end

    state:set("gold", state.gold - price)
    local inv = table.clone(state.inventory)
    table.insert(inv, itemId)
    state:set("inventory", inv)
    return true
end

return ShopActions
```

### Example: Thin Client View

```lua
-- StarterPlayerScripts/client/ShopView.lua
-- Only GUI binding - no business logic
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShopActions = require(ReplicatedStorage.shared.ShopActions)

local ShopView = {}

function ShopView.new(gui, state)
    local self = {gui = gui, state = state}

    -- Bind button to shared action
    gui.BuyButton.MouseButton1Click:Connect(function()
        local item = self.selectedItem
        local ok, err = ShopActions.buy(state, item.id, item.price)

        if not ok then
            self:showError(err)  -- Client-only: show error
        else
            self:playSound("Purchase")  -- Client-only: audio
        end
    end)

    -- Bind state changes to GUI updates
    state:subscribe(function(key, value)
        if key == "gold" then
            gui.GoldLabel.Text = tostring(value)
        end
    end)

    return self
end

return ShopView
```

### Testing in Studio

**TestService** (server-side) can test shared modules:

```lua
-- ServerScriptService/TestRunner.server.lua
local TestService = game:GetService("TestService")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then return end

local UIState = require(game.ReplicatedStorage.shared.UIState)
local ShopActions = require(game.ReplicatedStorage.shared.ShopActions)

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        TestService:Message("✅ " .. name)
    else
        TestService:Error("❌ " .. name .. ": " .. tostring(err))
    end
end

test("ShopActions.canBuy with enough gold", function()
    local state = UIState.new({gold = 100, inventory = {}, maxSlots = 10})
    local canBuy = ShopActions.canBuy(state, "sword", 50)
    assert(canBuy == true)
end)

test("ShopActions.canBuy insufficient gold", function()
    local state = UIState.new({gold = 10, inventory = {}, maxSlots = 10})
    local canBuy, err = ShopActions.canBuy(state, "sword", 50)
    assert(canBuy == false)
    assert(err == "NOT_ENOUGH_GOLD")
end)
```

**LocalScript** for client-only tests (GUI validation):

```lua
-- StarterPlayerScripts/ClientTestRunner.client.lua
local RunService = game:GetService("RunService")
if not RunService:IsStudio() then return end

task.wait(2) -- Wait for GUI to load

local player = game:GetService("Players").LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Now can test client-specific things
local function test(name, fn)
    local ok, err = pcall(fn)
    print(ok and "✅" or "❌", name, ok and "" or err)
end

test("Inventory GUI loaded", function()
    assert(playerGui:FindFirstChild("InventoryGui"))
end)

test("Buy button is large enough", function()
    local btn = playerGui.ShopGui.BuyButton
    assert(btn.AbsoluteSize.X >= 44)
    assert(btn.AbsoluteSize.Y >= 44)
end)
```

## Benefits

1. **90% testable without GUI** - State and Actions have no Roblox dependencies
2. **Fast iteration** - Run tests in Lune instantly, no Studio needed
3. **Reliable** - Business logic tested separately from rendering
4. **Easy debugging** - State snapshots show exactly what happened
5. **Refactorable** - Change Views without touching logic
