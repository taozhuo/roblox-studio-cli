--!strict
--[[
    Query - jq-like query DSL for instance trees

    Syntax:
        .. | ClassName | .Property == value | {Name, Position}

    Examples:
        ".. | Part"                              -- All Parts
        ".. | BasePart | .Anchored == false"    -- Unanchored parts
        ".. | Part | .Transparency > 0.5"       -- Transparent parts
        ".. | .Name ~ '^Spawn'"                 -- Name matches pattern
        ".Workspace.Map | .. | Model"           -- Models under Map
        ".. | Part | {Name, Position, Size}"    -- Select specific props
        ".. | Script | limit(10)"               -- First 10 scripts
        ".. | #Enemy"                           -- Has tag "Enemy"
        ".. | @Health > 50"                     -- Attribute Health > 50
]]

local CollectionService = game:GetService("CollectionService")

local Query = {}

-- Helper: Get instance by path like ".Workspace.Map.Buildings"
local function getInstanceByPath(pathStr: string): Instance?
    local current: Instance = game

    -- Remove leading dot if present
    if pathStr:sub(1, 1) == "." then
        pathStr = pathStr:sub(2)
    end

    if pathStr == "" or pathStr == "game" then
        return game
    end

    for part in pathStr:gmatch("[^%.]+") do
        local child = current:FindFirstChild(part)
        if not child then
            return nil
        end
        current = child
    end

    return current
end

-- Helper: Get full path of instance
local function getInstancePath(instance: Instance): string
    local parts = {}
    local current: Instance? = instance

    while current and current ~= game do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end

    return table.concat(parts, ".")
end

-- Helper: Serialize a value for output
local function serializeValue(value: any): any
    local t = typeof(value)

    if t == "Vector3" then
        return { x = value.X, y = value.Y, z = value.Z }
    elseif t == "Vector2" then
        return { x = value.X, y = value.Y }
    elseif t == "CFrame" then
        return {
            position = { x = value.Position.X, y = value.Position.Y, z = value.Position.Z },
            lookVector = { x = value.LookVector.X, y = value.LookVector.Y, z = value.LookVector.Z }
        }
    elseif t == "Color3" then
        return { r = value.R, g = value.G, b = value.B }
    elseif t == "BrickColor" then
        return value.Name
    elseif t == "EnumItem" then
        return tostring(value)
    elseif t == "Instance" then
        return { name = value.Name, className = value.ClassName, path = getInstancePath(value) }
    elseif t == "UDim2" then
        return {
            x = { scale = value.X.Scale, offset = value.X.Offset },
            y = { scale = value.Y.Scale, offset = value.Y.Offset }
        }
    elseif t == "UDim" then
        return { scale = value.Scale, offset = value.Offset }
    else
        return value
    end
end

-- Helper: Compare values with operator
local function compare(value: any, operator: string, target: any): boolean
    -- Handle nil
    if value == nil then
        return operator == "==" and target == nil
    end

    -- Type coercion for comparison
    local valueType = typeof(value)

    if operator == "==" then
        if valueType == "EnumItem" then
            return tostring(value) == tostring(target)
        end
        return value == target
    elseif operator == "!=" or operator == "~=" then
        if valueType == "EnumItem" then
            return tostring(value) ~= tostring(target)
        end
        return value ~= target
    elseif operator == ">" then
        return value > target
    elseif operator == "<" then
        return value < target
    elseif operator == ">=" then
        return value >= target
    elseif operator == "<=" then
        return value <= target
    elseif operator == "~" or operator == "match" then
        -- Pattern match
        return string.match(tostring(value), tostring(target)) ~= nil
    elseif operator == "contains" then
        return string.find(tostring(value), tostring(target), 1, true) ~= nil
    end

    return false
end

-- Parse a condition like ".Transparency > 0.5" or ".Name ~ '^Spawn'"
-- Also supports @Attribute conditions
local function parseCondition(condStr: string): (string?, string?, any, boolean)?
    -- Check if it's an attribute condition (@AttrName op value)
    local isAttribute = condStr:sub(1, 1) == "@"

    local prop, op, valStr
    if isAttribute then
        -- Attribute: @Health > 50
        prop, op, valStr = condStr:match("^@(%w+)%s*([=!<>~]+)%s*(.+)$")
        if not prop then
            prop, op, valStr = condStr:match("^@(%w+)%s+(match|contains)%s+(.+)$")
        end
    else
        -- Property: .Transparency > 0.5
        prop, op, valStr = condStr:match("^%.(%w+)%s*([=!<>~]+)%s*(.+)$")
        if not prop then
            prop, op, valStr = condStr:match("^%.(%w+)%s+(match|contains)%s+(.+)$")
        end
    end

    if not prop or not op or not valStr then
        return nil
    end

    -- Parse value
    local value: any
    valStr = valStr:match("^%s*(.-)%s*$") -- trim

    if valStr == "true" then
        value = true
    elseif valStr == "false" then
        value = false
    elseif valStr == "nil" then
        value = nil
    elseif valStr:match("^%-?%d+%.?%d*$") then
        value = tonumber(valStr)
    elseif valStr:match("^['\"](.+)['\"]$") then
        value = valStr:match("^['\"](.+)['\"]$")
    else
        -- Unquoted string
        value = valStr
    end

    return prop, op, value, isAttribute
end

-- Parse projection like "{Name, Position, Size}"
local function parseProjection(projStr: string): {string}?
    local inner = projStr:match("^{%s*(.-)%s*}$")
    if not inner then
        return nil
    end

    local props = {}
    for prop in inner:gmatch("[^,%s]+") do
        table.insert(props, prop)
    end

    return props
end

-- Tokenize query string by | delimiter
local function tokenize(queryStr: string): {string}
    local tokens = {}

    -- Split by | but respect quoted strings
    local current = ""
    local inQuote = false
    local quoteChar = nil

    for i = 1, #queryStr do
        local char = queryStr:sub(i, i)

        if (char == '"' or char == "'") and not inQuote then
            inQuote = true
            quoteChar = char
            current = current .. char
        elseif char == quoteChar and inQuote then
            inQuote = false
            quoteChar = nil
            current = current .. char
        elseif char == "|" and not inQuote then
            local trimmed = current:match("^%s*(.-)%s*$")
            if trimmed and #trimmed > 0 then
                table.insert(tokens, trimmed)
            end
            current = ""
        else
            current = current .. char
        end
    end

    -- Don't forget last token
    local trimmed = current:match("^%s*(.-)%s*$")
    if trimmed and #trimmed > 0 then
        table.insert(tokens, trimmed)
    end

    return tokens
end

-- Execute a query string
function Query.execute(params: any): (boolean, any)
    local queryStr = params.query
    local rootPath = params.root  -- Optional root override
    local maxResults = params.limit or 1000

    if not queryStr or type(queryStr) ~= "string" then
        return false, "Missing or invalid query string"
    end

    local tokens = tokenize(queryStr)
    if #tokens == 0 then
        return false, "Empty query"
    end

    -- Current result set
    local results: {Instance} = {}
    local projection: {string}? = nil
    local limitCount: number? = nil

    -- Process each token
    for i, token in ipairs(tokens) do
        -- Path: .Workspace.Map or just .
        if token:match("^%.") and not token:match("^%.[%w_]+%s*[=!<>~]") then
            -- This is a path, not a condition
            if token == ".." then
                -- Descendants
                if #results == 0 then
                    -- From root
                    local root = rootPath and getInstanceByPath(rootPath) or game
                    if root then
                        for _, desc in (root :: Instance):GetDescendants() do
                            table.insert(results, desc)
                        end
                    end
                else
                    -- From current results
                    local newResults: {Instance} = {}
                    for _, inst in results do
                        for _, desc in inst:GetDescendants() do
                            table.insert(newResults, desc)
                        end
                    end
                    results = newResults
                end
            elseif token == ".[]" or token == "[]" then
                -- Children
                if #results == 0 then
                    local root = rootPath and getInstanceByPath(rootPath) or game
                    if root then
                        for _, child in (root :: Instance):GetChildren() do
                            table.insert(results, child)
                        end
                    end
                else
                    local newResults: {Instance} = {}
                    for _, inst in results do
                        for _, child in inst:GetChildren() do
                            table.insert(newResults, child)
                        end
                    end
                    results = newResults
                end
            elseif token == "." then
                -- Current root
                if #results == 0 then
                    local root = rootPath and getInstanceByPath(rootPath) or game
                    if root then
                        table.insert(results, root)
                    end
                end
            else
                -- Named path: .Workspace.Map
                local inst = getInstanceByPath(token)
                if inst then
                    if i == 1 then
                        results = { inst }
                    else
                        -- Filter results to only those that match path
                        local path = getInstancePath(inst)
                        local newResults: {Instance} = {}
                        for _, r in results do
                            if getInstancePath(r):sub(1, #path) == path then
                                table.insert(newResults, r)
                            end
                        end
                        results = newResults
                    end
                else
                    -- Path not found
                    results = {}
                end
            end

        -- ClassName filter: Part, BasePart, Model, Script
        elseif token:match("^%u[%w_]*$") then
            local className = token
            local newResults: {Instance} = {}
            for _, inst in results do
                if inst:IsA(className) then
                    table.insert(newResults, inst)
                end
            end
            results = newResults

        -- Tag filter: #TagName
        elseif token:match("^#%w+$") then
            local tagName = token:sub(2)  -- Remove # prefix
            local newResults: {Instance} = {}
            for _, inst in results do
                if CollectionService:HasTag(inst, tagName) then
                    table.insert(newResults, inst)
                end
            end
            results = newResults

        -- Attribute condition: @AttrName == value
        elseif token:match("^@%w+%s*[=!<>~]") then
            local prop, op, value, _ = parseCondition(token)
            if prop and op then
                local newResults: {Instance} = {}
                for _, inst in results do
                    local attrValue = inst:GetAttribute(prop)
                    if compare(attrValue, op, value) then
                        table.insert(newResults, inst)
                    end
                end
                results = newResults
            end

        -- Has attribute (no condition): @AttrName
        elseif token:match("^@%w+$") then
            local attrName = token:sub(2)  -- Remove @ prefix
            local newResults: {Instance} = {}
            for _, inst in results do
                if inst:GetAttribute(attrName) ~= nil then
                    table.insert(newResults, inst)
                end
            end
            results = newResults

        -- Condition: .Property == value
        elseif token:match("^%.%w+%s*[=!<>~]") then
            local prop, op, value, _ = parseCondition(token)
            if prop and op then
                local newResults: {Instance} = {}
                for _, inst in results do
                    local success, propValue = pcall(function()
                        return (inst :: any)[prop]
                    end)
                    if success and compare(propValue, op, value) then
                        table.insert(newResults, inst)
                    end
                end
                results = newResults
            end

        -- Projection: {Name, Position, Size}
        elseif token:match("^{") then
            projection = parseProjection(token)

        -- Limit: limit(10)
        elseif token:match("^limit%(") then
            local n = token:match("^limit%((%d+)%)")
            if n then
                limitCount = tonumber(n)
            end

        -- first, last
        elseif token == "first" then
            limitCount = 1
        elseif token == "last" then
            if #results > 0 then
                results = { results[#results] }
            end

        -- count (returns number instead of results)
        elseif token == "count" then
            return true, { count = #results }

        -- keys (returns unique class names)
        elseif token == "keys" or token == "classes" then
            local classes: {[string]: number} = {}
            for _, inst in results do
                classes[inst.ClassName] = (classes[inst.ClassName] or 0) + 1
            end
            return true, { classes = classes }
        end
    end

    -- Apply limit
    if limitCount and limitCount < #results then
        local limited: {Instance} = {}
        for i = 1, limitCount do
            table.insert(limited, results[i])
        end
        results = limited
    end

    -- Apply max results safety limit
    if #results > maxResults then
        local limited: {Instance} = {}
        for i = 1, maxResults do
            table.insert(limited, results[i])
        end
        results = limited
    end

    -- Format output
    local output = {}
    for _, inst in results do
        if projection then
            -- Select specific properties
            local row: any = { path = getInstancePath(inst), className = inst.ClassName }
            for _, propName in projection do
                local success, value = pcall(function()
                    return (inst :: any)[propName]
                end)
                if success then
                    row[propName] = serializeValue(value)
                end
            end
            table.insert(output, row)
        else
            -- Default: path and className
            table.insert(output, {
                path = getInstancePath(inst),
                name = inst.Name,
                className = inst.ClassName
            })
        end
    end

    return true, {
        results = output,
        count = #output,
        truncated = #results >= maxResults
    }
end

-- Structured query (alternative to DSL string)
function Query.find(params: any): (boolean, any)
    local className = params.class
    local conditions = params.where or params.conditions
    local selectProps = params.select
    local limitCount = params.limit or 1000
    local rootPath = params.root

    -- Start from root
    local root = rootPath and getInstanceByPath(rootPath) or game
    if not root then
        return false, "Root not found: " .. tostring(rootPath)
    end

    local results: {Instance} = {}

    -- Get all descendants
    for _, inst in (root :: Instance):GetDescendants() do
        -- Class filter
        if className and not inst:IsA(className) then
            continue
        end

        -- Condition filters
        local passAll = true
        if conditions and type(conditions) == "table" then
            for _, cond in conditions do
                local prop = cond[1] or cond.prop or cond.property
                local op = cond[2] or cond.op or cond.operator or "=="
                local value = cond[3] or cond.value

                local success, propValue = pcall(function()
                    return (inst :: any)[prop]
                end)

                if not success or not compare(propValue, op, value) then
                    passAll = false
                    break
                end
            end
        end

        if passAll then
            table.insert(results, inst)
            if #results >= limitCount then
                break
            end
        end
    end

    -- Format output
    local output = {}
    for _, inst in results do
        if selectProps and type(selectProps) == "table" then
            local row: any = { path = getInstancePath(inst), className = inst.ClassName }
            for _, propName in selectProps do
                local success, value = pcall(function()
                    return (inst :: any)[propName]
                end)
                if success then
                    row[propName] = serializeValue(value)
                end
            end
            table.insert(output, row)
        else
            table.insert(output, {
                path = getInstancePath(inst),
                name = inst.Name,
                className = inst.ClassName
            })
        end
    end

    return true, {
        results = output,
        count = #output,
        truncated = #results >= limitCount
    }
end

-- Grep: search script source
function Query.grep(params: any): (boolean, any)
    local pattern = params.pattern
    local caseInsensitive = params.ignoreCase or params.caseInsensitive
    local showLines = params.lines or params.showLines
    local limitCount = params.limit or 100

    if not pattern or type(pattern) ~= "string" then
        return false, "Missing or invalid pattern"
    end

    local searchPattern = caseInsensitive and pattern:lower() or pattern
    local results = {}

    for _, inst in game:GetDescendants() do
        if #results >= limitCount then
            break
        end

        if inst:IsA("LuaSourceContainer") then
            local source = (inst :: any).Source
            local searchSource = caseInsensitive and source:lower() or source

            if searchSource:find(searchPattern, 1, true) or searchSource:match(searchPattern) then
                if showLines then
                    -- Include matching lines
                    local lines = {}
                    for lineNum, line in ipairs(source:split("\n")) do
                        local searchLine = caseInsensitive and line:lower() or line
                        if searchLine:find(searchPattern, 1, true) or searchLine:match(searchPattern) then
                            table.insert(lines, {
                                line = lineNum,
                                content = line:match("^%s*(.-)%s*$") -- trim
                            })
                        end
                    end
                    table.insert(results, {
                        path = getInstancePath(inst),
                        className = inst.ClassName,
                        matches = lines
                    })
                else
                    table.insert(results, {
                        path = getInstancePath(inst),
                        className = inst.ClassName
                    })
                end
            end
        end
    end

    return true, {
        results = results,
        count = #results,
        truncated = #results >= limitCount
    }
end

-- Sed: find and replace in scripts
function Query.sed(params: any): (boolean, any)
    local pattern = params.pattern
    local replacement = params.replacement
    local dryRun = params.dryRun or params.preview

    if not pattern or type(pattern) ~= "string" then
        return false, "Missing or invalid pattern"
    end
    if replacement == nil then
        return false, "Missing replacement"
    end

    local results = {}
    local totalReplacements = 0

    for _, inst in game:GetDescendants() do
        if inst:IsA("LuaSourceContainer") then
            local source = (inst :: any).Source
            local newSource, count = source:gsub(pattern, replacement)

            if count > 0 then
                if not dryRun then
                    (inst :: any).Source = newSource
                end

                table.insert(results, {
                    path = getInstancePath(inst),
                    replacements = count
                })
                totalReplacements = totalReplacements + count
            end
        end
    end

    return true, {
        results = results,
        scriptsModified = #results,
        totalReplacements = totalReplacements,
        dryRun = dryRun or false
    }
end

-- Count: count instances matching criteria
function Query.count(params: any): (boolean, any)
    local className = params.class
    local rootPath = params.root

    local root = rootPath and getInstanceByPath(rootPath) or game
    if not root then
        return false, "Root not found: " .. tostring(rootPath)
    end

    local count = 0

    for _, inst in (root :: Instance):GetDescendants() do
        if className then
            if inst:IsA(className) then
                count = count + 1
            end
        else
            count = count + 1
        end
    end

    return true, {
        count = count,
        class = className,
        root = rootPath or "game"
    }
end

-- CountByClass: count instances grouped by ClassName
function Query.countByClass(params: any): (boolean, any)
    local rootPath = params.root

    local root = rootPath and getInstanceByPath(rootPath) or game
    if not root then
        return false, "Root not found: " .. tostring(rootPath)
    end

    local classes: {[string]: number} = {}
    local total = 0

    for _, inst in (root :: Instance):GetDescendants() do
        local className = inst.ClassName
        classes[className] = (classes[className] or 0) + 1
        total = total + 1
    end

    -- Sort by count (convert to array)
    local sorted = {}
    for className, count in pairs(classes) do
        table.insert(sorted, { className = className, count = count })
    end
    table.sort(sorted, function(a, b)
        return a.count > b.count
    end)

    return true, {
        classes = classes,
        sorted = sorted,
        total = total,
        root = rootPath or "game"
    }
end

-- Utility: Get instance path (exported for other modules)
function Query.getPath(instance: Instance): string
    return getInstancePath(instance)
end

-- Utility: Get instance by path (exported for other modules)
function Query.getByPath(path: string): Instance?
    return getInstanceByPath(path)
end

-- ============ Tag Operations ============

-- FindByTag: find all instances with a specific tag
function Query.findByTag(params: any): (boolean, any)
    local tag = params.tag
    local selectProps = params.select
    local limitCount = params.limit or 1000

    if not tag or type(tag) ~= "string" then
        return false, "Missing or invalid tag parameter"
    end

    local tagged = CollectionService:GetTagged(tag)
    local results = {}

    for i, inst in tagged do
        if i > limitCount then break end

        if selectProps and type(selectProps) == "table" then
            local row: any = { path = getInstancePath(inst), className = inst.ClassName }
            for _, propName in selectProps do
                local success, value = pcall(function()
                    return (inst :: any)[propName]
                end)
                if success then
                    row[propName] = serializeValue(value)
                end
            end
            table.insert(results, row)
        else
            table.insert(results, {
                path = getInstancePath(inst),
                name = inst.Name,
                className = inst.ClassName
            })
        end
    end

    return true, {
        results = results,
        count = #results,
        tag = tag
    }
end

-- GetTags: get all tags on an instance
function Query.getTags(params: any): (boolean, any)
    local path = params.path

    if not path then
        return false, "Missing path parameter"
    end

    local inst = getInstanceByPath(path)
    if not inst then
        return false, "Instance not found: " .. path
    end

    local tags = CollectionService:GetTags(inst)

    return true, {
        path = path,
        tags = tags,
        count = #tags
    }
end

-- ListAllTags: get all unique tags in the game
function Query.listAllTags(params: any): (boolean, any)
    local rootPath = params.root

    local root = rootPath and getInstanceByPath(rootPath) or game
    if not root then
        return false, "Root not found: " .. tostring(rootPath)
    end

    local tagCounts: {[string]: number} = {}

    for _, inst in (root :: Instance):GetDescendants() do
        for _, tag in CollectionService:GetTags(inst) do
            tagCounts[tag] = (tagCounts[tag] or 0) + 1
        end
    end

    -- Sort by count
    local sorted = {}
    for tag, count in pairs(tagCounts) do
        table.insert(sorted, { tag = tag, count = count })
    end
    table.sort(sorted, function(a, b)
        return a.count > b.count
    end)

    return true, {
        tags = tagCounts,
        sorted = sorted,
        totalTags = #sorted
    }
end

-- AddTag: add a tag to instances matching a query
function Query.addTag(params: any): (boolean, any)
    local tag = params.tag
    local path = params.path  -- Single instance
    local query = params.query  -- Or use query to match multiple

    if not tag or type(tag) ~= "string" then
        return false, "Missing or invalid tag parameter"
    end

    local modified = {}

    if path then
        -- Single instance
        local inst = getInstanceByPath(path)
        if not inst then
            return false, "Instance not found: " .. path
        end
        CollectionService:AddTag(inst, tag)
        table.insert(modified, path)
    elseif query then
        -- Query to match multiple
        local success, result = Query.execute({ query = query, limit = 1000 })
        if not success then
            return false, "Query failed: " .. tostring(result)
        end
        for _, r in result.results do
            local inst = getInstanceByPath(r.path)
            if inst then
                CollectionService:AddTag(inst, tag)
                table.insert(modified, r.path)
            end
        end
    else
        return false, "Missing path or query parameter"
    end

    return true, {
        tag = tag,
        modified = modified,
        count = #modified
    }
end

-- RemoveTag: remove a tag from instances
function Query.removeTag(params: any): (boolean, any)
    local tag = params.tag
    local path = params.path
    local query = params.query

    if not tag or type(tag) ~= "string" then
        return false, "Missing or invalid tag parameter"
    end

    local modified = {}

    if path then
        local inst = getInstanceByPath(path)
        if not inst then
            return false, "Instance not found: " .. path
        end
        CollectionService:RemoveTag(inst, tag)
        table.insert(modified, path)
    elseif query then
        local success, result = Query.execute({ query = query, limit = 1000 })
        if not success then
            return false, "Query failed: " .. tostring(result)
        end
        for _, r in result.results do
            local inst = getInstanceByPath(r.path)
            if inst then
                CollectionService:RemoveTag(inst, tag)
                table.insert(modified, r.path)
            end
        end
    else
        -- Remove from all with this tag
        local tagged = CollectionService:GetTagged(tag)
        for _, inst in tagged do
            CollectionService:RemoveTag(inst, tag)
            table.insert(modified, getInstancePath(inst))
        end
    end

    return true, {
        tag = tag,
        modified = modified,
        count = #modified
    }
end

-- ============ Attribute Operations ============

-- GetAttributes: get all attributes on an instance
function Query.getAttributes(params: any): (boolean, any)
    local path = params.path

    if not path then
        return false, "Missing path parameter"
    end

    local inst = getInstanceByPath(path)
    if not inst then
        return false, "Instance not found: " .. path
    end

    local attrs = inst:GetAttributes()
    local serialized: {[string]: any} = {}

    for name, value in pairs(attrs) do
        serialized[name] = serializeValue(value)
    end

    return true, {
        path = path,
        attributes = serialized,
        count = 0  -- Will be updated below
    }
end

-- SetAttribute: set an attribute on instances
function Query.setAttribute(params: any): (boolean, any)
    local path = params.path
    local query = params.query
    local name = params.name or params.attribute
    local value = params.value

    if not name then
        return false, "Missing attribute name"
    end

    local modified = {}

    if path then
        local inst = getInstanceByPath(path)
        if not inst then
            return false, "Instance not found: " .. path
        end
        inst:SetAttribute(name, value)
        table.insert(modified, path)
    elseif query then
        local success, result = Query.execute({ query = query, limit = 1000 })
        if not success then
            return false, "Query failed: " .. tostring(result)
        end
        for _, r in result.results do
            local inst = getInstanceByPath(r.path)
            if inst then
                inst:SetAttribute(name, value)
                table.insert(modified, r.path)
            end
        end
    else
        return false, "Missing path or query parameter"
    end

    return true, {
        attribute = name,
        value = serializeValue(value),
        modified = modified,
        count = #modified
    }
end

-- ListAttributes: list all unique attributes in the game
function Query.listAttributes(params: any): (boolean, any)
    local rootPath = params.root

    local root = rootPath and getInstanceByPath(rootPath) or game
    if not root then
        return false, "Root not found: " .. tostring(rootPath)
    end

    local attrCounts: {[string]: number} = {}

    for _, inst in (root :: Instance):GetDescendants() do
        for attrName, _ in pairs(inst:GetAttributes()) do
            attrCounts[attrName] = (attrCounts[attrName] or 0) + 1
        end
    end

    -- Sort by count
    local sorted = {}
    for name, count in pairs(attrCounts) do
        table.insert(sorted, { name = name, count = count })
    end
    table.sort(sorted, function(a, b)
        return a.count > b.count
    end)

    return true, {
        attributes = attrCounts,
        sorted = sorted,
        totalAttributes = #sorted
    }
end

return Query
