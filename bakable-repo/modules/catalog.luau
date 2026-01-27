-- Catalog: Asset cataloging with persistent cache
-- Requires: bootstrap

if not _G.Bakable then
    error("Run bootstrap first: _G.Bakable not found")
end

local HttpService = game:GetService("HttpService")

local Catalog = {}
local cache = {} -- { folderPath = { assets = {...}, timestamp = tick() } }

-- Category detection from name
local function guessCategory(name)
    local lower = name:lower()
    if lower:match("tree") or lower:match("pine") or lower:match("oak") or lower:match("palm") or lower:match("birch") then return "tree" end
    if lower:match("rock") or lower:match("stone") or lower:match("boulder") then return "rock" end
    if lower:match("house") or lower:match("building") or lower:match("cabin") or lower:match("shop") or lower:match("tower") then return "building" end
    if lower:match("fence") or lower:match("wall") or lower:match("gate") then return "fence" end
    if lower:match("bush") or lower:match("plant") or lower:match("flower") or lower:match("grass") or lower:match("shrub") then return "vegetation" end
    if lower:match("bench") or lower:match("table") or lower:match("chair") or lower:match("stool") then return "furniture" end
    if lower:match("lamp") or lower:match("light") or lower:match("torch") or lower:match("lantern") then return "lighting" end
    if lower:match("road") or lower:match("path") or lower:match("tile") or lower:match("floor") then return "path" end
    if lower:match("water") or lower:match("pond") or lower:match("river") or lower:match("lake") then return "water" end
    if lower:match("cactus") or lower:match("mushroom") or lower:match("coral") then return "vegetation" end
    if lower:match("cart") or lower:match("truck") or lower:match("vehicle") or lower:match("car") then return "vehicle" end
    if lower:match("stall") or lower:match("market") or lower:match("booth") or lower:match("stand") then return "structure" end
    if lower:match("sign") or lower:match("post") or lower:match("pole") then return "signage" end
    if lower:match("barrel") or lower:match("crate") or lower:match("box") or lower:match("chest") then return "container" end
    return "prop"
end

-- Inspect a single model
function Catalog.inspect(model)
    if not model:IsA("Model") then
        return { error = "Not a Model" }
    end

    local cf, size = model:GetBoundingBox()
    local pivot = model:GetPivot()
    local bottomY = cf.Position.Y - size.Y / 2
    local groundOffset = pivot.Position.Y - bottomY

    return {
        name = model.Name,
        category = guessCategory(model.Name),
        size = {
            x = math.floor(size.X * 10) / 10,
            y = math.floor(size.Y * 10) / 10,
            z = math.floor(size.Z * 10) / 10,
        },
        footprint = ("%dx%d"):format(math.ceil(size.X), math.ceil(size.Z)),
        groundOffset = math.floor(groundOffset * 100) / 100,
        pivotY = math.floor(pivot.Position.Y * 10) / 10,
        boundingCenter = {
            x = math.floor(cf.Position.X * 10) / 10,
            y = math.floor(cf.Position.Y * 10) / 10,
            z = math.floor(cf.Position.Z * 10) / 10,
        },
        recommendedSpacing = math.ceil(math.max(size.X, size.Z) * 1.2),
    }
end

-- Resolve folder from path like "Workspace/AssetPack" or "Workspace.AssetPack"
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

-- Catalog all models in a folder
function Catalog.folder(folderPath, forceRefresh)
    -- Check cache
    if not forceRefresh and cache[folderPath] then
        local cached = cache[folderPath]
        if tick() - cached.timestamp < 60 then -- 60 second cache
            return cached.data
        end
    end

    local folder, err = resolveFolder(folderPath)
    if not folder then
        return { error = err }
    end

    local assets = {}
    for _, child in ipairs(folder:GetChildren()) do
        if child:IsA("Model") then
            local info = Catalog.inspect(child)
            info.path = folderPath .. "/" .. child.Name
            table.insert(assets, info)
        end
    end

    table.sort(assets, function(a, b)
        if a.category ~= b.category then
            return a.category < b.category
        end
        return a.name < b.name
    end)

    local result = {
        folder = folderPath,
        count = #assets,
        assets = assets,
        categories = {},
    }

    -- Count by category
    for _, asset in ipairs(assets) do
        result.categories[asset.category] = (result.categories[asset.category] or 0) + 1
    end

    -- Cache it
    cache[folderPath] = {
        data = result,
        timestamp = tick(),
    }

    return result
end

-- Get asset by name from cached folder
function Catalog.get(folderPath, assetName)
    local data = Catalog.folder(folderPath)
    if data.error then return data end

    for _, asset in ipairs(data.assets) do
        if asset.name == assetName then
            return asset
        end
    end
    return { error = ("Asset not found: %s"):format(assetName) }
end

-- Filter assets by category
function Catalog.filter(folderPath, category)
    local data = Catalog.folder(folderPath)
    if data.error then return data end

    local filtered = {}
    for _, asset in ipairs(data.assets) do
        if asset.category == category then
            table.insert(filtered, asset)
        end
    end
    return { count = #filtered, assets = filtered }
end

-- Export catalog as JSON string
function Catalog.toJSON(folderPath)
    local data = Catalog.folder(folderPath)
    return HttpService:JSONEncode(data)
end

-- Clear cache
function Catalog.clearCache()
    cache = {}
    return { ok = true }
end

-- Destroy
function Catalog.destroy()
    cache = {}
end

_G.Bakable.register("Catalog", Catalog)
return { ok = true, module = "Catalog" }
