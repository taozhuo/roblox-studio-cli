---
name: query-tools
description: Bash-like query tools for searching and transforming instances in Roblox Studio via eval
---

# Query Tools Guide

Bash-like tools for querying and transforming instances in Studio eval.

## Quick Reference

| Bash | Eval Equivalent |
|------|-----------------|
| `grep "pattern" *.lua` | `grep("pattern")` |
| `find . -name "Part"` | `find("Part")` |
| `find . -type Part` | `findClass("Part")` |
| `sed 's/old/new/g'` | `sed("old", "new")` |
| `jq '.[] \| select(.x > 5)'` | `where("x", ">", 5)` |
| `cmd1 \| cmd2` | Chain with variables |

---

## 1. grep - Search Script Source

```lua
-- Find scripts containing pattern
grep("RemoteEvent")
grep("wait%(")  -- Lua pattern: escape (

-- With line numbers
grepLines("RemoteEvent")
-- Returns: { {script, lineNum, lineContent}, ... }

-- Case insensitive
grep("remote", true)
```

### Implementation
```lua
function grep(pattern, caseInsensitive)
    local results = {}
    for _, inst in game:GetDescendants() do
        if inst:IsA("LuaSourceContainer") then
            local source = caseInsensitive and inst.Source:lower() or inst.Source
            local searchPattern = caseInsensitive and pattern:lower() or pattern
            if source:find(searchPattern) then
                table.insert(results, inst)
            end
        end
    end
    return results
end

function grepLines(pattern)
    local results = {}
    for _, inst in game:GetDescendants() do
        if inst:IsA("LuaSourceContainer") then
            for lineNum, line in ipairs(inst.Source:split("\n")) do
                if line:find(pattern) then
                    table.insert(results, {
                        script = inst:GetFullName(),
                        line = lineNum,
                        content = line:match("^%s*(.-)%s*$")  -- trim
                    })
                end
            end
        end
    end
    return results
end
```

---

## 2. find - Find by Name

```lua
-- Find by exact name
find("SpawnLocation")

-- Find by pattern
find("^Spawn")      -- starts with Spawn
find("Part$")       -- ends with Part
find(".*Door.*")    -- contains Door

-- Find with class filter
find("Spawn", "SpawnLocation")
```

### Implementation
```lua
function find(namePattern, className)
    local results = {}
    for _, inst in game:GetDescendants() do
        if inst.Name:match(namePattern) then
            if not className or inst:IsA(className) then
                table.insert(results, inst)
            end
        end
    end
    return results
end
```

---

## 3. findClass - Find by ClassName

```lua
-- Find all of a class
findClass("Part")
findClass("RemoteEvent")
findClass("Script")

-- With additional filter
findClass("Part", function(p)
    return p.Transparency > 0.5
end)
```

### Implementation
```lua
function findClass(className, filter)
    local results = {}
    for _, inst in game:GetDescendants() do
        if inst:IsA(className) then
            if not filter or filter(inst) then
                table.insert(results, inst)
            end
        end
    end
    return results
end
```

---

## 4. where - Filter by Property (jq-style)

```lua
-- Filter by property value
where(parts, "Anchored", "==", false)
where(parts, "Transparency", ">", 0.5)
where(parts, "Name", "match", "^Spawn")
where(parts, "BrickColor", "==", BrickColor.new("Bright red"))

-- Operators: ==, ~=, >, <, >=, <=, match
```

### Implementation
```lua
function where(instances, property, operator, value)
    local results = {}
    for _, inst in instances do
        local propValue = inst[property]
        local match = false

        if operator == "==" then match = propValue == value
        elseif operator == "~=" then match = propValue ~= value
        elseif operator == ">" then match = propValue > value
        elseif operator == "<" then match = propValue < value
        elseif operator == ">=" then match = propValue >= value
        elseif operator == "<=" then match = propValue <= value
        elseif operator == "match" then match = tostring(propValue):match(value)
        end

        if match then
            table.insert(results, inst)
        end
    end
    return results
end
```

---

## 5. sed - Find/Replace in Scripts

```lua
-- Replace in all scripts
sed("wait%(", "task.wait(")

-- Dry run (preview changes)
sedPreview("wait%(", "task.wait(")

-- Replace in specific scripts
sedIn(grep("MyModule"), "oldFunc", "newFunc")
```

### Implementation
```lua
function sed(pattern, replacement)
    local modified = {}
    for _, inst in game:GetDescendants() do
        if inst:IsA("LuaSourceContainer") then
            local newSource, count = inst.Source:gsub(pattern, replacement)
            if count > 0 then
                inst.Source = newSource
                table.insert(modified, {
                    script = inst:GetFullName(),
                    replacements = count
                })
            end
        end
    end
    return modified
end

function sedPreview(pattern, replacement)
    local previews = {}
    for _, inst in game:GetDescendants() do
        if inst:IsA("LuaSourceContainer") then
            local _, count = inst.Source:gsub(pattern, replacement)
            if count > 0 then
                table.insert(previews, {
                    script = inst:GetFullName(),
                    wouldReplace = count
                })
            end
        end
    end
    return previews
end
```

---

## 6. select - Extract Properties (Projection)

```lua
-- Get specific properties
select(parts, {"Name", "Position", "Size"})

-- Returns: { {Name="Part1", Position=..., Size=..., path="..."}, ... }
```

### Implementation
```lua
function select(instances, properties)
    local results = {}
    for _, inst in instances do
        local row = { path = inst:GetFullName() }
        for _, prop in properties do
            pcall(function()
                row[prop] = inst[prop]
            end)
        end
        table.insert(results, row)
    end
    return results
end
```

---

## 7. Piping (Chaining)

Bash pipes with `|`. In Luau, chain with variables:

```bash
# Bash
find . -name "Part" | grep -l "Spawn" | xargs rename Block
```

```lua
-- Eval: chain operations
local parts = findClass("Part")                    -- find
local filtered = where(parts, "Name", "match", "Spawn")  -- grep/filter
for _, p in filtered do p.Name = "Block" end       -- xargs rename
return #filtered
```

### One-liner Style
```lua
-- Compact chaining
return #(function()
    local r = {}
    for _, p in findClass("Part") do
        if p.Name:match("Spawn") then
            p.Name = "Block"
            table.insert(r, p)
        end
    end
    return r
end)()
```

---

## 8. count - Count Results

```lua
-- Count instances
count(findClass("Part"))
count(grep("RemoteEvent"))

-- Count by class (like wc -l per file)
countByClass()
-- Returns: { Part = 150, Script = 45, ... }
```

### Implementation
```lua
function count(instances)
    return #instances
end

function countByClass()
    local counts = {}
    for _, inst in game:GetDescendants() do
        local class = inst.ClassName
        counts[class] = (counts[class] or 0) + 1
    end
    return counts
end
```

---

## 9. Common Patterns

### Find Deprecated API
```lua
return grepLines("wait%(")
-- or
return grepLines(":connect%(")  -- should be :Connect
-- or
return grepLines("spawn%(")     -- should be task.spawn
```

### Find Unanchored Parts
```lua
return select(
    where(findClass("BasePart"), "Anchored", "==", false),
    {"Name", "Position"}
)
```

### Find Large Scripts
```lua
local results = {}
for _, s in findClass("LuaSourceContainer") do
    local lines = #s.Source:split("\n")
    if lines > 500 then
        table.insert(results, {script = s:GetFullName(), lines = lines})
    end
end
return results
```

### Find Parts by Size
```lua
return select(
    where(findClass("Part"), "Size", ">", Vector3.new(100,100,100)),
    {"Name", "Size", "Position"}
)
-- Note: Vector3 comparison uses magnitude
```

### Bulk Rename
```lua
local count = 0
for _, inst in find("^Part%d+$") do  -- Part1, Part2, etc.
    inst.Name = "Block" .. count
    count += 1
end
return count
```

### Find RemoteEvents Without Validation
```lua
local suspicious = {}
for _, remote in findClass("RemoteEvent") do
    -- Check if any script connects without validation
    for _, script in grep(remote.Name) do
        if not script.Source:find("validate") and not script.Source:find("sanity") then
            table.insert(suspicious, {
                remote = remote:GetFullName(),
                script = script:GetFullName()
            })
        end
    end
end
return suspicious
```

---

## 10. Full Query DSL (Advanced)

Chainable query builder:

```lua
-- Usage
query("BasePart")
    :where("Anchored", "==", false)
    :where("Transparency", ">", 0.5)
    :select("Name", "Position")
    :limit(10)
    :run()
```

### Implementation
```lua
local Query = {}
Query.__index = Query

function query(className)
    local self = setmetatable({}, Query)
    self.className = className
    self.conditions = {}
    self.projection = nil
    self.maxResults = nil
    return self
end

function Query:where(prop, op, value)
    table.insert(self.conditions, {prop, op, value})
    return self
end

function Query:select(...)
    self.projection = {...}
    return self
end

function Query:limit(n)
    self.maxResults = n
    return self
end

function Query:run()
    local results = {}

    for _, inst in game:GetDescendants() do
        if self.maxResults and #results >= self.maxResults then
            break
        end

        if not inst:IsA(self.className) then
            continue
        end

        local pass = true
        for _, cond in self.conditions do
            local prop, op, value = cond[1], cond[2], cond[3]
            local v = inst[prop]

            if op == "==" and v ~= value then pass = false
            elseif op == "~=" and v == value then pass = false
            elseif op == ">" and v <= value then pass = false
            elseif op == "<" and v >= value then pass = false
            elseif op == "match" and not tostring(v):match(value) then pass = false
            end

            if not pass then break end
        end

        if pass then
            if self.projection then
                local row = {path = inst:GetFullName()}
                for _, p in self.projection do
                    pcall(function() row[p] = inst[p] end)
                end
                table.insert(results, row)
            else
                table.insert(results, inst)
            end
        end
    end

    return results
end
```

---

## Summary

| Function | Purpose | Returns |
|----------|---------|---------|
| `grep(pattern)` | Search script source | `{Script, ...}` |
| `grepLines(pattern)` | Search with line info | `{script, line, content}` |
| `find(name)` | Find by name pattern | `{Instance, ...}` |
| `findClass(class)` | Find by class | `{Instance, ...}` |
| `where(list, prop, op, val)` | Filter by property | `{Instance, ...}` |
| `sed(old, new)` | Find/replace in scripts | `{script, count}` |
| `select(list, props)` | Extract properties | `{prop1, prop2, path}` |
| `count(list)` | Count items | `number` |
| `query(class):...:run()` | Chainable DSL | `{...}` |
