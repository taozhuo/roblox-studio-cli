-- Placer: Place models with proper ground offset and transforms
-- Requires: bootstrap, catalog (optional but recommended)

if not _G.Bakable then
    error("Run bootstrap first: _G.Bakable not found")
end

local Placer = {}
local history = {} -- Track placed models for undo

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

-- Get model from folder
local function getModel(folderPath, modelName)
    local folder, err = resolveFolder(folderPath)
    if not folder then return nil, err end

    local model = folder:FindFirstChild(modelName)
    if not model then
        return nil, ("Model not found: %s in %s"):format(modelName, folderPath)
    end
    return model
end

-- Calculate ground offset for a model
local function getGroundOffset(model)
    local cf, size = model:GetBoundingBox()
    local pivot = model:GetPivot()
    local bottomY = cf.Position.Y - size.Y / 2
    return pivot.Position.Y - bottomY
end

-- Place a model clone at position
-- Options:
--   x, z: required position
--   y: ground level (default 0)
--   rotation: Y rotation in degrees (default 0)
--   parent: where to put it (default Workspace)
--   autoGround: add groundOffset automatically (default true)
function Placer.place(folderPath, modelName, options)
    options = options or {}

    local srcModel, err = getModel(folderPath, modelName)
    if not srcModel then
        return { error = err }
    end

    local clone = srcModel:Clone()

    -- Calculate position
    local x = options.x or 0
    local z = options.z or 0
    local groundY = options.y or 0
    local rotation = options.rotation or 0

    local y = groundY
    if options.autoGround ~= false then
        y = y + getGroundOffset(srcModel)
    end

    -- Build CFrame
    local cf = CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(rotation), 0)
    clone:PivotTo(cf)

    -- Parent
    local parent = workspace
    if options.parent then
        parent = resolveFolder(options.parent) or workspace
    end
    clone.Parent = parent

    -- Track for undo
    table.insert(history, clone)

    return {
        ok = true,
        name = clone.Name,
        position = { x = x, y = y, z = z },
        rotation = rotation,
        groundOffset = getGroundOffset(srcModel),
    }
end

-- Place multiple models in a batch
-- items: array of { model, x, z, y?, rotation? }
function Placer.placeBatch(folderPath, items, options)
    options = options or {}
    local results = {}
    local placed = 0
    local failed = 0

    for _, item in ipairs(items) do
        local result = Placer.place(folderPath, item.model or item[1], {
            x = item.x or item[2],
            z = item.z or item[3],
            y = item.y or options.y or 0,
            rotation = item.rotation or item[4] or 0,
            parent = options.parent,
            autoGround = options.autoGround,
        })

        if result.ok then
            placed = placed + 1
        else
            failed = failed + 1
        end
        table.insert(results, result)
    end

    return {
        ok = failed == 0,
        placed = placed,
        failed = failed,
        results = results,
    }
end

-- Place model at grid positions
function Placer.placeGrid(folderPath, modelName, options)
    options = options or {}
    local startX = options.startX or 0
    local startZ = options.startZ or 0
    local cols = options.cols or 3
    local rows = options.rows or 3
    local spacing = options.spacing or 10
    local y = options.y or 0

    local items = {}
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            table.insert(items, {
                model = modelName,
                x = startX + col * spacing,
                z = startZ + row * spacing,
            })
        end
    end

    return Placer.placeBatch(folderPath, items, { y = y, parent = options.parent })
end

-- Place along a line
function Placer.placeLine(folderPath, modelName, options)
    options = options or {}
    local x1 = options.x1 or 0
    local z1 = options.z1 or 0
    local x2 = options.x2 or 100
    local z2 = options.z2 or 0
    local count = options.count or 5
    local y = options.y or 0

    local items = {}
    for i = 0, count - 1 do
        local t = count > 1 and (i / (count - 1)) or 0
        table.insert(items, {
            model = modelName,
            x = x1 + (x2 - x1) * t,
            z = z1 + (z2 - z1) * t,
        })
    end

    return Placer.placeBatch(folderPath, items, { y = y, parent = options.parent })
end

-- Undo last N placements
function Placer.undo(count)
    count = count or 1
    local removed = 0

    for i = 1, count do
        if #history == 0 then break end
        local model = table.remove(history)
        if model and model.Parent then
            model:Destroy()
            removed = removed + 1
        end
    end

    return { removed = removed, remaining = #history }
end

-- Clear all placed models
function Placer.clear()
    local count = #history
    for _, model in ipairs(history) do
        if model and model.Parent then
            model:Destroy()
        end
    end
    history = {}
    return { cleared = count }
end

-- Get placement history info
function Placer.info()
    return {
        count = #history,
        models = (function()
            local names = {}
            for _, m in ipairs(history) do
                if m and m.Parent then
                    table.insert(names, m.Name)
                end
            end
            return names
        end)(),
    }
end

function Placer.destroy()
    history = {}
end

_G.Bakable.register("Placer", Placer)
return { ok = true, module = "Placer" }
