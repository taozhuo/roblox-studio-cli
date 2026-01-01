--!strict
--[[
    Console Handler - Logs and code evaluation

    Provides Chrome DevTools Console panel functionality:
    - Log history retrieval
    - Log filtering
    - Luau code evaluation (command bar style)
]]

local LogService = game:GetService("LogService")

local Console = {}

-- Log history buffer
local logHistory: {{
    timestamp: number,
    level: string,
    message: string,
    source: string?
}} = {}

local MAX_LOG_HISTORY = 1000
local logConnection: RBXScriptConnection? = nil

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

    print("[Bakable] Console log capture initialized")
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
        timestamp = os.time(),
        level = level,
        message = message,
        source = nil -- Could parse from message if needed
    })

    -- Trim history if too large
    while #logHistory > MAX_LOG_HISTORY do
        table.remove(logHistory, 1)
    end
end

-- Get log history
function Console.getLogHistory(params: any): (boolean, any)
    local limit = params.limit or 100
    local levels = params.levels
    local pattern = params.pattern

    local result = {}
    local count = 0

    -- Iterate from newest to oldest
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
        count = count + 1
    end

    return true, {
        logs = result,
        count = #result,
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
        print = print,
        warn = warn,
        error = error,
        typeof = typeof,
        type = type,
        tostring = tostring,
        tonumber = tonumber,
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        select = select,
        unpack = unpack,
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
