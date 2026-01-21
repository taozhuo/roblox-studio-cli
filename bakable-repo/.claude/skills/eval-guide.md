---
name: eval-guide
description: How to use studio.eval for building, testing, and interacting with Studio
---

# Eval Guide

`studio.eval` is the core tool for interacting with Roblox Studio. Use it for:
- **Building** - Create/modify instances, set properties, arrange scenes
- **Testing** - Run code during playtest, check game state
- **Querying** - Find instances, inspect properties, debug issues

## When to Use Eval vs Scripts

| Use `studio.eval` for | Use Script containers for |
|----------------------|---------------------------|
| Building the world | Game logic |
| Moving/arranging parts | Player interactions |
| Setting properties | RemoteEvents/Functions |
| Testing during playtest | Persistent behaviors |
| One-off commands | Reusable systems |
| Debugging | Production code |

## Building with Eval

### Create Instances
```lua
local part = Instance.new("Part")
part.Name = "Floor"
part.Size = Vector3.new(100, 1, 100)
part.Position = Vector3.new(0, 0, 0)
part.Anchored = true
part.Parent = workspace
return part:GetFullName()
```

### Create from Template
```lua
local template = game.ServerStorage.Templates.House
local house = template:Clone()
house.Name = "House_" .. #workspace.Buildings:GetChildren()
house:PivotTo(CFrame.new(50, 0, 50))
house.Parent = workspace.Buildings
return house:GetFullName()
```

### Bulk Operations
```lua
-- Color all parts in a model
local model = workspace.MyBuilding
local count = 0
for _, part in model:GetDescendants() do
    if part:IsA("BasePart") then
        part.BrickColor = BrickColor.new("Bright blue")
        count += 1
    end
end
return count .. " parts colored"
```

### Arrange in Grid
```lua
local spacing = 10
local cols = 5
for i = 0, 24 do
    local part = Instance.new("Part", workspace)
    part.Size = Vector3.new(4, 4, 4)
    part.Position = Vector3.new(
        (i % cols) * spacing,
        2,
        math.floor(i / cols) * spacing
    )
    part.Anchored = true
end
return "Created 25 parts in 5x5 grid"
```

## State Tracking

Always track what you create for undo/cleanup:

```lua
_G.bakable = _G.bakable or { created = {}, lastAction = nil }

local part = Instance.new("Part", workspace)
part.Name = "MyPart"
part.Anchored = true
table.insert(_G.bakable.created, part)
_G.bakable.lastAction = "Created " .. part.Name

return _G.bakable.lastAction
```

### Check What We've Done
```lua
local b = _G.bakable or {}
return {
    created = #(b.created or {}),
    lastAction = b.lastAction or "none"
}
```

### Undo/Cleanup
```lua
local count = 0
for _, inst in _G.bakable.created or {} do
    if inst and inst.Parent then
        inst:Destroy()
        count += 1
    end
end
_G.bakable.created = {}
return "Deleted " .. count .. " instances"
```

## Querying with Eval

### Find by Name
```lua
local results = {}
for _, inst in game:GetDescendants() do
    if inst.Name:match("^Spawn") then
        table.insert(results, inst:GetFullName())
    end
end
return results
```

### Find by Class
```lua
local parts = {}
for _, inst in workspace:GetDescendants() do
    if inst:IsA("Part") and not inst.Anchored then
        table.insert(parts, {
            name = inst.Name,
            path = inst:GetFullName(),
            position = inst.Position
        })
    end
end
return parts
```

### Find by Property
```lua
local transparent = {}
for _, part in workspace:GetDescendants() do
    if part:IsA("BasePart") and part.Transparency > 0.5 then
        table.insert(transparent, part:GetFullName())
    end
end
return transparent
```

## Testing with Eval

### During Playtest
```lua
-- Check player state
local player = game.Players:GetPlayers()[1]
if player and player.Character then
    local humanoid = player.Character:FindFirstChild("Humanoid")
    return {
        health = humanoid and humanoid.Health,
        position = player.Character:GetPivot().Position,
        speed = humanoid and humanoid.WalkSpeed
    }
end
return "No player"
```

### Test a Function
```lua
-- Call a module function
local MyModule = require(game.ReplicatedStorage.Modules.MyModule)
return MyModule.calculate(10, 20)
```

### Fire a Remote
```lua
-- Simulate client action
local remote = game.ReplicatedStorage.Remotes.BuyItem
local player = game.Players:GetPlayers()[1]
remote:FireClient(player, "Sword", 100)
return "Fired BuyItem to " .. player.Name
```

## Common Patterns

### Safe Instance Access
```lua
local part = workspace:FindFirstChild("MyPart", true)
if not part then
    return "MyPart not found"
end
part.Position = Vector3.new(0, 10, 0)
return "Moved " .. part.Name
```

### Create Folder Structure
```lua
local function ensureFolder(parent, name)
    return parent:FindFirstChild(name) or Instance.new("Folder", parent)
end

local maps = ensureFolder(workspace, "Maps")
local props = ensureFolder(maps, "Props")
local buildings = ensureFolder(maps, "Buildings")
return "Folders ready"
```

### Clone and Position
```lua
local template = game.ServerStorage.Props.Tree
local positions = {
    Vector3.new(10, 0, 10),
    Vector3.new(20, 0, 15),
    Vector3.new(30, 0, 10),
}

_G.bakable = _G.bakable or { created = {} }
for _, pos in positions do
    local tree = template:Clone()
    tree:PivotTo(CFrame.new(pos))
    tree.Parent = workspace.Props
    table.insert(_G.bakable.created, tree)
end
return "Placed " .. #positions .. " trees"
```

### Raycast to Ground
```lua
local function placeOnGround(position)
    local ray = workspace:Raycast(
        position + Vector3.new(0, 100, 0),
        Vector3.new(0, -200, 0)
    )
    if ray then
        return ray.Position
    end
    return position
end

local groundPos = placeOnGround(Vector3.new(50, 0, 50))
return "Ground at Y=" .. groundPos.Y
```

### Weld Parts Together
```lua
local part1 = workspace.Part1
local part2 = workspace.Part2

local weld = Instance.new("WeldConstraint")
weld.Part0 = part1
weld.Part1 = part2
weld.Parent = part1

return "Welded " .. part1.Name .. " to " .. part2.Name
```

## Return Values

Always return useful information:

```lua
-- Good: Returns actionable info
return {
    created = part:GetFullName(),
    position = part.Position,
    size = part.Size
}

-- Bad: No feedback
part.Position = Vector3.new(0, 10, 0)
-- (returns nil)
```

## Error Handling

```lua
local success, result = pcall(function()
    return workspace.NonExistent.Property
end)

if success then
    return result
else
    return "Error: " .. tostring(result)
end
```

## Tips

1. **Track state** - Use `_G.bakable` to remember what you created
2. **Return info** - Always return what you did for context
3. **Use PivotTo** - Better than setting Position for models
4. **Anchor parts** - Unless physics is needed
5. **Batch operations** - One eval with a loop beats many evals
6. **Check existence** - Use FindFirstChild before accessing
