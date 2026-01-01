# Vision Integration Roadmap

## Context

Analysis of SOTA computer use models and how Bakable can learn from them while leveraging our semantic API advantage.

---

## Current SOTA Computer Use Landscape

### Screenshot-Based Agents (Claude Computer Use, Operator, etc.)

```
Loop: screenshot → vision → action (click/type) → screenshot → verify → repeat
```

**Strengths:**
- Universal - works with any app, no integration needed
- Visual grounding - AI sees what user sees
- Self-verification - screenshot after action confirms success

**Weaknesses:**
- Slow (screenshot + vision per action)
- No semantic access (sees pixels, not data models)
- Fragile to UI changes
- Can't access internal state (logs, memory, hidden data)

### Hybrid Approaches (Microsoft UFO, etc.)
- Combines vision with accessibility/UI automation APIs
- Gets element tree + visual context
- Faster, more reliable targeting

---

## Where Bakable Already Wins

We have **semantic access** that screenshot agents lack:

| Computer Use Agent | Bakable |
|-------------------|---------|
| Screenshot → find button → click → screenshot → verify | `studio.instances.setProps()` - done |
| 10+ actions to navigate UI | 1 API call |
| Sees pixels, guesses meaning | Knows exact instance tree, properties, types |
| Can't see logs, memory, HTTP | Full access via runtime tools |

---

## What We Should Learn

### 1. Visual Grounding / Verification

Computer use agents verify actions worked by capturing screenshots. We have `studio.captureViewport` but don't use it systematically.

**Idea**: After significant actions, auto-capture viewport and include in context so AI can verify its changes.

```
AI: studio.instances.create({...})
→ Auto-capture viewport
→ AI sees the new part in scene
→ "I created the part, I can see it's positioned correctly"
```

### 2. Vision-Assisted Selection

User says: "delete the red brick"

- Current Bakable: Needs to know the name or path
- Computer Use: Would see the screen and identify which brick is red

**Idea**: Combine vision + semantic API:
```
1. Capture viewport
2. Vision identifies "red brick" visually
3. Match to instance tree (by position/bounds)
4. Use API to delete
```

### 3. Spatial Commands with Vision

User: "move it next to the door"

This requires understanding scene layout. Pure API gives coordinates, but vision understands spatial relationships.

**Idea**: Viewport capture + instance tree = rich spatial reasoning

### 4. Annotated Screenshots

SOTA agents sometimes overlay bounding boxes/labels on screenshots.

**Idea**: `studio.captureViewport` could optionally:
- Highlight current selection
- Show path points with numbers
- Label key instances
- Draw pointer marker

### 5. Observation-Action-Verification Loop

Best computer use agents run iteratively:
```
Observe → Plan → Act → Observe → Evaluate → Repeat/Done
```

Current Bakable:
```
Get context → Act (tools) → Done
```

**Idea**: More agentic loop:
```
1. Inject context + viewport image
2. Plan
3. Act (tool calls)
4. Auto-capture viewport
5. Evaluate result
6. Iterate if needed
```

---

## Concrete Features to Add

### Priority 1: Auto-Viewport in Context

```javascript
// Before each chat, capture viewport and include as image
const screenshot = await callPlugin('studio.captureViewport');
messages.push({
  role: 'user',
  content: [
    { type: 'image', source: { data: screenshot } },
    { type: 'text', text: userMessage }
  ]
});
```

AI now has visual awareness of current scene.

### Priority 2: Vision-Assisted Selection

New tool: `studio.selectByDescription`
```
User: "select the red car"
→ Capture viewport
→ Vision: "I see a red car-shaped model at position (10, 0, 5)"
→ Query instance tree for objects near that position
→ Select matching instance
```

### Priority 3: Before/After Verification

```javascript
// Capture before
const before = await captureViewport();

// Execute user's request (multiple tool calls)
await agent.query(userMessage);

// Capture after
const after = await captureViewport();

// AI verifies
await agent.query([
  { type: 'image', data: before, label: 'Before' },
  { type: 'image', data: after, label: 'After' },
  { type: 'text', text: 'Did the changes look correct?' }
]);
```

### Priority 4: Hybrid Mode for Non-API Features

Some Studio features aren't exposed via API. Could fall back to computer use:
```
if (canUseAPI(task)) {
  // Fast path: direct API
  await studio.instances.setProps(...)
} else {
  // Slow path: screenshot + click
  await computerUse.click(x, y)
}
```

---

## Architecture Evolution

### Current
```
User message
→ Text context (selection, path, pointer)
→ Claude Agent SDK
→ Tool calls
→ Response
```

### Enhanced
```
User message
→ Text context + Viewport IMAGE
→ Claude with vision
→ Tool calls (API-first, vision-guided)
→ Auto-capture after significant changes
→ Verification / iteration
→ Response
```

---

## Key Insight

**Computer use agents compensate for lack of semantic access with vision.**

**Bakable has semantic access but lacks visual grounding.**

**Best of both worlds: Keep our 51 semantic tools, ADD vision for grounding, verification, and spatial reasoning.**

We shouldn't regress to screenshot-per-action (slow), but we should use vision strategically:
- Scene understanding ("the red brick near the door")
- Verification (did my action work?)
- Spatial commands ("put it there")

---

## Comparison: Roblox Official MCP vs Bakable

| Aspect | Roblox/studio-rust-mcp-server | Bakable |
|--------|-------------------------------|---------|
| Language | Rust | Node.js + Lua + Rust desktop |
| Tools | 2 (`insert_model`, `run_code`) | 51+ |
| Transport | stdio | HTTP + WebSocket + SSE |
| UI | None (CLI only) | Full desktop chat app |
| Vision | None | Viewport capture (planned: auto-inject) |

Both use `loadstring` for code execution, meaning neither can be published to Plugin Marketplace.

---

## Implementation Checklist

- [ ] Auto-inject viewport capture in chat context
- [ ] Add `studio.selectByDescription` tool (vision-assisted)
- [ ] Before/after screenshot verification
- [ ] Annotated screenshots (selection highlight, labels)
- [ ] Agentic verification loop
- [ ] Hybrid computer use fallback for non-API features

---

*Last updated: 2026-01-01*
