---
name: tool-making
description: Creating Tools (weapons, items) that characters can equip and use
---

# Tool Making Guide

Tools are objects that players can pick up and use. Common examples: swords, guns, wands, building tools.

## Tool Structure

```
Tool (Instance)
├── Handle (Part) -- REQUIRED: The part the character holds
├── Blade (Part)  -- Optional: Additional parts welded to Handle
└── Script        -- Optional: Tool behavior
```

## Basic Tool via Eval

```lua
local tool = Instance.new("Tool")
tool.Name = "Sword"
tool.Parent = game.ServerStorage

-- Handle is REQUIRED
local handle = Instance.new("Part")
handle.Name = "Handle"  -- Must be named "Handle"
handle.Size = Vector3.new(0.6, 3.6, 0.4)  -- Blade shape
handle.BrickColor = BrickColor.new("Medium stone grey")
handle.Parent = tool

return tool:GetFullName()
```

## Grip Configuration

Tool Grip uses **direction vectors**, not angles. This avoids Roblox's confusing rotation order issues.

### The 3 Grip Vectors = Rotation Matrix

Think of it as: "Where does each Handle axis point when held?"

```
GripRight   = where Handle's X axis points (in world/hand space)
GripUp      = where Handle's Y axis points
GripForward = where Handle's Z axis points
```

These 3 vectors form an orthonormal basis (rotation matrix). They must be perpendicular to each other.

### Sword Example (Blade UP)

**Step 1: Check Handle size**
```
Size = (0.6, 3.6, 0.4)
       X     Y     Z
```
Y = 3.6 is longest → **Y axis is the blade**

**Step 2: Decide orientation when held**
- We want blade pointing UP → Handle's Y should point UP
- Character faces forward → Handle's X should point forward

**Step 3: Set Grip vectors**
```lua
tool.GripUp = Vector3.new(0, 1, 0)       -- Handle Y → World Y (blade UP)
tool.GripForward = Vector3.new(1, 0, 0)  -- Handle Z → World X (forward)
tool.GripRight = Vector3.new(0, 0, 1)    -- Handle X → World Z (right)
```

**Step 4: Set GripPos (where hand grabs)**
```lua
tool.GripPos = Vector3.new(0, -1.5, 0)
```

### GripPos Explained

GripPos offsets the Handle relative to the hand, **in Handle's local space**:

```
GripPos.Y negative → Handle moves DOWN → Hand grips the BOTTOM (handle)
GripPos.Y positive → Handle moves UP   → Hand grips the TOP (blade)
```

For a sword with Y=3.6 blade, use about half: `GripPos = (0, -1.5, 0)`

### Complete Sword Example

```lua
local tool = Instance.new("Tool")
tool.Name = "Sword"

-- Handle (the blade in this case)
local handle = Instance.new("Part")
handle.Name = "Handle"
handle.Size = Vector3.new(0.6, 3.6, 0.4)  -- Y is blade length
handle.BrickColor = BrickColor.new("Medium stone grey")
handle.Parent = tool

-- Grip: Blade UP, holding the handle end
tool.GripForward = Vector3.new(1, 0, 0)
tool.GripRight = Vector3.new(0, 0, 1)
tool.GripUp = Vector3.new(0, 1, 0)
tool.GripPos = Vector3.new(0, -1.5, 0)  -- Grip lower part (handle)

tool.Parent = game.ServerStorage
return "Created sword with proper grip"
```

### Different Orientations

**Blade pointing FORWARD (like a spear):**
```lua
-- If blade is along Y axis but you want it forward
tool.GripForward = Vector3.new(0, 1, 0)   -- Y axis points forward
tool.GripRight = Vector3.new(1, 0, 0)     -- X axis points right
tool.GripUp = Vector3.new(0, 0, 1)        -- Z axis points up
tool.GripPos = Vector3.new(0, -1.5, 0)    -- Offset along blade
```

**Horizontal tool (like a bat):**
```lua
tool.GripForward = Vector3.new(0, 0, 1)   -- Z forward
tool.GripRight = Vector3.new(0, 1, 0)     -- Y right (blade horizontal)
tool.GripUp = Vector3.new(1, 0, 0)        -- X up
tool.GripPos = Vector3.new(0, -1, 0)
```

## Tool Properties

| Property | Description |
|----------|-------------|
| `CanBeDropped` | Can player drop the tool (default: true) |
| `RequiresHandle` | Must have Handle part (default: true) |
| `ManualActivationOnly` | Disable auto-activate on equip |
| `ToolTip` | Text shown when hovering |

## Tool Events

```lua
-- In a Script inside the Tool
local tool = script.Parent

tool.Equipped:Connect(function(mouse)
    print("Equipped by", tool.Parent.Name)
end)

tool.Unequipped:Connect(function()
    print("Unequipped")
end)

tool.Activated:Connect(function()
    print("Used (clicked)")
end)
```

## Give Tool to Player

```lua
-- Give tool when player joins
local Players = game:GetService("Players")
local template = game.ServerStorage.Sword

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        local sword = template:Clone()
        sword.Parent = player.Backpack
    end)
end)
```

## Debugging Grip Issues

If the tool looks wrong when held:

1. **Check Handle exists** - Must be named exactly "Handle"
2. **Check Handle size** - Identify which axis is the blade
3. **Test GripPos sign** - Flip between positive/negative Y
4. **Visualize grip axes** - The three Grip vectors form a rotation matrix

```lua
-- Debug: Print current grip settings
local tool = workspace.Sword  -- or wherever it is
print("Size:", tool.Handle.Size)
print("GripPos:", tool.GripPos)
print("GripUp:", tool.GripUp)
print("GripForward:", tool.GripForward)
print("GripRight:", tool.GripRight)
```

## Quick Reference

| Desired Result | GripUp | GripForward | GripRight | GripPos.Y |
|---------------|--------|-------------|-----------|-----------|
| Blade UP (sword) | (0,1,0) | (1,0,0) | (0,0,1) | negative |
| Blade FORWARD (spear) | (0,0,1) | (0,1,0) | (1,0,0) | negative |
| Blade DOWN (dagger) | (0,-1,0) | (1,0,0) | (0,0,-1) | positive |

## Why Vectors Instead of Angles?

Roblox rotation is confusing due to different orders:

| Method | Order | Use Case |
|--------|-------|----------|
| `Part.Orientation` | Y → X → Z | Inspector property |
| `CFrame.Angles()` | Z → Y → X | Code (different!) |
| `CFrame.fromEulerAnglesYXZ()` | Y → X → Z | Matches Orientation |

**Tool Grip avoids this** by using direction vectors directly. No angle order confusion - just specify where each axis points.
