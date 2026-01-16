# Roblox Scripting Best Practices

## Script Architecture

Always use a modular architecture:

1. **ModuleScripts** - Contains all logic (in ReplicatedStorage or ServerStorage)
2. **Server Script** - Entry point that requires and calls modules (in ServerScriptService)
3. **Test Script** - Separate script to test in Run mode (in ServerScriptService)

## Creating Scripts

### Step 1: Create ModuleScript with Logic

Place in `ReplicatedStorage` (if shared) or `ServerStorage` (server-only):

```lua
-- ModuleScript: ReplicatedStorage/Modules/HouseBuilder
local HouseBuilder = {}

function HouseBuilder.createWall(parent, position, size)
    local wall = Instance.new("Part")
    wall.Name = "Wall"
    wall.Anchored = true
    wall.Position = position
    wall.Size = size
    wall.Parent = parent
    return wall
end

function HouseBuilder.createHouse(position)
    local house = Instance.new("Model")
    house.Name = "House"

    -- Create walls
    HouseBuilder.createWall(house, position + Vector3.new(0, 5, -10), Vector3.new(20, 10, 1))
    HouseBuilder.createWall(house, position + Vector3.new(0, 5, 10), Vector3.new(20, 10, 1))
    HouseBuilder.createWall(house, position + Vector3.new(-10, 5, 0), Vector3.new(1, 10, 20))
    HouseBuilder.createWall(house, position + Vector3.new(10, 5, 0), Vector3.new(1, 10, 20))

    house.Parent = workspace
    return house
end

return HouseBuilder
```

### Step 2: Create Entry Point Script

Place in `ServerScriptService`:

```lua
-- Script: ServerScriptService/Main
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HouseBuilder = require(ReplicatedStorage.Modules.HouseBuilder)

-- Initialize game systems
print("[Main] Starting game...")

-- Example: Create a house when game starts
local house = HouseBuilder.createHouse(Vector3.new(0, 0, 0))
print("[Main] House created:", house.Name)
```

### Step 3: Create Test Script

Place in `ServerScriptService`, disabled by default:

```lua
-- Script: ServerScriptService/TestRunner (Disabled = true)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HouseBuilder = require(ReplicatedStorage.Modules.HouseBuilder)

print("=== Running Tests ===")

-- Test 1: Create wall
local testWall = HouseBuilder.createWall(workspace, Vector3.new(0, 5, 0), Vector3.new(10, 10, 1))
assert(testWall:IsA("Part"), "Wall should be a Part")
assert(testWall.Anchored == true, "Wall should be anchored")
print("PASS: createWall")
testWall:Destroy()

-- Test 2: Create house
local testHouse = HouseBuilder.createHouse(Vector3.new(50, 0, 0))
assert(testHouse:IsA("Model"), "House should be a Model")
assert(#testHouse:GetChildren() >= 4, "House should have at least 4 walls")
print("PASS: createHouse")
testHouse:Destroy()

print("=== All Tests Passed ===")
```

## Testing Workflow

1. **Create the ModuleScript** with your logic
2. **Create a TestRunner script** in ServerScriptService (keep it Disabled)
3. **Enable TestRunner** temporarily: `studio.eval` to set `Disabled = false`
4. **Run playtest** in Run mode (F8): `studio.playtest.run`
5. **Check logs**: `studio.logs.getHistory`
6. **Stop playtest**: `studio.playtest.stop`
7. **Disable TestRunner** again after testing

## Tool Usage Pattern

When asked to create a feature:

```
1. studio.scripts.create - Create ModuleScript in ReplicatedStorage/Modules/
2. studio.scripts.create - Create entry Script in ServerScriptService/
3. studio.scripts.create - Create TestRunner in ServerScriptService/ (Disabled)
4. studio.eval - Enable TestRunner: game.ServerScriptService.TestRunner.Disabled = false
5. studio.playtest.run - Start Run mode
6. studio.logs.getHistory - Check test output
7. studio.playtest.stop - Stop playtest
8. studio.eval - Disable TestRunner: game.ServerScriptService.TestRunner.Disabled = true
```

## Communication Between Scripts

Use **BindableEvents** for server-to-server script communication:

```lua
-- ModuleScript: Create event
local Events = {}
Events.OnHouseBuilt = Instance.new("BindableEvent")

function Events.fireHouseBuilt(house)
    Events.OnHouseBuilt:Fire(house)
end

return Events

-- Another script: Listen
local Events = require(ReplicatedStorage.Modules.Events)
Events.OnHouseBuilt.Event:Connect(function(house)
    print("House was built:", house.Name)
end)
```

## Folder Structure

```
game
├── ReplicatedStorage
│   └── Modules
│       ├── HouseBuilder (ModuleScript)
│       ├── Events (ModuleScript)
│       └── Utils (ModuleScript)
├── ServerStorage
│   └── ServerModules
│       └── DataManager (ModuleScript)
├── ServerScriptService
│   ├── Main (Script) - Entry point
│   └── TestRunner (Script, Disabled) - Tests
└── StarterGui
    └── UI (ScreenGui)
```

## Key Rules

1. **Never put logic directly in Scripts** - Always use ModuleScripts
2. **Scripts are entry points only** - Just require modules and call functions
3. **Test with Run mode (F8)** - Server-only, no client needed
4. **Use BindableEvents** for script-to-script communication
5. **Keep TestRunner disabled** - Only enable during testing
6. **Check logs after playtest** - Use studio.logs.getHistory
