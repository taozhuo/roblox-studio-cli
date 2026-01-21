---
name: map-planner
description: Use Gemini 3 Flash vision to analyze asset packs and generate map building plans
---

# Map Planner

Uses **Gemini 3 Flash** to analyze asset pack screenshots and generate detailed procedural map blueprints.

## MCP Tools Available

| Tool | Purpose |
|------|---------|
| `studio.map.positionCameraForOverview` | Position camera above asset folder |
| `studio.map.catalogAssets` | Generate asset catalog with sizes |
| `studio.captureViewport` | Capture screenshot |
| `studio.map.generatePlan` | Send to Gemini, get building plan |

## Quick Workflow

```
1. studio.map.positionCameraForOverview({ folderPath: "Workspace/AssetPack" })
2. studio.map.catalogAssets({ folderPath: "Workspace/AssetPack" })
3. studio.captureViewport({})  // Get base64 screenshot
4. studio.map.generatePlan({ screenshot, catalog, description: "...", mapSize: 400 })
5. Use map-builder subagent with the returned plan
```

## Step 1: Position Camera

Use the MCP tool to position camera for bird's eye view:

```lua
-- Position camera above asset pack looking down
local assetFolder = workspace:FindFirstChild("AssetPack") or workspace:FindFirstChild("Assets")
if not assetFolder then
    return { error = "No asset folder found" }
end

-- Get bounding box of all assets
local minX, minZ = math.huge, math.huge
local maxX, maxZ = -math.huge, -math.huge
local maxY = 0

for _, model in assetFolder:GetDescendants() do
    if model:IsA("BasePart") then
        local pos = model.Position
        local size = model.Size
        minX = math.min(minX, pos.X - size.X/2)
        maxX = math.max(maxX, pos.X + size.X/2)
        minZ = math.min(minZ, pos.Z - size.Z/2)
        maxZ = math.max(maxZ, pos.Z + size.Z/2)
        maxY = math.max(maxY, pos.Y + size.Y/2)
    end
end

-- Calculate camera position (bird's eye, slightly angled)
local centerX = (minX + maxX) / 2
local centerZ = (minZ + maxZ) / 2
local width = maxX - minX
local depth = maxZ - minZ
local viewSize = math.max(width, depth)

local camHeight = viewSize * 1.5
local camOffset = viewSize * 0.3

local camera = workspace.CurrentCamera
camera.CFrame = CFrame.lookAt(
    Vector3.new(centerX + camOffset, camHeight, centerZ + camOffset),
    Vector3.new(centerX, 0, centerZ)
)

return {
    bounds = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ, maxY = maxY },
    center = { x = centerX, z = centerZ },
    viewSize = viewSize
}
```

## Step 2: Generate Asset Catalog with Sizes

```lua
local function catalogAssets(folderPath)
    local folder = workspace:FindFirstChild(folderPath) or workspace[folderPath]
    local catalog = {}

    for _, item in folder:GetChildren() do
        if item:IsA("Model") then
            local cf, size = item:GetBoundingBox()
            table.insert(catalog, {
                name = item.Name,
                category = guessCategory(item.Name),
                size = {
                    x = math.floor(size.X * 10) / 10,
                    y = math.floor(size.Y * 10) / 10,
                    z = math.floor(size.Z * 10) / 10
                },
                footprint = math.floor(size.X) .. "x" .. math.floor(size.Z)
            })
        end
    end

    return catalog
end

local function guessCategory(name)
    local lower = name:lower()
    if lower:match("tree") or lower:match("pine") or lower:match("oak") then return "tree" end
    if lower:match("rock") or lower:match("stone") then return "rock" end
    if lower:match("house") or lower:match("building") then return "building" end
    if lower:match("fence") or lower:match("wall") then return "fence" end
    if lower:match("bush") or lower:match("plant") then return "vegetation" end
    if lower:match("bench") or lower:match("table") then return "furniture" end
    if lower:match("lamp") or lower:match("light") then return "lighting" end
    if lower:match("road") or lower:match("path") then return "path" end
    return "prop"
end

return catalogAssets("AssetPack")
```

## Step 3: Gemini Prompt Template

Send screenshot + catalog to Gemini with this prompt:

```
You are a Roblox map designer. Analyze this asset pack screenshot and catalog.

ASSET CATALOG:
{catalog_json}

USER REQUEST:
{user_description}

MAP SIZE: {size}x{size} studs

Generate a detailed "Procedural Generation Manifest" with:

1. GLOBAL SPECIFICATIONS
- Total size, style, perimeter treatment
- Path/road system layout

2. ZONE DEFINITIONS
For each zone provide:
- Name and theme
- Region coordinates (assume center is 0,0)
- Floor color (BrickColor name)
- Dominant assets from the catalog
- Density rules (items per area)
- Special features

3. ASSET PLACEMENT LOGIC
- Scatter algorithm for natural areas (density, rotation type)
- Grid algorithm for organized areas (spacing, alignment)
- Focal rules (what objects face toward)

4. HERO STRUCTURES (Landmarks)
- Exact coordinates for key buildings
- Surrounding decoration rules

5. VISUAL SUMMARY
- Quick zone description for verification

Format as structured text that a coding agent can parse.
Use exact asset names from the catalog.
Use BrickColor.new("ColorName") for floor colors.
```

## Step 4: Parse Gemini Response

The response should be structured for the map-builder:

```lua
-- Expected parsed structure
local mapPlan = {
    size = 400,
    style = "True Retro 2008",
    perimeter = { asset = "WoodenFence", spacing = 4 },

    zones = {
        {
            name = "Desert",
            region = { xMin = 0, xMax = 200, zMin = -200, zMax = 0 },
            floor = "Bright yellow",
            assets = {
                { name = "Cactus", density = 0.0025, rotation = "upright" },
                { name = "GreyRock", density = 0.002, rotation = "chaos" },
            }
        },
        {
            name = "Forest",
            region = { xMin = -200, xMax = 0, zMin = -200, zMax = 0 },
            floor = "Dark green",
            assets = {
                { name = "PineTree", density = 0.004, rotation = "upright" },
                { name = "LargeRock", density = 0.001, rotation = "chaos" },
            }
        },
        -- more zones...
    },

    landmarks = {
        { name = "Mine", position = { x = -160, z = -160 }, rotation = 0 },
        { name = "BlueTruck", position = { x = -40, z = 10 }, faceToward = { x = 0, z = 0 } },
    },

    paths = {
        { type = "road", width = 30, from = { x = -200, z = 0 }, to = { x = 200, z = 0 } },
    }
}
```

## Step 5: Execute with Map Builder

Pass the parsed plan to the map-builder subagent:

```
Use the map-builder subagent with this plan:

MAP PLAN:
{parsed_plan_json}

Build in this order:
1. Create floor tiles for each zone
2. Build perimeter fence
3. Create paths/roads
4. Place landmarks at exact coordinates
5. Scatter assets in each zone by density
6. Run placement-validator
```

## API Integration

### Gemini 3 Flash Request

```javascript
// In daemon/services/gemini.js
async function generateMapPlan(screenshot, catalog, userRequest, mapSize) {
    const response = await fetch('https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': process.env.GEMINI_API_KEY
        },
        body: JSON.stringify({
            contents: [{
                parts: [
                    {
                        inline_data: {
                            mime_type: 'image/png',
                            data: screenshot // base64
                        }
                    },
                    {
                        text: buildPrompt(catalog, userRequest, mapSize)
                    }
                ]
            }],
            generationConfig: {
                temperature: 0.7,
                maxOutputTokens: 8192
            }
        })
    });

    return response.json();
}
```

## Usage Flow

1. User provides asset pack in workspace
2. Run asset cataloger to get sizes
3. Position camera and capture screenshot
4. User describes desired map ("fantasy village with forest and river")
5. Send to Gemini with catalog + screenshot
6. Parse response into structured plan
7. Execute with map-builder subagent

## Example Prompt to Start

```
Analyze my asset pack and create a 400x400 map plan for:
"A small medieval village with a central marketplace,
surrounding farms, a forest to the north, and a river
running through the east side"
```
