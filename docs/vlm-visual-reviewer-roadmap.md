# VLM Visual Reviewer Roadmap

## Vision

Use a fast, low-latency Vision Language Model (Gemini 3 Flash) as an autonomous visual reviewer that can verify game builds, UI layouts, and gameplay recordings without human intervention.

---

## Why Gemini 3 Flash?

Released December 2025, Gemini 3 Flash combines Pro-level reasoning with Flash-line speed and efficiency.

| Requirement | Gemini 3 Flash |
|-------------|------------------|
| **Latency** | 3x faster than 2.5 Pro |
| **Cost** | $0.50/1M input, $3.00/1M output tokens |
| **Vision** | 81.2% on MMMU-Pro (best in class) |
| **Multimodal** | Screenshots, GIFs, video frames, documents |
| **Structured Output** | JSON mode for programmatic verification |
| **Modes** | "Fast" for quick answers, "Thinking" for complex |

### Comparison

| Model | Speed | Cost (input/1M) | Vision (MMMU-Pro) |
|-------|-------|-----------------|-------------------|
| Gemini 3 Flash | Fastest | $0.50 | 81.2% |
| Gemini 3 Pro | Fast | ~$2.00 | ~80% |
| Gemini 2.5 Flash | Fast | $0.30 | ~70% |
| GPT-4V | Slow | ~$10.00 | ~75% |
| Claude Vision | Medium | ~$3.00 | ~78% |

**Gemini 3 Flash is ideal for high-frequency verification checks** - Pro-level vision quality at Flash-line speed and cost.

### Key Stats
- 78% on SWE-bench Verified (agentic coding)
- 33.7% on Humanity's Last Exam (expert reasoning)
- Processing 1T+ tokens/day on Google's API
- Used by Salesforce, Workday, Figma

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Claude Code (Orchestrator)                │
│                                                             │
│  "Build a shop UI with 3 item buttons"                      │
│                          │                                  │
│                          ▼                                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Bakable MCP Tools                       │   │
│  │                                                      │   │
│  │  studio.eval() → Create UI                          │   │
│  │  studio.gui.showOnly() → Display it                 │   │
│  │  studio.recording.captureFrame() → Screenshot       │   │
│  │                          │                          │   │
│  └──────────────────────────┼──────────────────────────┘   │
│                             │                               │
│                             ▼                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Gemini 3 Flash (Visual Judge)            │   │
│  │                                                      │   │
│  │  Input: Screenshot + Expected Description            │   │
│  │  Output: { pass: bool, issues: [], suggestions: [] } │   │
│  │                                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                             │                               │
│                             ▼                               │
│                 pass? → DONE : iterate                      │
└─────────────────────────────────────────────────────────────┘
```

---

## Verification Areas

Roblox games have distinct visual domains that require different verification strategies:

| Area | What to Verify | Capture Method | Complexity |
|------|---------------|----------------|------------|
| **GUI** | Layout, text, buttons, colors | `gui.showOnly` + screenshot | Low |
| **Parts/Models** | Shape, size, position, materials | Camera position + screenshot | Medium |
| **Tools** | Equip state, visual effects, UI | Playtest + recording | Medium |
| **Animations** | Motion, timing, transitions | GIF recording + frame analysis | High |
| **Lighting/FX** | Particles, beams, atmosphere | Screenshot comparison | Medium |
| **Gameplay** | Player movement, interactions | Full playtest recording | High |

---

## Area 1: GUI Verification

### What to Check
- Layout matches mockup/spec
- Text is readable and correct
- Buttons are visible and identifiable
- Colors match brand/theme
- No overlapping elements
- Proper spacing and alignment
- Responsive to different screen sizes

### Verification Prompt Template

```
You are reviewing a Roblox ScreenGui screenshot.

EXPECTED UI:
- Name: {guiName}
- Layout: {description}
- Elements: {list of expected elements}

CHECK FOR:
1. All expected elements present and visible
2. Text is readable (not too small, good contrast)
3. Layout matches description (centered, aligned, spaced)
4. Colors match specification
5. No visual errors (overflow, overlap, missing assets)

RETURN JSON:
{
  "elements": {
    "expected": ["list"],
    "found": ["list"],
    "missing": ["list"]
  },
  "layout": {
    "correct": boolean,
    "issues": ["list of layout problems"]
  },
  "text": {
    "readable": boolean,
    "issues": ["list of text problems"]
  },
  "colors": {
    "correct": boolean,
    "issues": ["list of color mismatches"]
  },
  "pass": boolean,
  "score": 0-100
}
```

### Example Workflow

```javascript
// Build a shop UI
await studio.eval({ code: createShopUICode });

// Verify it
await studio.gui.showOnly({ name: "ShopUI" });
const screenshot = await studio.recording.captureFrame();

const result = await vlm.verify({
  image: screenshot,
  area: "gui",
  spec: {
    name: "ShopUI",
    layout: "Centered modal, 400x500 pixels",
    elements: [
      "Title 'SHOP' at top center",
      "3 item cards in horizontal row",
      "Each card has: icon, name, price, buy button",
      "Close X button in top-right corner"
    ],
    colors: {
      background: "dark blue (#1a1a2e)",
      buttons: "gold (#ffd700)",
      text: "white"
    }
  }
});
```

---

## Area 2: Part-Based Modeling

### What to Check
- Parts exist with correct shapes
- Sizes match specifications
- Positions are correct (aligned, spaced)
- Materials and colors applied
- Model hierarchy is correct
- No floating or intersecting parts

### Verification Prompt Template

```
You are reviewing a Roblox 3D viewport screenshot showing parts/models.

EXPECTED MODEL:
- Name: {modelName}
- Description: {what it should look like}
- Parts: {list of expected parts with properties}

CHECK FOR:
1. All expected parts visible
2. Shapes match description (cube, sphere, wedge, etc.)
3. Proportions look correct
4. Parts are properly connected (no gaps, no overlap)
5. Materials/colors match specification
6. Model is complete (no missing pieces)

RETURN JSON:
{
  "partsVisible": {
    "expected": ["list"],
    "found": ["list"],
    "missing": ["list"]
  },
  "structure": {
    "correct": boolean,
    "issues": ["gaps", "overlaps", "misalignment"]
  },
  "appearance": {
    "materialsCorrect": boolean,
    "colorsCorrect": boolean,
    "issues": []
  },
  "pass": boolean,
  "score": 0-100
}
```

### Example Workflow

```javascript
// Create a simple house model
await studio.instances.create({
  parent: "Workspace",
  className: "Model",
  name: "House"
});
await studio.eval({ code: buildHouseCode });

// Position camera to view it
await studio.camera.focusOn({ target: "Workspace.House" });
const screenshot = await studio.recording.captureFrame();

const result = await vlm.verify({
  image: screenshot,
  area: "model",
  spec: {
    name: "House",
    description: "Simple house with walls, roof, door, windows",
    parts: [
      "4 wall parts forming rectangle",
      "Triangular roof on top",
      "Door-shaped opening in front wall",
      "2 window openings on side walls"
    ],
    materials: {
      walls: "Brick",
      roof: "Slate",
      floor: "Wood"
    }
  }
});
```

---

## Area 3: Tools Verification

### What to Check
- Tool appears in player's hand when equipped
- Tool has correct visual appearance
- Tool UI elements appear (ammo count, cooldown, etc.)
- Visual effects play correctly (muzzle flash, trails)
- Tool animations play

### Verification Prompt Template

```
You are reviewing Roblox gameplay showing a player with an equipped tool.

EXPECTED TOOL:
- Name: {toolName}
- Type: {weapon/building/utility}
- Appearance: {description}
- UI Elements: {list}
- Effects: {list of visual effects}

CHECK FOR:
1. Tool visible in player's hand/character
2. Tool appearance matches description
3. UI elements visible (if applicable)
4. Effects visible when activated (if captured)
5. Correct positioning relative to character

RETURN JSON:
{
  "toolEquipped": boolean,
  "appearance": {
    "correct": boolean,
    "issues": []
  },
  "uiElements": {
    "expected": ["list"],
    "found": ["list"],
    "missing": ["list"]
  },
  "effects": {
    "visible": boolean,
    "issues": []
  },
  "pass": boolean,
  "score": 0-100
}
```

### Example Workflow

```javascript
// Create and equip a sword tool
await studio.eval({ code: createSwordCode });
await studio.playtest.play();
await waitForPlayer();

// Equip the tool
await studio.eval({
  code: `
    local player = game.Players.LocalPlayer
    local sword = player.Backpack:FindFirstChild("Sword")
    player.Character.Humanoid:EquipTool(sword)
  `
});

// Capture equipped state
await wait(500);
const screenshot = await studio.recording.captureFrame();

const result = await vlm.verify({
  image: screenshot,
  area: "tool",
  spec: {
    name: "Sword",
    type: "weapon",
    appearance: "Medieval sword with silver blade, brown handle",
    uiElements: [],
    effects: []
  }
});

// Test swing animation
await studio.recording.start({ fps: 15 });
await studio.eval({ code: "-- trigger sword swing" });
await wait(1000);
await studio.recording.stop();
const gif = await studio.recording.createGif();

const animResult = await vlm.analyzeAnimation({
  gif: gif,
  expectedMotion: "Sword swings in arc from right to left"
});
```

---

## Area 4: Animation Verification

### What to Check
- Animation plays (not stuck on frame 1)
- Motion matches expected movement
- Timing feels correct
- Transitions are smooth
- Loop is seamless (if looping)
- No visual glitches

### Verification Prompt Template

```
You are analyzing a Roblox animation recording (sequence of frames).

EXPECTED ANIMATION:
- Name: {animationName}
- Type: {walk/run/attack/idle/custom}
- Duration: {approximate seconds}
- Motion: {description of movement}
- Loop: {yes/no}

ANALYZE FRAMES FOR:
1. Character/object is moving (not static)
2. Motion matches expected description
3. Movement is smooth (no jerky transitions)
4. Animation appears complete (has start, middle, end)
5. If looping, last frame connects to first

RETURN JSON:
{
  "animationPlays": boolean,
  "motion": {
    "detected": "description of observed motion",
    "matchesExpected": boolean,
    "issues": []
  },
  "quality": {
    "smooth": boolean,
    "complete": boolean,
    "loopSeamless": boolean | null
  },
  "timing": {
    "tooFast": boolean,
    "tooSlow": boolean,
    "correct": boolean
  },
  "pass": boolean,
  "score": 0-100
}
```

### Example Workflow

```javascript
// Test walk animation
await studio.playtest.play();
await waitForPlayer();

// Record walking
await studio.recording.start({ fps: 20 });
await studio.playtest.sendInput({ keys: ["W"], duration: 2000 });
await studio.recording.stop();
const walkGif = await studio.recording.createGif();

const walkResult = await vlm.analyzeAnimation({
  gif: walkGif,
  spec: {
    name: "Walk",
    type: "walk",
    duration: 2,
    motion: "Character walks forward with alternating leg movement",
    loop: true
  }
});

// Test jump animation
await studio.recording.start({ fps: 20 });
await studio.playtest.sendInput({ keys: ["Space"], duration: 100 });
await wait(1500);
await studio.recording.stop();
const jumpGif = await studio.recording.createGif();

const jumpResult = await vlm.analyzeAnimation({
  gif: jumpGif,
  spec: {
    name: "Jump",
    type: "jump",
    duration: 1.5,
    motion: "Character jumps up, reaches peak, falls back down",
    loop: false
  }
});

await studio.playtest.stop();
```

---

## Area 5: Lighting & Effects

### What to Check
- Particles spawn and animate
- Beams/trails render correctly
- Lighting creates expected mood
- Shadows appear correctly
- Post-processing effects applied

### Verification Prompt Template

```
You are reviewing a Roblox scene screenshot focusing on visual effects.

EXPECTED EFFECTS:
- Lighting: {description of lighting mood}
- Particles: {list of particle effects}
- Beams: {list of beam effects}
- Atmosphere: {fog, bloom, color correction}

CHECK FOR:
1. Overall lighting matches expected mood
2. Particle effects visible and active
3. Beams/trails rendering correctly
4. Atmospheric effects present
5. No visual artifacts or glitches

RETURN JSON:
{
  "lighting": {
    "moodCorrect": boolean,
    "description": "observed lighting",
    "issues": []
  },
  "particles": {
    "expected": ["list"],
    "visible": ["list"],
    "missing": ["list"]
  },
  "beams": {
    "expected": ["list"],
    "visible": ["list"],
    "missing": ["list"]
  },
  "atmosphere": {
    "present": boolean,
    "correct": boolean,
    "issues": []
  },
  "pass": boolean,
  "score": 0-100
}
```

---

## Area 6: Gameplay Integration

### What to Check
- Player can move in the world
- Interactions work (touch, click, proximity)
- Game mechanics function (collecting, scoring, damage)
- UI updates reflect game state
- No errors or freezes

### Verification Prompt Template

```
You are analyzing a Roblox gameplay recording showing a player testing game mechanics.

TEST SCENARIO:
{description of what player is testing}

EXPECTED BEHAVIOR:
{list of expected outcomes}

ANALYZE FOR:
1. Player successfully performs actions
2. Game responds correctly to player input
3. Visual feedback appears (effects, UI updates)
4. No freezes, errors, or unexpected behavior
5. Game state changes as expected

RETURN JSON:
{
  "actions": [
    {
      "action": "what player did",
      "expectedResult": "what should happen",
      "actualResult": "what happened",
      "success": boolean
    }
  ],
  "feedback": {
    "visualFeedback": boolean,
    "uiUpdates": boolean,
    "audioFeedback": "cannot verify"
  },
  "errors": {
    "freezes": boolean,
    "glitches": boolean,
    "unexpectedBehavior": []
  },
  "pass": boolean,
  "score": 0-100
}
```

### Example Workflow

```javascript
// Full gameplay test: collect coins
await studio.playtest.play();
await waitForPlayer();

// Get initial state
const initialScore = await studio.eval({
  code: "return _G.PlayerScore or 0"
});

// Record gameplay
await studio.recording.start({ fps: 15 });

// Walk toward coin
await studio.playtest.sendInput({ keys: ["W"], duration: 3000 });

await studio.recording.stop();
const gif = await studio.recording.createGif();

// Get final state
const finalScore = await studio.eval({
  code: "return _G.PlayerScore or 0"
});

await studio.playtest.stop();

// Verify with VLM
const result = await vlm.analyzeGameplay({
  gif: gif,
  scenario: "Player walks forward to collect a coin",
  expectations: [
    "Player character moves forward",
    "Coin is visible ahead of player",
    "Player touches coin",
    "Coin disappears on contact",
    "Score UI updates"
  ],
  programmaticCheck: {
    scoreBefore: initialScore,
    scoreAfter: finalScore,
    scoreIncreased: finalScore > initialScore
  }
});
```

---

## Use Cases

**Scenario**: AI builds a shop UI, needs to verify it looks correct.

```javascript
// After building UI
const screenshot = await captureFrame("shop-ui.png");

const result = await geminiFlash.verify({
  image: screenshot,
  prompt: `
    Verify this Roblox UI matches the spec:
    - Blue frame centered on screen
    - Title "SHOP" at top in white text
    - 3 item buttons arranged horizontally
    - Each button has an icon and price label

    Return JSON:
    {
      "pass": boolean,
      "score": 0-100,
      "issues": ["list of problems"],
      "suggestions": ["how to fix"]
    }
  `
});

if (!result.pass) {
  // Iterate based on issues
  for (const issue of result.issues) {
    await fixIssue(issue);
  }
}
```

### 2. Gameplay Verification

**Scenario**: AI needs to verify player can collect coins.

```javascript
// Record gameplay
await playtest.play();
await recording.start({ fps: 10 });
await playtest.sendInput({ keys: ["W"], duration: 2000 });
await recording.stop();
const gif = await recording.createGif();
await playtest.stop();

// Analyze the recording
const frames = await extractFrames(gif);
const result = await geminiFlash.analyzeSequence({
  frames: frames,
  prompt: `
    Analyze this Roblox gameplay sequence:
    1. Is there a player character visible?
    2. Does the player move forward?
    3. Are there collectible coins visible?
    4. Does a coin disappear when player reaches it?
    5. Does a score/counter increase?

    Return JSON:
    {
      "playerVisible": boolean,
      "playerMoved": boolean,
      "coinsVisible": boolean,
      "coinCollected": boolean,
      "scoreIncreased": boolean,
      "pass": boolean,
      "notes": "description of what happened"
    }
  `
});
```

### 3. Visual Diff / Regression

**Scenario**: AI modified something, needs to verify it didn't break existing UI.

```javascript
const before = await loadScreenshot("ui-before.png");
const after = await captureFrame("ui-after.png");

const result = await geminiFlash.compare({
  images: [before, after],
  prompt: `
    Compare these two Roblox UI screenshots.
    The second should look the same except:
    - New "Settings" button added to top-right

    Identify any unintended changes.

    Return JSON:
    {
      "intendedChangesFound": ["list"],
      "unintendedChanges": ["list"],
      "pass": boolean
    }
  `
});
```

### 4. Error Detection

**Scenario**: Check if UI has visual errors or placeholder content.

```javascript
const screenshot = await captureFrame();

const result = await geminiFlash.verify({
  image: screenshot,
  prompt: `
    Check this Roblox UI for errors:
    - Any "TODO" or placeholder text?
    - Any missing images (gray boxes)?
    - Any text overflow/clipping?
    - Any overlapping elements?
    - Any elements outside the frame?

    Return JSON:
    {
      "hasErrors": boolean,
      "errors": [{ "type": "string", "description": "string", "location": "string" }]
    }
  `
});
```

### 5. Accessibility Check

**Scenario**: Verify UI is readable and usable.

```javascript
const screenshot = await captureFrame();

const result = await geminiFlash.verify({
  image: screenshot,
  prompt: `
    Check this Roblox UI for accessibility:
    - Is text large enough to read?
    - Is there sufficient contrast between text and background?
    - Are interactive elements clearly identifiable?
    - Is the layout logical and scannable?

    Return JSON:
    {
      "textReadable": boolean,
      "contrastOk": boolean,
      "buttonsIdentifiable": boolean,
      "layoutClear": boolean,
      "score": 0-100,
      "issues": []
    }
  `
});
```

---

## Implementation

### Phase 1: Basic Visual Verification

```javascript
// daemon/vlm/gemini.js
import { GoogleGenerativeAI } from "@google/generative-ai";

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
const model = genAI.getGenerativeModel({
  model: "gemini-3.0-flash",
  generationConfig: {
    responseMimeType: "application/json"
  }
});

export async function verifyScreenshot(imagePath, spec) {
  const imageData = await fs.readFile(imagePath);
  const base64 = imageData.toString("base64");

  const result = await model.generateContent([
    {
      inlineData: {
        mimeType: "image/png",
        data: base64
      }
    },
    {
      text: `You are a visual QA reviewer for Roblox games.

Verify this screenshot matches the specification:
${spec}

Return JSON:
{
  "pass": boolean,
  "score": number (0-100),
  "issues": [{ "description": string, "severity": "low"|"medium"|"high" }],
  "suggestions": [string]
}`
    }
  ]);

  return JSON.parse(result.response.text());
}
```

### Phase 2: MCP Tool Integration

```javascript
// daemon/mcp/tools/vlm.verify.js
export function registerVlmTools(registerTool) {
  registerTool('vlm.verify', {
    description: 'Verify a screenshot matches a visual specification',
    inputSchema: {
      type: 'object',
      properties: {
        imagePath: { type: 'string', description: 'Path to screenshot' },
        spec: { type: 'string', description: 'What should the image show' }
      },
      required: ['imagePath', 'spec']
    }
  }, async (params) => {
    return await verifyScreenshot(params.imagePath, params.spec);
  });

  registerTool('vlm.compare', {
    description: 'Compare two screenshots for differences',
    inputSchema: {
      type: 'object',
      properties: {
        beforePath: { type: 'string' },
        afterPath: { type: 'string' },
        expectedChanges: { type: 'string' }
      },
      required: ['beforePath', 'afterPath']
    }
  }, async (params) => {
    return await compareScreenshots(params);
  });

  registerTool('vlm.analyzeGameplay', {
    description: 'Analyze a gameplay recording',
    inputSchema: {
      type: 'object',
      properties: {
        gifPath: { type: 'string', description: 'Path to GIF recording' },
        expectations: { type: 'string', description: 'What should happen' }
      },
      required: ['gifPath', 'expectations']
    }
  }, async (params) => {
    return await analyzeGameplayGif(params);
  });
}
```

### Phase 3: Workflow Integration

```yaml
# Example skill using VLM verification
skill: build-and-verify-ui
steps:
  1. studio.eval: create UI code
  2. studio.gui.showOnly: display UI
  3. studio.recording.captureFrame: screenshot
  4. vlm.verify:
      imagePath: screenshot
      spec: |
        Blue shop window centered on screen
        Title "SHOP" in white at top
        3 item cards with images and prices
        Close button in top-right corner
  5. if !pass:
      for each issue:
        fix issue based on suggestion
        recapture and reverify
  6. done when: vlm.verify.pass == true
```

---

## Prompt Templates

### UI Verification Prompt

```
You are a Roblox UI QA reviewer. Analyze this screenshot.

EXPECTED:
{spec}

VERIFY:
1. Layout matches description
2. All elements present
3. Colors/fonts correct
4. No visual errors

RETURN JSON:
{
  "pass": boolean,
  "score": 0-100,
  "elements": {
    "found": ["list of expected elements found"],
    "missing": ["list of expected elements not found"],
    "extra": ["list of unexpected elements"]
  },
  "issues": [
    { "element": "name", "problem": "description", "severity": "low|medium|high" }
  ],
  "suggestions": ["how to fix each issue"]
}
```

### Gameplay Analysis Prompt

```
You are analyzing Roblox gameplay frames. These frames are from a {duration}s recording at {fps}fps.

EXPECTED BEHAVIOR:
{expectations}

ANALYZE:
1. Identify the player character
2. Track movement/actions across frames
3. Identify game objects (coins, enemies, UI)
4. Detect events (collection, damage, score changes)

RETURN JSON:
{
  "playerDetected": boolean,
  "playerActions": ["list of actions observed"],
  "gameEvents": [
    { "frame": number, "event": "description" }
  ],
  "expectations": {
    "{expectation1}": { "met": boolean, "evidence": "description" },
    "{expectation2}": { "met": boolean, "evidence": "description" }
  },
  "pass": boolean,
  "summary": "brief description of what happened"
}
```

### Comparison Prompt

```
You are comparing two Roblox screenshots: BEFORE and AFTER.

EXPECTED CHANGES:
{expectedChanges}

ANALYZE:
1. Identify all differences between images
2. Categorize as "intended" or "unintended"
3. Flag any regressions

RETURN JSON:
{
  "differences": [
    { "location": "description", "change": "what changed", "intended": boolean }
  ],
  "intendedChangesFound": boolean,
  "unintendedChanges": [
    { "location": "description", "problem": "description" }
  ],
  "regressions": [],
  "pass": boolean
}
```

---

## Caching & Optimization

### Reduce API Calls

```javascript
// Cache verification results by content hash
const verificationCache = new Map();

async function verifyWithCache(imagePath, spec) {
  const imageHash = await hashFile(imagePath);
  const specHash = hashString(spec);
  const cacheKey = `${imageHash}-${specHash}`;

  if (verificationCache.has(cacheKey)) {
    return verificationCache.get(cacheKey);
  }

  const result = await verifyScreenshot(imagePath, spec);
  verificationCache.set(cacheKey, result);
  return result;
}
```

### Batch Frame Analysis

```javascript
// Instead of analyzing each frame separately, batch them
async function analyzeGameplayGif(gifPath, expectations) {
  // Extract key frames (not all frames)
  const frames = await extractKeyFrames(gifPath, {
    maxFrames: 10,  // Limit to 10 key frames
    interval: 'even' // Evenly distributed
  });

  // Send all frames in one request
  const result = await model.generateContent([
    ...frames.map((f, i) => ({
      inlineData: { mimeType: "image/png", data: f.base64 },
      label: `Frame ${i + 1} at ${f.timestamp}s`
    })),
    { text: buildGameplayPrompt(expectations) }
  ]);

  return JSON.parse(result.response.text());
}
```

---

## Failure Modes & Mitigations

| Failure | Cause | Mitigation |
|---------|-------|------------|
| False negative | VLM too strict | Lower threshold, use "issues" not just "pass" |
| False positive | VLM misses errors | Add specific checks, multi-pass verification |
| Hallucination | VLM invents elements | Cross-check with structural tools |
| Inconsistency | Same image, different results | Cache results, use temperature=0 |
| Latency spike | API congestion | Timeout + retry, fallback to cached |

### Confidence Scoring

```javascript
async function verifyWithConfidence(imagePath, spec) {
  // Run verification 3 times
  const results = await Promise.all([
    verifyScreenshot(imagePath, spec),
    verifyScreenshot(imagePath, spec),
    verifyScreenshot(imagePath, spec)
  ]);

  // Consensus voting
  const passes = results.filter(r => r.pass).length;
  const avgScore = results.reduce((a, r) => a + r.score, 0) / 3;

  return {
    pass: passes >= 2,  // Majority vote
    confidence: passes / 3,
    score: avgScore,
    issues: mergeIssues(results.map(r => r.issues))
  };
}
```

---

## Integration with AI Skills

### Skill: Visual Build Verification

```yaml
skill: build-verified-ui
inputs:
  name: string
  spec: string (description of expected UI)
steps:
  1. studio.eval: create UI from spec
  2. studio.gui.showOnly: {name}
  3. studio.recording.captureFrame: → screenshot.png
  4. vlm.verify:
      imagePath: screenshot.png
      spec: {spec}
  5. if result.pass:
      return { done: true, evidence: screenshot.png }
  6. else:
      for issue in result.issues:
        diagnose and fix
      goto step 3 (max 3 iterations)
  7. if iterations > 3:
      return { done: false, issues: result.issues, screenshot: screenshot.png }
```

### Skill: Gameplay Test

```yaml
skill: test-gameplay-behavior
inputs:
  actions: [{key, duration}]
  expectations: string
steps:
  1. studio.playtest.play
  2. wait for player spawn
  3. studio.recording.start
  4. for action in actions:
      studio.playtest.sendInput: action
  5. studio.recording.stop
  6. studio.recording.createGif: → gameplay.gif
  7. vlm.analyzeGameplay:
      gifPath: gameplay.gif
      expectations: {expectations}
  8. studio.playtest.stop
  9. return result
```

---

## Roadmap

### Week 1: Basic Integration
- [ ] Set up Gemini 3 Flash API client
- [ ] Implement `vlm.verify` tool
- [ ] Test with simple UI screenshots

### Week 2: Gameplay Analysis
- [ ] Implement `vlm.analyzeGameplay` tool
- [ ] GIF frame extraction
- [ ] Test with recorded gameplay

### Week 3: Workflow Integration
- [ ] Add VLM verification to build skills
- [ ] Implement retry/fix loop
- [ ] Cache optimization

### Week 4: Reliability
- [ ] Confidence scoring
- [ ] Error handling
- [ ] Fallback strategies
- [ ] Metrics/logging

---

## Success Metrics

| Metric | Target |
|--------|--------|
| Verification latency | < 1s |
| UI verification accuracy | > 90% |
| Gameplay analysis accuracy | > 85% |
| False positive rate | < 5% |
| False negative rate | < 10% |
| API cost per verification | < $0.001 |
