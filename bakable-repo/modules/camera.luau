-- Camera: Position camera for screenshots and overviews
-- Requires: bootstrap

if not _G.Bakable then
    error("Run bootstrap first: _G.Bakable not found")
end

local Camera = {}
local savedPositions = {}

-- Get current camera
local function getCamera()
    return workspace.CurrentCamera
end

-- Look at a position from a given distance and angle
function Camera.lookAt(options)
    options = options or {}

    local targetX = options.x or 0
    local targetY = options.y or 0
    local targetZ = options.z or 0
    local distance = options.distance or 50
    local pitch = options.pitch or -30 -- degrees, negative = looking down
    local yaw = options.yaw or 45 -- degrees

    local target = Vector3.new(targetX, targetY, targetZ)
    local pitchRad = math.rad(pitch)
    local yawRad = math.rad(yaw)

    -- Calculate camera position
    local offsetX = distance * math.cos(pitchRad) * math.sin(yawRad)
    local offsetY = distance * math.sin(-pitchRad)
    local offsetZ = distance * math.cos(pitchRad) * math.cos(yawRad)

    local camPos = target + Vector3.new(offsetX, offsetY, offsetZ)
    local cam = getCamera()
    cam.CFrame = CFrame.lookAt(camPos, target)

    return {
        ok = true,
        position = { x = camPos.X, y = camPos.Y, z = camPos.Z },
        target = { x = targetX, y = targetY, z = targetZ },
    }
end

-- Bird's eye view over a region
function Camera.birdEye(options)
    options = options or {}

    local x = options.x or 0
    local z = options.z or 0
    local width = options.width or 100
    local depth = options.depth or 100
    local height = options.height or nil -- auto-calculate
    local tilt = options.tilt or 0 -- 0 = straight down, positive = tilt forward

    local viewSize = math.max(width, depth)
    local camHeight = height or viewSize * 0.8

    local cam = getCamera()
    local target = Vector3.new(x, 0, z)

    if tilt == 0 then
        -- Straight down
        cam.CFrame = CFrame.lookAt(
            Vector3.new(x, camHeight, z),
            target
        )
    else
        -- Tilted view
        local tiltRad = math.rad(tilt)
        local offsetZ = camHeight * math.tan(tiltRad)
        cam.CFrame = CFrame.lookAt(
            Vector3.new(x, camHeight, z + offsetZ),
            Vector3.new(x, 0, z)
        )
    end

    return {
        ok = true,
        height = camHeight,
        viewSize = viewSize,
        center = { x = x, z = z },
    }
end

-- Frame a folder/model to fit in view
function Camera.frameFolder(folderPath, options)
    options = options or {}

    local current = game
    local parts = folderPath:gsub("%.", "/"):split("/")
    for _, part in ipairs(parts) do
        current = current:FindFirstChild(part)
        if not current then
            return { error = ("Not found: %s"):format(part) }
        end
    end

    -- Get bounding box of all parts
    local minX, minZ = math.huge, math.huge
    local maxX, maxZ = -math.huge, -math.huge
    local maxY = 0

    for _, item in ipairs(current:GetDescendants()) do
        if item:IsA("BasePart") then
            local pos = item.Position
            local size = item.Size
            minX = math.min(minX, pos.X - size.X / 2)
            maxX = math.max(maxX, pos.X + size.X / 2)
            minZ = math.min(minZ, pos.Z - size.Z / 2)
            maxZ = math.max(maxZ, pos.Z + size.Z / 2)
            maxY = math.max(maxY, pos.Y + size.Y / 2)
        end
    end

    if minX == math.huge then
        return { error = "No parts found in folder" }
    end

    local centerX = (minX + maxX) / 2
    local centerZ = (minZ + maxZ) / 2
    local width = maxX - minX
    local depth = maxZ - minZ
    local viewSize = math.max(width, depth)

    local angle = options.angle or 30
    local angleRad = math.rad(angle)
    local camHeight = viewSize * (0.8 + math.cos(angleRad) * 0.5)
    local camOffset = viewSize * math.sin(angleRad) * 0.5

    local cam = getCamera()
    cam.CFrame = CFrame.lookAt(
        Vector3.new(centerX + camOffset, camHeight, centerZ + camOffset),
        Vector3.new(centerX, maxY / 2, centerZ)
    )

    return {
        ok = true,
        bounds = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ, maxY = maxY },
        center = { x = centerX, z = centerZ },
        viewSize = viewSize,
        cameraHeight = camHeight,
    }
end

-- Frame a specific model
function Camera.frameModel(model, options)
    options = options or {}

    if type(model) == "string" then
        model = game:FindFirstChild(model, true)
    end
    if not model then
        return { error = "Model not found" }
    end

    local cf, size = model:GetBoundingBox()
    local center = cf.Position
    local maxDim = math.max(size.X, size.Y, size.Z)

    local distance = options.distance or maxDim * 2
    local pitch = options.pitch or -20
    local yaw = options.yaw or 35

    local pitchRad = math.rad(pitch)
    local yawRad = math.rad(yaw)
    local look = (CFrame.Angles(pitchRad, yawRad, 0)).LookVector

    local cam = getCamera()
    cam.CFrame = CFrame.lookAt(center - look * distance, center)
    cam.FieldOfView = options.fov or 40

    return {
        ok = true,
        center = { x = center.X, y = center.Y, z = center.Z },
        size = { x = size.X, y = size.Y, z = size.Z },
        distance = distance,
    }
end

-- Save current camera position
function Camera.save(name)
    name = name or "default"
    local cam = getCamera()
    savedPositions[name] = {
        cframe = cam.CFrame,
        fov = cam.FieldOfView,
    }
    return { ok = true, saved = name }
end

-- Restore saved camera position
function Camera.restore(name)
    name = name or "default"
    local saved = savedPositions[name]
    if not saved then
        return { error = ("No saved position: %s"):format(name) }
    end

    local cam = getCamera()
    cam.CFrame = saved.cframe
    cam.FieldOfView = saved.fov

    return { ok = true, restored = name }
end

-- List saved positions
function Camera.listSaved()
    local names = {}
    for name in pairs(savedPositions) do
        table.insert(names, name)
    end
    return names
end

-- Get current camera info
function Camera.info()
    local cam = getCamera()
    local cf = cam.CFrame
    return {
        position = { x = cf.Position.X, y = cf.Position.Y, z = cf.Position.Z },
        lookVector = { x = cf.LookVector.X, y = cf.LookVector.Y, z = cf.LookVector.Z },
        fov = cam.FieldOfView,
    }
end

function Camera.destroy()
    savedPositions = {}
end

_G.Bakable.register("Camera", Camera)
return { ok = true, module = "Camera" }
