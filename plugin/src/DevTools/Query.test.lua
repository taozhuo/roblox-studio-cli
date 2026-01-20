--[[
    Query Module Test Script

    Run this in Studio's command bar or as a Script to verify Query.lua works.

    Usage:
        1. Copy this file to a Script in Studio
        2. Run the script
        3. Check Output for test results
]]

local Query = require(script.Parent.Query)

local function test(name, func)
    local success, result = pcall(func)
    if success then
        print("✅ PASS:", name)
        return true
    else
        warn("❌ FAIL:", name, "-", tostring(result))
        return false
    end
end

local function assertEquals(expected, actual, msg)
    if expected ~= actual then
        error(string.format("%s: expected %s, got %s", msg or "Assertion failed", tostring(expected), tostring(actual)))
    end
end

local function assertNotNil(value, msg)
    if value == nil then
        error(msg or "Expected non-nil value")
    end
end

local passed = 0
local failed = 0

print("=== Query Module Tests ===")
print("")

-- Test 1: Basic DSL query
if test("DSL: .. | Part", function()
    local success, result = Query.execute({ query = ".. | Part", limit = 10 })
    assert(success, "Query failed")
    assertNotNil(result.results, "No results")
    assertNotNil(result.count, "No count")
end) then passed += 1 else failed += 1 end

-- Test 2: DSL with class filter
if test("DSL: .. | BasePart", function()
    local success, result = Query.execute({ query = ".. | BasePart", limit = 10 })
    assert(success, "Query failed")
    for _, r in result.results do
        -- Verify all results are BasePart
        local inst = Query.getByPath(r.path)
        assert(inst and inst:IsA("BasePart"), "Result is not BasePart: " .. r.path)
    end
end) then passed += 1 else failed += 1 end

-- Test 3: DSL with condition
if test("DSL: .. | Part | .Anchored == true", function()
    local success, result = Query.execute({ query = ".. | Part | .Anchored == true", limit = 10 })
    assert(success, "Query failed")
    for _, r in result.results do
        local inst = Query.getByPath(r.path)
        assert(inst and inst.Anchored == true, "Part is not anchored: " .. r.path)
    end
end) then passed += 1 else failed += 1 end

-- Test 4: DSL with projection
if test("DSL: .. | Part | {Name, Position}", function()
    local success, result = Query.execute({ query = ".. | Part | {Name, Position}", limit = 5 })
    assert(success, "Query failed")
    for _, r in result.results do
        assertNotNil(r.Name, "Missing Name in projection")
        assertNotNil(r.Position, "Missing Position in projection")
    end
end) then passed += 1 else failed += 1 end

-- Test 5: DSL count
if test("DSL: .. | Part | count", function()
    local success, result = Query.execute({ query = ".. | Part | count" })
    assert(success, "Query failed")
    assertNotNil(result.count, "No count returned")
    assert(type(result.count) == "number", "Count should be number")
end) then passed += 1 else failed += 1 end

-- Test 6: DSL limit
if test("DSL: .. | Instance | limit(5)", function()
    local success, result = Query.execute({ query = ".. | limit(5)" })
    assert(success, "Query failed")
    assert(result.count <= 5, "Limit not respected: " .. result.count)
end) then passed += 1 else failed += 1 end

-- Test 7: Structured find
if test("Structured: find(class=Part)", function()
    local success, result = Query.find({ class = "Part", limit = 10 })
    assert(success, "Find failed")
    for _, r in result.results do
        local inst = Query.getByPath(r.path)
        assert(inst and inst:IsA("Part"), "Result is not Part: " .. r.path)
    end
end) then passed += 1 else failed += 1 end

-- Test 8: Structured find with conditions
if test("Structured: find with where", function()
    local success, result = Query.find({
        class = "BasePart",
        where = {{"Anchored", "==", true}},
        limit = 10
    })
    assert(success, "Find failed")
    for _, r in result.results do
        local inst = Query.getByPath(r.path)
        assert(inst and inst.Anchored == true, "Part not anchored: " .. r.path)
    end
end) then passed += 1 else failed += 1 end

-- Test 9: Grep (may return 0 results if no scripts)
if test("Grep: search for 'game'", function()
    local success, result = Query.grep({ pattern = "game", limit = 5 })
    assert(success, "Grep failed")
    assertNotNil(result.results, "No results array")
    assertNotNil(result.count, "No count")
end) then passed += 1 else failed += 1 end

-- Test 10: Grep with lines
if test("Grep: with line numbers", function()
    local success, result = Query.grep({ pattern = "function", lines = true, limit = 5 })
    assert(success, "Grep failed")
    -- If there are results, they should have matches
    if result.count > 0 then
        assertNotNil(result.results[1].matches, "No matches array in result")
    end
end) then passed += 1 else failed += 1 end

-- Test 11: Sed dry run
if test("Sed: dry run", function()
    local success, result = Query.sed({
        pattern = "UNLIKELY_PATTERN_12345",
        replacement = "REPLACED",
        dryRun = true
    })
    assert(success, "Sed failed")
    assert(result.dryRun == true, "dryRun should be true")
    assertEquals(0, result.totalReplacements, "Should have 0 replacements for unlikely pattern")
end) then passed += 1 else failed += 1 end

-- Test 12: Count
if test("Count: all instances", function()
    local success, result = Query.count({})
    assert(success, "Count failed")
    assertNotNil(result.count, "No count")
    assert(result.count > 0, "Should have at least 1 instance")
end) then passed += 1 else failed += 1 end

-- Test 13: Count by class
if test("CountByClass", function()
    local success, result = Query.countByClass({})
    assert(success, "CountByClass failed")
    assertNotNil(result.classes, "No classes")
    assertNotNil(result.total, "No total")
    assertNotNil(result.sorted, "No sorted array")
end) then passed += 1 else failed += 1 end

-- Test 14: Path traversal
if test("DSL: .Workspace path", function()
    local success, result = Query.execute({ query = ".Workspace | .[] | limit(5)" })
    assert(success, "Query failed: " .. tostring(result))
end) then passed += 1 else failed += 1 end

-- Test 15: Name pattern match
if test("DSL: name pattern .Name ~ 'Part'", function()
    local success, result = Query.execute({ query = ".. | .Name ~ 'Part' | limit(5)" })
    assert(success, "Query failed")
    for _, r in result.results do
        assert(r.name:match("Part"), "Name should match 'Part': " .. r.name)
    end
end) then passed += 1 else failed += 1 end

print("")
print("=== Test Results ===")
print(string.format("Passed: %d", passed))
print(string.format("Failed: %d", failed))
print(string.format("Total:  %d", passed + failed))

if failed == 0 then
    print("✅ All tests passed!")
else
    warn("❌ Some tests failed")
end

return {
    passed = passed,
    failed = failed
}
