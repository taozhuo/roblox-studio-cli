---
name: debugging-tools
description: Input recording, network debugging, and animation inspection tools for Roblox game development
---

# Debugging Tools Guide

## 1. Input Recording & Replay

Record player inputs during playtest and replay them for automated testing.

### Start Recording
```lua
studio.input.startRecording({ includeMouseMovement = false })
```
- Must be in Play mode
- Captures: keyboard (WASD, space, etc), mouse clicks
- Set `includeMouseMovement = true` for mouse position (verbose)

### Stop & Get Results
```lua
studio.input.stopRecording()
-- Returns: { sequence = [...], duration = 5.2, eventCount = 47 }
```

### Replay Inputs
```lua
studio.input.replay({ sequence = capturedSequence, speed = 1.0 })
```
- `speed = 2.0` plays 2x faster
- `speed = 0.5` plays half speed

### Export as Test Code
```lua
studio.input.exportTest({ sequence = capturedSequence, testName = "JumpTest" })
-- Returns Luau code using VirtualInputManager
```

---

## 2. Network/Replication Debugging

Monitor RemoteEvents and network ownership.

### How Remote Capture Works

```
[startRemoteCapture]
        |
        ├── Hook existing RemoteEvents (game:GetDescendants)
        |
        ├── Listen for new ones (game.DescendantAdded)
        |
[Game Running] ──→ All FireServer/FireClient calls logged
        |
[stopRemoteCapture] ──→ Returns captured events
```

### Start Monitoring
```lua
studio.network.startRemoteCapture({
    filter = "Damage",  -- Optional: only capture remotes containing "Damage"
    maxEvents = 1000
})
```

### Get Captured Events
```lua
studio.network.stopRemoteCapture()
-- Returns:
{
    events = {
        { time = 0.5, remoteName = "DamagePlayer", playerName = "Player1", args = {50} },
        { time = 1.2, remoteName = "BuyItem", playerName = "Player1", args = {"Sword"} },
    }
}
```

### Network Ownership
```lua
-- Who owns physics simulation?
studio.network.getOwnership({ path = "workspace.Ball", recursive = true })
-- Returns: { parts = [{ path = "...", owner = "Player1" or "Server" }] }

-- Change ownership
studio.network.setOwnership({ path = "workspace.Ball", playerName = "Player1" })
studio.network.setOwnership({ path = "workspace.Ball", playerName = nil })  -- Server
studio.network.setOwnership({ path = "workspace.Ball", auto = true })       -- Auto
```

### List All Remotes
```lua
studio.network.listRemotes()
-- Returns: { remoteEvents = [...], remoteFunctions = [...] }
```

### Measure Latency
```lua
studio.network.measureLatency({ samples = 5 })
-- Returns: { averageMs = 45, minMs = 32, maxMs = 67 }
```

---

## 3. Animation Inspection

Inspect and control animations during playtest.

### Get Playing Animations
```lua
studio.animation.getPlaying({ path = "workspace.Player1" })
-- Returns:
{
    tracks = [{
        name = "WalkAnim",
        animationId = "rbxassetid://123",
        isPlaying = true,
        length = 1.5,
        timePosition = 0.7,
        speed = 1,
        weight = 1,
        looped = true
    }]
}
```

### Play Animation
```lua
studio.animation.play({
    path = "workspace.Player1",
    animationId = "rbxassetid://123456",
    fadeTime = 0.1,
    speed = 1,
    weight = 1
})
```

### Control Playback
```lua
-- Pause (set speed to 0)
studio.animation.setTrackSpeed({ animationId = "rbxassetid://123", speed = 0 })

-- Resume
studio.animation.setTrackSpeed({ animationId = "rbxassetid://123", speed = 1 })

-- Reverse
studio.animation.setTrackSpeed({ animationId = "rbxassetid://123", speed = -1 })

-- Scrub to specific time
studio.animation.setTrackTime({ animationId = "rbxassetid://123", time = 0.5 })
```

### Stop Animation
```lua
studio.animation.stop({ animationId = "rbxassetid://123", fadeTime = 0.1 })
studio.animation.stop({})  -- Stop all
```

### List All Animations in Game
```lua
studio.animation.listAnimations()
-- Returns all Animation instances in ReplicatedStorage, StarterPlayer, etc.
```

---

## 4. Debugging Workflows

### Debug "Why isn't my remote working?"
```lua
-- 1. List all remotes
studio.network.listRemotes()

-- 2. Start capture
studio.network.startRemoteCapture({ filter = "MyRemote" })

-- 3. Trigger the action in game

-- 4. Check if it fired
studio.network.getRemoteHistory()
-- If empty → client never called FireServer
-- If present → server received it, check server script
```

### Debug Animation Issues
```lua
-- 1. Check what's playing
studio.animation.getPlaying({ path = "workspace.MyNPC" })

-- 2. If nothing playing, check if animations exist
studio.animation.listAnimations()

-- 3. Try playing manually
studio.animation.play({ path = "workspace.MyNPC", animationId = "rbxassetid://123" })
```

### Record Test for CI
```lua
-- 1. Record a play session
studio.input.startRecording()
-- ... play the game ...
local result = studio.input.stopRecording()

-- 2. Export as test
local testCode = studio.input.exportTest({
    sequence = result.sequence,
    testName = "WalkAndJumpTest"
})

-- 3. Save to TestService script
studio.scripts.create({
    path = "ServerScriptService.Tests.WalkAndJumpTest",
    source = testCode.code
})
```

---

## 5. Limitations

| Feature | Limitation |
|---------|------------|
| Input replay | Can't inject real inputs, only simulates via VirtualInputManager |
| Remote capture | Only sees events AFTER capture starts |
| Animation control | Only works on Animators, not legacy Humanoid:LoadAnimation |
| Network ownership | Only works on unanchored parts |
| Client debugging | Can't see inside LocalScript variables, only what they send |
