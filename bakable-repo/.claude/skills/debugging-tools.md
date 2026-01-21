---
name: debugging-tools
description: Input recording, network debugging, and animation inspection via studio.eval
---

# Debugging Tools Guide

All debugging is done via `studio.eval`. No specialized MCP tools needed.

## 1. Input Recording & Replay

Record player inputs during playtest and replay them.

### Record Inputs
```lua
-- Start recording (in Play mode)
local recording = {}
local conn
conn = game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
    if not processed then
        table.insert(recording, {
            time = tick(),
            type = input.UserInputType.Name,
            key = input.KeyCode.Name,
        })
    end
end)
_G.inputRecording = recording
_G.inputConn = conn
return "Recording started"
```

### Stop Recording
```lua
if _G.inputConn then
    _G.inputConn:Disconnect()
end
return _G.inputRecording
```

### Replay Inputs (via VirtualInputManager)
```lua
local VIM = game:GetService("VirtualInputManager")
local recording = _G.inputRecording
local startTime = tick()
for _, event in recording do
    task.delay(event.time - recording[1].time, function()
        VIM:SendKeyEvent(true, Enum.KeyCode[event.key], false, nil)
        task.wait(0.05)
        VIM:SendKeyEvent(false, Enum.KeyCode[event.key], false, nil)
    end)
end
return "Replaying " .. #recording .. " events"
```

---

## 2. Network/Replication Debugging

Monitor RemoteEvents and network ownership.

### Capture Remote Calls
```lua
local captured = {}
for _, remote in game:GetDescendants() do
    if remote:IsA("RemoteEvent") then
        remote.OnServerEvent:Connect(function(player, ...)
            table.insert(captured, {
                time = tick(),
                remote = remote:GetFullName(),
                player = player.Name,
                args = {...}
            })
        end)
    end
end
_G.remoteCaptured = captured
return "Capturing remotes"
```

### Get Captured Events
```lua
return _G.remoteCaptured or {}
```

### List All Remotes
```lua
local remotes = { events = {}, functions = {} }
for _, inst in game:GetDescendants() do
    if inst:IsA("RemoteEvent") then
        table.insert(remotes.events, inst:GetFullName())
    elseif inst:IsA("RemoteFunction") then
        table.insert(remotes.functions, inst:GetFullName())
    end
end
return remotes
```

### Network Ownership
```lua
-- Get ownership
local part = workspace:FindFirstChild("Ball", true)
if part then
    local owner = part:GetNetworkOwner()
    return owner and owner.Name or "Server"
end

-- Set ownership
local part = workspace:FindFirstChild("Ball", true)
local player = game.Players:FindFirstChild("Player1")
part:SetNetworkOwner(player)  -- or nil for Server
return "Set owner to " .. (player and player.Name or "Server")
```

---

## 3. Animation Inspection

Inspect and control animations during playtest.

### Get Playing Animations
```lua
local results = {}
local char = workspace:FindFirstChild("Player1")
if char then
    local animator = char:FindFirstChildWhichIsA("Animator", true)
    if animator then
        for _, track in animator:GetPlayingAnimationTracks() do
            table.insert(results, {
                name = track.Name,
                animId = track.Animation.AnimationId,
                length = track.Length,
                time = track.TimePosition,
                speed = track.Speed,
                looped = track.Looped
            })
        end
    end
end
return results
```

### Play Animation
```lua
local char = workspace:FindFirstChild("Player1")
local animator = char:FindFirstChildWhichIsA("Animator", true)
local anim = Instance.new("Animation")
anim.AnimationId = "rbxassetid://123456"
local track = animator:LoadAnimation(anim)
track:Play(0.1)  -- fadeTime
return "Playing animation"
```

### Control Playback
```lua
-- Pause/resume by adjusting speed
local animator = workspace.Player1:FindFirstChildWhichIsA("Animator", true)
for _, track in animator:GetPlayingAnimationTracks() do
    track:AdjustSpeed(0)  -- Pause
    -- track:AdjustSpeed(1)  -- Resume
    -- track:AdjustSpeed(-1) -- Reverse
end
return "Paused all animations"
```

### Stop Animation
```lua
local animator = workspace.Player1:FindFirstChildWhichIsA("Animator", true)
for _, track in animator:GetPlayingAnimationTracks() do
    track:Stop(0.1)  -- fadeTime
end
return "Stopped all animations"
```

---

## 4. Performance Debugging

### Memory Usage
```lua
return {
    gcMemory = collectgarbage("count"),
    instanceCount = #game:GetDescendants()
}
```

### Part Count
```lua
local count = 0
for _, inst in workspace:GetDescendants() do
    if inst:IsA("BasePart") then count += 1 end
end
return count
```

### Script Performance
```lua
local stats = game:GetService("Stats")
return {
    heartbeatTime = stats.HeartbeatTimeMs,
    dataReceive = stats.DataReceiveKbps,
    dataSend = stats.DataSendKbps
}
```

---

## 5. Debugging Workflows

### Debug "Why isn't my remote working?"
```lua
-- Step 1: List all remotes
local remotes = {}
for _, inst in game:GetDescendants() do
    if inst:IsA("RemoteEvent") and inst.Name:find("MyRemote") then
        table.insert(remotes, inst:GetFullName())
    end
end
return remotes
-- If empty → remote doesn't exist
-- If exists → hook it and trigger
```

### Debug Animation Issues
```lua
-- Check if animator exists and what's playing
local char = workspace:FindFirstChild("MyNPC")
if not char then return "NPC not found" end

local animator = char:FindFirstChildWhichIsA("Animator", true)
if not animator then return "No Animator found" end

local tracks = animator:GetPlayingAnimationTracks()
if #tracks == 0 then return "No animations playing" end

local info = {}
for _, t in tracks do
    table.insert(info, t.Name .. " @ " .. t.TimePosition)
end
return info
```

---

## Summary

| Task | Eval Pattern |
|------|-------------|
| Record inputs | `UserInputService.InputBegan` |
| Replay inputs | `VirtualInputManager:SendKeyEvent` |
| Capture remotes | `RemoteEvent.OnServerEvent:Connect` |
| Network ownership | `part:GetNetworkOwner/SetNetworkOwner` |
| Animation state | `animator:GetPlayingAnimationTracks` |
| Play animation | `animator:LoadAnimation():Play()` |
| Memory stats | `collectgarbage("count")` |
