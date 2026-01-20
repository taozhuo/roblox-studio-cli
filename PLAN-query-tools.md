# Query Tools Implementation Plan

## Overview

Implement bash-like query tools for Roblox Studio instances and scripts.

```
Scripts → bash equivalents (grep, sed)
Instances → jq equivalents (query DSL, find, where, select)
```

## Tool Categories

### 1. Script Tools (grep, sed)

| Tool | Bash Equivalent | Purpose |
|------|-----------------|---------|
| `studio.query.grep` | `grep` | Search script source |
| `studio.query.sed` | `sed` | Find/replace in scripts |

### 2. Instance Tools (jq-like)

| Tool | jq Equivalent | Purpose |
|------|---------------|---------|
| `studio.query.run` | `jq '...'` | Execute query DSL |
| `studio.query.find` | `jq 'select(...)'` | Structured query |

### 3. Utility Tools

| Tool | Bash Equivalent | Purpose |
|------|-----------------|---------|
| `studio.query.count` | `wc -l` | Count instances |
| `studio.query.countByClass` | `sort \| uniq -c` | Count by ClassName |

---

## API Design

### studio.query.run (jq-like DSL)

```javascript
// MCP Tool
{
  name: "studio.query.run",
  params: {
    query: ".. | Part | .Transparency > 0.5 | {Name, Position}",
    root: "Workspace",  // optional, default: game
    limit: 100          // optional, default: 1000
  }
}
```

**DSL Syntax:**
```
Query      = Segment ("|" Segment)*
Segment    = Path | ClassName | Condition | Projection | Function

Path       = "."              // current
           | ".."             // descendants
           | ".[]"            // children
           | ".Name.Sub"      // path traversal

ClassName  = /^[A-Z]\w+$/     // Part, BasePart, Model, Script

Condition  = "." Property Op Value
Property   = /^\w+$/
Op         = "==" | "!=" | ">" | "<" | ">=" | "<=" | "~" | "contains"
Value      = number | boolean | "nil" | "string" | 'string'

Projection = "{" Property ("," Property)* "}"

Function   = "limit(" number ")"
           | "first"
           | "last"
           | "count"
           | "keys"
```

**Examples:**
```
.. | Part                              -- All Parts
.. | BasePart | .Anchored == false     -- Unanchored parts
.. | Part | .Transparency > 0.5        -- Transparent parts
.. | .Name ~ '^Spawn'                  -- Name matches pattern
.Workspace.Map | .. | Model            -- Models under Map
.. | Part | {Name, Position, Size}     -- Select props
.. | Part | limit(10)                  -- First 10
.. | Part | count                      -- Just count
.. | keys                              -- ClassName counts
```

### studio.query.find (Structured)

```javascript
// MCP Tool
{
  name: "studio.query.find",
  params: {
    class: "BasePart",
    where: [
      ["Anchored", "==", false],
      ["Transparency", ">", 0.5]
    ],
    select: ["Name", "Position", "Size"],
    root: "Workspace",
    limit: 100
  }
}
```

### studio.query.grep

```javascript
// MCP Tool
{
  name: "studio.query.grep",
  params: {
    pattern: "RemoteEvent",      // Lua pattern or literal
    ignoreCase: false,           // optional
    lines: true,                 // show matching lines
    limit: 100
  }
}
```

**Output:**
```json
{
  "results": [
    {
      "path": "ServerScriptService.Main",
      "className": "Script",
      "matches": [
        { "line": 15, "content": "local RE = Instance.new(\"RemoteEvent\")" },
        { "line": 23, "content": "RE:FireClient(player, data)" }
      ]
    }
  ],
  "count": 1
}
```

### studio.query.sed

```javascript
// MCP Tool
{
  name: "studio.query.sed",
  params: {
    pattern: "wait%(",           // Lua pattern
    replacement: "task.wait(",
    dryRun: true                 // preview only, don't modify
  }
}
```

**Output:**
```json
{
  "results": [
    { "path": "ServerScriptService.Main", "replacements": 3 },
    { "path": "StarterPlayer.StarterPlayerScripts.Client", "replacements": 1 }
  ],
  "scriptsModified": 2,
  "totalReplacements": 4,
  "dryRun": true
}
```

### studio.query.count

```javascript
// MCP Tool
{
  name: "studio.query.count",
  params: {
    class: "Part",               // optional class filter
    root: "Workspace"            // optional root
  }
}
```

### studio.query.countByClass

```javascript
// MCP Tool
{
  name: "studio.query.countByClass",
  params: {
    root: "Workspace"
  }
}
```

**Output:**
```json
{
  "classes": {
    "Part": 150,
    "MeshPart": 45,
    "Model": 30,
    "Script": 12
  },
  "total": 237
}
```

---

## File Structure

```
daemon/mcp/tools/
└── studio.query.js         # MCP tool definitions

plugin/src/DevTools/
└── Query.lua               # Implementation
    ├── execute(query)      # DSL parser + executor
    ├── find(params)        # Structured query
    ├── grep(params)        # Script search
    ├── sed(params)         # Script replace
    ├── count(params)       # Instance count
    └── countByClass(params)# Count by ClassName
```

---

## Implementation Details

### Query.lua Structure

```lua
local Query = {}

-- Tokenizer: split by | respecting quotes
local function tokenize(queryStr) ... end

-- Path resolver: .Workspace.Map -> Instance
local function getInstanceByPath(path) ... end

-- Condition parser: .Transparency > 0.5 -> {prop, op, value}
local function parseCondition(str) ... end

-- Projection parser: {Name, Position} -> {"Name", "Position"}
local function parseProjection(str) ... end

-- Value comparison with type coercion
local function compare(value, op, target) ... end

-- Value serialization (Vector3 -> {x,y,z}, etc.)
local function serializeValue(value) ... end

-- Main DSL executor
function Query.execute(params) ... end

-- Structured query
function Query.find(params) ... end

-- Script search
function Query.grep(params) ... end

-- Script replace
function Query.sed(params) ... end

-- Count instances
function Query.count(params) ... end

-- Count by class
function Query.countByClass(params) ... end

return Query
```

### ToolHandler.lua Registration

```lua
-- Query Tools
if Query then
    handlers["studio.query.run"] = Query.execute
    handlers["studio.query.find"] = Query.find
    handlers["studio.query.grep"] = Query.grep
    handlers["studio.query.sed"] = Query.sed
    handlers["studio.query.count"] = Query.count
    handlers["studio.query.countByClass"] = Query.countByClass
end
```

---

## Output Format

All tools return consistent format:

```json
{
  "results": [...],     // Array of result objects
  "count": 10,          // Number of results
  "truncated": false    // True if limit was hit
}
```

Instance result object:
```json
{
  "path": "Workspace.Map.Part1",
  "name": "Part1",
  "className": "Part",
  // + any selected properties
}
```

---

## Error Handling

```json
{
  "error": "Root not found: Workspace.NonExistent",
  "success": false
}
```

---

## Performance Considerations

1. **Default limit**: 1000 results to prevent huge payloads
2. **Early termination**: Stop iterating when limit reached
3. **Lazy evaluation**: Don't serialize until needed
4. **Filter first**: Apply className filter before property filters (cheaper)

---

## Testing Examples

```lua
-- Test 1: Basic query
studio.query.run({ query = ".. | Part" })

-- Test 2: With conditions
studio.query.run({ query = ".. | BasePart | .Anchored == false" })

-- Test 3: With projection
studio.query.run({ query = ".. | Part | {Name, Position, Size}" })

-- Test 4: Structured query
studio.query.find({
    class = "Part",
    where = {{"Transparency", ">", 0}},
    select = {"Name", "Transparency"}
})

-- Test 5: Grep
studio.query.grep({ pattern = "RemoteEvent", lines = true })

-- Test 6: Sed preview
studio.query.sed({ pattern = "wait%(", replacement = "task.wait(", dryRun = true })

-- Test 7: Count
studio.query.count({ class = "Part" })

-- Test 8: Count by class
studio.query.countByClass({ root = "Workspace" })
```
