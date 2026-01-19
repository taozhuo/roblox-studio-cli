--!strict
--[[
    Network/Replication Debugging - Monitor network ownership, RemoteEvent traffic
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Network = {}

-- Remote capture state
local isCapturing = false
local capturedEvents: {{
    time: number,
    remoteName: string,
    remotePath: string,
    direction: string,
    playerName: string?,
    args: {any}?
}} = {}
local captureStartTime = 0
local captureConnections: {RBXScriptConnection} = {}
local maxEvents = 1000
local filterPattern: string? = nil

-- Helper to get instance path
local function getPath(instance: Instance): string
    local path = instance.Name
    local current = instance.Parent
    while current and current ~= game do
        path = current.Name .. "." .. path
        current = current.Parent
    end
    return path
end

-- Helper to safely serialize arguments
local function serializeArgs(args: {any}): {any}
    local result = {}
    for i, arg in ipairs(args) do
        local argType = typeof(arg)
        if argType == "Instance" then
            result[i] = { _type = "Instance", path = getPath(arg), className = arg.ClassName }
        elseif argType == "Vector3" then
            result[i] = { _type = "Vector3", x = arg.X, y = arg.Y, z = arg.Z }
        elseif argType == "CFrame" then
            result[i] = { _type = "CFrame", position = {x = arg.Position.X, y = arg.Position.Y, z = arg.Position.Z} }
        elseif argType == "table" then
            result[i] = { _type = "table", preview = "[table]" }
        elseif argType == "string" or argType == "number" or argType == "boolean" then
            result[i] = arg
        else
            result[i] = { _type = argType, preview = tostring(arg) }
        end
    end
    return result
end

-- Get network ownership of parts
function Network.getOwnership(params: any): (boolean, any)
    local path = params.path or "workspace"
    local recursive = params.recursive or false

    local target = game
    for part in string.gmatch(path, "[^%.]+") do
        target = target:FindFirstChild(part)
        if not target then
            return false, "Instance not found: " .. path
        end
    end

    local results = {}

    local function checkOwnership(instance: Instance)
        if instance:IsA("BasePart") then
            local canSet, autoOwner = instance:CanSetNetworkOwnership()
            if canSet then
                local owner = instance:GetNetworkOwner()
                table.insert(results, {
                    path = getPath(instance),
                    owner = owner and owner.Name or "Server",
                    isAuto = autoOwner
                })
            end
        end
    end

    if target:IsA("BasePart") then
        checkOwnership(target)
    end

    if recursive then
        for _, desc in ipairs(target:GetDescendants()) do
            checkOwnership(desc)
            if #results >= 100 then break end -- Limit results
        end
    else
        for _, child in ipairs(target:GetChildren()) do
            checkOwnership(child)
        end
    end

    return true, {
        path = path,
        count = #results,
        parts = results
    }
end

-- Set network ownership
function Network.setOwnership(params: any): (boolean, any)
    local path = params.path
    if not path then
        return false, "Missing path parameter"
    end

    local target = game
    for part in string.gmatch(path, "[^%.]+") do
        target = target:FindFirstChild(part)
        if not target then
            return false, "Instance not found: " .. path
        end
    end

    if not target:IsA("BasePart") then
        return false, "Instance is not a BasePart"
    end

    local canSet = target:CanSetNetworkOwnership()
    if not canSet then
        return false, "Cannot set network ownership on this part (may be anchored)"
    end

    if params.auto then
        target:SetNetworkOwnershipAuto()
        return true, { path = path, owner = "Auto" }
    end

    local playerName = params.playerName
    if playerName then
        local player = Players:FindFirstChild(playerName)
        if not player then
            return false, "Player not found: " .. playerName
        end
        target:SetNetworkOwner(player)
        return true, { path = path, owner = playerName }
    else
        target:SetNetworkOwner(nil)
        return true, { path = path, owner = "Server" }
    end
end

-- Start capturing RemoteEvent traffic
function Network.startRemoteCapture(params: any): (boolean, any)
    if isCapturing then
        return false, "Already capturing"
    end

    filterPattern = params.filter
    maxEvents = params.maxEvents or 1000
    capturedEvents = {}
    captureStartTime = os.clock()
    isCapturing = true

    -- Find all RemoteEvents and RemoteFunctions
    local function hookRemote(remote: Instance)
        if filterPattern and not string.find(remote.Name, filterPattern) then
            return
        end

        if remote:IsA("RemoteEvent") then
            -- Server-side: OnServerEvent
            if RunService:IsServer() then
                local conn = remote.OnServerEvent:Connect(function(player, ...)
                    if isCapturing and #capturedEvents < maxEvents then
                        table.insert(capturedEvents, {
                            time = os.clock() - captureStartTime,
                            remoteName = remote.Name,
                            remotePath = getPath(remote),
                            direction = "ClientToServer",
                            playerName = player.Name,
                            args = serializeArgs({...})
                        })
                    end
                end)
                table.insert(captureConnections, conn)
            end
        elseif remote:IsA("RemoteFunction") then
            -- Note: Can't easily hook RemoteFunctions without replacing them
            -- This is a limitation
        end
    end

    -- Hook existing remotes
    for _, desc in ipairs(game:GetDescendants()) do
        if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
            hookRemote(desc)
        end
    end

    -- Hook new remotes
    local addedConn = game.DescendantAdded:Connect(function(desc)
        if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
            hookRemote(desc)
        end
    end)
    table.insert(captureConnections, addedConn)

    return true, {
        message = "Remote capture started",
        filter = filterPattern,
        maxEvents = maxEvents
    }
end

-- Stop capturing
function Network.stopRemoteCapture(params: any): (boolean, any)
    if not isCapturing then
        return false, "Not capturing"
    end

    isCapturing = false

    -- Disconnect all
    for _, conn in ipairs(captureConnections) do
        conn:Disconnect()
    end
    captureConnections = {}

    local duration = os.clock() - captureStartTime

    return true, {
        message = "Remote capture stopped",
        duration = duration,
        eventCount = #capturedEvents,
        events = capturedEvents
    }
end

-- Get captured history
function Network.getRemoteHistory(params: any): (boolean, any)
    local limit = params.limit or 100

    local events = {}
    local startIdx = math.max(1, #capturedEvents - limit + 1)
    for i = startIdx, #capturedEvents do
        table.insert(events, capturedEvents[i])
    end

    return true, {
        isCapturing = isCapturing,
        totalEvents = #capturedEvents,
        events = events
    }
end

-- Measure latency (requires Play mode with client)
function Network.measureLatency(params: any): (boolean, any)
    if not RunService:IsRunning() then
        return false, "Must be in Play mode"
    end

    -- In Studio, we can get the local player's ping
    local player = Players.LocalPlayer
    if not player then
        return false, "No local player (server-only mode?)"
    end

    local samples = params.samples or 5
    local measurements = {}

    -- Use Stats service for network stats
    local Stats = game:GetService("Stats")

    for i = 1, samples do
        -- Get current ping from Stats
        local ping = player:GetNetworkPing() * 1000 -- Convert to ms
        table.insert(measurements, ping)
        if i < samples then
            task.wait(0.1)
        end
    end

    local sum = 0
    local min = measurements[1]
    local max = measurements[1]
    for _, m in ipairs(measurements) do
        sum = sum + m
        min = math.min(min, m)
        max = math.max(max, m)
    end

    return true, {
        samples = measurements,
        averageMs = sum / #measurements,
        minMs = min,
        maxMs = max
    }
end

-- List all remotes in game
function Network.listRemotes(params: any): (boolean, any)
    local remoteEvents = {}
    local remoteFunctions = {}

    for _, desc in ipairs(game:GetDescendants()) do
        if desc:IsA("RemoteEvent") then
            table.insert(remoteEvents, {
                name = desc.Name,
                path = getPath(desc)
            })
        elseif desc:IsA("RemoteFunction") then
            table.insert(remoteFunctions, {
                name = desc.Name,
                path = getPath(desc)
            })
        end
    end

    return true, {
        remoteEvents = remoteEvents,
        remoteFunctions = remoteFunctions,
        totalEvents = #remoteEvents,
        totalFunctions = #remoteFunctions
    }
end

return Network
