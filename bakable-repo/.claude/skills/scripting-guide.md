---
name: scripting-guide
description: Writing game logic scripts (ServerScripts, LocalScripts, ModuleScripts)
---

# Scripting Guide

Use **script containers** for game logic. Use **eval** for building and testing.

| Container | Location | Runs On | Purpose |
|-----------|----------|---------|---------|
| Script | ServerScriptService | Server | Game logic, data, NPCs |
| LocalScript | StarterPlayerScripts | Client | UI, input, local effects |
| ModuleScript | ReplicatedStorage | Both | Shared code/config |

## Script Locations

```
game
├── ServerScriptService/     -- Server scripts (not replicated)
│   ├── GameManager.server.lua
│   └── DataStore.server.lua
├── StarterPlayer/
│   └── StarterPlayerScripts/ -- Client scripts
│       └── InputHandler.client.lua
├── ReplicatedStorage/       -- Shared (replicated to clients)
│   ├── Modules/
│   │   ├── Config.lua
│   │   └── Utils.lua
│   └── Remotes/            -- RemoteEvents/Functions
└── ServerStorage/          -- Server-only assets
    └── Templates/
```

## Creating Scripts via Eval

```lua
-- Create a server script
local script = Instance.new("Script")
script.Name = "GameManager"
script.Source = [[
print("Game started!")
-- Game logic here
]]
script.Parent = game.ServerScriptService
return script:GetFullName()
```

```lua
-- Create a LocalScript
local script = Instance.new("LocalScript")
script.Name = "InputHandler"
script.Source = [[
local UIS = game:GetService("UserInputService")
UIS.InputBegan:Connect(function(input)
    print("Key pressed:", input.KeyCode)
end)
]]
script.Parent = game.StarterPlayer.StarterPlayerScripts
return script:GetFullName()
```

## Using studio.scripts Tools

```lua
-- List all scripts
studio.scripts.list()

-- Read script source
studio.scripts.read({ path = "game/ServerScriptService/GameManager" })

-- Write script source
studio.scripts.write({
    path = "game/ServerScriptService/GameManager",
    source = "print('Hello')"
})

-- Create new script
studio.scripts.create({
    path = "game/ServerScriptService/NewScript",
    source = "-- New script",
    scriptType = "Script"  -- or "LocalScript", "ModuleScript"
})
```

## Server Scripts

Location: `ServerScriptService`

```lua
-- game/ServerScriptService/RoundManager.server.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Modules.Config)
local StartRoundEvent = ReplicatedStorage.Remotes.StartRound

local currentRound = 0

local function startRound()
    currentRound += 1
    print("Round", currentRound, "starting!")

    -- Notify all clients
    StartRoundEvent:FireAllClients(currentRound)

    task.wait(Config.ROUND_DURATION)
    endRound()
end

local function endRound()
    print("Round", currentRound, "ended!")
end

-- Start game when enough players
Players.PlayerAdded:Connect(function()
    if #Players:GetPlayers() >= Config.MIN_PLAYERS then
        startRound()
    end
end)
```

## Local Scripts

Location: `StarterPlayerScripts` or `StarterGui`

```lua
-- game/StarterPlayer/StarterPlayerScripts/Movement.client.lua

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

-- Sprint on Shift
local normalSpeed = 16
local sprintSpeed = 32

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.LeftShift then
        character.Humanoid.WalkSpeed = sprintSpeed
    end
end)

UIS.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftShift then
        character.Humanoid.WalkSpeed = normalSpeed
    end
end)
```

## Module Scripts

Location: `ReplicatedStorage` (shared) or `ServerStorage` (server-only)

```lua
-- game/ReplicatedStorage/Modules/Config.lua

local Config = {
    -- Game settings
    MIN_PLAYERS = 2,
    MAX_PLAYERS = 10,
    ROUND_DURATION = 120,

    -- Economy
    STARTING_CASH = 100,
    KILL_REWARD = 25,

    -- Debug
    DEBUG_MODE = true,
}

return Config
```

```lua
-- game/ReplicatedStorage/Modules/Utils.lua

local Utils = {}

function Utils.formatTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", mins, secs)
end

function Utils.randomPosition(min, max)
    return Vector3.new(
        math.random(min.X, max.X),
        math.random(min.Y, max.Y),
        math.random(min.Z, max.Z)
    )
end

return Utils
```

## Client-Server Communication

### Setup Remotes via Eval

```lua
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = game.ReplicatedStorage

local function createRemote(name, isFunction)
    local class = isFunction and "RemoteFunction" or "RemoteEvent"
    local remote = Instance.new(class)
    remote.Name = name
    remote.Parent = remotes
    return remote
end

createRemote("StartRound", false)
createRemote("PlayerDied", false)
createRemote("BuyItem", false)
createRemote("GetPlayerData", true)

return "Created remotes"
```

### Server Handling

```lua
-- ServerScriptService/RemoteHandler.server.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage.Remotes

Remotes.BuyItem.OnServerEvent:Connect(function(player, itemName)
    print(player.Name, "wants to buy", itemName)
    -- Validate and process purchase
end)

Remotes.GetPlayerData.OnServerInvoke = function(player)
    return {
        cash = 100,
        inventory = {"Sword", "Shield"}
    }
end
```

### Client Calling

```lua
-- StarterPlayerScripts/Shop.client.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage.Remotes

-- Fire event (no return)
Remotes.BuyItem:FireServer("Sword")

-- Invoke function (waits for return)
local data = Remotes.GetPlayerData:InvokeServer()
print("My cash:", data.cash)
```

## Testing Scripts with Eval

### Check Script Running

```lua
-- See if script is enabled
local script = game.ServerScriptService:FindFirstChild("GameManager")
return script and script.Enabled
```

### Call Module Function

```lua
local Utils = require(game.ReplicatedStorage.Modules.Utils)
return Utils.formatTime(125)  -- "02:05"
```

### Simulate Remote Call

```lua
local remote = game.ReplicatedStorage.Remotes.BuyItem
local player = game.Players:GetPlayers()[1]
-- Directly call the handler (server-side)
remote:Fire(player, "TestItem")
return "Simulated BuyItem"
```

## Best Practices

1. **Use ModuleScripts** for shared code/config
2. **Never trust client** - validate all RemoteEvent data on server
3. **Use task.spawn/defer** for non-blocking operations
4. **Require once** - cache module references
5. **Name scripts clearly** - `*.server.lua`, `*.client.lua`, `*.lua` (module)

## Script vs Eval

| Task | Use |
|------|-----|
| Build/arrange world | `studio.eval` |
| Test during playtest | `studio.eval` |
| One-off commands | `studio.eval` |
| Persistent game logic | Script containers |
| Player interactions | Script containers |
| Production code | Script containers |
