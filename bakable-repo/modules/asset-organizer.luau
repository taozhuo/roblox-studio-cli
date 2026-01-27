-- AssetOrganizer: Scan, display, identify, and rename assets
-- Requires: bootstrap
-- Works with Gemini VLM for asset identification
--
-- AGENTIC WORKFLOW:
-- 1. dumpTree() → Full structure for Claude to analyze
-- 2. Claude decides which paths are "real assets"
-- 3. showSelected([paths]) → Grid shows those items
-- 4. Screenshot → Gemini VLM → identify
-- 5. applyIdentifications() → Rename + catalog

-- Bakable table is provided directly by the eval sandbox

local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local AssetOrganizer = {}

-- State
local state = {
    rootFolder = nil,     -- The scanned folder
    treeData = nil,       -- Full tree structure
    assets = {},          -- Selected assets to show
    currentPage = 1,
    perPage = 9,
    columns = 3,
    rows = 3,
    gui = nil,
    guiName = "BakableAssetOrganizerGui",
}

-- Resolve a path like "Workspace/Folder/Model" to an instance
local function resolvePath(path)
    local current = game
    local parts = path:gsub("%.", "/"):split("/")
    for _, part in ipairs(parts) do
        current = current:FindFirstChild(part)
        if not current then
            return nil
        end
    end
    return current
end

-- Get info about any instance (Model, MeshPart, Part, etc.)
local function getInstanceInfo(inst)
    local info = {
        name = inst.Name,
        class = inst.ClassName,
        childCount = #inst:GetChildren(),
    }

    -- Get size for Models
    if inst:IsA("Model") then
        local success, cf, size = pcall(function()
            return inst:GetBoundingBox()
        end)
        if success and cf then
            info.size = {
                x = math.floor(size.X * 10) / 10,
                y = math.floor(size.Y * 10) / 10,
                z = math.floor(size.Z * 10) / 10,
            }
            info.sizeStr = math.floor(size.X) .. "x" .. math.floor(size.Y) .. "x" .. math.floor(size.Z)

            local pivot = inst:GetPivot()
            local bottomY = cf.Position.Y - size.Y / 2
            info.groundOffset = math.floor((pivot.Position.Y - bottomY) * 100) / 100
        end
    elseif inst:IsA("BasePart") then
        info.size = {
            x = math.floor(inst.Size.X * 10) / 10,
            y = math.floor(inst.Size.Y * 10) / 10,
            z = math.floor(inst.Size.Z * 10) / 10,
        }
        info.sizeStr = math.floor(inst.Size.X) .. "x" .. math.floor(inst.Size.Y) .. "x" .. math.floor(inst.Size.Z)
    end

    -- List child classes for context
    local childClasses = {}
    for _, child in ipairs(inst:GetChildren()) do
        childClasses[child.ClassName] = (childClasses[child.ClassName] or 0) + 1
    end
    if next(childClasses) then
        info.childClasses = childClasses
    end

    return info
end

-- Recursively dump tree structure
local function dumpTreeRecursive(inst, path, depth, maxDepth)
    if depth > maxDepth then
        return { path = path, truncated = true, childCount = #inst:GetChildren() }
    end

    local node = getInstanceInfo(inst)
    node.path = path

    local children = inst:GetChildren()
    if #children > 0 then
        node.children = {}
        for _, child in ipairs(children) do
            -- Only recurse into Models and Folders
            if child:IsA("Model") or child:IsA("Folder") then
                local childPath = path .. "/" .. child.Name
                table.insert(node.children, dumpTreeRecursive(child, childPath, depth + 1, maxDepth))
            elseif child:IsA("BasePart") then
                -- Include parts but don't recurse
                local partInfo = getInstanceInfo(child)
                partInfo.path = path .. "/" .. child.Name
                table.insert(node.children, partInfo)
            end
        end
    end

    return node
end

-- Dump full tree structure for Claude to analyze
function AssetOrganizer.dumpTree(folderPath, maxDepth)
    maxDepth = maxDepth or 6

    local folder = resolvePath(folderPath)
    if not folder then
        return { error = "Folder not found: " .. folderPath }
    end

    state.rootFolder = folder
    state.treeData = dumpTreeRecursive(folder, folderPath, 0, maxDepth)

    return state.treeData
end

-- Get bounding box info for a model (for selected assets)
local function getModelInfo(model)
    local success, cf, size = pcall(function()
        return model:GetBoundingBox()
    end)
    if not success or not cf then
        return nil
    end

    local pivot = model:GetPivot()
    local bottomY = cf.Position.Y - size.Y / 2
    local groundOffset = pivot.Position.Y - bottomY

    return {
        size = {
            x = math.floor(size.X * 10) / 10,
            y = math.floor(size.Y * 10) / 10,
            z = math.floor(size.Z * 10) / 10,
        },
        sizeStr = math.floor(size.X) .. "x" .. math.floor(size.Y) .. "x" .. math.floor(size.Z),
        groundOffset = math.floor(groundOffset * 100) / 100,
        center = cf.Position,
    }
end

-- Wrap a single Part/MeshPart in a Model
function AssetOrganizer.wrapInModel(path, modelName)
    local inst = resolvePath(path)
    if not inst then
        return { error = "Instance not found: " .. path }
    end

    if not inst:IsA("BasePart") then
        return { error = "Can only wrap BaseParts, got: " .. inst.ClassName }
    end

    -- Create wrapper model
    local model = Instance.new("Model")
    model.Name = modelName or inst.Name

    -- Reparent the part into the model
    local parent = inst.Parent
    model.Parent = parent
    inst.Parent = model

    -- Set PrimaryPart and pivot
    model.PrimaryPart = inst
    model:SetPrimaryPartCFrame(inst.CFrame)

    return {
        ok = true,
        modelPath = path:match("(.+)/[^/]+$") .. "/" .. model.Name,
        wrappedPart = inst.Name,
    }
end

-- Wrap multiple parts at once
function AssetOrganizer.wrapMultiple(items)
    -- items: array of { path, modelName }
    local results = {}
    for _, item in ipairs(items) do
        local result = AssetOrganizer.wrapInModel(item.path, item.modelName)
        table.insert(results, result)
    end
    return { ok = true, results = results }
end

-- Select specific paths to show in the grid (called by Claude after analyzing tree)
-- Handles both Models and BaseParts (wraps parts in Model automatically)
function AssetOrganizer.selectAssets(paths)
    state.assets = {}

    -- Track names for disambiguation
    local nameCount = {}

    for _, path in ipairs(paths) do
        local inst = resolvePath(path)
        if inst then
            -- If it's a BasePart, wrap it in a Model first
            if inst:IsA("BasePart") then
                local model = Instance.new("Model")
                model.Name = inst.Name
                local parent = inst.Parent
                model.Parent = parent
                inst.Parent = model
                model.PrimaryPart = inst
                inst = model
                -- Update path to reflect new structure
                path = path  -- path stays same, but inst is now the model
            end

            local info = getModelInfo(inst)
            if info then
                -- Count names for disambiguation
                nameCount[inst.Name] = (nameCount[inst.Name] or 0) + 1

                table.insert(state.assets, {
                    model = inst,
                    originalName = inst.Name,
                    path = path,
                    parentPath = path:match("(.+)/[^/]+$") or path,
                    info = info,
                })
            end
        end
    end

    -- Disambiguate duplicate names
    local nameSeen = {}
    for _, asset in ipairs(state.assets) do
        if nameCount[asset.originalName] > 1 then
            nameSeen[asset.originalName] = (nameSeen[asset.originalName] or 0) + 1
            asset.disambiguatedName = asset.originalName .. "_" .. nameSeen[asset.originalName]
            asset.model.Name = asset.disambiguatedName
        else
            asset.disambiguatedName = asset.originalName
        end
    end

    -- Assign indices
    for i, asset in ipairs(state.assets) do
        asset.index = i
    end

    state.currentPage = 1

    return {
        ok = true,
        selected = #state.assets,
        pages = math.ceil(#state.assets / state.perPage),
    }
end

-- Legacy scan function - auto-selects leaf models
function AssetOrganizer.scan(folderPath)
    -- Resolve folder
    local current = game
    local parts = folderPath:gsub("%.", "/"):split("/")
    for _, part in ipairs(parts) do
        current = current:FindFirstChild(part)
        if not current then
            return { error = "Folder not found: " .. part }
        end
    end

    -- Find all leaf models
    local assets = findLeafModels(current, folderPath)

    -- Sort by path then name
    table.sort(assets, function(a, b)
        if a.parentPath ~= b.parentPath then
            return a.parentPath < b.parentPath
        end
        return a.originalName < b.originalName
    end)

    -- Disambiguate duplicates
    disambiguateNames(assets)

    -- Assign indices
    for i, asset in ipairs(assets) do
        asset.index = i
    end

    state.assets = assets
    state.currentPage = 1

    return {
        ok = true,
        total = #assets,
        pages = math.ceil(#assets / state.perPage),
        assets = (function()
            local summary = {}
            for _, a in ipairs(assets) do
                table.insert(summary, {
                    index = a.index,
                    name = a.disambiguatedName,
                    parent = a.parentPath:match("[^/]+$") or a.parentPath,
                    size = a.info.sizeStr,
                })
            end
            return summary
        end)(),
    }
end

-- Destroy existing GUI
local function destroyGui()
    if state.gui and state.gui.Parent then
        state.gui:Destroy()
    end
    state.gui = nil

    local old = CoreGui:FindFirstChild(state.guiName)
    if old then old:Destroy() end
end

-- Sanitize model for viewport (no scripts, anchored)
local function sanitizeClone(model)
    local clone = model:Clone()
    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("BasePart") then
            d.Anchored = true
            d.CanCollide = false
        elseif d:IsA("Script") or d:IsA("LocalScript") then
            d:Destroy()
        end
    end
    return clone
end

-- Frame camera to show model
local function frameCamera(model, camera)
    local cf, size = model:GetBoundingBox()
    local center = cf.Position
    local maxDim = math.max(size.X, size.Y, size.Z)
    if maxDim < 1 then maxDim = 1 end

    local yaw = math.rad(35)
    local pitch = math.rad(-20)
    local look = (CFrame.Angles(pitch, yaw, 0)).LookVector
    local dist = maxDim * 1.9

    camera.FieldOfView = 35
    camera.CFrame = CFrame.new(center - look * dist + Vector3.new(0, maxDim * 0.15, 0), center)
end

-- Build and show the UI
function AssetOrganizer.show(page)
    if #state.assets == 0 then
        return { error = "No assets scanned. Run scan() first." }
    end

    destroyGui()

    page = page or state.currentPage
    state.currentPage = math.clamp(page, 1, math.ceil(#state.assets / state.perPage))

    local cellPx = 220
    local paddingPx = 14
    local panelSize = state.columns * cellPx + (state.columns + 1) * paddingPx
    local headerH = 70

    -- Create GUI
    local gui = Instance.new("ScreenGui")
    gui.Name = state.guiName
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.Parent = CoreGui
    state.gui = gui

    local root = Instance.new("Frame")
    root.Size = UDim2.fromScale(1, 1)
    root.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
    root.BorderSizePixel = 0
    root.Parent = gui

    local panel = Instance.new("Frame")
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.new(0, panelSize, 0, panelSize + headerH)
    panel.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    panel.BorderSizePixel = 0
    panel.Parent = root

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 16)
    corner.Parent = panel

    -- Title
    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Size = UDim2.new(1, -24, 0, 24)
    title.Position = UDim2.new(0, 12, 0, 10)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(235, 235, 235)
    title.Text = "Asset Organizer"
    title.Parent = panel

    -- Info line
    local totalPages = math.ceil(#state.assets / state.perPage)
    local info = Instance.new("TextLabel")
    info.BackgroundTransparency = 1
    info.Size = UDim2.new(1, -24, 0, 20)
    info.Position = UDim2.new(0, 12, 0, 34)
    info.Font = Enum.Font.Gotham
    info.TextSize = 12
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextColor3 = Color3.fromRGB(180, 180, 180)
    info.Text = string.format("Page %d / %d  •  %d assets  •  Camera: -Z toward you",
        state.currentPage, totalPages, #state.assets)
    info.Parent = panel

    -- Legend
    local legend = Instance.new("TextLabel")
    legend.BackgroundTransparency = 1
    legend.Size = UDim2.new(0, 200, 0, 16)
    legend.Position = UDim2.new(0, 12, 0, 54)
    legend.Font = Enum.Font.Gotham
    legend.TextSize = 11
    legend.TextXAlignment = Enum.TextXAlignment.Left
    legend.TextColor3 = Color3.fromRGB(140, 140, 140)
    legend.Text = "Front faces camera (-Z) • Use for rotation reference"
    legend.Parent = panel

    -- Grid
    local gridFrame = Instance.new("Frame")
    gridFrame.BackgroundTransparency = 1
    gridFrame.Position = UDim2.new(0, 0, 0, headerH)
    gridFrame.Size = UDim2.new(1, 0, 1, -headerH)
    gridFrame.Parent = panel

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, paddingPx)
    pad.PaddingLeft = UDim.new(0, paddingPx)
    pad.PaddingRight = UDim.new(0, paddingPx)
    pad.PaddingBottom = UDim.new(0, paddingPx)
    pad.Parent = gridFrame

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0, cellPx, 0, cellPx)
    gridLayout.CellPadding = UDim2.new(0, paddingPx, 0, paddingPx)
    gridLayout.FillDirectionMaxCells = state.columns
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.Parent = gridFrame

    -- Render cells for current page
    local startIdx = (state.currentPage - 1) * state.perPage + 1
    local endIdx = math.min(startIdx + state.perPage - 1, #state.assets)

    local pageAssets = {}

    for idx = startIdx, endIdx do
        local asset = state.assets[idx]
        local cellOrder = idx - startIdx

        local cell = Instance.new("Frame")
        cell.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
        cell.BorderSizePixel = 0
        cell.LayoutOrder = cellOrder
        cell.Parent = gridFrame

        local cc = Instance.new("UICorner")
        cc.CornerRadius = UDim.new(0, 10)
        cc.Parent = cell

        -- Parent folder label (top)
        local parentLabel = Instance.new("TextLabel")
        parentLabel.BackgroundTransparency = 1
        parentLabel.Size = UDim2.new(1, -8, 0, 14)
        parentLabel.Position = UDim2.new(0, 4, 0, 4)
        parentLabel.Font = Enum.Font.Gotham
        parentLabel.TextSize = 10
        parentLabel.TextXAlignment = Enum.TextXAlignment.Left
        parentLabel.TextColor3 = Color3.fromRGB(120, 180, 255)
        parentLabel.Text = asset.parentPath:match("[^/]+$") or "root"
        parentLabel.TextTruncate = Enum.TextTruncate.AtEnd
        parentLabel.Parent = cell

        -- Name label
        local nameLabel = Instance.new("TextLabel")
        nameLabel.BackgroundTransparency = 1
        nameLabel.Size = UDim2.new(1, -8, 0, 16)
        nameLabel.Position = UDim2.new(0, 4, 0, 16)
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 12
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
        nameLabel.Text = asset.disambiguatedName
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Parent = cell

        -- Size label
        local sizeLabel = Instance.new("TextLabel")
        sizeLabel.BackgroundTransparency = 1
        sizeLabel.Size = UDim2.new(1, -8, 0, 12)
        sizeLabel.Position = UDim2.new(0, 4, 0, 32)
        sizeLabel.Font = Enum.Font.Gotham
        sizeLabel.TextSize = 10
        sizeLabel.TextXAlignment = Enum.TextXAlignment.Left
        sizeLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
        sizeLabel.Text = asset.info.sizeStr .. " studs"
        sizeLabel.Parent = cell

        -- Viewport
        local viewport = Instance.new("ViewportFrame")
        viewport.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
        viewport.BorderSizePixel = 0
        viewport.Size = UDim2.new(1, -8, 1, -52)
        viewport.Position = UDim2.new(0, 4, 0, 48)
        viewport.Parent = cell

        local vpCorner = Instance.new("UICorner")
        vpCorner.CornerRadius = UDim.new(0, 6)
        vpCorner.Parent = viewport

        local world = Instance.new("WorldModel")
        world.Parent = viewport

        local cam = Instance.new("Camera")
        cam.Parent = viewport
        viewport.CurrentCamera = cam

        -- Light
        local lightPart = Instance.new("Part")
        lightPart.Anchored = true
        lightPart.CanCollide = false
        lightPart.Transparency = 1
        lightPart.Parent = world

        local light = Instance.new("PointLight")
        light.Range = 60
        light.Brightness = 2
        light.Parent = lightPart

        -- Clone and position model
        local clone = sanitizeClone(asset.model)
        clone.Parent = world

        -- Center model and face -Z toward camera
        local bboxCf, bboxSize = clone:GetBoundingBox()
        clone:PivotTo(CFrame.new(-bboxCf.Position) * CFrame.Angles(0, math.rad(180), 0))

        lightPart.Position = Vector3.new(bboxSize.X, bboxSize.Y, bboxSize.Z) * 0.6 + Vector3.new(4, 6, 4)
        frameCamera(clone, cam)

        -- Track for return data
        table.insert(pageAssets, {
            index = asset.index,
            gridPosition = cellOrder + 1,
            name = asset.disambiguatedName,
            parent = asset.parentPath:match("[^/]+$") or "root",
            size = asset.info.sizeStr,
        })
    end

    return {
        ok = true,
        page = state.currentPage,
        totalPages = totalPages,
        showing = #pageAssets,
        assets = pageAssets,
    }
end

-- Navigation
function AssetOrganizer.next()
    local totalPages = math.ceil(#state.assets / state.perPage)
    if state.currentPage < totalPages then
        return AssetOrganizer.show(state.currentPage + 1)
    end
    return AssetOrganizer.info()
end

function AssetOrganizer.prev()
    if state.currentPage > 1 then
        return AssetOrganizer.show(state.currentPage - 1)
    end
    return AssetOrganizer.info()
end

function AssetOrganizer.goto(page)
    return AssetOrganizer.show(tonumber(page) or 1)
end

-- Get current state
function AssetOrganizer.info()
    return {
        scanned = #state.assets,
        page = state.currentPage,
        totalPages = math.ceil(#state.assets / state.perPage),
        perPage = state.perPage,
        guiVisible = state.gui ~= nil and state.gui.Parent ~= nil,
    }
end

-- Get assets for current page (for Gemini prompt)
function AssetOrganizer.getPageAssets()
    local startIdx = (state.currentPage - 1) * state.perPage + 1
    local endIdx = math.min(startIdx + state.perPage - 1, #state.assets)

    local assets = {}
    for idx = startIdx, endIdx do
        local asset = state.assets[idx]
        table.insert(assets, {
            gridPosition = idx - startIdx + 1,
            index = asset.index,
            currentName = asset.disambiguatedName,
            parent = asset.parentPath:match("[^/]+$") or "root",
            size = asset.info.sizeStr,
        })
    end
    return assets
end

-- Apply identifications from Gemini
-- identifications: array of { index, identifiedName, rotationOffset, comment }
function AssetOrganizer.applyIdentifications(identifications)
    local applied = 0
    local errors = {}

    for _, ident in ipairs(identifications) do
        local asset = nil
        for _, a in ipairs(state.assets) do
            if a.index == ident.index then
                asset = a
                break
            end
        end

        if asset then
            -- Rename the model
            if ident.identifiedName and ident.identifiedName ~= "" then
                asset.model.Name = ident.identifiedName
                asset.identifiedName = ident.identifiedName
            end

            -- Store metadata
            asset.rotationOffset = ident.rotationOffset
            asset.comment = ident.comment
            applied = applied + 1
        else
            table.insert(errors, "Asset not found: index " .. tostring(ident.index))
        end
    end

    return {
        ok = #errors == 0,
        applied = applied,
        errors = errors,
    }
end

-- Export catalog as JSON
function AssetOrganizer.exportCatalog()
    local catalog = {}

    for _, asset in ipairs(state.assets) do
        table.insert(catalog, {
            name = asset.identifiedName or asset.disambiguatedName,
            originalName = asset.originalName,
            path = asset.parentPath .. "/" .. (asset.identifiedName or asset.disambiguatedName),
            size = asset.info.size,
            sizeStr = asset.info.sizeStr,
            groundOffset = asset.info.groundOffset,
            rotationOffset = asset.rotationOffset or 0,
            comment = asset.comment or "",
        })
    end

    return HttpService:JSONEncode({
        exportedAt = os.date("%Y-%m-%d %H:%M:%S"),
        total = #catalog,
        assets = catalog,
    })
end

-- Get catalog as table (not JSON)
function AssetOrganizer.getCatalog()
    local catalog = {}

    for _, asset in ipairs(state.assets) do
        table.insert(catalog, {
            name = asset.identifiedName or asset.disambiguatedName,
            originalName = asset.originalName,
            path = asset.parentPath .. "/" .. (asset.identifiedName or asset.disambiguatedName),
            size = asset.info.size,
            sizeStr = asset.info.sizeStr,
            groundOffset = asset.info.groundOffset,
            rotationOffset = asset.rotationOffset or 0,
            comment = asset.comment or "",
        })
    end

    return {
        total = #catalog,
        assets = catalog,
    }
end

-- Hide UI
function AssetOrganizer.hide()
    destroyGui()
    return { ok = true }
end

-- Reset everything
function AssetOrganizer.reset()
    destroyGui()
    state.assets = {}
    state.currentPage = 1
    return { ok = true }
end

function AssetOrganizer.destroy()
    AssetOrganizer.reset()
end

Bakable.register("AssetOrganizer", AssetOrganizer)
return { ok = true, module = "AssetOrganizer" }
