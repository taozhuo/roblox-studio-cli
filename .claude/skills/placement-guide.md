---
name: placement-guide
description: Understanding CFrame, Pivot, and how to place objects correctly
---

# Object Placement Guide

## The Core Problem

You want to place a house at position (50, 0, 100). But:
- Does Y=0 mean the bottom touches ground, or the center is at ground?
- Where is the model's "origin" point?
- How do you rotate it to face a direction?

## Key Concepts

### 1. Position vs Pivot vs CFrame

```
Part.Position    = Center of the part (Vector3)
Part.CFrame      = Position + Rotation combined (CFrame)
Model:GetPivot() = The model's "handle point" (CFrame)
```

**Parts** have a center. Position (0, 5, 0) means the CENTER is at Y=5.

**Models** have a pivot. The pivot can be anywhere - center, bottom, or custom.

### 2. Why Models Are Confusing

A Model's pivot could be:
- At the center (default for many assets)
- At the bottom (good assets)
- Somewhere random (bad assets)

```
Model A (pivot at center):     Model B (pivot at bottom):
    ┌───┐                          ┌───┐
    │ ● │ ← pivot at center        │   │
    └───┘                          └─●─┘ ← pivot at bottom

PivotTo(0,0,0) puts center       PivotTo(0,0,0) puts bottom
at ground → half underground!    at ground → correct!
```

### 3. The Bounding Box Solution

Don't guess - measure the model:

```lua
local cf, size = model:GetBoundingBox()
-- cf = CFrame at center of bounding box
-- size = Vector3 (width, height, depth)

local bottomY = cf.Position.Y - size.Y/2  -- Bottom of model
local pivot = model:GetPivot()
local groundOffset = pivot.Position.Y - bottomY  -- Distance from pivot to bottom
```

**groundOffset** tells you how much to adjust:
- groundOffset = 0 → pivot is at bottom, place at Y=0
- groundOffset = 5 → pivot is 5 studs above bottom, place at Y=5

---

## Placement Methods

### Method 1: PivotTo (Recommended for Models)

```lua
-- Place model so its PIVOT is at this position
model:PivotTo(CFrame.new(50, groundOffset, 100))
```

PivotTo moves the entire model so the pivot point lands at the target.

### Method 2: Part.Position (Only for Parts)

```lua
-- Place part so its CENTER is at this position
part.Position = Vector3.new(50, part.Size.Y/2, 100)  -- Sits on ground
```

### Method 3: Part.CFrame (Position + Rotation)

```lua
-- Place AND rotate
part.CFrame = CFrame.new(50, 5, 100) * CFrame.Angles(0, math.rad(90), 0)
```

---

## Rotation Confusion

### The Problem

Roblox has multiple rotation systems with DIFFERENT orders:

| Method | Rotation Order | Example |
|--------|---------------|---------|
| `Part.Orientation` | Y → X → Z | `Vector3.new(0, 90, 0)` |
| `CFrame.Angles(x,y,z)` | Z → Y → X | `CFrame.Angles(0, math.rad(90), 0)` |
| `CFrame.fromEulerAnglesYXZ(y,x,z)` | Y → X → Z | Matches Orientation |

### Simple Solution: Use CFrame.Angles for Y rotation only

For placing objects, you usually only need Y rotation (yaw):

```lua
-- Rotate 90 degrees around Y axis (turn right)
local rotation = CFrame.Angles(0, math.rad(90), 0)

-- Place at position with rotation
model:PivotTo(CFrame.new(50, 0, 100) * rotation)
```

### Common Rotations

```lua
CFrame.Angles(0, math.rad(0), 0)    -- Facing default (-Z)
CFrame.Angles(0, math.rad(90), 0)   -- Facing -X (turned right)
CFrame.Angles(0, math.rad(180), 0)  -- Facing +Z (turned around)
CFrame.Angles(0, math.rad(270), 0)  -- Facing +X (turned left)
CFrame.Angles(0, math.rad(-90), 0)  -- Same as 270
```

### Point At Target

```lua
-- Make model face a target position
local pos = Vector3.new(50, 0, 100)
local target = Vector3.new(0, 0, 0)  -- Face toward origin

local lookAt = CFrame.lookAt(pos, target)
model:PivotTo(lookAt)
```

---

## Complete Placement Function

```lua
local function placeOnGround(model, x, z, rotationDegrees)
    -- 1. Get bounding box
    local cf, size = model:GetBoundingBox()

    -- 2. Calculate ground offset
    local bottomY = cf.Position.Y - size.Y/2
    local pivot = model:GetPivot()
    local groundOffset = pivot.Position.Y - bottomY

    -- 3. Create position (Y = groundOffset so bottom touches Y=0)
    local position = CFrame.new(x, groundOffset, z)

    -- 4. Create rotation (Y axis only)
    local rotation = CFrame.Angles(0, math.rad(rotationDegrees or 0), 0)

    -- 5. Combine and apply
    model:PivotTo(position * rotation)

    return {
        position = {x = x, y = groundOffset, z = z},
        rotation = rotationDegrees or 0,
        size = {x = size.X, y = size.Y, z = size.Z}
    }
end

-- Usage
local house = workspace.Assets.House:Clone()
house.Parent = workspace
placeOnGround(house, 50, 100, 90)  -- At (50, ?, 100) facing right
```

---

## Place on Terrain/Surface

Use raycast to find the ground height:

```lua
local function placeOnSurface(model, x, z, rotationDegrees)
    -- Raycast down to find ground
    local ray = workspace:Raycast(
        Vector3.new(x, 1000, z),  -- Start high
        Vector3.new(0, -2000, 0), -- Cast down
        RaycastParams.new()
    )

    local groundY = ray and ray.Position.Y or 0

    -- Get model info
    local cf, size = model:GetBoundingBox()
    local bottomY = cf.Position.Y - size.Y/2
    local pivot = model:GetPivot()
    local groundOffset = pivot.Position.Y - bottomY

    -- Place on ground
    local position = CFrame.new(x, groundY + groundOffset, z)
    local rotation = CFrame.Angles(0, math.rad(rotationDegrees or 0), 0)

    model:PivotTo(position * rotation)

    return { groundY = groundY, finalY = groundY + groundOffset }
end
```

---

## Quick Reference

| Task | Code |
|------|------|
| Move model | `model:PivotTo(CFrame.new(x, y, z))` |
| Rotate Y only | `CFrame.Angles(0, math.rad(degrees), 0)` |
| Move + rotate | `model:PivotTo(CFrame.new(x,y,z) * CFrame.Angles(0,rad,0))` |
| Get size | `local cf, size = model:GetBoundingBox()` |
| Get pivot | `model:GetPivot()` |
| Face target | `CFrame.lookAt(from, to)` |

## Common Mistakes

1. **Using Position on Models** - Models don't have Position, use PivotTo
2. **Forgetting groundOffset** - Model sinks into ground or floats
3. **Wrong rotation order** - Use CFrame.Angles for code, not Orientation values
4. **Assuming pivot is at bottom** - Always check with GetBoundingBox
