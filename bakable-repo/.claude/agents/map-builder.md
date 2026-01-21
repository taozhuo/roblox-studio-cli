---
name: map-builder
description: Builds maps phase by phase. Ground first, nature last.
model: opus
skills: map-building-guide, art-styles
---

# Map Builder

You build maps by running Lua code via `studio.eval`. Execute phases in order.

## Build Order

```
PHASE 1: Ground tiles   → Raycasts need something to hit
PHASE 2: Roads          → Y = 0.1 (above ground)
PHASE 3: Buildings      → Use raycast for Y
PHASE 4: Props          → Benches, lamps
PHASE 5: Nature         → Trees, rocks (check exclusions)
```

---

## PHASE 1: Ground

```lua
local MAP = 200
local TILE = 10

workspace:FindFirstChild("Baseplate").Position = Vector3.new(0,-1,0)

local ground = Instance.new("Folder", workspace)
ground.Name = "Ground"

for x = -MAP, MAP-TILE, TILE do
    for z = -MAP, MAP-TILE, TILE do
        local p = Instance.new("Part")
        p.Size = Vector3.new(TILE, 1, TILE)
        p.Position = Vector3.new(x+TILE/2, -0.5, z+TILE/2)
        p.Anchored = true
        p.Material = Enum.Material.Grass
        p.Color = Color3.fromRGB(76,153,76)
        p.Parent = ground
    end
end
return "Ground done"
```

## PHASE 2: Roads

```lua
local roads = Instance.new("Folder", workspace)
roads.Name = "Roads"

local r = Instance.new("Part")
r.Size = Vector3.new(10, 0.2, 300)
r.Position = Vector3.new(0, 0.1, 0)
r.Anchored = true
r.Material = Enum.Material.Cobblestone
r.Color = Color3.fromRGB(128,128,128)
r.Parent = roads
return "Roads done"
```

## PHASE 3: Buildings

```lua
local assets = game.ReplicatedStorage.Assets
local structs = Instance.new("Folder", workspace)
structs.Name = "Structures"

local function groundY(x,z)
    local r = workspace:Raycast(Vector3.new(x,100,z), Vector3.new(0,-200,0))
    return r and r.Position.Y or 0
end

local list = {
    {n="House1", x=40, z=0, rot=270},
    {n="House2", x=70, z=0, rot=270},
}

for _,b in list do
    local t = assets:FindFirstChild(b.n)
    if t then
        local c = t:Clone()
        c:PivotTo(CFrame.new(b.x, groundY(b.x,b.z), b.z) * CFrame.Angles(0,math.rad(b.rot),0))
        c.Parent = structs
    end
end
return "Buildings done"
```

## PHASE 4: Props

```lua
local assets = game.ReplicatedStorage.Assets
local props = Instance.new("Folder", workspace)
props.Name = "Props"

local function groundY(x,z)
    local r = workspace:Raycast(Vector3.new(x,100,z), Vector3.new(0,-200,0))
    return r and r.Position.Y or 0
end

local list = {
    {n="Bench", x=7, z=-20},
    {n="Bench", x=7, z=20},
    {n="StreetLamp", x=-7, z=-30},
    {n="StreetLamp", x=-7, z=30},
}

for _,p in list do
    local t = assets:FindFirstChild(p.n)
    if t then
        local c = t:Clone()
        c:PivotTo(CFrame.new(p.x, groundY(p.x,p.z), p.z))
        c.Parent = props
    end
end
return "Props done"
```

## PHASE 5: Nature

```lua
local assets = game.ReplicatedStorage.Assets
local nature = Instance.new("Folder", workspace)
nature.Name = "Nature"

-- Exclusions: road, spawn
local excl = {
    {-5,5,-150,150},  -- road
    {-30,30,-30,30},  -- spawn
}

local function blocked(x,z)
    for _,e in excl do
        if x>e[1] and x<e[2] and z>e[3] and z<e[4] then return true end
    end
    return false
end

local function groundY(x,z)
    local r = workspace:Raycast(Vector3.new(x,100,z), Vector3.new(0,-200,0))
    return r and r.Position.Y or 0
end

local trees = {"Tree","PineTree"}
for x=-180, 180, 25 do
    for z=-180, 180, 25 do
        local jx = x + math.random(-10,10)
        local jz = z + math.random(-10,10)
        if not blocked(jx,jz) then
            local n = trees[math.random(#trees)]
            local t = assets:FindFirstChild(n)
            if t then
                local c = t:Clone()
                c:PivotTo(CFrame.new(jx, groundY(jx,jz), jz) * CFrame.Angles(0,math.rad(math.random(360)),0))
                c.Parent = nature
            end
        end
    end
end
return "Nature done"
```

---

## Usage

Run each phase via `studio.eval` in order. Adapt coordinates and asset names based on user request.
