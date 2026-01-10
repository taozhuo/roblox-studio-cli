--!strict
--[[
    Elements Handler - Instance tree and selection operations

    Provides Chrome DevTools Elements panel functionality:
    - Selection management
    - Instance tree traversal
    - Property get/set
    - Instance creation/deletion
]]

local Selection = game:GetService("Selection")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Elements = {}

-- Plugin reference for PluginMouse control
local pluginRef: Plugin? = nil
local pluginMouse: PluginMouse? = nil

-- Store last mouse position for "point here" feature
local lastMouseHit: {
    position: Vector3?,
    instance: Instance?,
    normal: Vector3?,
    timestamp: number
} = { timestamp = 0 }

-- Path drawing state
local pathPoints: {{
    position: {x: number, y: number, z: number},
    instance: string?,
    timestamp: number
}} = {}
local isRecordingPath: boolean = false
local isDragging: boolean = false
local pathConnections: {RBXScriptConnection} = {}
local visualsFolder: Folder? = nil
local lastPointPosition: Vector3? = nil
local MIN_POINT_DISTANCE = 2 -- Minimum studs between points when dragging

-- Initialize with plugin reference (call from init.server.lua)
function Elements.setPlugin(plugin: Plugin)
    pluginRef = plugin
end

-- Helper: Parse instance path like "Workspace/Part1/SubPart"
local function getInstanceByPath(pathStr: string): Instance?
    local parts = string.split(pathStr, "/")
    local current: Instance = game

    for _, part in ipairs(parts) do
        if part == "game" then
            current = game
        else
            local child = current:FindFirstChild(part)
            if not child then
                return nil
            end
            current = child
        end
    end

    return current
end

-- Helper: Get full path of an instance
local function getInstancePath(instance: Instance): string
    local parts = {}
    local current: Instance? = instance

    while current and current ~= game do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end

    return table.concat(parts, "/")
end

-- Helper: Serialize instance for JSON
local function serializeInstance(instance: Instance, includeProps: boolean?): any
    local result: any = {
        name = instance.Name,
        className = instance.ClassName,
        path = getInstancePath(instance)
    }

    if includeProps then
        result.properties = {}
        -- Get common properties safely
        local props = {"Name", "Parent", "Archivable"}

        -- Class-specific properties
        if instance:IsA("BasePart") then
            table.insert(props, "Position")
            table.insert(props, "Size")
            table.insert(props, "Color")
            table.insert(props, "Material")
            table.insert(props, "Anchored")
            table.insert(props, "CanCollide")
            table.insert(props, "Transparency")
        elseif instance:IsA("Model") then
            table.insert(props, "PrimaryPart")
        elseif instance:IsA("LuaSourceContainer") then
            -- Script properties handled in Sources module
        end

        for _, propName in ipairs(props) do
            local success, value = pcall(function()
                return (instance :: any)[propName]
            end)
            if success then
                -- Convert complex types to string
                if typeof(value) == "Vector3" then
                    result.properties[propName] = string.format("%.2f, %.2f, %.2f", value.X, value.Y, value.Z)
                elseif typeof(value) == "Color3" then
                    result.properties[propName] = string.format("%.2f, %.2f, %.2f", value.R, value.G, value.B)
                elseif typeof(value) == "Instance" then
                    result.properties[propName] = value.Name
                elseif typeof(value) == "EnumItem" then
                    result.properties[propName] = tostring(value)
                else
                    result.properties[propName] = value
                end
            end
        end
    end

    return result
end

-- Get current selection
function Elements.getSelection(params: any): (boolean, any)
    local selected = Selection:Get()
    local result = {}

    for _, instance in ipairs(selected) do
        table.insert(result, serializeInstance(instance, true))
    end

    return true, { selection = result, count = #result }
end

-- Set selection by paths
function Elements.setSelection(params: any): (boolean, any)
    local paths = params.paths
    if not paths or type(paths) ~= "table" then
        return false, "Missing or invalid paths array"
    end

    local instances = {}
    local notFound = {}

    for _, pathStr in ipairs(paths) do
        local instance = getInstanceByPath(pathStr)
        if instance then
            table.insert(instances, instance)
        else
            table.insert(notFound, pathStr)
        end
    end

    Selection:Set(instances)

    return true, {
        selected = #instances,
        notFound = notFound
    }
end

-- Get instance tree
function Elements.getInstanceTree(params: any): (boolean, any)
    local rootPath = params.root or "game"
    local maxDepth = params.depth or 3
    local classFilter = params.classFilter
    local namePattern = params.namePattern

    local root = getInstanceByPath(rootPath)
    if not root then
        return false, string.format("Root not found: %s", rootPath)
    end

    local function shouldInclude(instance: Instance): boolean
        -- Class filter
        if classFilter and type(classFilter) == "table" then
            local found = false
            for _, cls in ipairs(classFilter) do
                if instance:IsA(cls) then
                    found = true
                    break
                end
            end
            if not found then return false end
        end

        -- Name pattern
        if namePattern and type(namePattern) == "string" then
            if not string.match(instance.Name, namePattern) then
                return false
            end
        end

        return true
    end

    local function buildTree(instance: Instance, depth: number): any?
        if depth > maxDepth then
            return nil
        end

        if not shouldInclude(instance) then
            return nil
        end

        local node: any = {
            name = instance.Name,
            className = instance.ClassName,
            path = getInstancePath(instance),
            children = {}
        }

        if depth < maxDepth then
            for _, child in ipairs(instance:GetChildren()) do
                local childNode = buildTree(child, depth + 1)
                if childNode then
                    table.insert(node.children, childNode)
                end
            end
        else
            -- Just count children at max depth
            node.childCount = #instance:GetChildren()
        end

        return node
    end

    local tree = buildTree(root, 0)
    return true, { tree = tree }
end

-- Get instance properties
function Elements.getInstanceProps(params: any): (boolean, any)
    local pathStr = params.path
    if not pathStr then
        return false, "Missing path parameter"
    end

    local instance = getInstanceByPath(pathStr)
    if not instance then
        return false, string.format("Instance not found: %s", pathStr)
    end

    return true, serializeInstance(instance, true)
end

-- Set instance properties
function Elements.setInstanceProps(params: any): (boolean, any)
    local pathStr = params.path
    local properties = params.properties

    if not pathStr then
        return false, "Missing path parameter"
    end
    if not properties or type(properties) ~= "table" then
        return false, "Missing or invalid properties"
    end

    local instance = getInstanceByPath(pathStr)
    if not instance then
        return false, string.format("Instance not found: %s", pathStr)
    end

    local set = {}
    local failed = {}

    for propName, value in pairs(properties) do
        local success, err = pcall(function()
            -- Handle special type conversions
            if propName == "Position" or propName == "Size" then
                if type(value) == "string" then
                    local x, y, z = string.match(value, "([%d%.%-]+),%s*([%d%.%-]+),%s*([%d%.%-]+)")
                    if x and y and z then
                        (instance :: any)[propName] = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
                    end
                elseif type(value) == "table" then
                    (instance :: any)[propName] = Vector3.new(value.x or value[1], value.y or value[2], value.z or value[3])
                end
            elseif propName == "Color" then
                if type(value) == "string" then
                    local r, g, b = string.match(value, "([%d%.]+),%s*([%d%.]+),%s*([%d%.]+)")
                    if r and g and b then
                        (instance :: any)[propName] = Color3.new(tonumber(r), tonumber(g), tonumber(b))
                    end
                elseif type(value) == "table" then
                    (instance :: any)[propName] = Color3.new(value.r or value[1], value.g or value[2], value.b or value[3])
                end
            else
                (instance :: any)[propName] = value
            end
        end)

        if success then
            table.insert(set, propName)
        else
            table.insert(failed, { property = propName, error = tostring(err) })
        end
    end

    return true, { set = set, failed = failed }
end

-- Create new instance
function Elements.createInstance(params: any): (boolean, any)
    local className = params.className
    local parentPath = params.parent
    local name = params.name
    local properties = params.properties

    if not className then
        return false, "Missing className parameter"
    end
    if not parentPath then
        return false, "Missing parent parameter"
    end

    local parent = getInstanceByPath(parentPath)
    if not parent then
        return false, string.format("Parent not found: %s", parentPath)
    end

    local success, result = pcall(function()
        local instance = Instance.new(className)
        if name then
            instance.Name = name
        end

        -- Set properties before parenting
        if properties and type(properties) == "table" then
            for propName, value in pairs(properties) do
                pcall(function()
                    (instance :: any)[propName] = value
                end)
            end
        end

        instance.Parent = parent
        return instance
    end)

    if not success then
        return false, string.format("Failed to create instance: %s", tostring(result))
    end

    return true, serializeInstance(result :: Instance, false)
end

-- Delete instance
function Elements.deleteInstance(params: any): (boolean, any)
    local pathStr = params.path
    if not pathStr then
        return false, "Missing path parameter"
    end

    local instance = getInstanceByPath(pathStr)
    if not instance then
        return false, string.format("Instance not found: %s", pathStr)
    end

    if instance == game or instance == workspace then
        return false, "Cannot delete game or workspace"
    end

    local name = instance.Name
    instance:Destroy()

    return true, { deleted = name }
end

-- Get mouse pointer position (raycast from camera through mouse)
function Elements.getMousePointer(params: any): (boolean, any)
    local camera = Workspace.CurrentCamera
    if not camera then
        return false, "No camera found"
    end

    -- Get mouse location
    local mouseLocation = UserInputService:GetMouseLocation()

    -- Create ray from camera through mouse position
    local unitRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
    local ray = Ray.new(unitRay.Origin, unitRay.Direction * 1000)

    -- Raycast to find what mouse is pointing at
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {} -- Don't exclude anything

    local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)

    if result then
        lastMouseHit = {
            position = result.Position,
            instance = result.Instance,
            normal = result.Normal,
            timestamp = os.time()
        }

        return true, {
            position = {
                x = result.Position.X,
                y = result.Position.Y,
                z = result.Position.Z
            },
            normal = {
                x = result.Normal.X,
                y = result.Normal.Y,
                z = result.Normal.Z
            },
            instance = result.Instance and {
                name = result.Instance.Name,
                className = result.Instance.ClassName,
                path = getInstancePath(result.Instance)
            } or nil,
            distance = result.Distance
        }
    else
        return true, {
            position = nil,
            instance = nil,
            message = "Mouse not pointing at anything"
        }
    end
end

-- Get last recorded mouse hit (for "put it here" commands)
function Elements.getLastPointer(params: any): (boolean, any)
    if lastMouseHit.position then
        return true, {
            position = {
                x = lastMouseHit.position.X,
                y = lastMouseHit.position.Y,
                z = lastMouseHit.position.Z
            },
            normal = lastMouseHit.normal and {
                x = lastMouseHit.normal.X,
                y = lastMouseHit.normal.Y,
                z = lastMouseHit.normal.Z
            } or nil,
            instance = lastMouseHit.instance and {
                name = lastMouseHit.instance.Name,
                className = lastMouseHit.instance.ClassName,
                path = getInstancePath(lastMouseHit.instance)
            } or nil,
            timestamp = lastMouseHit.timestamp,
            age = os.time() - lastMouseHit.timestamp
        }
    else
        return true, {
            position = nil,
            message = "No pointer recorded yet. Use studio.pointer.capture first."
        }
    end
end

-- ============ Path Drawing & Visual Markers ============

-- Create or get the visuals folder (must be defined before showCapturedMarker)
local function getVisualsFolder(): Folder
    if visualsFolder and visualsFolder.Parent then
        return visualsFolder
    end
    visualsFolder = Instance.new("Folder")
    visualsFolder.Name = "DetAI_PathVisuals"
    visualsFolder.Parent = Workspace
    return visualsFolder
end

-- Visual marker for captured pointer
local capturedMarker: Part? = nil

-- Create a visual marker for captured position
local function showCapturedMarker(position: Vector3)
    -- Remove old marker if exists
    if capturedMarker and capturedMarker.Parent then
        capturedMarker:Destroy()
    end

    local folder = getVisualsFolder()

    capturedMarker = Instance.new("Part")
    capturedMarker.Name = "CapturedPoint"
    capturedMarker.Shape = Enum.PartType.Ball
    capturedMarker.Size = Vector3.new(2, 2, 2)
    capturedMarker.Position = position
    capturedMarker.Anchored = true
    capturedMarker.CanCollide = false
    capturedMarker.Material = Enum.Material.Neon
    capturedMarker.Color = Color3.fromRGB(255, 100, 0) -- Orange for captured point
    capturedMarker.Transparency = 0.2
    capturedMarker.Parent = folder

    -- Add a beam pointing up for visibility
    local attachment0 = Instance.new("Attachment")
    attachment0.Position = Vector3.new(0, 0, 0)
    attachment0.Parent = capturedMarker

    local attachment1 = Instance.new("Attachment")
    attachment1.Position = Vector3.new(0, 5, 0)
    attachment1.Parent = capturedMarker

    local beam = Instance.new("Beam")
    beam.Attachment0 = attachment0
    beam.Attachment1 = attachment1
    beam.Width0 = 0.5
    beam.Width1 = 0
    beam.Color = ColorSequence.new(Color3.fromRGB(255, 100, 0))
    beam.LightEmission = 1
    beam.Parent = capturedMarker
end

-- Capture current mouse position (call this when user says "here")
function Elements.capturePointer(params: any): (boolean, any)
    local success, result = Elements.getMousePointer(params)

    -- Show visual marker if we got a position
    if success and result and result.position then
        local pos = Vector3.new(result.position.x, result.position.y, result.position.z)
        showCapturedMarker(pos)
    end

    return success, result
end

-- Create a visual marker at a position
local function createPointMarker(position: Vector3, index: number): Part
    local folder = getVisualsFolder()

    local marker = Instance.new("Part")
    marker.Name = "PathPoint_" .. index
    marker.Shape = Enum.PartType.Ball
    marker.Size = Vector3.new(1, 1, 1)
    marker.Position = position
    marker.Anchored = true
    marker.CanCollide = false
    marker.Material = Enum.Material.Neon
    marker.Color = Color3.fromRGB(0, 170, 255)
    marker.Transparency = 0.3
    marker.Parent = folder

    return marker
end

-- Create a line between two points
local function createLineBetween(from: Vector3, to: Vector3, index: number): Part
    local folder = getVisualsFolder()

    local distance = (to - from).Magnitude
    local midpoint = (from + to) / 2

    local line = Instance.new("Part")
    line.Name = "PathLine_" .. index
    line.Size = Vector3.new(0.3, 0.3, distance)
    line.CFrame = CFrame.lookAt(midpoint, to)
    line.Anchored = true
    line.CanCollide = false
    line.Material = Enum.Material.Neon
    line.Color = Color3.fromRGB(0, 255, 100)
    line.Transparency = 0.5
    line.Parent = folder

    return line
end

-- Clear all visual markers
local function clearVisuals()
    if visualsFolder and visualsFolder.Parent then
        visualsFolder:Destroy()
        visualsFolder = nil
    end
end

-- Add a point to the path from current mouse position
local function addPathPoint(forceAdd: boolean?): boolean
    local camera = Workspace.CurrentCamera
    if not camera then return false end

    local mouseLocation = UserInputService:GetMouseLocation()
    local unitRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = { getVisualsFolder() } -- Ignore our own visuals

    local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)

    if result then
        local newPos = result.Position

        -- Check minimum distance when dragging (unless forceAdd)
        if not forceAdd and lastPointPosition then
            local distance = (newPos - lastPointPosition).Magnitude
            if distance < MIN_POINT_DISTANCE then
                return false -- Too close to last point
            end
        end

        -- Add the point
        table.insert(pathPoints, {
            position = {
                x = newPos.X,
                y = newPos.Y,
                z = newPos.Z
            },
            instance = result.Instance and getInstancePath(result.Instance) or nil,
            timestamp = os.time()
        })

        local pointIndex = #pathPoints

        -- Create visual marker
        createPointMarker(newPos, pointIndex)

        -- Create line to previous point
        if lastPointPosition then
            createLineBetween(lastPointPosition, newPos, pointIndex - 1)
        end

        lastPointPosition = newPos

        print(string.format("[Bakable] Path point %d added at (%.1f, %.1f, %.1f)",
            pointIndex, newPos.X, newPos.Y, newPos.Z))

        return true
    end

    return false
end

-- Disconnect all path connections
local function disconnectPathConnections()
    for _, conn in ipairs(pathConnections) do
        if conn.Connected then
            conn:Disconnect()
        end
    end
    pathConnections = {}
end

-- Start recording a path (drag to draw)
function Elements.startPath(params: any): (boolean, any)
    if isRecordingPath then
        return false, "Already recording a path. Use studio.path.stop first."
    end

    if not pluginRef then
        return false, "Plugin reference not set. Call Elements.setPlugin() first."
    end

    -- Clear previous path and visuals
    pathPoints = {}
    lastPointPosition = nil
    isDragging = false
    isRecordingPath = true
    clearVisuals()

    -- Disconnect any existing connections
    disconnectPathConnections()

    -- Activate plugin to get exclusive mouse control
    pluginRef:Activate(true)
    pluginMouse = pluginRef:GetMouse()

    if pluginMouse then
        -- Mouse down - start dragging and add first point
        table.insert(pathConnections, pluginMouse.Button1Down:Connect(function()
            isDragging = true
            addPathPoint(true) -- Force add first point
        end))

        -- Mouse move - add points while dragging
        table.insert(pathConnections, pluginMouse.Move:Connect(function()
            if isDragging then
                addPathPoint(false) -- Distance check applies
            end
        end))

        -- Mouse up - stop dragging (but keep recording mode)
        table.insert(pathConnections, pluginMouse.Button1Up:Connect(function()
            isDragging = false
        end))

        print("[Bakable] Path recording started - click and drag to draw path")
    else
        -- Fallback to UserInputService
        table.insert(pathConnections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isDragging = true
                addPathPoint(true)
            end
        end))

        table.insert(pathConnections, UserInputService.InputChanged:Connect(function(input, gameProcessed)
            if input.UserInputType == Enum.UserInputType.MouseMovement and isDragging then
                addPathPoint(false)
            end
        end))

        table.insert(pathConnections, UserInputService.InputEnded:Connect(function(input, gameProcessed)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isDragging = false
            end
        end))

        print("[Bakable] Path recording started (fallback mode) - click and drag to draw")
    end

    return true, {
        recording = true,
        message = "Click and drag in the viewport to draw a path. Use studio.path.stop when done."
    }
end

-- Stop recording path
function Elements.stopPath(params: any): (boolean, any)
    if not isRecordingPath then
        return false, "Not currently recording a path"
    end

    isRecordingPath = false
    isDragging = false

    -- Disconnect all connections
    disconnectPathConnections()

    -- Deactivate plugin to return mouse control to Studio
    if pluginRef then
        pluginRef:Deactivate()
    end
    pluginMouse = nil

    -- Clear visuals (optional - could keep them until clearPath)
    clearVisuals()

    print(string.format("[Bakable] Path recording stopped - %d points captured", #pathPoints))

    return true, {
        recording = false,
        pointCount = #pathPoints,
        points = pathPoints
    }
end

-- Get current path points
function Elements.getPath(params: any): (boolean, any)
    return true, {
        recording = isRecordingPath,
        pointCount = #pathPoints,
        points = pathPoints
    }
end

-- Clear path
function Elements.clearPath(params: any): (boolean, any)
    local count = #pathPoints
    pathPoints = {}
    lastPointPosition = nil

    -- Clear visuals
    clearVisuals()

    if isRecordingPath then
        isRecordingPath = false
        isDragging = false
        disconnectPathConnections()
        -- Deactivate plugin to return mouse control to Studio
        if pluginRef then
            pluginRef:Deactivate()
        end
        pluginMouse = nil
    end

    return true, {
        cleared = count,
        message = string.format("Cleared %d path points", count)
    }
end

-- Add single point to path manually (without clicking)
function Elements.addPathPoint(params: any): (boolean, any)
    if params.position then
        -- Use provided position
        table.insert(pathPoints, {
            position = {
                x = params.position.x or params.position[1],
                y = params.position.y or params.position[2],
                z = params.position.z or params.position[3]
            },
            instance = nil,
            timestamp = os.time()
        })
    else
        -- Use current mouse position
        addPathPoint()
    end

    return true, {
        pointCount = #pathPoints,
        lastPoint = pathPoints[#pathPoints]
    }
end

return Elements
