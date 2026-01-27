# Bakable Automation Modules

Reusable Luau modules installed in `_G.Bakable` for automating Roblox Studio tasks.

## Quick Start

```lua
-- 1. Install bootstrap (run once per session)
-- Then install modules you need

-- 2. Use modules via studio.eval:
_G.Bakable.Catalog.folder("Workspace/AssetPack")
_G.Bakable.Placer.place("Workspace/AssetPack", "Tree1", { x = 0, z = 0 })
_G.Bakable.Camera.birdEye({ x = 0, z = 0, width = 200 })
```

## Available Modules

| Module | Purpose |
|--------|---------|
| `Catalog` | Catalog assets with sizes, categories, groundOffset |
| `Placer` | Place models with proper Y offset, batch placement |
| `Scatterer` | Scatter objects by density in zones |
| `Zone` | Create floor parts, perimeters, paths |
| `Camera` | Position camera for screenshots |
| `InventoryUI` | Visual asset inspection grid |

## Module Installation

Install via `studio.eval` by reading the module file:

```lua
-- Bootstrap first (required)
-- Then chain other modules as needed
```

Or install all at once using the MCP tool:
```
studio.modules.install(["Catalog", "Placer", "Scatterer"])
```

## Catalog Module

```lua
local Catalog = _G.Bakable.Catalog

-- Catalog entire folder (cached for 60s)
Catalog.folder("Workspace/AssetPack")
-- Returns: { folder, count, assets: [{name, category, size, footprint, groundOffset}], categories }

-- Get single asset info
Catalog.get("Workspace/AssetPack", "Tree1")
-- Returns: { name, category, size, footprint, groundOffset, recommendedSpacing }

-- Filter by category
Catalog.filter("Workspace/AssetPack", "tree")
-- Returns: { count, assets }

-- Inspect any model
Catalog.inspect(workspace.SomeModel)

-- Clear cache
Catalog.clearCache()
```

## Placer Module

```lua
local Placer = _G.Bakable.Placer

-- Place single model (auto ground offset)
Placer.place("Workspace/AssetPack", "Tree1", {
    x = 10,
    z = 20,
    y = 0,           -- ground level (default 0)
    rotation = 45,   -- degrees (default 0)
    autoGround = true, -- add groundOffset (default true)
})

-- Batch placement
Placer.placeBatch("Workspace/AssetPack", {
    { model = "Tree1", x = 0, z = 0 },
    { model = "Rock1", x = 10, z = 10, rotation = 90 },
}, { y = 0 })

-- Grid placement
Placer.placeGrid("Workspace/AssetPack", "Fence", {
    startX = -50, startZ = -50,
    cols = 10, rows = 1,
    spacing = 5,
})

-- Line placement
Placer.placeLine("Workspace/AssetPack", "Tree1", {
    x1 = 0, z1 = 0,
    x2 = 100, z2 = 0,
    count = 10,
})

-- Undo placements
Placer.undo(5)    -- undo last 5
Placer.clear()    -- clear all
Placer.info()     -- get history
```

## Scatterer Module

```lua
local Scatterer = _G.Bakable.Scatterer

-- Scatter in zone with density
Scatterer.scatter("Workspace/AssetPack", {
    zone = { minX = -50, maxX = 50, minZ = -50, maxZ = 50 },
    -- OR: zone = { centerX = 0, centerZ = 0, width = 100, depth = 100 },
    models = { "Tree1", "Tree2", "Bush1" },
    density = 0.002,  -- items per sq stud (2 per 1000 sq studs)
    -- OR: count = 50, -- exact count
    minSpacing = 5,
    rotationType = "upright", -- "upright", "random", "fixed"
})

-- Scatter with weights
Scatterer.scatterWeighted("Workspace/AssetPack", {
    zone = { minX = -50, maxX = 50, minZ = -50, maxZ = 50 },
    assets = {
        { name = "Tree1", weight = 3 },
        { name = "Rock1", weight = 1 },
    },
    count = 30,
})

-- Scatter along a path
Scatterer.scatterPath("Workspace/AssetPack", {
    path = { {x=0, z=0}, {x=50, z=20}, {x=100, z=0} },
    models = { "Bush1", "Flower1" },
    spacing = 8,
    spread = 5,  -- random offset from path
})
```

## Zone Module

```lua
local Zone = _G.Bakable.Zone

-- Create floor
Zone.createFloor({
    x = 0, z = 0,
    width = 200, depth = 200,
    color = "grass",  -- or Zone.Colors.grass
    material = Enum.Material.Grass,
    name = "MainFloor",
})

-- Available colors: grass, darkGrass, dirt, sand, stone, darkStone, water, snow, wood

-- Create perimeter walls
Zone.createPerimeter({
    x = 0, z = 0,
    width = 200, depth = 200,
    wallHeight = 4,
    color = "wood",
})

-- Create path
Zone.createPath({
    points = { {x=0, z=-100}, {x=0, z=0}, {x=50, z=50} },
    width = 4,
    color = "stone",
})

-- Create multiple zones at once
Zone.createMultiple({
    { type = "floor", x = 0, z = 0, width = 200, depth = 200, color = "grass" },
    { type = "perimeter", x = 0, z = 0, width = 200, depth = 200, wallHeight = 4 },
})

-- Undo
Zone.undo(1)
Zone.clear()
```

## Camera Module

```lua
local Camera = _G.Bakable.Camera

-- Look at position
Camera.lookAt({
    x = 0, y = 0, z = 0,
    distance = 50,
    pitch = -30,  -- degrees, negative = looking down
    yaw = 45,
})

-- Bird's eye view
Camera.birdEye({
    x = 0, z = 0,
    width = 200, depth = 200,
    tilt = 0,  -- 0 = straight down
})

-- Frame a folder to fit in view
Camera.frameFolder("Workspace/AssetPack", { angle = 30 })

-- Frame a model
Camera.frameModel(workspace.SomeModel, { distance = 20 })

-- Save/restore positions
Camera.save("overview")
Camera.restore("overview")
Camera.listSaved()

-- Get current camera info
Camera.info()
```

## InventoryUI Module

Visual grid for inspecting assets:

```lua
local UI = _G.Bakable.InventoryUI

-- Show folder contents
UI.show("AssetPack")  -- folder must be in Workspace

-- Navigate pages
UI.next()
UI.prev()
UI.goto(3)

-- Get current state
UI.info()
-- Returns: { folder, page, totalPages, totalItems, perPage }

-- Close
UI.destroy()
```

## Common Workflows

### Catalog + Place Assets

```lua
-- 1. Catalog available assets
local data = _G.Bakable.Catalog.folder("Workspace/AssetPack")

-- 2. Place specific assets
_G.Bakable.Placer.place("Workspace/AssetPack", "HouseLarge", { x = 0, z = 0 })

-- 3. Scatter trees around it
_G.Bakable.Scatterer.scatter("Workspace/AssetPack", {
    zone = { centerX = 0, centerZ = 0, width = 100, depth = 100 },
    models = { "Tree1", "Tree2" },
    count = 20,
    minSpacing = 8,
})
```

### Create Complete Map Zone

```lua
-- 1. Create floor
_G.Bakable.Zone.createFloor({ width = 200, depth = 200, color = "grass" })

-- 2. Add perimeter
_G.Bakable.Zone.createPerimeter({ width = 200, depth = 200, color = "wood" })

-- 3. Place landmark
_G.Bakable.Placer.place("Workspace/AssetPack", "Castle", { x = 0, z = 0 })

-- 4. Scatter environment
_G.Bakable.Scatterer.scatter("Workspace/AssetPack", {
    zone = { minX = -90, maxX = 90, minZ = -90, maxZ = 90 },
    models = { "Tree1", "Rock1", "Bush1" },
    count = 50,
})

-- 5. Screenshot for verification
_G.Bakable.Camera.birdEye({ width = 220, depth = 220 })
```

### Inspect Then Place

```lua
-- 1. Open visual inspector
_G.Bakable.InventoryUI.show("AssetPack")

-- 2. Get detailed catalog for planning
local catalog = _G.Bakable.Catalog.folder("Workspace/AssetPack")

-- 3. Frame for screenshot
_G.Bakable.Camera.frameFolder("Workspace/AssetPack")
```

## Tips

1. **Always run bootstrap first** - other modules depend on `_G.Bakable` namespace
2. **Catalog caches for 60s** - use `Catalog.clearCache()` after adding new assets
3. **Placer tracks history** - use `Placer.undo()` to revert placements
4. **Zone.undo()** works independently from Placer.undo()
5. **Check module status**: `_G.Bakable.list()` shows installed modules
6. **Reset everything**: `_G.Bakable.reset()` uninstalls all modules
