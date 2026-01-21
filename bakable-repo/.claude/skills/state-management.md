---
name: state-management
description: Use _G table to persist state across eval calls
---

# State Management via _G

Use Lua's `_G` (global table) to persist state across `studio.eval` calls.

## Why?

Each eval call is stateless - the agent doesn't remember what it created or modified. Use `_G` to:
- Track created instances
- Store undo history
- Keep counters/progress
- Cache expensive computations

## Basic Pattern

```lua
-- Initialize state (idempotent)
_G.bakable = _G.bakable or {
    created = {},      -- instances we created
    modified = {},     -- {instance, property, oldValue}
    lastAction = nil,  -- what we just did
}

-- Track what we create
local part = Instance.new("Part", workspace)
part.Name = "MyPart"
table.insert(_G.bakable.created, part)
_G.bakable.lastAction = "Created " .. part.Name

return _G.bakable.lastAction
```

## Undo Pattern

```lua
-- Before modifying, save old value
local part = workspace.MyPart
table.insert(_G.bakable.modified, {
    instance = part,
    property = "Position",
    oldValue = part.Position
})
part.Position = Vector3.new(0, 10, 0)
```

```lua
-- Undo last modification
local last = table.remove(_G.bakable.modified)
if last then
    last.instance[last.property] = last.oldValue
    return "Undid: " .. last.property
end
return "Nothing to undo"
```

## Cleanup Pattern

```lua
-- Delete everything we created
local count = 0
for _, inst in _G.bakable.created or {} do
    if inst and inst.Parent then
        inst:Destroy()
        count += 1
    end
end
_G.bakable.created = {}
return "Deleted " .. count .. " instances"
```

## Status Check

```lua
-- What have we done?
local b = _G.bakable or {}
return {
    created = #(b.created or {}),
    modified = #(b.modified or {}),
    lastAction = b.lastAction or "none"
}
```

## Per-Task State

```lua
-- Namespace by task
_G.task_build_house = _G.task_build_house or {
    walls = {},
    roof = nil,
    floor = nil,
    phase = "walls"  -- walls, roof, floor, done
}

-- Check progress
local t = _G.task_build_house
return "Phase: " .. t.phase .. ", Walls: " .. #t.walls
```

## Selection Tracking

```lua
-- Remember what user had selected
_G.bakable.savedSelection = game.Selection:Get()

-- ... do work ...

-- Restore selection
game.Selection:Set(_G.bakable.savedSelection or {})
```

## Clear All State

```lua
-- Full reset
_G.bakable = nil
_G.task_build_house = nil
return "State cleared"
```

## Tips

1. Always use `or {}` / `or {default}` for safe initialization
2. Check `inst.Parent` before operating - instance may be destroyed
3. Use namespaced keys (`_G.bakable.*`) to avoid conflicts
4. Clear state when starting a new unrelated task
5. The `lastAction` pattern helps the agent remember context
