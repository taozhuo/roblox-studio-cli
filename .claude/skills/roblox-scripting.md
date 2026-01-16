# Roblox Development Best Practices

## Two Modes of Development

### 1. Edit Time (studio.eval) - Creating Assets

Use `studio.eval` to create models, parts, UI directly. Objects persist in the place file.

**When to use:** Creating/modifying instances, building structures, setting up UI

```lua
-- Create a house directly via eval - no scripts needed
local house = Instance.new("Model")
house.Name = "House"

local floor = Instance.new("Part")
floor.Name = "Floor"
floor.Size = Vector3.new(20, 1, 20)
floor.Position = Vector3.new(0, 0, 0)
floor.Anchored = true
floor.Parent = house

local wall = Instance.new("Part")
wall.Name = "Wall"
wall.Size = Vector3.new(20, 10, 1)
wall.Position = Vector3.new(0, 5, -10)
wall.Anchored = true
wall.Parent = house

house.Parent = workspace
```

**Benefits:**
- Objects save with the place
- No runtime overhead
- Immediate visual feedback
- Can undo/redo in Studio

### 2. Runtime (Scripts) - Game Logic

Use Scripts for logic that runs when the game plays.

**When to use:** Player interactions, game mechanics, data persistence, multiplayer logic

## Script Architecture for Runtime

Use modular architecture:

1. **ModuleScripts** - Contains all logic (in ReplicatedStorage or ServerStorage)
2. **Server Script** - Entry point that requires modules (in ServerScriptService)
3. **Test Script** - For testing in Run mode (in ServerScriptService)

### ModuleScript Example

```lua
-- ModuleScript: ReplicatedStorage/Modules/CoinSystem
local CoinSystem = {}

local coins = {}

function CoinSystem.spawnCoin(position)
    local coin = Instance.new("Part")
    coin.Name = "Coin"
    coin.Shape = Enum.PartType.Cylinder
    coin.Size = Vector3.new(0.2, 2, 2)
    coin.Position = position
    coin.Anchored = true
    coin.BrickColor = BrickColor.new("Gold")
    coin.Parent = workspace.Coins
    table.insert(coins, coin)
    return coin
end

function CoinSystem.collectCoin(coin, player)
    local index = table.find(coins, coin)
    if index then
        table.remove(coins, index)
        coin:Destroy()
        return true
    end
    return false
end

return CoinSystem
```

### Entry Point Script

```lua
-- Script: ServerScriptService/Main
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoinSystem = require(ReplicatedStorage.Modules.CoinSystem)

-- Setup
local coinsFolder = Instance.new("Folder")
coinsFolder.Name = "Coins"
coinsFolder.Parent = workspace

-- Spawn initial coins
for i = 1, 10 do
    CoinSystem.spawnCoin(Vector3.new(math.random(-50, 50), 5, math.random(-50, 50)))
end

print("[Main] Game initialized with 10 coins")
```

### Test Script

```lua
-- Script: ServerScriptService/TestRunner (Disabled = true)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoinSystem = require(ReplicatedStorage.Modules.CoinSystem)

print("=== Running CoinSystem Tests ===")

-- Setup test folder
local testFolder = Instance.new("Folder")
testFolder.Name = "Coins"
testFolder.Parent = workspace

-- Test: spawnCoin
local coin = CoinSystem.spawnCoin(Vector3.new(0, 5, 0))
assert(coin ~= nil, "Coin should be created")
assert(coin.Parent == testFolder, "Coin should be in Coins folder")
print("PASS: spawnCoin")

-- Test: collectCoin
local collected = CoinSystem.collectCoin(coin, nil)
assert(collected == true, "Should return true on collect")
assert(coin.Parent == nil, "Coin should be destroyed")
print("PASS: collectCoin")

-- Cleanup
testFolder:Destroy()

print("=== All Tests Passed ===")
```

## Testing Workflow

1. **Create ModuleScript** with logic
2. **Create TestRunner** script (Disabled = true)
3. **Enable TestRunner**:
   ```lua
   game.ServerScriptService.TestRunner.Disabled = false
   ```
4. **Run playtest** in Run mode (F8): `studio.playtest.run`
5. **Check logs**: `studio.logs.getHistory`
6. **Stop playtest**: `studio.playtest.stop`
7. **Disable TestRunner**:
   ```lua
   game.ServerScriptService.TestRunner.Disabled = true
   ```

## When to Use What

| Task | Method | Why |
|------|--------|-----|
| Create a building | `studio.eval` | Edit-time, saves with place |
| Create UI layout | `studio.eval` | Edit-time, visual setup |
| Set part properties | `studio.eval` | Edit-time, immediate |
| Player movement | Script | Runtime logic |
| Coin collection | Script | Runtime interaction |
| Save player data | Script | Runtime persistence |
| Spawn enemies | Script | Runtime game loop |
| Setup RemoteEvents | `studio.eval` | Edit-time structure, runtime use |

## Hybrid Example: Setup + Logic

**Step 1: Create structure at edit time (studio.eval)**
```lua
-- Create the coin template
local coinTemplate = Instance.new("Part")
coinTemplate.Name = "CoinTemplate"
coinTemplate.Shape = Enum.PartType.Cylinder
coinTemplate.Size = Vector3.new(0.2, 2, 2)
coinTemplate.Anchored = true
coinTemplate.CanCollide = false
coinTemplate.BrickColor = BrickColor.new("Gold")
coinTemplate.Parent = game.ReplicatedStorage

-- Create coins folder
local coinsFolder = Instance.new("Folder")
coinsFolder.Name = "Coins"
coinsFolder.Parent = workspace

-- Create RemoteEvent for collection
local collectEvent = Instance.new("RemoteEvent")
collectEvent.Name = "CollectCoin"
collectEvent.Parent = game.ReplicatedStorage
```

**Step 2: Create runtime logic (Scripts)**
```lua
-- ModuleScript uses the template created at edit time
local CoinSystem = {}
local template = game.ReplicatedStorage.CoinTemplate

function CoinSystem.spawnCoin(position)
    local coin = template:Clone()
    coin.Position = position
    coin.Parent = workspace.Coins
    return coin
end

return CoinSystem
```

## Communication Between Scripts

Use **BindableEvents** for server script communication:

```lua
-- Create at edit time via eval
local event = Instance.new("BindableEvent")
event.Name = "OnCoinCollected"
event.Parent = game.ReplicatedStorage

-- Script A fires
game.ReplicatedStorage.OnCoinCollected:Fire(coinData)

-- Script B listens
game.ReplicatedStorage.OnCoinCollected.Event:Connect(function(data)
    print("Coin collected:", data)
end)
```

## Folder Structure

```
game
├── ReplicatedStorage
│   ├── Modules/           -- ModuleScripts (shared)
│   ├── CoinTemplate       -- Created via eval
│   ├── CollectCoin        -- RemoteEvent (via eval)
│   └── OnCoinCollected    -- BindableEvent (via eval)
├── ServerStorage
│   └── ServerModules/     -- Server-only ModuleScripts
├── ServerScriptService
│   ├── Main               -- Entry point Script
│   └── TestRunner         -- Test Script (Disabled)
└── workspace
    └── Coins/             -- Folder for runtime coins
```

## Key Rules

1. **Use eval for creating assets** - Models, parts, UI, events
2. **Use Scripts for runtime logic** - Game mechanics, interactions
3. **ModuleScripts for reusable code** - Never put logic in entry Scripts
4. **Test with Run mode (F8)** - Server-only, faster iteration
5. **Keep TestRunner disabled** - Only enable during testing
6. **Check logs after playtest** - Use studio.logs.getHistory
