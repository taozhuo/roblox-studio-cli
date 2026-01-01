--!strict
--[[
    Studio Handler - Plugin-level Studio features

    Provides access to Studio-only APIs:
    - StudioService (active script, theme)
    - Plugin:OpenScript (jump to line)
    - ScriptEditorService (open documents)
    - DebuggerManager (breakpoints)
]]

local StudioService = game:GetService("StudioService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local DebuggerManager = game:GetService("DebuggerManager")

local Studio = {}

-- Plugin reference (set from init)
local pluginRef: Plugin? = nil

function Studio.setPlugin(plugin: Plugin)
    pluginRef = plugin
end

-- Get the currently active/focused script in the editor
function Studio.getActiveScript(params: any): (boolean, any)
    local activeScript = StudioService.ActiveScript

    if activeScript then
        return true, {
            name = activeScript.Name,
            className = activeScript.ClassName,
            path = activeScript:GetFullName(),
            lineCount = #activeScript.Source:split("\n")
        }
    else
        return true, {
            activeScript = nil,
            message = "No script is currently active in the editor"
        }
    end
end

-- Get Studio theme and settings info
function Studio.getStudioInfo(params: any): (boolean, any)
    local theme = settings().Studio.Theme

    return true, {
        theme = theme and theme.Name or "Unknown",
        studioLocaleId = StudioService.StudioLocaleId,
        -- Add more settings as needed
    }
end

-- Get current place info (for session detection)
function Studio.getPlaceInfo(params: any): (boolean, any)
    local placeId = game.PlaceId
    local gameId = game.GameId
    local placeName = game.Name

    return true, {
        placeId = placeId,
        gameId = gameId,
        placeName = placeName,
        isPublished = placeId ~= 0,
        -- Generate a session key based on place
        sessionKey = placeId ~= 0 and tostring(placeId) or ("local_" .. placeName)
    }
end

-- Open a script at a specific line number
function Studio.openScript(params: any): (boolean, any)
    if not pluginRef then
        return false, "Plugin reference not set"
    end

    local scriptPath = params.path
    local lineNumber = params.line or 1

    if not scriptPath then
        return false, "Script path required"
    end

    -- Find the script by path
    local parts = string.split(scriptPath, "/")
    local current: Instance = game

    for _, part in ipairs(parts) do
        if part == "game" then
            current = game
        else
            local child = current:FindFirstChild(part)
            if not child then
                return false, "Script not found: " .. scriptPath
            end
            current = child
        end
    end

    if not current:IsA("LuaSourceContainer") then
        return false, "Path does not point to a script: " .. scriptPath
    end

    -- Open the script at the specified line
    pluginRef:OpenScript(current, lineNumber)

    return true, {
        opened = true,
        script = current:GetFullName(),
        line = lineNumber
    }
end

-- Get all currently open script documents
function Studio.getOpenDocuments(params: any): (boolean, any)
    local documents = ScriptEditorService:GetScriptDocuments()
    local result = {}

    for _, doc in ipairs(documents) do
        -- ScriptDocument has limited API, get what we can
        local script = doc:GetScript()
        if script then
            table.insert(result, {
                name = script.Name,
                className = script.ClassName,
                path = script:GetFullName(),
                isCommandBar = doc:IsCommandBar()
            })
        end
    end

    return true, {
        count = #result,
        documents = result
    }
end

-- Get the source of the currently active script
function Studio.getActiveScriptSource(params: any): (boolean, any)
    local activeScript = StudioService.ActiveScript

    if not activeScript then
        return false, "No script is currently active"
    end

    local source = activeScript.Source
    local lines = source:split("\n")

    -- Optionally limit to a range
    local startLine = params.startLine or 1
    local endLine = params.endLine or #lines

    local selectedLines = {}
    for i = startLine, math.min(endLine, #lines) do
        table.insert(selectedLines, {
            lineNumber = i,
            content = lines[i]
        })
    end

    return true, {
        script = activeScript:GetFullName(),
        totalLines = #lines,
        startLine = startLine,
        endLine = math.min(endLine, #lines),
        lines = selectedLines
    }
end

-- ============ Camera Tools ============

-- Scan what's visible in viewport using WorldToViewportPoint
-- Only includes models actually visible on screen
function Studio.scanViewport(params: any): (boolean, any)
    local camera = workspace.CurrentCamera
    if not camera then
        return false, "No camera found"
    end

    local distance = params.distance or 150
    local radius = params.radius or 100
    local maxModels = params.maxModels or 50

    local camPos = camera.CFrame.Position
    local camLook = camera.CFrame.LookVector
    local viewportSize = camera.ViewportSize

    -- Query center point in front of camera
    local queryCenter = camPos + camLook * (distance / 2)

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = {}

    local parts = workspace:GetPartBoundsInRadius(queryCenter, radius, overlapParams)

    -- Group by model and classify position
    local seenModels = {}
    local modelList = {}

    for _, part in ipairs(parts) do
        -- Traverse up to find the topmost meaningful model (not named "Model" or "Part")
        local ancestor = part
        repeat
            ancestor = ancestor:FindFirstAncestorOfClass("Model") or ancestor:FindFirstAncestorOfClass("Tool")
        until not ancestor or (ancestor.Name ~= "Model" and ancestor.Name ~= "Part")

        -- Use the meaningful ancestor, or fall back to first model, or the part itself
        local target = ancestor or part:FindFirstAncestorOfClass("Model") or part

        -- Skip if already seen
        if not seenModels[target] then
            seenModels[target] = true

            -- Get position using GetBoundingBox for models, or part position
            local targetPos: Vector3
            local sizeStr = ""
            if target:IsA("Model") then
                local success, cf, size = pcall(function()
                    return target:GetBoundingBox()
                end)
                if success and cf then
                    targetPos = cf.Position
                    sizeStr = string.format("%dx%dx%d",
                        math.floor(size.X), math.floor(size.Z), math.floor(size.Y))
                else
                    local primary = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
                    targetPos = primary and primary.Position or part.Position
                end
            else
                targetPos = part.Position
            end

            -- Check if actually in viewport using WorldToViewportPoint
            local screenPos, onScreen = camera:WorldToViewportPoint(targetPos)

            -- Only include if on screen (in front of camera and within viewport bounds)
            if onScreen then
                -- Classify left/center/right based on screen X position
                local screenX = screenPos.X / viewportSize.X -- normalize to 0-1
                local horizontal = "center"
                if screenX < 0.33 then
                    horizontal = "left"
                elseif screenX > 0.66 then
                    horizontal = "right"
                end

                local dist = math.floor((targetPos - camPos).Magnitude)

                table.insert(modelList, {
                    name = target.Name,
                    path = target:GetFullName(),
                    position = horizontal,
                    distance = dist,
                    size = sizeStr,
                    isModel = target:IsA("Model")
                })
            end
        end
    end

    -- Sort by distance and limit
    table.sort(modelList, function(a, b) return a.distance < b.distance end)
    while #modelList > maxModels do
        table.remove(modelList)
    end

    -- Build simple description
    local left, center, right = {}, {}, {}
    for _, m in ipairs(modelList) do
        local entry = m.name .. " (" .. m.distance .. ")"
        if m.position == "left" then
            table.insert(left, entry)
        elseif m.position == "right" then
            table.insert(right, entry)
        else
            table.insert(center, entry)
        end
    end

    local description = ""
    if #left > 0 then description = description .. "Left: " .. table.concat(left, ", ") .. "\n" end
    if #center > 0 then description = description .. "Center: " .. table.concat(center, ", ") .. "\n" end
    if #right > 0 then description = description .. "Right: " .. table.concat(right, ", ") .. "\n" end

    if description == "" then
        description = "Nothing visible in front of camera"
    end

    return true, {
        cameraPosition = { x = camPos.X, y = camPos.Y, z = camPos.Z },
        modelCount = #modelList,
        models = modelList,
        description = description
    }
end

-- Get current camera position, orientation, and info
function Studio.getCameraInfo(params: any): (boolean, any)
    local camera = workspace.CurrentCamera
    if not camera then
        return false, "No camera found"
    end

    local cframe = camera.CFrame
    local pos = cframe.Position
    local lookVector = cframe.LookVector
    local upVector = cframe.UpVector

    return true, {
        position = { x = pos.X, y = pos.Y, z = pos.Z },
        lookVector = { x = lookVector.X, y = lookVector.Y, z = lookVector.Z },
        upVector = { x = upVector.X, y = upVector.Y, z = upVector.Z },
        fieldOfView = camera.FieldOfView,
        viewportSize = { x = camera.ViewportSize.X, y = camera.ViewportSize.Y },
        cameraType = camera.CameraType.Name,
        focus = camera.Focus and {
            x = camera.Focus.Position.X,
            y = camera.Focus.Position.Y,
            z = camera.Focus.Position.Z
        } or nil
    }
end

-- Get models/parts in front of camera using spatial query
function Studio.getModelsInView(params: any): (boolean, any)
    local camera = workspace.CurrentCamera
    if not camera then
        return false, "No camera found"
    end

    local distance = params.distance or 100
    local radius = params.radius or 50

    -- Query center point in front of camera
    local center = camera.CFrame.Position + camera.CFrame.LookVector * (distance / 2)

    -- Use GetPartBoundsInRadius for spatial query
    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Exclude
    overlapParams.FilterDescendantsInstances = {}

    local parts = workspace:GetPartBoundsInRadius(center, radius, overlapParams)

    -- Group by model and collect unique models
    local models = {}
    local seenModels = {}
    local looseParts = {}

    for _, part in ipairs(parts) do
        local model = part:FindFirstAncestorOfClass("Model")
        if model then
            if not seenModels[model] then
                seenModels[model] = true
                local primaryPart = model.PrimaryPart
                table.insert(models, {
                    name = model.Name,
                    className = model.ClassName,
                    path = model:GetFullName(),
                    position = primaryPart and {
                        x = primaryPart.Position.X,
                        y = primaryPart.Position.Y,
                        z = primaryPart.Position.Z
                    } or nil
                })
            end
        else
            -- Loose part not in a model
            if #looseParts < 20 then -- Limit loose parts
                table.insert(looseParts, {
                    name = part.Name,
                    className = part.ClassName,
                    path = part:GetFullName(),
                    position = {
                        x = part.Position.X,
                        y = part.Position.Y,
                        z = part.Position.Z
                    }
                })
            end
        end
    end

    return true, {
        queryCenter = { x = center.X, y = center.Y, z = center.Z },
        queryRadius = radius,
        models = models,
        modelCount = #models,
        looseParts = looseParts,
        loosePartCount = #looseParts,
        totalPartsFound = #parts
    }
end

-- Move camera to a specific position/orientation
function Studio.setCameraPosition(params: any): (boolean, any)
    local camera = workspace.CurrentCamera
    if not camera then
        return false, "No camera found"
    end

    local pos = params.position
    local lookAt = params.lookAt
    local cframe = params.cframe

    if cframe then
        -- Full CFrame provided
        camera.CFrame = CFrame.new(
            cframe.x, cframe.y, cframe.z,
            cframe.r00 or 1, cframe.r01 or 0, cframe.r02 or 0,
            cframe.r10 or 0, cframe.r11 or 1, cframe.r12 or 0,
            cframe.r20 or 0, cframe.r21 or 0, cframe.r22 or 1
        )
    elseif pos and lookAt then
        -- Position + look at target
        camera.CFrame = CFrame.lookAt(
            Vector3.new(pos.x, pos.y, pos.z),
            Vector3.new(lookAt.x, lookAt.y, lookAt.z)
        )
    elseif pos then
        -- Just position, keep orientation
        local currentLookVector = camera.CFrame.LookVector
        camera.CFrame = CFrame.new(
            Vector3.new(pos.x, pos.y, pos.z),
            Vector3.new(pos.x, pos.y, pos.z) + currentLookVector
        )
    else
        return false, "Provide position (and optionally lookAt) or full cframe"
    end

    local newPos = camera.CFrame.Position
    return true, {
        moved = true,
        position = { x = newPos.X, y = newPos.Y, z = newPos.Z }
    }
end

-- Focus camera on an instance (move to look at it)
function Studio.focusCameraOn(params: any): (boolean, any)
    local camera = workspace.CurrentCamera
    if not camera then
        return false, "No camera found"
    end

    local targetPath = params.path
    local distance = params.distance or 20

    if not targetPath then
        return false, "Target path required"
    end

    -- Find the instance
    local parts = string.split(targetPath, "/")
    local current: Instance = game

    for _, part in ipairs(parts) do
        if part == "game" then
            current = game
        else
            local child = current:FindFirstChild(part)
            if not child then
                return false, "Instance not found: " .. targetPath
            end
            current = child
        end
    end

    -- Get the target position
    local targetPos: Vector3
    if current:IsA("BasePart") then
        targetPos = current.Position
    elseif current:IsA("Model") then
        local primaryPart = current.PrimaryPart or current:FindFirstChildWhichIsA("BasePart")
        if primaryPart then
            targetPos = primaryPart.Position
        else
            return false, "Model has no parts to focus on"
        end
    else
        return false, "Can only focus on BasePart or Model"
    end

    -- Position camera at distance, looking at target
    local currentPos = camera.CFrame.Position
    local direction = (currentPos - targetPos).Unit
    local newPos = targetPos + direction * distance

    camera.CFrame = CFrame.lookAt(newPos, targetPos)

    return true, {
        focused = true,
        target = current:GetFullName(),
        cameraPosition = { x = newPos.X, y = newPos.Y, z = newPos.Z },
        targetPosition = { x = targetPos.X, y = targetPos.Y, z = targetPos.Z }
    }
end

-- ============ Debugger Tools ============

-- Get all breakpoints
function Studio.getBreakpoints(params: any): (boolean, any)
    local breakpoints = DebuggerManager:GetBreakpoints()
    local result = {}

    for _, bp in ipairs(breakpoints) do
        local script = bp.Script
        table.insert(result, {
            id = bp:GetDebugId(),
            enabled = bp.Enabled,
            line = bp.Line,
            script = script and script:GetFullName() or nil,
            condition = bp.Condition,
            isLogpoint = bp.IsLogpoint,
            logMessage = bp.LogMessage
        })
    end

    return true, {
        count = #result,
        breakpoints = result
    }
end

-- Add a breakpoint to a script
function Studio.addBreakpoint(params: any): (boolean, any)
    local scriptPath = params.path
    local lineNumber = params.line
    local condition = params.condition
    local isLogpoint = params.isLogpoint or false
    local logMessage = params.logMessage

    if not scriptPath or not lineNumber then
        return false, "Script path and line number required"
    end

    -- Find the script
    local parts = string.split(scriptPath, "/")
    local current: Instance = game

    for _, part in ipairs(parts) do
        if part == "game" then
            current = game
        else
            local child = current:FindFirstChild(part)
            if not child then
                return false, "Script not found: " .. scriptPath
            end
            current = child
        end
    end

    if not current:IsA("LuaSourceContainer") then
        return false, "Path does not point to a script"
    end

    -- Add breakpoint
    local bp = DebuggerManager:AddBreakpoint(current, lineNumber)

    if condition then
        bp.Condition = condition
    end

    if isLogpoint then
        bp.IsLogpoint = true
        bp.LogMessage = logMessage or ""
    end

    return true, {
        added = true,
        id = bp:GetDebugId(),
        script = current:GetFullName(),
        line = lineNumber
    }
end

-- Remove a breakpoint
function Studio.removeBreakpoint(params: any): (boolean, any)
    local scriptPath = params.path
    local lineNumber = params.line

    if not scriptPath or not lineNumber then
        return false, "Script path and line number required"
    end

    local breakpoints = DebuggerManager:GetBreakpoints()

    for _, bp in ipairs(breakpoints) do
        local script = bp.Script
        if script and script:GetFullName() == scriptPath and bp.Line == lineNumber then
            bp:Destroy()
            return true, {
                removed = true,
                script = scriptPath,
                line = lineNumber
            }
        end
    end

    return false, "Breakpoint not found at " .. scriptPath .. ":" .. tostring(lineNumber)
end

-- Clear all breakpoints
function Studio.clearAllBreakpoints(params: any): (boolean, any)
    local breakpoints = DebuggerManager:GetBreakpoints()
    local count = #breakpoints

    for _, bp in ipairs(breakpoints) do
        bp:Destroy()
    end

    return true, {
        cleared = count,
        message = "Cleared " .. count .. " breakpoints"
    }
end

return Studio
