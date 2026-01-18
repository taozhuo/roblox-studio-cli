---
name: art-styles
description: Art style guidelines for different Roblox game aesthetics
---

# Roblox Art Styles

## Classic Stud Style (Grow a Garden Style)

Based on research of how **Grow a Garden** actually implements their style:

### How Grow a Garden Does It

From [WoodReviewerRBX analysis](https://woodreviewerrbx.com/2025/04/18/good-for-once-grow-a-garden/):

> "All the planks, fences, and everything in the garden is **smooth plastic**, with just the **original studs and welds textures** added to give the game some texture."

**Key points:**
- Base material: `Enum.Material.SmoothPlastic`
- Overlay: Classic stud/weld Texture objects
- Even stalls and signs use this same approach
- NO custom PBR materials - just simple texture overlays

---

### Method 1: Texture Overlay (How Grow a Garden Does It)

```lua
-- Apply stud texture overlay to a part
local function applyStudTexture(part, face)
    face = face or Enum.NormalId.Top

    local texture = Instance.new("Texture")
    texture.Texture = "rbxassetid://8130710802"  -- Classic stud texture
    texture.StudsPerTileU = 1
    texture.StudsPerTileV = 1
    texture.Face = face
    texture.Parent = part

    part.Material = Enum.Material.SmoothPlastic
end

-- Apply to all faces
local function applyStudsAllFaces(part)
    part.Material = Enum.Material.SmoothPlastic
    for _, face in ipairs(Enum.NormalId:GetEnumItems()) do
        local texture = Instance.new("Texture")
        texture.Texture = "rbxassetid://8130710802"
        texture.StudsPerTileU = 1
        texture.StudsPerTileV = 1
        texture.Face = face
        texture.Parent = part
    end
end
```

### Known Stud Texture Asset IDs

| Asset ID | Description | StudsPerTile |
|----------|-------------|--------------|
| `8130710802` | Classic stud texture | 1 |
| `6965996718` | 5x5 stud grid (baseplate style) | 10 |

---

### Method 2: HD PBR Materials (Modern Alternative)

For higher quality with proper lighting, use MaterialService:

**Get the materials:**
1. Search Toolbox for **"2008-2024 Studs As PBR Materials"** (ID: 11120912366)
2. Drag the MaterialVariants into `MaterialService`
3. Apply to parts

```lua
-- Apply HD stud material
part.Material = Enum.Material.SmoothPlastic
part.MaterialVariant = "Studs_2022"  -- or other variant from the pack
```

**Or create manually:**
```lua
local materialVariant = Instance.new("MaterialVariant")
materialVariant.Name = "Studs_Classic"
materialVariant.BaseMaterial = Enum.Material.SmoothPlastic
materialVariant.ColorMap = "rbxassetid://9873266399"   -- diffuse
materialVariant.NormalMap = "rbxassetid://9873266790"  -- normal for 3D bumps
materialVariant.Parent = game:GetService("MaterialService")
```

---

### Ground & Terrain Rules

1. **Remove Baseplate** - Replace with custom stud ground part
2. **Use Parts, NOT Terrain** - Terrain doesn't support stud textures
3. **Ground = Flat SmoothPlastic + Stud Texture**

```lua
-- Create stud ground (Grow a Garden style)
local ground = Instance.new("Part")
ground.Name = "Ground"
ground.Size = Vector3.new(500, 1, 500)
ground.Position = Vector3.new(0, -0.5, 0)
ground.Anchored = true
ground.Material = Enum.Material.SmoothPlastic
ground.Color = Color3.fromRGB(76, 153, 76)  -- Grass green

-- Add stud texture to top
local texture = Instance.new("Texture")
texture.Texture = "rbxassetid://8130710802"
texture.StudsPerTileU = 1
texture.StudsPerTileV = 1
texture.Face = Enum.NormalId.Top
texture.Parent = ground

-- Remove default baseplate
local baseplate = workspace:FindFirstChild("Baseplate")
if baseplate then baseplate:Destroy() end

ground.Parent = workspace
```

---

### Path Rules

```lua
-- Create path (slightly raised to avoid Z-fighting)
local path = Instance.new("Part")
path.Size = Vector3.new(10, 0.2, 100)
path.Position = Vector3.new(0, 0.1, 0)  -- 0.1 above ground
path.Material = Enum.Material.SmoothPlastic
path.Color = Color3.fromRGB(204, 178, 127)  -- Dirt/tan
path.Anchored = true

-- Add stud texture
local texture = Instance.new("Texture")
texture.Texture = "rbxassetid://8130710802"
texture.StudsPerTileU = 1
texture.StudsPerTileV = 1
texture.Face = Enum.NormalId.Top
texture.Parent = path
```

---

### Color Palette (Classic Grow a Garden Style)

| Element | Color | RGB |
|---------|-------|-----|
| Grass | Bright Green | (76, 153, 76) |
| Dirt/Path | Tan | (204, 178, 127) |
| Stone | Gray | (128, 128, 128) |
| Water | Bright Blue | (51, 153, 255) |
| Wood | Brown | (139, 90, 43) |

---

### UI Stud Background

For GUI elements (also how Grow a Garden does it):

```lua
local frame = Instance.new("Frame")
frame.BackgroundColor3 = Color3.fromRGB(76, 153, 76)

local studImage = Instance.new("ImageLabel")
studImage.Image = "rbxassetid://8130710802"  -- Same stud texture
studImage.ImageTransparency = 0.5
studImage.ScaleType = Enum.ScaleType.Tile
studImage.TileSize = UDim2.new(0, 32, 0, 32)
studImage.Size = UDim2.fromScale(1, 1)
studImage.BackgroundTransparency = 1
studImage.Parent = frame
```

---

### Best Practices

1. **Consistency** - ALL surfaces should have stud texture
2. **SmoothPlastic base** - Always use SmoothPlastic material
3. **Texture overlay** - Add Texture objects to each face
4. **StudsPerTile = 1** - Keep studs consistent size
5. **Bright colors** - Use saturated, distinct colors
6. **Flat surfaces** - Keep geometry simple and blocky

---

## Resources

- [How Grow a Garden does it](https://woodreviewerrbx.com/2025/04/18/good-for-once-grow-a-garden/)
- [HD Stud Materials 2008-2022](https://devforum.roblox.com/t/hd-stud-materials-from-2008-2022-auto-converter-script/1911578)
- [Resurface Plugin](https://devforum.roblox.com/t/resurface-convert-surfaces-to-studs-and-more/1226536)
- [Stud UI Discussion](https://devforum.roblox.com/t/how-do-you-make-stud-ui/4020877)
