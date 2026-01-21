# Scripting Guide

## Eval as REPL

`studio.eval` executes Luau code and returns results, like a REPL.

### Basic Usage

```lua
studio.eval({ code = "return 1 + 1" })           -- 2
studio.eval({ code = "return workspace.Name" })  -- "Workspace"
```

### Problem: State Lost

```lua
studio.eval({ code = "local x = 10" })
studio.eval({ code = "return x" })  -- nil (gone!)
```

### Solution: _G for Persistence

```lua
-- Store variables
_G.counter = 0
_G.data = {}

-- Later call
_G.counter += 1
return _G.counter  -- 1
```

### Initialize Once Pattern

```lua
_G.cache = _G.cache or {}
_G.config = _G.config or { debug = true }
```

### Store Functions

```lua
-- Define once
_G.utils = _G.utils or {}
_G.utils.countParts = function()
    local count = 0
    for _, v in workspace:GetDescendants() do
        if v:IsA("BasePart") then count += 1 end
    end
    return count
end

-- Use later
return _G.utils.countParts()
```

### Namespace to Avoid Collisions

```lua
-- Good
_G.bakable = _G.bakable or {}
_G.bakable.cache = {}

-- Bad (might conflict)
_G.cache = {}
```

### Cleanup

```lua
_G.myData = nil  -- clear key

-- View all _G keys
local keys = {}
for k in pairs(_G) do table.insert(keys, k) end
return keys
```

## Eval vs Bash

| Feature | studio.eval | Bash |
|---------|-------------|------|
| Persistence | Manual via `_G` | Automatic (env vars) |
| State type | Tables, functions | Strings only |
| Context | Plugin | System shell |

## Common Patterns

### Accumulate Data

```lua
_G.log = _G.log or {}
table.insert(_G.log, { time = os.time(), event = "action" })
return _G.log
```

### State Machine

```lua
_G.state = _G.state or { phase = "lobby", round = 0 }
_G.state.phase = "playing"
_G.state.round += 1
```

### Memoization

```lua
_G.memo = _G.memo or {}
local function expensive(key)
    if _G.memo[key] then return _G.memo[key] end
    local result = -- compute...
    _G.memo[key] = result
    return result
end
```
