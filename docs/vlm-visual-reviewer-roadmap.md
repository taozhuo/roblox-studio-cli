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

## Use Cases

### 1. UI Layout Verification

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
