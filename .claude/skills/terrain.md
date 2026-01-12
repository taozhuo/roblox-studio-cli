# Terrain Manipulation Skill

Use this skill when the user asks you to:
- Create, modify, or sculpt terrain
- Generate rivers, creeks, lakes, mountains, islands, caves
- Erode, flatten, smooth, or paint terrain
- Work with terrain materials (grass, rock, sand, water, etc.)

## Available MCP Tools

### terrain.fill
Fill a shape with terrain material.

```json
{
  "tool": "terrain.fill",
  "params": {
    "x": 0, "y": 10, "z": 0,
    "shape": "ball",           // "ball", "block", "cylinder"
    "radius": 20,              // for ball/cylinder
    "sizeX": 50, "sizeY": 10, "sizeZ": 30,  // for block
    "height": 20,              // for cylinder
    "material": "Grass"
  }
}
```

### terrain.erode
Erode terrain at a position with smooth natural falloff.

```json
{
  "tool": "terrain.erode",
  "params": {
    "x": 0, "y": 10, "z": 0,
    "radius": 15,
    "strength": 0.3,          // 0.0-1.0
    "natural": true           // use noise for organic edges
  }
}
```

### terrain.flatten
Flatten terrain to a specific height.

```json
{
  "tool": "terrain.flatten",
  "params": {
    "x": 0, "y": 10, "z": 0,
    "radius": 20,
    "height": 10,             // target height
    "strength": 0.5
  }
}
```

### terrain.smooth
Smooth terrain by averaging with neighbors.

```json
{
  "tool": "terrain.smooth",
  "params": {
    "x": 0, "y": 10, "z": 0,
    "radius": 15,
    "strength": 0.5
  }
}
```

### terrain.paint
Change terrain material without changing shape.

```json
{
  "tool": "terrain.paint",
  "params": {
    "x": 0, "y": 10, "z": 0,
    "radius": 15,
    "material": "Sand"
  }
}
```

### terrain.river
Generate a river or creek along a path with natural transitions.

```json
{
  "tool": "terrain.river",
  "params": {
    "points": [
      {"x": 0, "y": 20, "z": 0},
      {"x": 50, "y": 18, "z": 30},
      {"x": 100, "y": 15, "z": 20}
    ],
    "width": 12,
    "depth": 5,
    "addWater": true,
    "natural": true           // meandering + noise
  }
}
```

### terrain.clear
Clear terrain in a region.

```json
{
  "tool": "terrain.clear",
  "params": {
    "x": 0, "y": 10, "z": 0,
    "radius": 20
  }
}
```

---

## Terrain Materials

| Material | Use Case |
|----------|----------|
| `Air` | Clear/remove terrain |
| `Grass` | Fields, meadows, lawns |
| `LeafyGrass` | Dense vegetation |
| `Sand` | Beaches, deserts |
| `Rock` | Mountains, cliffs, caves |
| `Slate` | Dark rock formations |
| `Limestone` | Light rock, cliffs |
| `Basalt` | Volcanic areas |
| `Sandstone` | Desert canyons |
| `CrackedLava` | Volcanic/lava |
| `Snow` | Snowy peaks, winter |
| `Ice` | Frozen lakes, glaciers |
| `Glacier` | Large ice formations |
| `Mud` | Swamps, riverbeds |
| `Ground` | Dirt paths, bare earth |
| `Asphalt` | Roads |
| `Pavement` | Sidewalks |
| `Water` | Rivers, lakes, oceans |

---

## Natural Erosion Principles

When creating natural-looking terrain features, apply these principles:

### 1. Gradual Occupancy
Don't use just 0 (empty) or 1 (full). Use intermediate values for smooth edges:
- Center of carve: `0.0`
- Edge transition: `0.3`, `0.5`, `0.7`

### 2. Cosine Falloff
Smooth curve from center to edge:
```
falloff = (1 + cos(distance/radius * pi)) / 2
```

### 3. Perlin Noise
Add variation to radius and depth for organic, irregular edges:
```
noisyRadius = radius * (0.8 + noise * 0.4)
```

### 4. Material Zones
Layer materials naturally from water outward:
```
Water (center) → Mud → Ground → Grass (edges)
```

### 5. Path Meandering
Rivers shouldn't be straight. Add wobble:
```
wobble = noise(t / 20) * width * 0.3
```

---

## Common Patterns

### Create a Lake
```
1. terrain.erode at center with large radius, natural=true
2. terrain.paint the bottom with Mud
3. terrain.fill with Water at lower height
```

### Create a River/Creek
```
1. Get path points (from user or generate)
2. terrain.river with points, width, depth, addWater=true
```

### Create a Mountain
```
1. terrain.fill with ball shape, Rock material, large radius
2. terrain.paint top with Snow
3. terrain.smooth to blend
```

### Create a Road/Path
```
1. terrain.flatten along path points
2. terrain.paint with Asphalt or Pavement
```

### Create a Cliff
```
1. terrain.fill with block shape on one side
2. terrain.erode the edge for natural look
3. terrain.paint exposed face with Rock
```

### Create a Cave
```
1. Generate winding path with noise
2. terrain.clear along path with varying radius
3. Optionally add stalactites with small terrain.fill
```

---

## Lua Implementation Reference

If tools aren't available, use these implementations directly via `studio.eval`:

### Basic Fill Methods
```lua
local Terrain = workspace.Terrain

-- Ball
Terrain:FillBall(Vector3.new(x, y, z), radius, Enum.Material.Grass)

-- Block
Terrain:FillBlock(CFrame.new(x, y, z), Vector3.new(sizeX, sizeY, sizeZ), Enum.Material.Rock)

-- Cylinder
Terrain:FillCylinder(CFrame.new(x, y, z), height, radius, Enum.Material.Sand)

-- Clear
Terrain:FillBall(Vector3.new(x, y, z), radius, Enum.Material.Air)
```

### ReadVoxels / WriteVoxels
```lua
local region = Region3.new(
    Vector3.new(minX, minY, minZ),
    Vector3.new(maxX, maxY, maxZ)
):ExpandToGrid(4)

local materials, occupancies = Terrain:ReadVoxels(region, 4)

-- Modify arrays
for x = 1, materials.Size.X do
    for y = 1, materials.Size.Y do
        for z = 1, materials.Size.Z do
            occupancies[x][y][z] = 0.5  -- Half-filled
            materials[x][y][z] = Enum.Material.Rock
        end
    end
end

Terrain:WriteVoxels(region, 4, materials, occupancies)
```

### Natural Creek with Smooth Transitions
```lua
local function carveNaturalCreek(points, width, depth)
    local seed = math.random(1, 10000)
    local Terrain = workspace.Terrain

    for i = 1, #points - 1 do
        local p1, p2 = points[i], points[i + 1]
        local direction = (p2 - p1).Unit
        local distance = (p2 - p1).Magnitude

        for t = 0, distance, 3 do
            local pos = p1 + direction * t

            -- Meandering
            local wobble = math.noise(t / 20 + seed, i) * width * 0.3
            local perpendicular = direction:Cross(Vector3.yAxis).Unit
            pos = pos + perpendicular * wobble

            -- Vary width/depth
            local localWidth = width * (0.8 + math.noise(t / 15 + seed * 2, i) * 0.4)
            local localDepth = depth * (0.7 + math.noise(t / 25 + seed * 3, i) * 0.6)

            -- Carve with ReadVoxels/WriteVoxels for smooth edges
            local region = Region3.new(
                pos - Vector3.new(localWidth, localDepth + 2, localWidth),
                pos + Vector3.new(localWidth, 2, localWidth)
            ):ExpandToGrid(4)

            local materials, occupancies = Terrain:ReadVoxels(region, 4)
            local size = materials.Size
            local regionMin = region.CFrame.Position - region.Size / 2

            for x = 1, size.X do
                for y = 1, size.Y do
                    for z = 1, size.Z do
                        local worldPos = regionMin + Vector3.new((x-1)*4, (y-1)*4, (z-1)*4)
                        local horizDist = math.sqrt(
                            (worldPos.X - pos.X)^2 + (worldPos.Z - pos.Z)^2
                        )

                        local noisyRadius = localWidth * (0.8 + math.noise(worldPos.X/10 + seed, worldPos.Z/10) * 0.4)
                        local normalizedDist = horizDist / noisyRadius

                        if normalizedDist < 1.5 then
                            if normalizedDist < 1 then
                                -- Erode with cosine falloff
                                local falloff = (1 + math.cos(normalizedDist * math.pi)) / 2
                                local vertFactor = math.max(0, 1 - (pos.Y - worldPos.Y) / localDepth)
                                occupancies[x][y][z] = math.max(0, occupancies[x][y][z] - falloff * vertFactor)

                                -- Riverbed
                                if occupancies[x][y][z] > 0 and normalizedDist < 0.5 then
                                    materials[x][y][z] = Enum.Material.Mud
                                end
                            elseif normalizedDist < 1.2 and occupancies[x][y][z] > 0 then
                                materials[x][y][z] = Enum.Material.Mud
                            elseif normalizedDist < 1.5 and occupancies[x][y][z] > 0 then
                                materials[x][y][z] = Enum.Material.Ground
                            end
                        end
                    end
                end
            end

            Terrain:WriteVoxels(region, 4, materials, occupancies)
        end
        task.wait()
    end

    -- Add water
    for i = 1, #points - 1 do
        local p1, p2 = points[i], points[i + 1]
        local direction = (p2 - p1).Unit
        local distance = (p2 - p1).Magnitude

        for t = 0, distance, 6 do
            local pos = p1 + direction * t
            local wobble = math.noise(t / 20 + seed, i) * width * 0.3
            local perpendicular = direction:Cross(Vector3.yAxis).Unit
            pos = pos + perpendicular * wobble

            local localWidth = width * (0.8 + math.noise(t / 15 + seed * 2, i) * 0.4)
            local localDepth = depth * (0.7 + math.noise(t / 25 + seed * 3, i) * 0.6)

            Terrain:FillBall(
                pos - Vector3.new(0, localDepth * 0.5, 0),
                localWidth * 0.5,
                Enum.Material.Water
            )
        end
    end
end
```

### Bezier Curves for Smooth Paths
```lua
local function bezierCubic(p0, p1, p2, p3, t)
    local u = 1 - t
    return u*u*u*p0 + 3*u*u*t*p1 + 3*u*t*t*p2 + t*t*t*p3
end

local function sampleBezierPath(controlPoints, samples)
    local path = {}
    for i = 0, samples do
        local t = i / samples
        local point = bezierCubic(
            controlPoints[1], controlPoints[2],
            controlPoints[3], controlPoints[4], t
        )
        table.insert(path, point)
    end
    return path
end
```

---

## Performance Notes

- **Yield frequently**: Use `task.wait()` every ~40 iterations to prevent timeout
- **Batch operations**: One large `WriteVoxels` is faster than many `FillBall` calls
- **Chunk large regions**: Split regions larger than 64 studs into chunks
- **Resolution is always 4**: The terrain grid is 4x4x4 studs per voxel
