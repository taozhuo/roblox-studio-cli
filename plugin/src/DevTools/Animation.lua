--!strict
--[[
    Animation State Inspection - Inspect and control animations on Humanoids/Animators
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Animation = {}

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

-- Helper to find Animator from path or default to local character
local function getAnimator(path: string?): (Animator?, string?)
    local target: Instance? = nil

    if path and path ~= "" then
        target = game
        for part in string.gmatch(path, "[^%.]+") do
            target = target:FindFirstChild(part)
            if not target then
                return nil, "Instance not found: " .. path
            end
        end
    else
        -- Default to local character
        local player = Players.LocalPlayer
        if player and player.Character then
            target = player.Character
        else
            return nil, "No path provided and no local character available"
        end
    end

    -- Find Animator
    local animator: Animator? = nil

    if target:IsA("Animator") then
        animator = target :: Animator
    elseif target:IsA("Humanoid") then
        animator = target:FindFirstChildOfClass("Animator")
    elseif target:IsA("Model") then
        local humanoid = target:FindFirstChildOfClass("Humanoid")
        if humanoid then
            animator = humanoid:FindFirstChildOfClass("Animator")
        end
    end

    if not animator then
        return nil, "No Animator found at path"
    end

    return animator, nil
end

-- Get playing animations
function Animation.getPlaying(params: any): (boolean, any)
    local animator, err = getAnimator(params.path)
    if not animator then
        return false, err
    end

    local tracks = animator:GetPlayingAnimationTracks()
    local result = {}

    for _, track in ipairs(tracks) do
        table.insert(result, {
            name = track.Name,
            animationId = track.Animation and track.Animation.AnimationId or "unknown",
            isPlaying = track.IsPlaying,
            length = track.Length,
            timePosition = track.TimePosition,
            speed = track.Speed,
            weight = track.WeightCurrent,
            looped = track.Looped,
            priority = track.Priority.Name
        })
    end

    return true, {
        animatorPath = getPath(animator),
        playingCount = #result,
        tracks = result
    }
end

-- Get all loaded tracks
function Animation.getTracks(params: any): (boolean, any)
    local animator, err = getAnimator(params.path)
    if not animator then
        return false, err
    end

    -- GetPlayingAnimationTracks only returns playing ones
    -- We need to track loaded tracks ourselves or use a workaround
    local tracks = animator:GetPlayingAnimationTracks()
    local result = {}

    for _, track in ipairs(tracks) do
        table.insert(result, {
            name = track.Name,
            animationId = track.Animation and track.Animation.AnimationId or "unknown",
            isPlaying = track.IsPlaying,
            length = track.Length
        })
    end

    return true, {
        animatorPath = getPath(animator),
        trackCount = #result,
        tracks = result
    }
end

-- Get detailed track info
function Animation.getTrackInfo(params: any): (boolean, any)
    local animator, err = getAnimator(params.path)
    if not animator then
        return false, err
    end

    local animationId = params.animationId
    if not animationId then
        return false, "Missing animationId parameter"
    end

    local tracks = animator:GetPlayingAnimationTracks()
    for _, track in ipairs(tracks) do
        local trackAnimId = track.Animation and track.Animation.AnimationId or ""
        if trackAnimId == animationId or track.Name == animationId then
            return true, {
                name = track.Name,
                animationId = trackAnimId,
                isPlaying = track.IsPlaying,
                length = track.Length,
                timePosition = track.TimePosition,
                speed = track.Speed,
                weightCurrent = track.WeightCurrent,
                weightTarget = track.WeightTarget,
                looped = track.Looped,
                priority = track.Priority.Name,
                fadeIn = track.FadeInTime,
                fadeOut = track.FadeOutTime
            }
        end
    end

    return false, "Animation track not found: " .. animationId
end

-- Play an animation
function Animation.play(params: any): (boolean, any)
    local animator, err = getAnimator(params.path)
    if not animator then
        return false, err
    end

    local animationId = params.animationId
    if not animationId then
        return false, "Missing animationId parameter"
    end

    -- Create Animation instance
    local animation = Instance.new("Animation")
    animation.AnimationId = animationId

    local ok, trackOrErr = pcall(function()
        return animator:LoadAnimation(animation)
    end)

    if not ok then
        animation:Destroy()
        return false, "Failed to load animation: " .. tostring(trackOrErr)
    end

    local track = trackOrErr :: AnimationTrack

    local fadeTime = params.fadeTime or 0.1
    local weight = params.weight or 1
    local speed = params.speed or 1

    track:Play(fadeTime, weight, speed)

    return true, {
        animationId = animationId,
        length = track.Length,
        speed = speed,
        weight = weight,
        message = "Animation playing"
    }
end

-- Stop an animation
function Animation.stop(params: any): (boolean, any)
    local animator, err = getAnimator(params.path)
    if not animator then
        return false, err
    end

    local animationId = params.animationId
    local fadeTime = params.fadeTime or 0.1

    local tracks = animator:GetPlayingAnimationTracks()
    local stoppedCount = 0

    for _, track in ipairs(tracks) do
        local trackAnimId = track.Animation and track.Animation.AnimationId or ""
        if not animationId or trackAnimId == animationId or track.Name == animationId then
            track:Stop(fadeTime)
            stoppedCount = stoppedCount + 1
        end
    end

    if stoppedCount == 0 and animationId then
        return false, "No matching animation found to stop"
    end

    return true, {
        stoppedCount = stoppedCount,
        message = animationId and ("Stopped " .. animationId) or "Stopped all animations"
    }
end

-- Set track time position
function Animation.setTrackTime(params: any): (boolean, any)
    local animator, err = getAnimator(params.path)
    if not animator then
        return false, err
    end

    local animationId = params.animationId
    local time = params.time

    if not animationId or time == nil then
        return false, "Missing animationId or time parameter"
    end

    local tracks = animator:GetPlayingAnimationTracks()
    for _, track in ipairs(tracks) do
        local trackAnimId = track.Animation and track.Animation.AnimationId or ""
        if trackAnimId == animationId or track.Name == animationId then
            track.TimePosition = time
            return true, {
                animationId = animationId,
                newTime = time,
                length = track.Length
            }
        end
    end

    return false, "Animation track not found: " .. animationId
end

-- Set track speed
function Animation.setTrackSpeed(params: any): (boolean, any)
    local animator, err = getAnimator(params.path)
    if not animator then
        return false, err
    end

    local animationId = params.animationId
    local speed = params.speed

    if not animationId or speed == nil then
        return false, "Missing animationId or speed parameter"
    end

    local tracks = animator:GetPlayingAnimationTracks()
    for _, track in ipairs(tracks) do
        local trackAnimId = track.Animation and track.Animation.AnimationId or ""
        if trackAnimId == animationId or track.Name == animationId then
            track:AdjustSpeed(speed)
            return true, {
                animationId = animationId,
                newSpeed = speed,
                isPaused = speed == 0
            }
        end
    end

    return false, "Animation track not found: " .. animationId
end

-- List all Animation instances in game
function Animation.listAnimations(params: any): (boolean, any)
    local animations = {}

    for _, desc in ipairs(game:GetDescendants()) do
        if desc:IsA("Animation") then
            table.insert(animations, {
                name = desc.Name,
                path = getPath(desc),
                animationId = desc.AnimationId
            })
        end
    end

    return true, {
        count = #animations,
        animations = animations
    }
end

return Animation
