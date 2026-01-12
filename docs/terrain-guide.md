# Roblox Terrain Programming Guide

A comprehensive guide to manipulating terrain programmatically in Roblox.

## Table of Contents

1. [Basics](#basics)
2. [Fill Methods](#fill-methods)
3. [Voxel Manipulation](#voxel-manipulation)
4. [Sculpting Tools](#sculpting-tools)
5. [Procedural Generation](#procedural-generation)
6. [Materials Reference](#materials-reference)
7. [Performance Tips](#performance-tips)
8. [MCP Tool Examples](#mcp-tool-examples)

---

## Basics

### What is Terrain?

Roblox terrain is a **voxel-based system** where each voxel is a 4x4x4 stud cube that contains:
- **Material** - What the voxel is made of (Grass, Rock, Water, etc.)
- **Occupancy** - How "full" the voxel is (0.0 = empty, 1.0 = full)

```lua
local Terrain = workspace.Terrain
```

### Coordinate System

- Terrain grid is aligned to 4-stud increments
- Regions must be expanded to grid: `region:ExpandToGrid(4)`
- Resolution parameter is always `4`

---

## Fill Methods

### FillBall
Creates a sphere of terrain.

```lua
Terrain:FillBall(
    Vector3.new(0, 10, 0),  -- center position
    20,                      -- radius (studs)
    Enum.Material.Rock       -- material
)
```

### FillBlock
Creates a box of terrain (supports rotation).

```lua
Terrain:FillBlock(
    CFrame.new(0, 10, 0) * CFrame.Angles(0, math.rad(45), 0),  -- position + rotation
    Vector3.new(50, 10, 30),  -- size
    Enum.Material.Grass       -- material
)
```

### FillCylinder
Creates a cylinder of terrain.

```lua
Terrain:FillCylinder(
    CFrame.new(0, 10, 0),  -- position (Y-axis is cylinder axis by default)
    20,                     -- height
    10,                     -- radius
    Enum.Material.Sand      -- material
)

-- Horizontal cylinder (rotate 90 degrees on X)
Terrain:FillCylinder(
    CFrame.new(0, 10, 0) * CFrame.Angles(math.rad(90), 0, 0),
    50,   -- length
    5,    -- radius
    Enum.Material.Rock
)
```

### FillWedge
Creates a wedge/ramp of terrain.

```lua
Terrain:FillWedge(
    CFrame.new(0, 10, 0),   -- position
    Vector3.new(20, 10, 30), -- size
    Enum.Material.Grass      -- material
)
```

### FillRegion
Fills an axis-aligned box region.

```lua
local region = Region3.new(
    Vector3.new(-50, 0, -50),  -- min corner
    Vector3.new(50, 20, 50)    -- max corner
):ExpandToGrid(4)

Terrain:FillRegion(region, 4, Enum.Material.Grass)
```

### Clear Terrain

```lua
-- Clear a ball-shaped area
Terrain:FillBall(position, radius, Enum.Material.Air)

-- Clear entire terrain
Terrain:Clear()
```

---

## Voxel Manipulation

For fine-grained control, use `ReadVoxels` and `WriteVoxels`.

### Reading Voxels

```lua
local region = Region3.new(
    Vector3.new(-20, -20, -20),
    Vector3.new(20, 20, 20)
):ExpandToGrid(4)

local materials, occupancies = Terrain:ReadVoxels(region, 4)

-- materials and occupancies are 3D arrays
-- Access: materials[x][y][z], occupancies[x][y][z]
local size = materials.Size  -- Vector3 with dimensions

for x = 1, size.X do
    for y = 1, size.Y do
        for z = 1, size.Z do
            local mat = materials[x][y][z]   -- Enum.Material
            local occ = occupancies[x][y][z] -- 0.0 to 1.0
        end
    end
end
```

### Writing Voxels

```lua
-- Modify the arrays
occupancies[5][5][5] = 0.5  -- Half-filled voxel
materials[5][5][5] = Enum.Material.Rock

-- Write back
Terrain:WriteVoxels(region, 4, materials, occupancies)
```

### Replace Material

```lua
local region = Region3.new(
    Vector3.new(-100, -10, -100),
    Vector3.new(100, 50, 100)
):ExpandToGrid(4)

-- Replace all Grass with Sand in region
Terrain:ReplaceMaterial(
    region,
    4,
    Enum.Material.Grass,  -- source
    Enum.Material.Sand    -- target
)
```

---

## Sculpting Tools

### Erode (Remove Material Gradually)

```lua
local function erode(centerPos, radius, strength)
    local region = Region3.new(
        centerPos - Vector3.new(radius, radius, radius),
        centerPos + Vector3.new(radius, radius, radius)
    ):ExpandToGrid(4)

    local materials, occupancies = Terrain:ReadVoxels(region, 4)
    local size = materials.Size
    local center = Vector3.new(size.X/2, size.Y/2, size.Z/2)

    for x = 1, size.X do
        for y = 1, size.Y do
            for z = 1, size.Z do
                local dist = (Vector3.new(x, y, z) - center).Magnitude
                local falloff = math.max(0, 1 - dist / (radius / 4))

                occupancies[x][y][z] = math.max(0,
                    occupancies[x][y][z] - strength * falloff
                )
            end
        end
    end

    Terrain:WriteVoxels(region, 4, materials, occupancies)
end

-- Usage
erode(Vector3.new(0, 10, 0), 20, 0.3)
```

### Grow (Add Material Gradually)

```lua
local function grow(centerPos, radius, strength, material)
    local region = Region3.new(
        centerPos - Vector3.new(radius, radius, radius),
        centerPos + Vector3.new(radius, radius, radius)
    ):ExpandToGrid(4)

    local materials, occupancies = Terrain:ReadVoxels(region, 4)
    local size = materials.Size
    local center = Vector3.new(size.X/2, size.Y/2, size.Z/2)

    for x = 1, size.X do
        for y = 1, size.Y do
            for z = 1, size.Z do
                local dist = (Vector3.new(x, y, z) - center).Magnitude
                local falloff = math.max(0, 1 - dist / (radius / 4))

                local newOcc = occupancies[x][y][z] + strength * falloff
                if newOcc > 0 then
                    occupancies[x][y][z] = math.min(1, newOcc)
                    materials[x][y][z] = material
                end
            end
        end
    end

    Terrain:WriteVoxels(region, 4, materials, occupancies)
end
```

### Smooth

```lua
local function smooth(centerPos, radius, strength)
    local region = Region3.new(
        centerPos - Vector3.new(radius, radius, radius),
        centerPos + Vector3.new(radius, radius, radius)
    ):ExpandToGrid(4)

    local materials, occupancies = Terrain:ReadVoxels(region, 4)
    local size = materials.Size
    local newOccupancies = table.clone(occupancies)  -- Copy

    for x = 2, size.X - 1 do
        for y = 2, size.Y - 1 do
            for z = 2, size.Z - 1 do
                -- Average with neighbors
                local sum = 0
                local count = 0

                for dx = -1, 1 do
                    for dy = -1, 1 do
                        for dz = -1, 1 do
                            sum = sum + occupancies[x+dx][y+dy][z+dz]
                            count = count + 1
                        end
                    end
                end

                local avg = sum / count
                local current = occupancies[x][y][z]
                newOccupancies[x][y][z] = current + (avg - current) * strength
            end
        end
    end

    Terrain:WriteVoxels(region, 4, materials, newOccupancies)
end
```

### Flatten

```lua
local function flatten(centerPos, radius, targetHeight, strength)
    local region = Region3.new(
        centerPos - Vector3.new(radius, 50, radius),
        centerPos + Vector3.new(radius, 50, radius)
    ):ExpandToGrid(4)

    local materials, occupancies = Terrain:ReadVoxels(region, 4)
    local size = materials.Size
    local regionMin = region.CFrame.Position - region.Size/2

    for x = 1, size.X do
        for z = 1, size.Z do
            -- Check if within circular brush
            local worldX = regionMin.X + (x - 1) * 4
            local worldZ = regionMin.Z + (z - 1) * 4
            local dist = math.sqrt(
                (worldX - centerPos.X)^2 + (worldZ - centerPos.Z)^2
            )

            if dist < radius then
                local falloff = 1 - (dist / radius)^2

                for y = 1, size.Y do
                    local worldY = regionMin.Y + (y - 1) * 4
                    local diff = worldY - targetHeight

                    if diff > 0 then
                        -- Above target: reduce
                        occupancies[x][y][z] = math.max(0,
                            occupancies[x][y][z] - strength * falloff
                        )
                    elseif diff > -4 then
                        -- At target: set to edge
                        local targetOcc = 1 - (diff + 4) / 4
                        local current = occupancies[x][y][z]
                        occupancies[x][y][z] = current +
                            (targetOcc - current) * strength * falloff
                    end
                end
            end
        end
    end

    Terrain:WriteVoxels(region, 4, materials, occupancies)
end
```

### Paint (Change Material Only)

```lua
local function paint(centerPos, radius, material)
    local region = Region3.new(
        centerPos - Vector3.new(radius, radius, radius),
        centerPos + Vector3.new(radius, radius, radius)
    ):ExpandToGrid(4)

    local materials, occupancies = Terrain:ReadVoxels(region, 4)
    local size = materials.Size
    local center = Vector3.new(size.X/2, size.Y/2, size.Z/2)

    for x = 1, size.X do
        for y = 1, size.Y do
            for z = 1, size.Z do
                local dist = (Vector3.new(x, y, z) - center).Magnitude

                -- Only paint existing terrain within radius
                if dist < radius / 4 and occupancies[x][y][z] > 0 then
                    materials[x][y][z] = material
                end
            end
        end
    end

    Terrain:WriteVoxels(region, 4, materials, occupancies)
end
```

---

## Natural Erosion Techniques

Creating natural-looking terrain requires **smooth transitions** rather than hard edges.

### The Problem: Hard Edges

```
HARD EDGE (artificial):           NATURAL TRANSITION (smooth):

████████░░░░░░██████████          ████████▓▒░░░░▒▓████████
████████░░░░░░██████████          ███████▓▒░░░░░░▒▓███████
████████░░░░░░██████████          ██████▓▒░░░░░░░░▒▓██████

█ = full (1.0)  ░ = empty (0.0)   ▓ = 0.7   ▒ = 0.3
```

### Key Principles

| Technique | Description |
|-----------|-------------|
| **Gradual occupancy** | Use `0.7`, `0.5`, `0.3` instead of just `0` or `1` |
| **Cosine falloff** | Smooth curve from center to edge |
| **Perlin noise** | Irregular, organic edges |
| **Material zones** | Water → Mud → Ground → Grass transitions |
| **Width/depth variation** | Natural features aren't uniform |
| **Path meandering** | Rivers and creeks wobble naturally |

### Natural Erode with Smooth Falloff

```lua
local function naturalErode(centerPos, radius, depth)
    local region = Region3.new(
        centerPos - Vector3.new(radius * 1.5, depth + 5, radius * 1.5),
        centerPos + Vector3.new(radius * 1.5, 5, radius * 1.5)
    ):ExpandToGrid(4)

    local materials, occupancies = Terrain:ReadVoxels(region, 4)
    local size = materials.Size
    local regionMin = region.CFrame.Position - region.Size / 2

    for x = 1, size.X do
        for y = 1, size.Y do
            for z = 1, size.Z do
                local worldPos = regionMin + Vector3.new((x-1)*4, (y-1)*4, (z-1)*4)

                -- Horizontal distance from center
                local horizDist = math.sqrt(
                    (worldPos.X - centerPos.X)^2 +
                    (worldPos.Z - centerPos.Z)^2
                )

                -- Normalized distance (0 = center, 1 = edge)
                local t = horizDist / radius

                if t < 1 then
                    -- SMOOTH FALLOFF using cosine curve
                    -- Center: remove more, Edge: remove less
                    local falloff = (1 + math.cos(t * math.pi)) / 2

                    -- Calculate how much to erode at this depth
                    local verticalFactor = math.max(0, 1 - (centerPos.Y - worldPos.Y) / depth)

                    -- Apply erosion with smooth transition
                    local erodeAmount = falloff * verticalFactor
                    occupancies[x][y][z] = math.max(0, occupancies[x][y][z] - erodeAmount)
                end
            end
        end
    end

    Terrain:WriteVoxels(region, 4, materials, occupancies)
end
```

### Natural Erode with Noise (Organic Edges)

```lua
local function naturalErodeWithNoise(centerPos, radius, depth, seed)
    seed = seed or math.random(1, 10000)

    local region = Region3.new(
        centerPos - Vector3.new(radius * 1.5, depth + 5, radius * 1.5),
        centerPos + Vector3.new(radius * 1.5, 5, radius * 1.5)
    ):ExpandToGrid(4)

    local materials, occupancies = Terrain:ReadVoxels(region, 4)
    local size = materials.Size
    local regionMin = region.CFrame.Position - region.Size / 2

    for x = 1, size.X do
        for y = 1, size.Y do
            for z = 1, size.Z do
                local worldPos = regionMin + Vector3.new((x-1)*4, (y-1)*4, (z-1)*4)

                -- Add noise to radius (irregular edges)
                local noiseValue = math.noise(
                    worldPos.X / 10 + seed,
                    worldPos.Z / 10 + seed
                )
                local noisyRadius = radius * (0.8 + noiseValue * 0.4)  -- ±20% variation

                local horizDist = math.sqrt(
                    (worldPos.X - centerPos.X)^2 +
                    (worldPos.Z - centerPos.Z)^2
                )

                local t = horizDist / noisyRadius

                if t < 1 then
                    -- Smooth falloff + depth noise
                    local falloff = (1 + math.cos(t * math.pi)) / 2

                    -- Add vertical noise too
                    local depthNoise = math.noise(worldPos.X/8, worldPos.Y/8, worldPos.Z/8 + seed)
                    local noisyDepth = depth * (0.7 + depthNoise * 0.6)

                    local verticalFactor = math.max(0, 1 - (centerPos.Y - worldPos.Y) / noisyDepth)

                    local erodeAmount = falloff * verticalFactor
                    occupancies[x][y][z] = math.max(0, occupancies[x][y][z] - erodeAmount)
                end
            end
        end
    end

    Terrain:WriteVoxels(region, 4, materials, occupancies)
end
```

### Erode with Material Transitions

Creates natural banks with material zones: Water → Mud → Ground → Grass

```lua
local function erodeWithMaterialTransition(centerPos, radius, depth, seed)
    seed = seed or math.random(1, 10000)

    local region = Region3.new(
        centerPos - Vector3.new(radius * 2, depth + 5, radius * 2),
        centerPos + Vector3.new(radius * 2, 5, radius * 2)
    ):ExpandToGrid(4)

    local materials, occupancies = Terrain:ReadVoxels(region, 4)
    local size = materials.Size
    local regionMin = region.CFrame.Position - region.Size / 2

    for x = 1, size.X do
        for y = 1, size.Y do
            for z = 1, size.Z do
                local worldPos = regionMin + Vector3.new((x-1)*4, (y-1)*4, (z-1)*4)

                local noiseValue = math.noise(worldPos.X/10 + seed, worldPos.Z/10 + seed)
                local noisyRadius = radius * (0.8 + noiseValue * 0.4)

                local horizDist = math.sqrt(
                    (worldPos.X - centerPos.X)^2 +
                    (worldPos.Z - centerPos.Z)^2
                )

                local t = horizDist / noisyRadius

                if t < 1.5 then  -- Extend beyond erode radius for material transition

                    if t < 1 then
                        -- ERODE ZONE: Remove terrain
                        local falloff = (1 + math.cos(t * math.pi)) / 2
                        local verticalFactor = math.max(0, 1 - (centerPos.Y - worldPos.Y) / depth)
                        occupancies[x][y][z] = math.max(0, occupancies[x][y][z] - falloff * verticalFactor)

                        -- Riverbed material
                        if occupancies[x][y][z] > 0 and t < 0.5 then
                            materials[x][y][z] = Enum.Material.Mud
                        end

                    elseif t < 1.2 and occupancies[x][y][z] > 0 then
                        -- MUD BANK: Transition zone
                        materials[x][y][z] = Enum.Material.Mud

                    elseif t < 1.5 and occupancies[x][y][z] > 0 then
                        -- DIRT EDGE: Outer transition
                        materials[x][y][z] = Enum.Material.Ground
                    end
                    -- Beyond 1.5: Keep original material (Grass, etc.)
                end
            end
        end
    end

    Terrain:WriteVoxels(region, 4, materials, occupancies)
end
```

### Bezier Curves for Smooth Paths

Instead of straight lines between points, use Bezier curves for natural-looking rivers and creeks.

```lua
-- Quadratic Bezier: 3 control points
local function bezierQuadratic(p0, p1, p2, t)
    local u = 1 - t
    return u*u*p0 + 2*u*t*p1 + t*t*p2
end

-- Cubic Bezier: 4 control points (smoother)
local function bezierCubic(p0, p1, p2, p3, t)
    local u = 1 - t
    return u*u*u*p0 + 3*u*u*t*p1 + 3*u*t*t*p2 + t*t*t*p3
end

-- Generate points along a Bezier curve
local function sampleBezierPath(controlPoints, samples)
    local path = {}

    for i = 0, samples do
        local t = i / samples
        local point

        if #controlPoints == 3 then
            point = bezierQuadratic(
                controlPoints[1],
                controlPoints[2],
                controlPoints[3],
                t
            )
        elseif #controlPoints == 4 then
            point = bezierCubic(
                controlPoints[1],
                controlPoints[2],
                controlPoints[3],
                controlPoints[4],
                t
            )
        end

        table.insert(path, point)
    end

    return path
end
```

### Complete Natural Creek Generator

Combines all techniques: smooth falloff, noise, material transitions, and path meandering.

```lua
local function carveNaturalCreek(points, width, depth)
    local seed = math.random(1, 10000)

    for i = 1, #points - 1 do
        local p1, p2 = points[i], points[i + 1]
        local direction = (p2 - p1).Unit
        local distance = (p2 - p1).Magnitude

        -- Sample along path
        for t = 0, distance, 3 do  -- Every 3 studs
            local pos = p1 + direction * t

            -- Add meandering (path wobbles naturally)
            local wobble = math.noise(t / 20 + seed, i) * width * 0.3
            local perpendicular = direction:Cross(Vector3.yAxis).Unit
            pos = pos + perpendicular * wobble

            -- Vary width naturally
            local widthNoise = math.noise(t / 15 + seed * 2, i)
            local localWidth = width * (0.8 + widthNoise * 0.4)

            -- Vary depth naturally
            local depthNoise = math.noise(t / 25 + seed * 3, i)
            local localDepth = depth * (0.7 + depthNoise * 0.6)

            -- Carve with natural transition
            erodeWithMaterialTransition(pos, localWidth, localDepth, seed + t)
        end

        task.wait()  -- Prevent timeout
    end

    -- Second pass: Add water with natural level variation
    for i = 1, #points - 1 do
        local p1, p2 = points[i], points[i + 1]
        local direction = (p2 - p1).Unit
        local distance = (p2 - p1).Magnitude

        for t = 0, distance, 6 do
            local pos = p1 + direction * t

            -- Match the wobble from carving
            local wobble = math.noise(t / 20 + seed, i) * width * 0.3
            local perpendicular = direction:Cross(Vector3.yAxis).Unit
            pos = pos + perpendicular * wobble

            local localWidth = width * (0.8 + math.noise(t / 15 + seed * 2, i) * 0.4)
            local localDepth = depth * (0.7 + math.noise(t / 25 + seed * 3, i) * 0.6)

            -- Water fills bottom portion
            Terrain:FillBall(
                pos - Vector3.new(0, localDepth * 0.5, 0),
                localWidth * 0.5,
                Enum.Material.Water
            )
        end
    end
end

-- Usage
carveNaturalCreek({
    Vector3.new(0, 20, 0),
    Vector3.new(80, 18, 40),
    Vector3.new(150, 15, 30),
    Vector3.new(220, 12, 70),
}, 10, 5)
```

### Visual Result

```
BEFORE:                          AFTER (Natural Creek):

██████████████████████████       ██████████████████████████
██████████████████████████       █████████▓▓▒▒░░▒▒▓████████
██████████████████████████       ███████▓▒░░░≈≈░░░▒▓██████
██████████████████████████  →    █████▓▒░░≈≈≈≈≈≈░░▒▓██████
██████████████████████████       ██████▓▒░░░≈≈░░░▒▓███████
██████████████████████████       ████████▓▓▒▒░░▒▓▓█████████

█ = Grass (full)      ░ = Mud (partial occupancy)
▓ = Ground (edge)     ≈ = Water
▒ = Mud bank
```

---

## Procedural Generation

### Heightmap-Based Terrain

```lua
local function generateFromHeightmap(origin, sizeX, sizeZ, heightFunc, material)
    local resolution = 4

    for x = 0, sizeX, resolution do
        for z = 0, sizeZ, resolution do
            local worldX = origin.X + x
            local worldZ = origin.Z + z

            -- Get height from function
            local height = heightFunc(worldX, worldZ)

            -- Fill column
            local region = Region3.new(
                Vector3.new(worldX, origin.Y, worldZ),
                Vector3.new(worldX + resolution, origin.Y + height, worldZ + resolution)
            ):ExpandToGrid(4)

            Terrain:FillRegion(region, 4, material)
        end

        -- Yield to prevent timeout
        if x % 40 == 0 then task.wait() end
    end
end

-- Usage with Perlin noise
local seed = math.random(1, 10000)
generateFromHeightmap(
    Vector3.new(-200, 0, -200),
    400, 400,
    function(x, z)
        local noise = math.noise(x / 50 + seed, z / 50 + seed)
        return 20 + noise * 30  -- Height between -10 and 50
    end,
    Enum.Material.Grass
)
```

### Island Generator

```lua
local function generateIsland(center, radius, maxHeight)
    local seed = math.random(1, 10000)

    for angle = 0, 360, 5 do
        for dist = 0, radius, 4 do
            local rad = math.rad(angle)
            local x = center.X + math.cos(rad) * dist
            local z = center.Z + math.sin(rad) * dist

            -- Island falloff + noise
            local falloff = 1 - (dist / radius)^2
            local noise = math.noise(x / 30 + seed, z / 30 + seed) * 0.3 + 0.7
            local height = maxHeight * falloff * noise

            if height > 1 then
                -- Main terrain
                Terrain:FillCylinder(
                    CFrame.new(x, center.Y + height/2, z),
                    height,
                    3,
                    height > maxHeight * 0.7 and Enum.Material.Rock or Enum.Material.Grass
                )

                -- Beach at edges
                if falloff < 0.3 then
                    Terrain:FillCylinder(
                        CFrame.new(x, center.Y + 1, z),
                        2,
                        4,
                        Enum.Material.Sand
                    )
                end
            end
        end

        if angle % 30 == 0 then task.wait() end
    end
end
```

### River/Creek Generator

```lua
local function generateRiver(points, width, depth, addWater)
    for i = 1, #points - 1 do
        local p1, p2 = points[i], points[i + 1]
        local direction = (p2 - p1).Unit
        local distance = (p2 - p1).Magnitude
        local perpendicular = direction:Cross(Vector3.yAxis).Unit

        -- Walk along path
        for t = 0, distance, 4 do
            local pos = p1 + direction * t

            -- Carve U-shaped channel
            for w = -width/2, width/2, 2 do
                local offset = perpendicular * w
                local carvePos = pos + offset

                -- U-shape: deeper in middle
                local depthHere = depth * (1 - (math.abs(w) / (width/2))^2)

                Terrain:FillBall(
                    carvePos - Vector3.new(0, depthHere/2, 0),
                    depthHere,
                    Enum.Material.Air
                )

                -- Riverbed material
                Terrain:FillBall(
                    carvePos - Vector3.new(0, depthHere + 1, 0),
                    2,
                    Enum.Material.Mud
                )
            end
        end

        task.wait()
    end

    -- Add water
    if addWater then
        for i = 1, #points - 1 do
            local p1, p2 = points[i], points[i + 1]
            local direction = (p2 - p1).Unit
            local distance = (p2 - p1).Magnitude

            for t = 0, distance, 8 do
                local pos = p1 + direction * t
                Terrain:FillBlock(
                    CFrame.new(pos - Vector3.new(0, depth * 0.3, 0)),
                    Vector3.new(width * 0.7, depth * 0.5, 8),
                    Enum.Material.Water
                )
            end
        end
    end
end

-- Usage
generateRiver({
    Vector3.new(0, 20, 0),
    Vector3.new(50, 18, 30),
    Vector3.new(100, 15, 20),
    Vector3.new(150, 12, 50),
}, 15, 6, true)
```

### Cave Generator

```lua
local function generateCave(startPos, length, radius, windiness)
    local pos = startPos
    local direction = Vector3.new(1, 0, 0)
    local seed = math.random(1, 10000)

    for i = 0, length, 4 do
        -- Carve sphere
        Terrain:FillBall(pos, radius, Enum.Material.Air)

        -- Winding path using noise
        local noiseX = math.noise(i / 20 + seed, 0) * windiness
        local noiseY = math.noise(i / 20, seed) * windiness * 0.3
        local noiseZ = math.noise(0, i / 20 + seed) * windiness

        direction = (direction + Vector3.new(noiseX, noiseY, noiseZ)).Unit
        pos = pos + direction * 4

        -- Vary radius
        radius = radius + math.noise(i / 10, seed * 2) * 2
        radius = math.clamp(radius, 5, 15)

        if i % 20 == 0 then task.wait() end
    end
end
```

### Mountain Generator

```lua
local function generateMountain(center, baseRadius, height, roughness)
    local seed = math.random(1, 10000)

    -- Build from bottom up in layers
    for y = 0, height, 4 do
        local progress = y / height
        local layerRadius = baseRadius * (1 - progress^0.7)  -- Taper

        for angle = 0, 360, 10 do
            local rad = math.rad(angle)

            -- Add noise to radius
            local noise = math.noise(angle / 30 + seed, y / 20 + seed)
            local r = layerRadius * (1 + noise * roughness)

            local x = center.X + math.cos(rad) * r
            local z = center.Z + math.sin(rad) * r

            -- Material based on height
            local mat
            if progress > 0.8 then
                mat = Enum.Material.Snow
            elseif progress > 0.5 then
                mat = Enum.Material.Rock
            else
                mat = Enum.Material.Grass
            end

            Terrain:FillBall(
                Vector3.new(x, center.Y + y, z),
                6,
                mat
            )
        end

        if y % 20 == 0 then task.wait() end
    end
end
```

---

## Materials Reference

### Terrain Materials

| Material | Use Case |
|----------|----------|
| `Air` | Empty space / clearing terrain |
| `Grass` | Fields, meadows, lawns |
| `LeafyGrass` | Dense vegetation areas |
| `Sand` | Beaches, deserts |
| `Rock` | Mountains, cliffs, caves |
| `Slate` | Darker rock formations |
| `Limestone` | Lighter rock, cliffs |
| `Basalt` | Volcanic areas |
| `Sandstone` | Desert canyons |
| `CrackedLava` | Volcanic/lava areas |
| `Snow` | Snowy peaks, winter |
| `Ice` | Frozen lakes, glaciers |
| `Glacier` | Large ice formations |
| `Mud` | Swamps, riverbeds |
| `Ground` | Dirt paths, bare earth |
| `Asphalt` | Roads, parking lots |
| `Pavement` | Sidewalks, plazas |
| `Brick` | Urban terrain |
| `Salt` | Salt flats |
| `Water` | Rivers, lakes, oceans |

### Material by Biome

```lua
local BIOME_MATERIALS = {
    forest = {
        ground = Enum.Material.Grass,
        accent = Enum.Material.LeafyGrass,
        rock = Enum.Material.Rock,
    },
    desert = {
        ground = Enum.Material.Sand,
        accent = Enum.Material.Sandstone,
        rock = Enum.Material.Sandstone,
    },
    arctic = {
        ground = Enum.Material.Snow,
        accent = Enum.Material.Ice,
        rock = Enum.Material.Glacier,
    },
    volcanic = {
        ground = Enum.Material.Basalt,
        accent = Enum.Material.CrackedLava,
        rock = Enum.Material.Rock,
    },
    swamp = {
        ground = Enum.Material.Mud,
        accent = Enum.Material.LeafyGrass,
        rock = Enum.Material.Slate,
    },
}
```

---

## Performance Tips

### 1. Batch Operations

```lua
-- BAD: Many small operations
for i = 1, 100 do
    Terrain:FillBall(positions[i], 5, Enum.Material.Rock)
end

-- GOOD: One large ReadVoxels/WriteVoxels
local region = calculateBoundingRegion(positions)
local mats, occs = Terrain:ReadVoxels(region, 4)
-- Modify arrays
Terrain:WriteVoxels(region, 4, mats, occs)
```

### 2. Yield During Generation

```lua
local function generateLargeTerrain()
    for x = 1, 1000, 4 do
        for z = 1, 1000, 4 do
            -- Generate terrain...
        end

        -- Yield every few iterations
        if x % 40 == 0 then
            task.wait()
        end
    end
end
```

### 3. Region Size Limits

```lua
-- ReadVoxels/WriteVoxels have limits
-- Split large regions into chunks

local CHUNK_SIZE = 64  -- studs

local function processLargeRegion(region, processFunc)
    local min = region.CFrame.Position - region.Size/2
    local max = region.CFrame.Position + region.Size/2

    for x = min.X, max.X, CHUNK_SIZE do
        for y = min.Y, max.Y, CHUNK_SIZE do
            for z = min.Z, max.Z, CHUNK_SIZE do
                local chunkRegion = Region3.new(
                    Vector3.new(x, y, z),
                    Vector3.new(
                        math.min(x + CHUNK_SIZE, max.X),
                        math.min(y + CHUNK_SIZE, max.Y),
                        math.min(z + CHUNK_SIZE, max.Z)
                    )
                ):ExpandToGrid(4)

                processFunc(chunkRegion)
                task.wait()
            end
        end
    end
end
```

### 4. Use Appropriate Methods

```lua
-- For simple shapes, use Fill methods (faster)
Terrain:FillBall(pos, radius, material)

-- For complex/precise edits, use ReadVoxels/WriteVoxels
local mats, occs = Terrain:ReadVoxels(region, 4)
```

---

## MCP Tool Examples

These tools can be added to the Bakable plugin for AI-controlled terrain manipulation.

```lua
-- terrain.fill - Fill a shape with terrain
handlers["terrain.fill"] = function(params)
    local pos = Vector3.new(params.x, params.y, params.z)
    local material = Enum.Material[params.material or "Grass"]

    if params.shape == "ball" then
        Terrain:FillBall(pos, params.radius, material)
    elseif params.shape == "block" then
        local size = Vector3.new(params.sizeX, params.sizeY, params.sizeZ)
        Terrain:FillBlock(CFrame.new(pos), size, material)
    elseif params.shape == "cylinder" then
        Terrain:FillCylinder(CFrame.new(pos), params.height, params.radius, material)
    end

    return true, { filled = true, shape = params.shape }
end

-- terrain.erode - Erode terrain at position
handlers["terrain.erode"] = function(params)
    local pos = Vector3.new(params.x, params.y, params.z)
    erode(pos, params.radius or 15, params.strength or 0.3)
    return true, { eroded = true }
end

-- terrain.flatten - Flatten terrain to height
handlers["terrain.flatten"] = function(params)
    local pos = Vector3.new(params.x, params.y, params.z)
    flatten(pos, params.radius or 20, params.height or pos.Y, params.strength or 0.5)
    return true, { flattened = true }
end

-- terrain.paint - Change material without changing shape
handlers["terrain.paint"] = function(params)
    local pos = Vector3.new(params.x, params.y, params.z)
    local material = Enum.Material[params.material]
    paint(pos, params.radius or 15, material)
    return true, { painted = true }
end

-- terrain.river - Generate a river along points
handlers["terrain.river"] = function(params)
    local points = {}
    for _, p in ipairs(params.points) do
        table.insert(points, Vector3.new(p.x, p.y, p.z))
    end
    generateRiver(points, params.width or 10, params.depth or 4, params.addWater ~= false)
    return true, { generated = true, pointCount = #points }
end

-- terrain.clear - Clear terrain in region
handlers["terrain.clear"] = function(params)
    local pos = Vector3.new(params.x, params.y, params.z)
    Terrain:FillBall(pos, params.radius, Enum.Material.Air)
    return true, { cleared = true }
end
```

---

## References

- [Terrain API Reference](https://create.roblox.com/docs/reference/engine/classes/Terrain)
- [Terrain Documentation](https://create.roblox.com/docs/parts/terrain)
- [Materials Reference](https://create.roblox.com/docs/parts/materials)
- [Studio Terrain Tools Source](https://github.com/Roblox/Studio-Tools/blob/master/TerrainTools.rbxmx)
