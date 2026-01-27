-- InventoryUI: Visual asset inspection grid
-- Requires: bootstrap
-- Shows models in a paginated grid with ViewportFrames

if not _G.Bakable then
    error("Run bootstrap first: _G.Bakable not found")
end

local InventoryUI = (function()
    local M = {}

    local CoreGui = game:GetService("CoreGui")
    local Workspace = game:GetService("Workspace")

    local state = {
        guiName = "BakableInventoryGui",
        gui = nil,
        folderName = nil,
        models = nil,
        page = 1,
        totalPages = 1,
        perPage = 9,
        columns = 3,
        rows = 3,
        cellPx = 220,
        paddingPx = 14,
        faceCameraY180 = true,
        gridFrame = nil,
        pageLabel = nil,
        prevBtn = nil,
        nextBtn = nil,
    }

    local function destroyExisting()
        if state.gui and state.gui.Parent then
            state.gui:Destroy()
        end
        state.gui = nil
        state.gridFrame = nil
        state.pageLabel = nil
        state.prevBtn = nil
        state.nextBtn = nil
    end

    local function clearGrid()
        if not state.gridFrame then return end
        for _, ch in ipairs(state.gridFrame:GetChildren()) do
            if ch:IsA("Frame") then ch:Destroy() end
        end
    end

    local function setButtonEnabled(btn, enabled)
        if not btn then return end
        btn.Active = enabled
        btn.AutoButtonColor = enabled
        btn.TextTransparency = enabled and 0 or 0.5
        btn.BackgroundTransparency = enabled and 0 or 0.4
    end

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

    local function frameCamera(model, camera)
        local cf, size = model:GetBoundingBox()
        local center = cf.Position
        local maxDim = math.max(size.X, size.Y, size.Z)
        if maxDim < 1e-3 then maxDim = 1 end

        local yaw = math.rad(35)
        local pitch = math.rad(-20)
        local look = (CFrame.Angles(pitch, yaw, 0)).LookVector
        local dist = maxDim * 1.9

        camera.FieldOfView = 35
        camera.CFrame = CFrame.new(center - look * dist + Vector3.new(0, maxDim * 0.15, 0), center)
    end

    local function buildUI()
        local old = CoreGui:FindFirstChild(state.guiName)
        if old then old:Destroy() end

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

        local panelSize = state.columns * state.cellPx + (state.columns + 1) * state.paddingPx
        local headerH = 62

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

        local title = Instance.new("TextLabel")
        title.BackgroundTransparency = 1
        title.Size = UDim2.new(1, -24, 0, 28)
        title.Position = UDim2.new(0, 12, 0, 10)
        title.Font = Enum.Font.GothamBold
        title.TextSize = 18
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextColor3 = Color3.fromRGB(235, 235, 235)
        title.Text = "Bakable Inventory"
        title.Parent = panel

        -- Legend
        local legend = Instance.new("Frame")
        legend.BackgroundTransparency = 1
        legend.Size = UDim2.new(0, 140, 0, 18)
        legend.Position = UDim2.new(0, 12 + 200, 0, 16)
        legend.Parent = panel

        local function chip(text, color, xPos)
            local f = Instance.new("Frame")
            f.BackgroundColor3 = color
            f.BorderSizePixel = 0
            f.Size = UDim2.new(0, 36, 0, 18)
            f.Position = UDim2.new(0, xPos, 0, 0)
            f.Parent = legend

            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 6)
            c.Parent = f

            local t = Instance.new("TextLabel")
            t.BackgroundTransparency = 1
            t.Size = UDim2.fromScale(1, 1)
            t.Font = Enum.Font.GothamBold
            t.TextSize = 12
            t.TextColor3 = Color3.fromRGB(0, 0, 0)
            t.Text = text
            t.Parent = f
        end

        chip("F -Z", Color3.fromRGB(255, 80, 80), 0)
        chip("R +X", Color3.fromRGB(80, 255, 120), 44)
        chip("U +Y", Color3.fromRGB(80, 160, 255), 88)

        -- Controls
        local controls = Instance.new("Frame")
        controls.BackgroundTransparency = 1
        controls.Size = UDim2.new(1, -24, 0, 24)
        controls.Position = UDim2.new(0, 12, 0, 34)
        controls.Parent = panel

        local function makeButton(text, xPos)
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(0, 70, 0, 24)
            b.Position = UDim2.new(0, xPos, 0, 0)
            b.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
            b.BorderSizePixel = 0
            b.Font = Enum.Font.GothamBold
            b.TextSize = 12
            b.TextColor3 = Color3.fromRGB(235, 235, 235)
            b.Text = text
            b.AutoButtonColor = true
            b.Parent = controls

            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 8)
            c.Parent = b
            return b
        end

        state.prevBtn = makeButton("Prev", 0)
        state.nextBtn = makeButton("Next", 78)

        state.pageLabel = Instance.new("TextLabel")
        state.pageLabel.BackgroundTransparency = 1
        state.pageLabel.Size = UDim2.new(1, -160, 1, 0)
        state.pageLabel.Position = UDim2.new(0, 160, 0, 0)
        state.pageLabel.Font = Enum.Font.Gotham
        state.pageLabel.TextSize = 12
        state.pageLabel.TextXAlignment = Enum.TextXAlignment.Left
        state.pageLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        state.pageLabel.Text = ""
        state.pageLabel.Parent = controls

        -- Grid
        state.gridFrame = Instance.new("Frame")
        state.gridFrame.BackgroundTransparency = 1
        state.gridFrame.Position = UDim2.new(0, 0, 0, headerH)
        state.gridFrame.Size = UDim2.new(1, 0, 1, -headerH)
        state.gridFrame.Parent = panel

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, state.paddingPx)
        pad.PaddingLeft = UDim.new(0, state.paddingPx)
        pad.PaddingRight = UDim.new(0, state.paddingPx)
        pad.PaddingBottom = UDim.new(0, state.paddingPx)
        pad.Parent = state.gridFrame

        local gridLayout = Instance.new("UIGridLayout")
        gridLayout.CellSize = UDim2.new(0, state.cellPx, 0, state.cellPx)
        gridLayout.CellPadding = UDim2.new(0, state.paddingPx, 0, state.paddingPx)
        gridLayout.FillDirectionMaxCells = state.columns
        gridLayout.Parent = state.gridFrame

        state.prevBtn.MouseButton1Click:Connect(function() M.prev() end)
        state.nextBtn.MouseButton1Click:Connect(function() M.next() end)
    end

    local function renderPage(p)
        if not state.gui or not state.gui.Parent then return end
        state.page = math.clamp(p, 1, state.totalPages)
        clearGrid()

        local startIndex = (state.page - 1) * state.perPage + 1
        local endIndex = math.min(startIndex + state.perPage - 1, #state.models)

        state.pageLabel.Text = ("Folder: %s  |  Page %d / %d  |  %d items")
            :format(state.folderName or "?", state.page, state.totalPages, #state.models)

        setButtonEnabled(state.prevBtn, state.page > 1)
        setButtonEnabled(state.nextBtn, state.page < state.totalPages)

        for idx = startIndex, endIndex do
            local src = state.models[idx]

            local cell = Instance.new("Frame")
            cell.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
            cell.BorderSizePixel = 0
            cell.Parent = state.gridFrame

            local cc = Instance.new("UICorner")
            cc.CornerRadius = UDim.new(0, 12)
            cc.Parent = cell

            local stroke = Instance.new("UIStroke")
            stroke.Thickness = 1
            stroke.Transparency = 0.65
            stroke.Parent = cell

            local nameLabel = Instance.new("TextLabel")
            nameLabel.BackgroundTransparency = 1
            nameLabel.Size = UDim2.new(1, -12, 0, 20)
            nameLabel.Position = UDim2.new(0, 6, 0, 6)
            nameLabel.Font = Enum.Font.Gotham
            nameLabel.TextSize = 12
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
            nameLabel.Text = src.Name
            nameLabel.Parent = cell

            local viewport = Instance.new("ViewportFrame")
            viewport.BackgroundTransparency = 1
            viewport.BorderSizePixel = 0
            viewport.Size = UDim2.new(1, -12, 1, -32)
            viewport.Position = UDim2.new(0, 6, 0, 26)
            viewport.Parent = cell

            local world = Instance.new("WorldModel")
            world.Parent = viewport

            local cam = Instance.new("Camera")
            cam.Parent = viewport
            viewport.CurrentCamera = cam

            local lightPart = Instance.new("Part")
            lightPart.Anchored = true
            lightPart.CanCollide = false
            lightPart.Transparency = 1
            lightPart.Parent = world

            local light = Instance.new("PointLight")
            light.Range = 60
            light.Brightness = 2
            light.Parent = lightPart

            local clone = sanitizeClone(src)
            clone.Parent = world

            local bboxCf, bboxSize = clone:GetBoundingBox()
            local base = CFrame.new(-bboxCf.Position)
            if state.faceCameraY180 then
                base = base * CFrame.Angles(0, math.rad(180), 0)
            end
            clone:PivotTo(base)

            lightPart.Position = Vector3.new(bboxSize.X, bboxSize.Y, bboxSize.Z) * 0.6 + Vector3.new(4, 6, 4)
            frameCamera(clone, cam)
        end
    end

    local function loadFolder(folderName)
        local folder = Workspace:FindFirstChild(folderName)
        if not folder then
            error(("Workspace.%s not found"):format(folderName))
        end

        local ms = {}
        for _, child in ipairs(folder:GetChildren()) do
            if child:IsA("Model") then
                table.insert(ms, child)
            end
        end
        table.sort(ms, function(a, b) return a.Name < b.Name end)
        if #ms == 0 then
            error(("No Models under Workspace.%s"):format(folderName))
        end

        state.folderName = folderName
        state.models = ms
        state.perPage = state.columns * state.rows
        state.totalPages = math.max(1, math.ceil(#ms / state.perPage))
        state.page = 1
    end

    function M.show(folderName)
        destroyExisting()
        buildUI()
        loadFolder(folderName)
        renderPage(1)
        return { ok = true, folder = folderName, pages = state.totalPages, items = #state.models }
    end

    function M.next()
        if state.page < state.totalPages then
            renderPage(state.page + 1)
        end
        return M.info()
    end

    function M.prev()
        if state.page > 1 then
            renderPage(state.page - 1)
        end
        return M.info()
    end

    function M.goto(p)
        renderPage(tonumber(p) or 1)
        return M.info()
    end

    function M.info()
        return {
            folder = state.folderName,
            page = state.page,
            totalPages = state.totalPages,
            totalItems = state.models and #state.models or 0,
            perPage = state.perPage,
        }
    end

    function M.destroy()
        destroyExisting()
        local old = CoreGui:FindFirstChild(state.guiName)
        if old then old:Destroy() end
    end

    return M
end)()

_G.Bakable.register("InventoryUI", InventoryUI)
return { ok = true, module = "InventoryUI" }
