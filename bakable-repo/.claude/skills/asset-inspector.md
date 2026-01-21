---
name: asset-inspector
description: ALWAYS inspect model size before placing. Use catalog or eval to get dimensions.
---

# Asset Inspector

**CRITICAL: ALWAYS inspect model size BEFORE placing it.**

Eval doesn't know model sizes. You MUST either:
1. Check the asset catalog JSON
2. Inspect via eval first

## Step 1: Check Asset Catalog

Read `bakable-repo/asset-catalog.json` first:

```json
{
  "name": "Rock1",
  "path": "Workspace/Oletro's Stud Asset Pack/Rocks/Rock1",
  "size": {"x": 5, "y": 2, "z": 3.5},
  "footprint": {"x": 5, "z": 3.5},
  "groundOffset": 1,
  "pivotAtBottom": false
}
```

Key fields:
- `size` - Full bounding box (X, Y, Z)
- `footprint` - Ground area (X, Z) for spacing
- `groundOffset` - How much to raise Y for proper grounding
- `pivotAtBottom` - If false, need to adjust placement

## Step 2: Inspect Unknown Models via Eval

If model not in catalog, inspect it first:

```lua
local function inspectModel(path)
    local model = game
    for _, part in path:split("/") do
        model = model:FindFirstChild(part)
        if not model then return { error = "Not found: " .. part } end
    end

    if not model:IsA("Model") then
        return { error = "Not a Model" }
    end

    local cf, size = model:GetBoundingBox()
    local pivot = model:GetPivot()

    -- Check if pivot is at bottom
    local bottomY = cf.Position.Y - size.Y/2
    local pivotFromBottom = pivot.Position.Y - bottomY

    return {
        name = model.Name,
        path = model:GetFullName(),
        size = {x = size.X, y = size.Y, z = size.Z},
        footprint = {x = size.X, z = size.Z},
        pivotAtBottom = pivotFromBottom < 0.5,
        groundOffset = pivotFromBottom,
        primaryPart = model.PrimaryPart and model.PrimaryPart.Name or "NONE"
    }
end

return inspectModel("Workspace/Assets/MyHouse")
```

## Step 3: Inspect All Models in Folder

```lua
local function inspectFolder(folderPath)
    local folder = game
    for _, part in folderPath:split("/") do
        folder = folder:FindFirstChild(part)
        if not folder then return { error = "Folder not found" } end
    end

    local results = {}
    for _, model in folder:GetChildren() do
        if model:IsA("Model") then
            local cf, size = model:GetBoundingBox()
            local pivot = model:GetPivot()
            local bottomY = cf.Position.Y - size.Y/2

            table.insert(results, {
                name = model.Name,
                size = {x = math.floor(size.X), y = math.floor(size.Y), z = math.floor(size.Z)},
                footprint = {x = math.floor(size.X), z = math.floor(size.Z)},
                groundOffset = math.floor((pivot.Position.Y - bottomY) * 10) / 10
            })
        end
    end

    return {
        folder = folderPath,
        count = #results,
        models = results
    }
end

return inspectFolder("Workspace/Oletro's Stud Asset Pack/Trees")
```

## Step 4: Place with Correct Height

Once you know the model info:

```lua
local function placeModel(templatePath, position)
    -- Get template
    local template = game
    for _, part in templatePath:split("/") do
        template = template:FindFirstChild(part)
    end

    -- Inspect it
    local cf, size = template:GetBoundingBox()
    local pivot = template:GetPivot()
    local bottomY = cf.Position.Y - size.Y/2
    local groundOffset = pivot.Position.Y - bottomY

    -- Clone and place
    local clone = template:Clone()
    clone.Parent = workspace

    -- Adjust Y for proper grounding
    local adjustedY = position.Y + groundOffset
    clone:PivotTo(CFrame.new(position.X, adjustedY, position.Z))

    return {
        placed = clone.Name,
        at = {x = position.X, y = adjustedY, z = position.Z},
        groundOffset = groundOffset
    }
end

return placeModel("ServerStorage/Assets/House1", Vector3.new(50, 0, 50))
```

## Normalize Pivot (Fix Bad Assets)

If pivot is not at bottom, normalize it:

```lua
local function normalizeModelPivot(model)
    if not model.PrimaryPart then
        model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
    end
    if not model.PrimaryPart then
        return { error = "No BasePart found" }
    end

    local cf, size = model:GetBoundingBox()
    local bottomCenter = cf * CFrame.new(0, -size.Y/2, 0)
    local pivotOffset = model.PrimaryPart.CFrame:Inverse() * bottomCenter
    model.PrimaryPart.PivotOffset = pivotOffset

    return {
        normalized = model.Name,
        newGroundOffset = 0
    }
end
```

## Quick Reference

| Task | Method |
|------|--------|
| Known asset | Read `asset-catalog.json` |
| Unknown asset | `inspectModel()` via eval |
| Bulk inspect | `inspectFolder()` via eval |
| Bad pivot | `normalizeModelPivot()` |
| Place correctly | Add `groundOffset` to Y |

## Rules

1. **NEVER** place a model without knowing its size
2. **ALWAYS** check catalog first, then inspect if missing
3. **ALWAYS** account for `groundOffset` when placing
4. **USE** the `asset-cataloger` subagent for bulk normalization
5. **TRACK** placed models in `_G.bakable.created`
