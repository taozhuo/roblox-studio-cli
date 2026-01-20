# DevTools Feature TODO

Features to add to match Chrome DevTools and game dev debugging tools.

---

## Unified Query Architecture: Bash + Lune + Eval

### The Three Pillars

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Query/Transform Pipeline                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐                 │
│  │    BASH     │      │    LUNE     │      │    EVAL     │                 │
│  │   (Files)   │      │  (Roblox)   │      │  (Runtime)  │                 │
│  └──────┬──────┘      └──────┬──────┘      └──────┬──────┘                 │
│         │                    │                    │                         │
│         ▼                    ▼                    ▼                         │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐                 │
│  │ .lua files  │      │ .rbxl/.rbxm │      │ Live game   │                 │
│  │ .json files │      │ Instance    │      │ Runtime     │                 │
│  │ Text/config │      │ tree        │      │ state       │                 │
│  └─────────────┘      └─────────────┘      └─────────────┘                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Capabilities Matrix

| Capability | Bash | Lune | Eval |
|------------|------|------|------|
| Search script source | ✅ `grep` | ✅ `roblox` lib | ✅ Script.Source |
| Search instance tree | ❌ | ✅ native | ✅ GetDescendants |
| Query properties | ❌ | ✅ native | ✅ native |
| Modify instances | ❌ | ✅ + save | ✅ live |
| Batch process files | ✅ | ✅ | ❌ |
| JSON/YAML/TOML | ✅ `jq` | ✅ `serde` | ❌ |
| Run shell commands | ✅ native | ✅ `process` | ❌ |
| HTTP requests | ✅ `curl` | ✅ `net` | ⚠️ HttpService |
| Access runtime state | ❌ | ❌ | ✅ |
| Playtest control | ❌ | ❌ | ✅ |
| File system | ✅ native | ✅ `fs` | ❌ |
| Regex | ✅ | ✅ | ✅ |
| Pipe/chain | ✅ `\|` | ⚠️ manual | ⚠️ manual |

### When to Use What

```
┌────────────────────────────────────────────────────────────────────┐
│                        Decision Tree                               │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  Need runtime state? (playing animations, live variables)          │
│       │                                                            │
│       ├── YES → use EVAL                                           │
│       │                                                            │
│       └── NO → Need to modify .rbxl/.rbxm file?                    │
│                   │                                                │
│                   ├── YES → use LUNE                               │
│                   │                                                │
│                   └── NO → Working with text files? (.lua, .json)  │
│                               │                                    │
│                               ├── YES → use BASH                   │
│                               │                                    │
│                               └── NO → Need instance queries?      │
│                                           │                        │
│                                           ├── On file → LUNE       │
│                                           └── Live → EVAL          │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### Use Cases by Tool

#### BASH (Text/Config Files)
```bash
# Search all scripts for deprecated API
grep -rn "wait(" src/ --include="*.lua"

# Find all RemoteEvents in scripts
grep -rn "RemoteEvent" src/ --include="*.lua" | wc -l

# Bulk rename in scripts
find src/ -name "*.lua" -exec sed -i 's/oldFunc/newFunc/g' {} \;

# Query Rojo project
jq '.tree.ReplicatedStorage' default.project.json

# Count lines of code
find src/ -name "*.lua" | xargs wc -l

# Find large scripts
find src/ -name "*.lua" -size +10k
```

#### LUNE (Roblox Files - Static Analysis)
```lua
-- query-instances.luau: Find all parts with specific properties
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local place = roblox.deserializePlace(fs.readFile("game.rbxl"))

local results = {}
for _, inst in place:GetDescendants() do
    if inst:IsA("BasePart") and inst.Transparency > 0.5 then
        table.insert(results, {
            path = inst:GetFullName(),
            class = inst.ClassName,
            transparency = inst.Transparency,
            size = {inst.Size.X, inst.Size.Y, inst.Size.Z}
        })
    end
end

-- Output as JSON for piping to jq
print(serde.encode("json", results))
```

```bash
# Pipe Lune output to jq
lune run query-instances.luau | jq '.[] | select(.size[0] > 100)'
```

```lua
-- transform-instances.luau: Batch modify and save
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")

local place = roblox.deserializePlace(fs.readFile("game.rbxl"))

-- Rename all generic "Part" names
local count = 0
for _, inst in place:GetDescendants() do
    if inst:IsA("Part") and inst.Name == "Part" then
        inst.Name = "UnnamedPart_" .. count
        count += 1
    end
end

fs.writeFile("game.rbxl", roblox.serializePlace(place))
print("Renamed", count, "parts")
```

```lua
-- audit-remotes.luau: Security audit
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")

local place = roblox.deserializePlace(fs.readFile("game.rbxl"))

-- Find all RemoteEvents
local remotes = {}
for _, inst in place:GetDescendants() do
    if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") then
        table.insert(remotes, {
            name = inst.Name,
            path = inst:GetFullName(),
            class = inst.ClassName
        })
    end
end

-- Check scripts for validation
for _, inst in place:GetDescendants() do
    if inst:IsA("Script") then
        local source = inst.Source
        for _, remote in remotes do
            if source:find(remote.name) and not source:find("sanity") and not source:find("validate") then
                print("⚠️  Potential unvalidated remote:", remote.name, "in", inst:GetFullName())
            end
        end
    end
end
```

#### EVAL (Runtime State)
```lua
-- Get currently playing animations (only possible at runtime)
local player = game.Players:GetPlayers()[1]
local animator = player.Character:FindFirstChildOfClass("Animator")
return animator:GetPlayingAnimationTracks()

-- Check live network ownership
local part = workspace.Ball
return part:GetNetworkOwner()

-- Monitor live RemoteEvent traffic (requires hooks set up at runtime)
return _G.remoteCapture:getHistory()

-- Get current camera position
return workspace.CurrentCamera.CFrame

-- Check live memory usage
return game:GetService("Stats"):GetTotalMemoryUsageMb()
```

### Integration Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           studioctl CLI                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   studioctl query "..."  ──┬── Detects target ──┬── bash (text files)      │
│                            │                    ├── lune (rbxl/rbxm)        │
│                            │                    └── eval (runtime)          │
│                            │                                                │
│   studioctl grep "..."   ──┴── Routes to appropriate tool                   │
│   studioctl transform                                                       │
│   studioctl audit                                                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                           MCP Tools                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   bash.*      │  Run shell commands, grep, sed, jq                          │
│   lune.*      │  Query/transform .rbxl/.rbxm files                          │
│   studio.*    │  Runtime eval, playtest, live state                         │
│                                                                             │
│   unified.*   │  Smart routing based on context                             │
│               │  - unified.query → picks best tool                          │
│               │  - unified.search → searches everywhere                     │
│               │  - unified.transform → modifies appropriately               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Data Flow Examples

#### Example 1: "Find all unanchored parts"
```
┌─────────────────────────────────────────────────────────────────┐
│  User: "Find all unanchored parts"                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Is Studio running?                                             │
│      │                                                          │
│      ├── YES → EVAL: game:GetDescendants() filter               │
│      │         (sees runtime-spawned parts too)                 │
│      │                                                          │
│      └── NO → LUNE: deserialize .rbxl and query                 │
│               (only sees saved state)                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Example 2: "Find deprecated API usage"
```
┌─────────────────────────────────────────────────────────────────┐
│  User: "Find deprecated wait() calls"                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Using Rojo project?                                            │
│      │                                                          │
│      ├── YES → BASH: grep -rn "wait(" src/ --include="*.lua"    │
│      │         (fastest, uses file system)                      │
│      │                                                          │
│      └── NO → LUNE: deserialize .rbxl, iterate scripts          │
│               (works on place file directly)                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Example 3: "Rename all 'Part' to 'Block'"
```
┌─────────────────────────────────────────────────────────────────┐
│  User: "Rename all parts named 'Part' to 'Block'"               │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Is Studio running?                                             │
│      │                                                          │
│      ├── YES → EVAL: GetDescendants + rename live               │
│      │         (immediate, includes runtime instances)          │
│      │                                                          │
│      └── NO → LUNE: deserialize, rename, serialize              │
│               (modifies file, need to reopen in Studio)         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

#### Example 4: "Check animation state"
```
┌─────────────────────────────────────────────────────────────────┐
│  User: "What animations are playing on the NPC?"                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ONLY EVAL works here (runtime state)                           │
│                                                                 │
│  → EVAL: Animator:GetPlayingAnimationTracks()                   │
│                                                                 │
│  BASH/LUNE cannot see runtime animation state                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Proposed MCP Tools

#### Bash Tools
- [ ] `bash.grep` - Search text files with pattern
- [ ] `bash.sed` - Find/replace in text files
- [ ] `bash.jq` - Query JSON files
- [ ] `bash.find` - Find files by name/pattern
- [ ] `bash.exec` - Run arbitrary shell command

#### Lune Tools
- [ ] `lune.query` - Query instances in .rbxl/.rbxm file
- [ ] `lune.transform` - Modify instances and save
- [ ] `lune.diff` - Compare two place files
- [ ] `lune.export` - Export instance tree to JSON
- [ ] `lune.import` - Import JSON changes to place file
- [ ] `lune.audit.security` - Find RemoteEvent vulnerabilities
- [ ] `lune.audit.deprecated` - Find deprecated API usage
- [ ] `lune.audit.performance` - Find potential performance issues
- [ ] `lune.script.search` - Search script source in place file
- [ ] `lune.script.replace` - Find/replace in scripts

#### Unified Tools (Smart Routing)
- [ ] `unified.search` - Search everywhere (scripts, instances, files)
- [ ] `unified.query` - Query instances (routes to lune or eval)
- [ ] `unified.transform` - Transform instances (routes appropriately)
- [ ] `unified.audit` - Run audits (combines static + runtime)

### Query Language Design

A unified query syntax that works across all three tools:

```
# Proposed syntax
studioctl query "BasePart WHERE Anchored = false"
studioctl query "Script WHERE Source CONTAINS 'wait('"
studioctl query "RemoteEvent WHERE Parent.Name = 'Events'"

# Under the hood
┌─────────────────────────────────────────────────────────────────┐
│  Parser → AST → Router → [Bash | Lune | Eval] → Results         │
└─────────────────────────────────────────────────────────────────┘
```

```lua
-- Query AST example
{
    class = "BasePart",
    conditions = {
        { property = "Anchored", operator = "=", value = false },
        { property = "Size.X", operator = ">", value = 10 }
    },
    select = { "Name", "Position", "Size" },
    limit = 100
}
```

### Sync Strategies

```
┌─────────────────────────────────────────────────────────────────┐
│                     File ↔ Studio Sync                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Rojo (Scripts)                                                 │
│  ├── File → Studio: `rojo serve` (live sync)                    │
│  └── Studio → File: `rojo sync` or manual export                │
│                                                                 │
│  Lune (Instances)                                               │
│  ├── Modify .rbxl → Reopen in Studio                            │
│  └── Studio save → Lune can read                                │
│                                                                 │
│  Daemon Plugin (Live Bridge)                                    │
│  ├── Export: studio.export.toJson → File system                 │
│  └── Import: studio.import.fromJson → Live Studio               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Implementation Priority

| Phase | Tools | Effort |
|-------|-------|--------|
| 1 | `bash.grep`, `bash.jq`, `bash.exec` | Low (shell passthrough) |
| 2 | `lune.query`, `lune.transform` | Medium (Lune scripts) |
| 3 | `lune.audit.*` | Medium (analysis scripts) |
| 4 | `unified.search`, `unified.query` | High (router + parser) |
| 5 | Query language DSL | High (parser + codegen) |

### File Structure

```
daemon/
├── tools/
│   ├── bash/
│   │   ├── grep.js
│   │   ├── jq.js
│   │   └── exec.js
│   ├── lune/
│   │   ├── query.js      # Calls Lune scripts
│   │   ├── transform.js
│   │   └── audit.js
│   └── unified/
│       ├── search.js     # Routes to bash/lune/eval
│       └── query.js
├── lune-scripts/
│   ├── query-instances.luau
│   ├── transform-instances.luau
│   ├── audit-security.luau
│   ├── audit-deprecated.luau
│   └── diff-places.luau
└── query-parser/
    ├── lexer.js
    ├── parser.js
    └── codegen.js        # Generates bash/lune/eval code
```

## Context Notification System (Like Claude Code)

Claude Code pushes notifications into AI context when background tasks complete. We could do similar:

### How Claude Code Does It
```
1. Background task runs
2. Task completes/errors
3. CLI injects <task-notification> into conversation
4. AI sees it on next turn
```

### What We Could Add
```javascript
// Tauri app listens to daemon WebSocket
daemon.onEvent("error-log", (data) => {
  conversation.inject(`<studio-notification>
    <type>error</type>
    <message>${data.message}</message>
  </studio-notification>`)
})

daemon.onEvent("remote-spike", (data) => {
  conversation.inject(`<studio-notification>
    <type>remote-spike</type>
    <summary>${data.count} events from "${data.name}" in 1s</summary>
  </studio-notification>`)
})
```

### Notification Types to Consider
- [ ] Error logs (immediate alert)
- [ ] RemoteEvent spikes (spam detection)
- [ ] Memory threshold exceeded
- [ ] Playtest started/stopped
- [ ] Script changed externally

### Requirements
- Tauri app must control conversation context
- Daemon pushes events via WebSocket (already have)
- Tauri injects into messages before API call

---

## High Priority (Needs Plugin Work)

### 1. Input Recording/Replay
- [ ] `studio.input.startRecording` - capture player inputs (WASD, mouse, jumps)
- [ ] `studio.input.stopRecording` - stop and return input sequence
- [ ] `studio.input.replay` - replay captured inputs on character
- [ ] `studio.input.exportTest` - generate TestService code from recording

### 2. Replication Debugging
- [ ] `studio.network.getOwnership` - get network owner of part(s)
- [ ] `studio.network.setOwnership` - set network owner
- [ ] `studio.network.getRemoteHistory` - log RemoteEvent/Function calls
- [ ] `studio.network.startRemoteCapture` - begin monitoring remotes
- [ ] `studio.network.stopRemoteCapture` - stop monitoring, return log
- [ ] `studio.network.measureLatency` - round-trip time measurement

### 3. Animation State Inspection
- [ ] `studio.animation.getPlaying` - list playing animations on humanoid/animator
- [ ] `studio.animation.getTracks` - get all animation tracks
- [ ] `studio.animation.getTrackInfo` - get track weight, speed, position, length
- [ ] `studio.animation.setTrackTime` - scrub to specific time
- [ ] `studio.animation.pause` - pause animation track
- [ ] `studio.animation.resume` - resume animation track

---

## Medium Priority (Scriptable via Eval)

### 4. Physics Panel
- [ ] `studio.physics.getContacts` - get collision contact points
- [ ] `studio.physics.visualize` - toggle `ShowCollisionGeometry`
- [ ] `studio.physics.raycastDebug` - cast ray and return hit info
- [ ] `studio.physics.getConstraints` - list constraints on selection
- [ ] `studio.physics.getAssemblies` - list physics assemblies

### 5. Memory Snapshots
- [ ] `studio.memory.snapshot` - capture instance count by ClassName
- [ ] `studio.memory.diff` - compare two snapshots (find leaks)
- [ ] `studio.memory.getTopClasses` - classes with most instances
- [ ] `studio.memory.trackInstance` - watch specific instance for GC

### 6. Rendering Debug
- [ ] `studio.render.setMode` - wireframe, normal, lighting-only
- [ ] `studio.render.getStats` - draw calls, triangles, instances
- [ ] `studio.render.toggleStreamingDebug` - show streaming regions
- [ ] `studio.render.getCamera` - camera position, FOV, etc.

### 7. Audit Tools (Lighthouse Equivalent)
- [ ] `studio.audit.performance` - find expensive scripts (profile + report)
- [ ] `studio.audit.memory` - find memory hogs
- [ ] `studio.audit.remotes` - find chatty RemoteEvents
- [ ] `studio.audit.deprecated` - find deprecated API usage in scripts
- [ ] `studio.audit.security` - find RemoteEvent vulnerabilities (no validation)

---

## Lower Priority

### 8. AI/Navigation Debug
- [ ] `studio.nav.computePath` - compute path between two points
- [ ] `studio.nav.visualizePath` - show path with debug parts
- [ ] `studio.nav.getWaypoints` - get path waypoints

### 9. DataStore Viewer (Application Panel Equivalent)
- [ ] `studio.datastore.preview` - read DataStore in Studio (mock)
- [ ] `studio.datastore.listKeys` - list keys in a DataStore
- [ ] `studio.datastore.inspect` - view value at key

### 10. Code Coverage
- [ ] `studio.coverage.start` - begin tracking executed lines
- [ ] `studio.coverage.stop` - stop and return coverage report
- [ ] `studio.coverage.getReport` - which lines were executed

---

## Already Have (Reference)

| Chrome DevTools | Our Tool | Status |
|-----------------|----------|--------|
| Elements | `studio.instances.tree`, `studio.selection` | ✅ |
| Console | `studio.logs`, `studio.eval` | ✅ |
| Sources | `studio.scripts`, `studio.debug.*` | ✅ |
| Network (HTTP) | `runtime.http.capture*` | ✅ |
| Performance | `runtime.perf.*` | ✅ |
| Memory (basic) | `runtime.memory.*` | ✅ |
| Application | `cloud.datastore.*` | ✅ |
| Recorder (viewport) | `studio.recording.*` | ✅ |

---

## Notes

- Input recording requires hooking `UserInputService` and `ContextActionService`
- RemoteEvent monitoring requires wrapping or hooking `.OnServerEvent`/`.OnClientEvent`
- Animation inspection uses `Humanoid:GetPlayingAnimationTracks()` or `Animator:GetPlayingAnimationTracks()`
- Physics visualization uses `workspace:SetAttribute("CollisionGeometry", true)` or similar debug settings
- Memory snapshots just iterate `GetDescendants()` and count by ClassName

---

## game.DescendantAdded Use Cases

| Use Case | How |
|----------|-----|
| Auto-hook RemoteEvents | ✅ We do this |
| Track all new Parts | Monitor part count, find leaks |
| Auto-tag instances | Add CollectionService tags automatically |
| Watch for specific classes | Alert when BasePart/Script/etc created |
| Debug memory leaks | Log what's being created |

### Memory Leak Detection Example
```lua
-- Find memory leaks (what keeps getting created?)
local counts = {}
game.DescendantAdded:Connect(function(inst)
    local class = inst.ClassName
    counts[class] = (counts[class] or 0) + 1
end)
-- Later check: which class has most new instances?
```

---

## Similar Roblox Events

| Event | Scope | Fires When |
|-------|-------|------------|
| `game.DescendantAdded` | Entire game | Any instance added anywhere |
| `game.DescendantRemoving` | Entire game | Any instance about to be removed |
| `folder.ChildAdded` | Direct children only | Child added to specific folder |
| `folder.ChildRemoved` | Direct children only | Child removed from specific folder |
| `Instance.AncestryChanged` | Single instance | Instance's parent chain changes |
| `Instance:GetPropertyChangedSignal(prop)` | Single instance | Specific property changes |
| `CollectionService:GetInstanceAddedSignal(tag)` | Tagged instances | Instance with tag added |
| `CollectionService:GetInstanceRemovedSignal(tag)` | Tagged instances | Instance with tag removed |
| `Players.PlayerAdded` | Players | Player joins |
| `Players.PlayerRemoving` | Players | Player leaves |
| `Workspace.CurrentCamera.Changed` | Camera | Camera property changes |

---

## Power Combos

### 1. Watch for script changes (hot reload detection)
```lua
game.DescendantAdded:Connect(function(inst)
    if inst:IsA("LuaSourceContainer") then
        print("New script:", inst:GetFullName())
    end
end)
```

### 2. Auto-anchor all new parts (prevent physics chaos)
```lua
game.DescendantAdded:Connect(function(inst)
    if inst:IsA("BasePart") and inst.Parent == workspace then
        inst.Anchored = true
    end
end)
```

### 3. Track instance count by class (memory debugging)
```lua
game.DescendantAdded:Connect(function(inst)
    _G.instanceCounts[inst.ClassName] = (_G.instanceCounts[inst.ClassName] or 0) + 1
end)
game.DescendantRemoving:Connect(function(inst)
    _G.instanceCounts[inst.ClassName] = (_G.instanceCounts[inst.ClassName] or 1) - 1
end)
```

### 4. Auto-apply collision groups
```lua
game.DescendantAdded:Connect(function(inst)
    if inst:IsA("BasePart") and inst:HasTag("Enemy") then
        inst.CollisionGroup = "Enemies"
    end
end)
```

### 5. Validate naming conventions
```lua
game.DescendantAdded:Connect(function(inst)
    if inst:IsA("RemoteEvent") and not inst.Name:match("^RE_") then
        warn("RemoteEvent should start with RE_:", inst.Name)
    end
end)
```

### 6. Security: Block suspicious instances
```lua
game.DescendantAdded:Connect(function(inst)
    if inst:IsA("Script") and inst.Parent == workspace then
        inst:Destroy()  -- Scripts shouldn't be in workspace
        warn("Blocked suspicious script")
    end
end)
```

### 7. Performance: Track part count
```lua
local partCount = 0
game.DescendantAdded:Connect(function(inst)
    if inst:IsA("BasePart") then
        partCount += 1
        if partCount > 10000 then warn("Too many parts!") end
    end
end)
game.DescendantRemoving:Connect(function(inst)
    if inst:IsA("BasePart") then partCount -= 1 end
end)
```

---

## Full List of Global Events

### Instance Tree Events
```lua
game.DescendantAdded        -- Any instance added
game.DescendantRemoving     -- Any instance removing (still exists)
```

### Service-Specific
```lua
Players.PlayerAdded
Players.PlayerRemoving
RunService.Heartbeat        -- Every frame (physics)
RunService.RenderStepped    -- Every frame (render, client only)
RunService.Stepped          -- Every frame (before physics)
```

### Workspace
```lua
workspace.PersistentLoaded  -- Streaming: persistent models loaded
workspace.ChildAdded
workspace.ChildRemoved
```

### CollectionService (Tag-Based)
```lua
CollectionService:GetInstanceAddedSignal("Enemy")
CollectionService:GetInstanceRemovedSignal("Enemy")
```

### Per-Instance
```lua
instance.Changed                           -- Any property (deprecated)
instance:GetPropertyChangedSignal("Name")  -- Specific property
instance.AttributeChanged                  -- Any attribute
instance:GetAttributeChangedSignal("Health") -- Specific attribute
instance.AncestryChanged                   -- Parent chain changed
instance.ChildAdded
instance.ChildRemoved
instance.Destroying                        -- About to be destroyed
```

---

## CollectionService vs DescendantAdded

| Approach | Pros | Cons |
|----------|------|------|
| DescendantAdded | Catches everything | Must filter manually |
| CollectionService | Pre-filtered by tag | Must tag instances first |

### CollectionService Approach (cleaner for known types)
```lua
local CS = game:GetService("CollectionService")

CS:GetInstanceAddedSignal("Lootable"):Connect(function(inst)
    -- Only fires for tagged instances
    setupLootable(inst)
end)
```

---

## Potential New Tools (Instance Tracking)

- [ ] `studio.tracking.startInstanceWatch` - Begin tracking DescendantAdded/Removing
- [ ] `studio.tracking.stopInstanceWatch` - Stop and return instance creation/removal counts
- [ ] `studio.tracking.getClassCounts` - Get current instance count by ClassName
- [ ] `studio.tracking.watchClass` - Alert when specific class is created
- [ ] `studio.tracking.detectLeaks` - Find classes with high creation rate
