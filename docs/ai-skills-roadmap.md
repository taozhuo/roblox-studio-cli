# Bakable AI Skills Roadmap

## The Core Problem

**How does an AI know when it's "done" building something in Roblox without a human checking?**

This is fundamentally a verification problem. The AI must:
1. Understand what "done" looks like for a given task
2. Have tools to check if that state has been achieved
3. Know how to iterate if verification fails

---

## Philosophy: The Observe-Act-Verify Loop

Every AI action should follow this pattern:

```
OBSERVE → ACT → VERIFY → (iterate or done)
     ↑                        |
     └────────────────────────┘
```

**Observe**: Understand current state before changing anything
**Act**: Make the smallest meaningful change
**Verify**: Confirm the change achieved its goal
**Iterate**: If verification fails, diagnose and retry

The AI should never assume an action succeeded. Always verify.

---

## Verification Hierarchy

### Level 0: Existence Verification
*"Does the thing exist?"*

```lua
-- Create a part
studio.instances.create({ parent: "Workspace", className: "Part", name: "MyPart" })

-- Verify it exists
result = studio.instances.tree({ root: "Workspace", depth: 1 })
assert(result.children.find(c => c.name === "MyPart"))
```

**Tools**: `studio.instances.tree`, `studio.selection.get`

### Level 1: Property Verification
*"Does it have the right properties?"*

```lua
-- Set properties
studio.instances.setProps({ path: "Workspace.MyPart", props: { Size: [10, 1, 10], Color: [0, 0.5, 1] } })

-- Verify properties
props = studio.instances.getProps({ path: "Workspace.MyPart" })
assert(props.Size[0] === 10 && props.Size[1] === 1 && props.Size[2] === 10)
```

**Tools**: `studio.instances.getProps`, `studio.scripts.read`

### Level 2: Visual Verification
*"Does it look right?"*

```lua
-- Create UI
studio.eval({ code: "createShopUI()" })

-- Capture what it looks like
studio.gui.showOnly({ name: "ShopUI" })
studio.recording.captureFrame({ output: "/tmp/shop-ui.png" })

-- AI analyzes image: "Is there a blue frame with 'Shop' title and 3 item buttons?"
```

**Tools**: `studio.recording.captureFrame`, `studio.camera.set` + capture

**Challenge**: Requires vision model to interpret screenshots

### Level 3: Behavioral Verification
*"Does it work correctly?"*

```lua
-- Write a script that sets a global when it runs
studio.scripts.write({
  path: "ServerScriptService.GameManager",
  source: "_G.GameReady = true; print('Game initialized')"
})

-- Run the game
studio.playtest.play()
wait(3000)

-- Check the behavior happened
result = studio.eval({ code: "return _G.GameReady" })
assert(result === true)

logs = studio.logs.getHistory()
assert(logs.some(l => l.message.includes("Game initialized")))

studio.playtest.stop()
```

**Tools**: `studio.playtest.*`, `studio.eval`, `studio.logs.getHistory`

### Level 4: Interaction Verification
*"Does it respond to user input correctly?"*

```lua
-- Test a button click
studio.playtest.play()
wait(2000)

-- Record gameplay
studio.recording.start({ fps: 10 })

-- Simulate clicking a button (via injected test script)
studio.eval({ code: [[
  local button = Players.LocalPlayer.PlayerGui.ShopUI.BuyButton
  button.Activated:Fire()  -- Simulate click
]] })

wait(1000)
studio.recording.stop()

-- Check inventory changed
result = studio.eval({ code: "return Players.LocalPlayer.Inventory:GetChildren()" })
assert(result.length > 0)  -- Player bought something
```

**Tools**: All playtest + recording tools

### Level 5: End-to-End Verification
*"Does the complete game work?"*

```lua
-- Full gameplay test
studio.playtest.play()
waitForPlayer()

studio.recording.start({ fps: 15 })

-- Play sequence
studio.playtest.sendInput({ keys: ["W"], duration: 3000 })  -- Walk forward
studio.playtest.sendInput({ keys: ["Space"], duration: 100 }) -- Jump
studio.playtest.sendInput({ keys: ["E"], duration: 100 })     // Interact

studio.recording.stop()
studio.recording.createGif({ output: "gameplay-test.gif" })

-- Analyze: Did player move? Jump? Interact with object?
-- This requires analyzing the GIF frames
```

**Tools**: Full tool suite + video analysis

---

## Skill Definitions

### Primitive Skills (Atomic Operations)

```yaml
skill: create-instance
description: Create a single instance in the game
inputs:
  parent: string (path)
  className: string
  name: string
  properties: object (optional)
execute:
  - studio.instances.create(inputs)
verify:
  - tree = studio.instances.tree({ root: inputs.parent, depth: 1 })
  - assert tree.children.includes(inputs.name)
done_when: instance exists in parent
```

```yaml
skill: write-script
description: Write source code to a script
inputs:
  path: string
  source: string
execute:
  - studio.scripts.write({ path, source })
verify:
  - current = studio.scripts.read({ path })
  - assert current.source === inputs.source
done_when: source matches exactly
```

```yaml
skill: set-camera
description: Position camera to view specific area
inputs:
  position: Vector3
  lookAt: Vector3
execute:
  - studio.camera.set({ position, lookAt })
verify:
  - cam = studio.camera.get()
  - assert cam.position ~= inputs.position (within tolerance)
done_when: camera at expected position
```

### Composite Skills (Built from Primitives)

```yaml
skill: build-part
description: Create a fully configured Part
inputs:
  name: string
  size: Vector3
  position: Vector3
  color: Color3
  material: string
steps:
  1. create-instance(Workspace, Part, name)
  2. set-properties(path, { Size: size, Position: position, Color: color, Material: material })
  3. verify-properties(path, all inputs)
done_when: all properties match inputs
```

```yaml
skill: build-ui-frame
description: Create a ScreenGui with a centered frame
inputs:
  name: string
  title: string
  size: UDim2
  color: Color3
steps:
  1. eval: create ScreenGui named {name} in StarterGui
  2. eval: create Frame with {size}, centered, {color}
  3. eval: create TextLabel with {title}
  4. gui.list() → verify {name} exists
  5. gui.showOnly({name})
  6. recording.captureFrame()
  7. (vision) verify: frame visible, title readable
done_when: GUI exists AND visual shows expected layout
```

```yaml
skill: test-script-runs
description: Verify a script executes without errors
inputs:
  scriptPath: string
  successIndicator: string (global variable or log message)
steps:
  1. playtest.play()
  2. wait(3 seconds)
  3. logs.getHistory() → check for errors mentioning scriptPath
  4. if successIndicator is global: eval("return " + successIndicator)
  5. if successIndicator is log: check logs contain it
  6. playtest.stop()
done_when: no errors AND successIndicator found
```

### Complex Skills (Multi-Step Workflows)

```yaml
skill: build-interactive-button
description: Create a button that does something when clicked
inputs:
  guiName: string
  buttonText: string
  onClick: string (Lua code)
steps:
  1. build-ui-frame(guiName, buttonText, ...)
  2. eval: add TextButton to frame
  3. eval: connect onClick handler
  4. playtest.play()
  5. waitForPlayer()
  6. eval: simulate button click
  7. verify onClick effect happened
  8. playtest.stop()
done_when: clicking button triggers expected effect
```

```yaml
skill: build-collectible-system
description: Create coins that player can collect
inputs:
  coinCount: number
  coinValue: number
steps:
  1. create-instance: Folder "Coins" in Workspace
  2. loop coinCount times:
     - create-instance: Part with coin appearance
     - write-script: LocalScript that detects touch and adds to player score
  3. write-script: PlayerScripts/CoinDisplay to show score
  4. playtest.play()
  5. recording.start()
  6. walk player into a coin
  7. verify: coin disappeared, score increased
  8. recording.stop() → createGif for proof
  9. playtest.stop()
done_when: coins collectible AND score updates AND visual proof captured
```

---

## The "Done" Framework

### Task Completion Checklist

For any task, AI should verify:

| Check | Question | Tool |
|-------|----------|------|
| **Exists** | Does the created thing exist? | `instances.tree` |
| **Correct** | Are properties/code correct? | `instances.getProps`, `scripts.read` |
| **Visible** | Does it appear correctly? | `recording.captureFrame` |
| **Functional** | Does it work when run? | `playtest.*` + `eval` |
| **Error-free** | Any errors in console? | `logs.getHistory` |
| **Integrated** | Does it work with rest of game? | End-to-end test |

### Done States

```
NOT_STARTED → IN_PROGRESS → VERIFY_FAILED → DONE
                   ↑              |
                   └──────────────┘
                    (iterate/fix)
```

**DONE** means:
- All existence checks pass
- All property checks pass
- Visual verification passes (if applicable)
- Behavioral verification passes (if applicable)
- No errors in logs

### Failure Recovery

When verification fails, AI should:

1. **Diagnose**: What specifically failed?
2. **Analyze**: Why might it have failed?
3. **Fix**: Make targeted correction
4. **Re-verify**: Check if fix worked
5. **Escalate**: If 3 attempts fail, ask human

```yaml
on_verify_fail:
  - diagnosis = compare(expected, actual)
  - if diagnosis.type == "missing":
      retry create step
  - if diagnosis.type == "wrong_value":
      retry set step with correct value
  - if diagnosis.type == "runtime_error":
      read error from logs
      analyze and fix code
  - if attempts > 3:
      report failure to human with diagnosis
```

---

## Skill Learning Path

### Stage 1: Observer (Read-Only)
AI learns to query and understand game state without modifying.

Skills:
- `observe-tree` - Read instance hierarchy
- `observe-properties` - Read any property
- `observe-scripts` - Read script source
- `observe-gui` - List and preview GUIs
- `observe-camera` - Get camera state

Verification: AI can accurately describe current game state.

### Stage 2: Creator (Single Changes)
AI learns to make atomic changes and verify them.

Skills:
- `create-instance` - Make one instance
- `set-property` - Change one property
- `write-script` - Write script source
- `delete-instance` - Remove instance

Verification: Each change verified immediately after.

### Stage 3: Builder (Composite Structures)
AI combines atomic skills into larger creations.

Skills:
- `build-part` - Configured Part
- `build-model` - Multi-part Model
- `build-ui` - ScreenGui with elements
- `build-script-system` - Scripts that work together

Verification: Structural + property verification.

### Stage 4: Tester (Runtime Verification)
AI learns to run and test what it built.

Skills:
- `test-script` - Verify script runs
- `test-ui` - Verify UI works
- `test-interaction` - Verify player can interact
- `test-gameplay` - Full play session

Verification: Behavioral verification during playtest.

### Stage 5: Autonomous Builder
AI builds complete features end-to-end.

Skills:
- `build-feature` - Complete game feature
- `iterate-on-feedback` - Improve based on test results
- `document-feature` - Explain what was built

Verification: Full verification hierarchy + can explain to human.

---

## Implementation Priority

### Week 1-2: Foundation
- [ ] Implement all observe skills
- [ ] Implement atomic create/modify skills
- [ ] Build verification framework
- [ ] Test with simple "create a red part" task

### Week 3-4: Building
- [ ] Implement composite building skills
- [ ] Add visual verification (screenshot capture)
- [ ] Test with "build a simple UI" task

### Week 5-6: Testing
- [ ] Implement playtest skills
- [ ] Add behavioral verification
- [ ] Test with "build and test a collectible" task

### Week 7-8: Integration
- [ ] Implement complex multi-step skills
- [ ] Add failure recovery
- [ ] Test with "build a complete minigame" task

### Week 9+: Autonomy
- [ ] AI can accept high-level requests
- [ ] AI plans and executes multi-skill workflows
- [ ] AI asks clarifying questions when needed
- [ ] AI reports completion with evidence

---

## Success Criteria

The AI skills system is successful when:

1. **Zero Human Verification**: AI can confirm task completion without human looking
2. **Reproducible**: Same task request produces consistent results
3. **Self-Diagnosing**: AI identifies why something failed
4. **Self-Correcting**: AI fixes failures without human help (most of the time)
5. **Evidence-Based**: AI provides screenshots/recordings as proof of completion

### Target Metrics

| Metric | Target |
|--------|--------|
| Single-change success rate | 99% |
| Composite build success rate | 95% |
| Behavioral test pass rate | 90% |
| Autonomous feature completion | 80% |
| Mean attempts before success | < 2 |
| Tasks requiring human help | < 10% |
