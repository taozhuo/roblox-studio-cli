--!strict
--[[
    Console Handler - Logs and code evaluation

    Provides Chrome DevTools Console panel functionality:
    - Log history retrieval
    - Log filtering
    - Luau code evaluation (command bar style)
]]

local LogService = game:GetService("LogService")

-- Capture require at module level for sandbox use
local _require = require

local Console = {}

-- Log history buffer
local logHistory: {{
    id: number,
    timestamp: number,
    level: string,
    message: string,
    source: string?
}} = {}

local MAX_LOG_HISTORY = 1000
local logConnection: RBXScriptConnection? = nil
local nextLogId = 1  -- Incrementing ID for cursor-based fetching

-- Ensure __Bakable ModuleScript exists in ReplicatedStorage
-- This serves as our persistent global namespace (like _G but scoped)
local function ensureBakableModule()
    local RS = game:GetService("ReplicatedStorage")
    local moduleScript = RS:FindFirstChild("__Bakable")

    if not moduleScript then
        moduleScript = Instance.new("ModuleScript")
        moduleScript.Name = "__Bakable"
        moduleScript.Source = "return {}"
        moduleScript.Parent = RS
        print("[Bakable] Created __Bakable module in ReplicatedStorage")
    end

    return moduleScript
end

-- Get the Bakable table (require it once, cache forever)
local _BakableTable = nil
local function getBakableTable()
    if _BakableTable then return _BakableTable end
    local mod = ensureBakableModule()
    _BakableTable = _require(mod)
    return _BakableTable
end

-- Call on load to ensure module exists
ensureBakableModule()

-- Initialize log capture
function Console.init()
    if logConnection then
        logConnection:Disconnect()
    end

    -- Capture existing logs
    local existingLogs = LogService:GetLogHistory()
    for _, entry in ipairs(existingLogs) do
        Console.addLogEntry(entry.message, entry.messageType)
    end

    -- Subscribe to new logs
    logConnection = LogService.MessageOut:Connect(function(message: string, messageType: Enum.MessageType)
        Console.addLogEntry(message, messageType)
    end)

    print("[Bakable] Console log capture initialized (v2-persist)")
end

-- Add log entry to history
function Console.addLogEntry(message: string, messageType: Enum.MessageType)
    local level = "info"
    if messageType == Enum.MessageType.MessageWarning then
        level = "warn"
    elseif messageType == Enum.MessageType.MessageError then
        level = "error"
    elseif messageType == Enum.MessageType.MessageInfo then
        level = "info"
    elseif messageType == Enum.MessageType.MessageOutput then
        level = "print"
    end

    table.insert(logHistory, {
        id = nextLogId,
        timestamp = os.time(),
        level = level,
        message = message,
        source = nil -- Could parse from message if needed
    })
    nextLogId = nextLogId + 1

    -- Trim history if too large
    while #logHistory > MAX_LOG_HISTORY do
        table.remove(logHistory, 1)
    end
end

-- Get log history (supports cursor-based incremental fetching)
function Console.getLogHistory(params: any): (boolean, any)
    local limit = params.limit or 100
    local levels = params.levels
    local pattern = params.pattern
    local cursor = params.cursor  -- Log ID to start after (for incremental fetching)

    local result = {}
    local count = 0
    local lastId = 0

    -- Find starting index if cursor provided
    local startIndex = 1
    if cursor and type(cursor) == "number" then
        for i, entry in ipairs(logHistory) do
            if entry.id > cursor then
                startIndex = i
                break
            end
        end
        -- If cursor is newer than all logs, start from end (no new logs)
        if #logHistory > 0 and logHistory[#logHistory].id <= cursor then
            return true, {
                logs = {},
                count = 0,
                cursor = cursor,
                hasMore = false
            }
        end
    end

    -- Iterate from startIndex (oldest first for cursor mode, newest first otherwise)
    if cursor then
        -- Cursor mode: return logs AFTER cursor, oldest first
        for i = startIndex, #logHistory do
            if count >= limit then
                break
            end

            local entry = logHistory[i]

            -- Filter by level
            if levels and type(levels) == "table" then
                local found = false
                for _, level in ipairs(levels) do
                    if entry.level == level then
                        found = true
                        break
                    end
                end
                if not found then
                    continue
                end
            end

            -- Filter by pattern
            if pattern and type(pattern) == "string" then
                if not string.find(entry.message, pattern, 1, true) then
                    continue
                end
            end

            table.insert(result, entry)
            lastId = entry.id
            count = count + 1
        end
    else
        -- No cursor: return newest logs (backwards iteration)
        for i = #logHistory, 1, -1 do
            if count >= limit then
                break
            end

            local entry = logHistory[i]

            -- Filter by level
            if levels and type(levels) == "table" then
                local found = false
                for _, level in ipairs(levels) do
                    if entry.level == level then
                        found = true
                        break
                    end
                end
                if not found then
                    continue
                end
            end

            -- Filter by pattern
            if pattern and type(pattern) == "string" then
                if not string.find(entry.message, pattern, 1, true) then
                    continue
                end
            end

            table.insert(result, 1, entry) -- Insert at beginning to maintain order
            if entry.id > lastId then
                lastId = entry.id
            end
            count = count + 1
        end
    end

    -- Determine if there are more logs
    local hasMore = false
    if #logHistory > 0 then
        hasMore = lastId < logHistory[#logHistory].id
    end

    return true, {
        logs = result,
        count = #result,
        cursor = lastId,  -- Use this cursor for next call to get only new logs
        hasMore = hasMore,
        totalInHistory = #logHistory
    }
end

-- Clear log history
function Console.clearLogs(params: any): (boolean, any)
    local count = #logHistory
    logHistory = {}
    return true, { cleared = count }
end

-- Evaluate Luau code
function Console.eval(params: any): (boolean, any)
    local code = params.code
    local timeout = params.timeout or 5000

    if not code or type(code) ~= "string" then
        return false, "Missing or invalid code parameter"
    end

    -- Compile the code
    local func, compileError = loadstring(code)
    if not func then
        return false, string.format("Compile error: %s", tostring(compileError))
    end

    -- Set up environment with common globals
    local env = setmetatable({
        game = game,
        workspace = workspace,
        script = nil,
        require = _require,  -- Allow require() for modules
        Bakable = getBakableTable(),  -- Direct access to __Bakable table
        pcall = pcall,
        xpcall = xpcall,
        print = print,
        warn = warn,
        error = error,
        assert = assert,
        typeof = typeof,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        select = select,
        unpack = unpack,
        rawget = rawget,
        rawset = rawset,
        rawequal = rawequal,
        setmetatable = setmetatable,
        getmetatable = getmetatable,
        table = table,
        string = string,
        math = math,
        os = { time = os.time, date = os.date, clock = os.clock },
        Instance = Instance,
        Vector3 = Vector3,
        Vector2 = Vector2,
        CFrame = CFrame,
        Color3 = Color3,
        BrickColor = BrickColor,
        UDim = UDim,
        UDim2 = UDim2,
        Enum = Enum,
        task = task,
        wait = task.wait,
        spawn = task.spawn,
        delay = task.delay,
    }, {__index = function(_, key)
        -- Allow access to services
        local success, service = pcall(function()
            return game:GetService(key)
        end)
        if success then
            return service
        end
        return nil
    end})

    setfenv(func, env)

    -- Execute with timeout protection
    local results = {}
    local execError = nil
    local completed = false

    task.spawn(function()
        local success, result = pcall(func)
        if success then
            results = {result}
        else
            execError = result
        end
        completed = true
    end)

    -- Wait for completion or timeout
    local startTime = os.clock()
    local timeoutSec = timeout / 1000

    while not completed and (os.clock() - startTime) < timeoutSec do
        task.wait(0.01)
    end

    if not completed then
        return false, "Execution timed out"
    end

    if execError then
        return false, string.format("Runtime error: %s", tostring(execError))
    end

    -- Serialize result
    local resultStr = ""
    if #results > 0 then
        local success, serialized = pcall(function()
            local value = results[1]
            if typeof(value) == "Instance" then
                return string.format("%s (%s)", value:GetFullName(), value.ClassName)
            elseif typeof(value) == "table" then
                -- Simple table serialization
                local parts = {}
                for k, v in pairs(value) do
                    table.insert(parts, string.format("[%s] = %s", tostring(k), tostring(v)))
                end
                return "{" .. table.concat(parts, ", ") .. "}"
            else
                return tostring(value)
            end
        end)

        if success then
            resultStr = serialized
        else
            resultStr = tostring(results[1])
        end
    end

    return true, {
        result = resultStr,
        type = #results > 0 and typeof(results[1]) or "nil"
    }
end

-- Initialize on load
Console.init()

return Console
