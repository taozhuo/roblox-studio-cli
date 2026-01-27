-- Zone: Create zone floors, perimeters, and boundaries
-- Requires: bootstrap

if not _G.Bakable then
    error("Run bootstrap first: _G.Bakable not found")
end

local Zone = {}
local created = {} -- Track created parts

-- Common colors for zones
Zone.Colors = {
    grass = BrickColor.new("Bright green"),
    darkGrass = BrickColor.new("Dark green"),
    dirt = BrickColor.new("Reddish brown"),
    sand = BrickColor.new("Brick yellow"),
    stone = BrickColor.new("Medium stone grey"),
    darkStone = BrickColor.new("Dark stone grey"),
    water = BrickColor.new("Bright blue"),
    snow = BrickColor.new("White"),
    wood = BrickColor.new("Brown"),
}

-- Create a floor/ground part
function Zone.createFloor(options)
    options = options or {}

    local x = options.x or 0
    local z = options.z or 0
    local y = options.y or 0
    local width = options.width or 100
    local depth = options.depth or 100
    local height = options.height or 1
    local color = options.color or Zone.Colors.grass
    local name = options.name or "ZoneFloor"

    if type(color) == "string" then
        color = Zone.Colors[color] or BrickColor.new(color)
    end

    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.Size = Vector3.new(width, height, depth)
    part.Position = Vector3.new(x, y - height / 2, z)
    part.BrickColor = color
    part.Material = options.material or Enum.Material.Grass
    part.TopSurface = Enum.SurfaceType.Studs
    part.BottomSurface = Enum.SurfaceType.Smooth

    local parent = options.parent or workspace
    if type(parent) == "string" then
        parent = game:FindFirstChild(parent, true) or workspace
    end
    part.Parent = parent

    table.insert(created, part)

    return {
        ok = true,
        name = part.Name,
        position = { x = x, y = y, z = z },
        size = { width = width, height = height, depth = depth },
    }
end

-- Create perimeter fence using Parts
function Zone.createPerimeter(options)
    options = options or {}

    local x = options.x or 0
    local z = options.z or 0
    local y = options.y or 0
    local width = options.width or 100
    local depth = options.depth or 100
    local wallHeight = options.wallHeight or 4
    local wallThickness = options.wallThickness or 1
    local color = options.color or Zone.Colors.wood
    local name = options.name or "Perimeter"

    if type(color) == "string" then
        color = Zone.Colors[color] or BrickColor.new(color)
    end

    local parent = options.parent or workspace
    if type(parent) == "string" then
        parent = game:FindFirstChild(parent, true) or workspace
    end

    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent

    local walls = {
        { -- North
            size = Vector3.new(width, wallHeight, wallThickness),
            pos = Vector3.new(x, y + wallHeight / 2, z - depth / 2),
        },
        { -- South
            size = Vector3.new(width, wallHeight, wallThickness),
            pos = Vector3.new(x, y + wallHeight / 2, z + depth / 2),
        },
        { -- East
            size = Vector3.new(wallThickness, wallHeight, depth),
            pos = Vector3.new(x + width / 2, y + wallHeight / 2, z),
        },
        { -- West
            size = Vector3.new(wallThickness, wallHeight, depth),
            pos = Vector3.new(x - width / 2, y + wallHeight / 2, z),
        },
    }

    for i, w in ipairs(walls) do
        local part = Instance.new("Part")
        part.Name = name .. "_Wall" .. i
        part.Anchored = true
        part.Size = w.size
        part.Position = w.pos
        part.BrickColor = color
        part.Material = options.material or Enum.Material.Wood
        part.TopSurface = Enum.SurfaceType.Studs
        part.Parent = folder
        table.insert(created, part)
    end

    table.insert(created, folder)

    return {
        ok = true,
        name = folder.Name,
        walls = 4,
        bounds = {
            minX = x - width / 2,
            maxX = x + width / 2,
            minZ = z - depth / 2,
            maxZ = z + depth / 2,
        },
    }
end

-- Create a simple path (strip of ground)
function Zone.createPath(options)
    options = options or {}

    local points = options.points or {} -- Array of {x, z}
    if #points < 2 then
        return { error = "Path needs at least 2 points" }
    end

    local y = options.y or 0.05 -- Slightly above ground to avoid z-fighting
    local pathWidth = options.width or 4
    local color = options.color or Zone.Colors.stone
    local name = options.name or "Path"

    if type(color) == "string" then
        color = Zone.Colors[color] or BrickColor.new(color)
    end

    local parent = options.parent or workspace
    if type(parent) == "string" then
        parent = game:FindFirstChild(parent, true) or workspace
    end

    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = parent

    for i = 1, #points - 1 do
        local p1 = points[i]
        local p2 = points[i + 1]
        local dx = p2.x - p1.x
        local dz = p2.z - p1.z
        local length = math.sqrt(dx * dx + dz * dz)
        local angle = math.atan2(dx, dz)

        local part = Instance.new("Part")
        part.Name = name .. "_Segment" .. i
        part.Anchored = true
        part.Size = Vector3.new(pathWidth, 0.5, length)
        part.CFrame = CFrame.new(
            (p1.x + p2.x) / 2,
            y,
            (p1.z + p2.z) / 2
        ) * CFrame.Angles(0, angle, 0)
        part.BrickColor = color
        part.Material = options.material or Enum.Material.Cobblestone
        part.TopSurface = Enum.SurfaceType.Smooth
        part.Parent = folder
        table.insert(created, part)
    end

    table.insert(created, folder)

    return {
        ok = true,
        name = folder.Name,
        segments = #points - 1,
    }
end

-- Create multiple zones from a definition
function Zone.createMultiple(zoneDefs)
    local results = {}
    for _, def in ipairs(zoneDefs) do
        local result
        if def.type == "floor" then
            result = Zone.createFloor(def)
        elseif def.type == "perimeter" then
            result = Zone.createPerimeter(def)
        elseif def.type == "path" then
            result = Zone.createPath(def)
        else
            result = { error = "Unknown zone type: " .. tostring(def.type) }
        end
        table.insert(results, result)
    end
    return { ok = true, zones = results }
end

-- Undo last N created items
function Zone.undo(count)
    count = count or 1
    local removed = 0

    for i = 1, count do
        if #created == 0 then break end
        local item = table.remove(created)
        if item and item.Parent then
            item:Destroy()
            removed = removed + 1
        end
    end

    return { removed = removed, remaining = #created }
end

-- Clear all created zones
function Zone.clear()
    local count = #created
    for _, item in ipairs(created) do
        if item and item.Parent then
            item:Destroy()
        end
    end
    created = {}
    return { cleared = count }
end

function Zone.destroy()
    created = {}
end

_G.Bakable.register("Zone", Zone)
return { ok = true, module = "Zone" }
