--!strict
--[[
    Input Recording/Replay - Records and replays player inputs during playtest
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Input = {}

-- Recording state
local isRecording = false
local recordedInputs: {{
    time: number,
    type: string,
    keyCode: string?,
    position: Vector3?,
    delta: Vector2?,
    state: string?
}} = {}
local recordingStartTime = 0
local includeMouseMovement = false
local inputConnections: {RBXScriptConnection} = {}

-- Replay state
local isReplaying = false
local replayCoroutine: thread? = nil

-- Helper to serialize input
local function serializeInput(input: InputObject, state: string): any
    local entry = {
        time = os.clock() - recordingStartTime,
        type = input.UserInputType.Name,
        state = state
    }

    if input.UserInputType == Enum.UserInputType.Keyboard then
        entry.keyCode = input.KeyCode.Name
    elseif input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.MouseButton2 then
        entry.position = {x = input.Position.X, y = input.Position.Y}
    elseif input.UserInputType == Enum.UserInputType.MouseMovement and includeMouseMovement then
        entry.position = {x = input.Position.X, y = input.Position.Y}
        entry.delta = {x = input.Delta.X, y = input.Delta.Y}
    end

    return entry
end

function Input.startRecording(params: any): (boolean, any)
    if isRecording then
        return false, "Already recording"
    end

    if not RunService:IsRunning() then
        return false, "Must be in Play mode to record inputs"
    end

    includeMouseMovement = params.includeMouseMovement or false
    recordedInputs = {}
    recordingStartTime = os.clock()
    isRecording = true

    -- Connect to input events
    table.insert(inputConnections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if isRecording and not gameProcessed then
            local entry = serializeInput(input, "Began")
            if entry.type ~= "MouseMovement" or includeMouseMovement then
                table.insert(recordedInputs, entry)
            end
        end
    end))

    table.insert(inputConnections, UserInputService.InputEnded:Connect(function(input, gameProcessed)
        if isRecording then
            local entry = serializeInput(input, "Ended")
            if entry.type ~= "MouseMovement" then
                table.insert(recordedInputs, entry)
            end
        end
    end))

    if includeMouseMovement then
        table.insert(inputConnections, UserInputService.InputChanged:Connect(function(input, gameProcessed)
            if isRecording and input.UserInputType == Enum.UserInputType.MouseMovement then
                -- Sample mouse movement at reduced rate
                if #recordedInputs == 0 or (os.clock() - recordingStartTime) - recordedInputs[#recordedInputs].time > 0.05 then
                    table.insert(recordedInputs, serializeInput(input, "Changed"))
                end
            end
        end))
    end

    return true, {
        message = "Recording started",
        includeMouseMovement = includeMouseMovement
    }
end

function Input.stopRecording(params: any): (boolean, any)
    if not isRecording then
        return false, "Not recording"
    end

    isRecording = false

    -- Disconnect all
    for _, conn in ipairs(inputConnections) do
        conn:Disconnect()
    end
    inputConnections = {}

    local duration = os.clock() - recordingStartTime

    return true, {
        message = "Recording stopped",
        duration = duration,
        eventCount = #recordedInputs,
        sequence = recordedInputs
    }
end

function Input.replay(params: any): (boolean, any)
    if isReplaying then
        return false, "Already replaying"
    end

    if not RunService:IsRunning() then
        return false, "Must be in Play mode to replay inputs"
    end

    local sequence = params.sequence
    if not sequence or #sequence == 0 then
        return false, "No input sequence provided"
    end

    local speed = params.speed or 1.0
    isReplaying = true

    -- Run replay in coroutine
    replayCoroutine = task.spawn(function()
        local startTime = os.clock()
        local eventIndex = 1

        while isReplaying and eventIndex <= #sequence do
            local event = sequence[eventIndex]
            local targetTime = event.time / speed
            local currentTime = os.clock() - startTime

            if currentTime >= targetTime then
                -- Simulate the input (limited - can only do some things)
                -- This is a best-effort simulation
                if event.type == "Keyboard" and event.keyCode then
                    -- Can't actually inject keyboard input, but we can log it
                    print(string.format("[Replay] Key %s %s at %.2fs", event.keyCode, event.state, event.time))
                elseif event.type == "MouseButton1" or event.type == "MouseButton2" then
                    print(string.format("[Replay] %s %s at (%.0f, %.0f) at %.2fs",
                        event.type, event.state, event.position.x or 0, event.position.y or 0, event.time))
                end
                eventIndex = eventIndex + 1
            else
                task.wait(0.01)
            end
        end

        isReplaying = false
    end)

    return true, {
        message = "Replay started",
        eventCount = #sequence,
        speed = speed
    }
end

function Input.exportTest(params: any): (boolean, any)
    local sequence = params.sequence
    if not sequence or #sequence == 0 then
        return false, "No input sequence provided"
    end

    local testName = params.testName or "ReplayInputTest"

    -- Generate Luau code
    local code = string.format([[
-- Auto-generated input replay test
-- Generated at %s
-- Events: %d

local TestService = game:GetService("TestService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local function %s()
    local startTime = os.clock()

]], os.date("%Y-%m-%d %H:%M:%S"), #sequence, testName)

    for i, event in ipairs(sequence) do
        if event.type == "Keyboard" and event.keyCode then
            if event.state == "Began" then
                code = code .. string.format("    task.wait(%.3f - (os.clock() - startTime))\n", event.time)
                code = code .. string.format("    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.%s, false, game)\n", event.keyCode)
            elseif event.state == "Ended" then
                code = code .. string.format("    task.wait(%.3f - (os.clock() - startTime))\n", event.time)
                code = code .. string.format("    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.%s, false, game)\n", event.keyCode)
            end
        end
    end

    code = code .. string.format([[

    print("%s completed")
end

return %s
]], testName, testName)

    return true, {
        testName = testName,
        eventCount = #sequence,
        code = code
    }
end

function Input.getStatus(params: any): (boolean, any)
    return true, {
        isRecording = isRecording,
        isReplaying = isReplaying,
        recordedEventCount = #recordedInputs,
        duration = isRecording and (os.clock() - recordingStartTime) or 0
    }
end

return Input
