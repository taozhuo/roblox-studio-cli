-- Scatterer: Scatter objects with density and zone constraints
-- Requires: bootstrap, placer

if not _G.Bakable then
    error("Run bootstrap first: _G.Bakable not found")
end

local Scatterer = {}
local rng = Random.new()

-- Resolve folder from path
local function resolveFolder(path)
    local current = game
    local parts = path:gsub("%.", "/"):split("/")
    for _, part in ipairs(parts) do
        current = current:FindFirstChild(part)
        if not current then
            return nil, ("Not found: %s"):format(part)
        end
    end
    return current
end

-- Check if point is inside rectangular zone
local function inZone(x, z, zone)
    return x >= zone.minX and x <= zone.maxX and z >= zone.minZ and z <= zone.maxZ
end

-- Check minimum spacing from existing points
local function hasSpace(x, z, existing, minSpacing)
    for _, p in ipairs(existing) do
        local dx = x - p.x
        local dz = z - p.z
        if dx * dx + dz * dz < minSpacing * minSpacing then
            return false
        end
    end
    return true
end

-- Scatter models in a rectangular zone
-- Options:
--   zone: { minX, maxX, minZ, maxZ } or { centerX, centerZ, width, depth }
--   models: array of model names, or single name
--   density: items per square stud (e.g., 0.001 = 1 per 1000 sq studs)
--   count: exact count (overrides density)
--   minSpacing: minimum distance between items
--   rotationType: "upright" (Y only), "random" (full), "fixed" (no rotation)
--   y: ground level
function Scatterer.scatter(folderPath, options)
    options = options or {}

    -- Parse zone
    local zone = options.zone or {}
    if zone.centerX then
        zone.minX = zone.centerX - (zone.width or 100) / 2
        zone.maxX = zone.centerX + (zone.width or 100) / 2
        zone.minZ = zone.centerZ - (zone.depth or 100) / 2
        zone.maxZ = zone.centerZ + (zone.depth or 100) / 2
    end
    zone.minX = zone.minX or -50
    zone.maxX = zone.maxX or 50
    zone.minZ = zone.minZ or -50
    zone.maxZ = zone.maxZ or 50

    local width = zone.maxX - zone.minX
    local depth = zone.maxZ - zone.minZ
    local area = width * depth

    -- Models to scatter
    local models = options.models or options.model
    if type(models) == "string" then
        models = { models }
    end
    if not models or #models == 0 then
        return { error = "No models specified" }
    end

    -- Count
    local count
    if options.count then
        count = options.count
    elseif options.density then
        count = math.floor(area * options.density)
    else
        count = 10
    end

    local minSpacing = options.minSpacing or 2
    local rotationType = options.rotationType or "upright"
    local y = options.y or 0

    -- Check if Placer is available
    local Placer = _G.Bakable and _G.Bakable.Placer
    if not Placer then
        return { error = "Placer module not installed" }
    end

    -- Generate positions
    local positions = {}
    local attempts = 0
    local maxAttempts = count * 20

    while #positions < count and attempts < maxAttempts do
        attempts = attempts + 1
        local x = zone.minX + rng:NextNumber() * width
        local z = zone.minZ + rng:NextNumber() * depth

        if hasSpace(x, z, positions, minSpacing) then
            local rotation = 0
            if rotationType == "upright" then
                rotation = rng:NextNumber() * 360
            elseif rotationType == "random" then
                rotation = rng:NextNumber() * 360
            end

            table.insert(positions, {
                x = x,
                z = z,
                rotation = rotation,
                model = models[rng:NextInteger(1, #models)],
            })
        end
    end

    -- Place all
    local placed = 0
    local failed = 0
    for _, pos in ipairs(positions) do
        local result = Placer.place(folderPath, pos.model, {
            x = pos.x,
            z = pos.z,
            y = y,
            rotation = pos.rotation,
            parent = options.parent,
        })
        if result.ok then
            placed = placed + 1
        else
            failed = failed + 1
        end
    end

    return {
        ok = true,
        placed = placed,
        failed = failed,
        requested = count,
        attempts = attempts,
        zone = zone,
    }
end

-- Scatter with multiple asset types and weights
function Scatterer.scatterWeighted(folderPath, options)
    options = options or {}

    -- assets: { { name = "Tree1", weight = 3 }, { name = "Rock1", weight = 1 } }
    local assets = options.assets or {}
    if #assets == 0 then
        return { error = "No assets specified" }
    end

    -- Build weighted list
    local totalWeight = 0
    for _, a in ipairs(assets) do
        totalWeight = totalWeight + (a.weight or 1)
    end

    local function pickAsset()
        local r = rng:NextNumber() * totalWeight
        local cumulative = 0
        for _, a in ipairs(assets) do
            cumulative = cumulative + (a.weight or 1)
            if r <= cumulative then
                return a.name
            end
        end
        return assets[1].name
    end

    -- Generate model list
    local count = options.count or 10
    local models = {}
    for i = 1, count do
        table.insert(models, pickAsset())
    end

    options.models = models
    options.count = count
    return Scatterer.scatter(folderPath, options)
end

-- Scatter along a path with some randomness
function Scatterer.scatterPath(folderPath, options)
    options = options or {}

    local path = options.path or {} -- Array of {x, z} points
    if #path < 2 then
        return { error = "Path needs at least 2 points" }
    end

    local models = options.models or options.model
    if type(models) == "string" then
        models = { models }
    end

    local spacing = options.spacing or 10
    local spread = options.spread or 5 -- Random offset from path
    local y = options.y or 0

    local Placer = _G.Bakable and _G.Bakable.Placer
    if not Placer then
        return { error = "Placer module not installed" }
    end

    -- Walk the path
    local placed = 0
    local distance = 0
    local nextPlace = 0

    for i = 1, #path - 1 do
        local p1 = path[i]
        local p2 = path[i + 1]
        local dx = p2.x - p1.x
        local dz = p2.z - p1.z
        local segLen = math.sqrt(dx * dx + dz * dz)

        if segLen > 0 then
            local nx = dx / segLen
            local nz = dz / segLen
            -- Perpendicular
            local px = -nz
            local pz = nx

            local segDist = 0
            while segDist < segLen do
                if distance >= nextPlace then
                    local t = segDist / segLen
                    local baseX = p1.x + dx * t
                    local baseZ = p1.z + dz * t

                    -- Add random offset perpendicular to path
                    local offset = (rng:NextNumber() - 0.5) * 2 * spread
                    local x = baseX + px * offset
                    local z = baseZ + pz * offset
                    local rotation = rng:NextNumber() * 360

                    local model = models[rng:NextInteger(1, #models)]
                    local result = Placer.place(folderPath, model, {
                        x = x,
                        z = z,
                        y = y,
                        rotation = rotation,
                        parent = options.parent,
                    })
                    if result.ok then
                        placed = placed + 1
                    end

                    nextPlace = nextPlace + spacing + (rng:NextNumber() - 0.5) * spacing * 0.5
                end
                segDist = segDist + 1
                distance = distance + 1
            end
        end
    end

    return { ok = true, placed = placed }
end

function Scatterer.destroy()
    -- Nothing to clean up
end

_G.Bakable.register("Scatterer", Scatterer)
return { ok = true, module = "Scatterer" }
