/**
 * Visual Verification Tool - Generic verifier using Gemini Flash
 *
 * Simple pattern: capture screenshot, verify against criteria, return pass/fail
 */

// Verification state for status bar
let lastVerification = null;
let pluginCaller = null;

// Update plugin status bar
async function updatePluginStatus(status, message) {
  if (pluginCaller) {
    try {
      await pluginCaller('vlm.verify.updateStatus', { status, message });
    } catch (e) { /* ignore */ }
  }
}

// Predefined verification criteria (like phase definitions)
const CRITERIA = {
  'gui-basic': {
    name: 'Basic GUI',
    requirements: [
      'ScreenGui is visible',
      'Frame or container is visible',
      'Text is readable (not cut off, proper contrast)',
      'Buttons look clickable',
    ],
    minimumScore: 70,
  },
  'gui-shop': {
    name: 'Shop UI',
    requirements: [
      'Shop title/header visible',
      'Item list or grid visible',
      'Price labels visible',
      'Buy/purchase button visible',
      'Close button visible',
    ],
    minimumScore: 70,
  },
  'gui-inventory': {
    name: 'Inventory UI',
    requirements: [
      'Inventory grid or list visible',
      'Item slots visible',
      'Item icons or placeholders visible',
      'Equipment section if applicable',
    ],
    minimumScore: 70,
  },
  'scene-basic': {
    name: 'Basic 3D Scene',
    requirements: [
      'Baseplate or ground visible',
      'Parts/models are rendering',
      'Camera is positioned correctly',
      'No obvious visual glitches',
    ],
    minimumScore: 70,
  },
  'scene-lighting': {
    name: 'Scene Lighting',
    requirements: [
      'Lighting is present (not flat)',
      'Shadows are rendering',
      'Light sources visible if expected',
      'Atmosphere/mood appropriate',
    ],
    minimumScore: 70,
  },
  'animation': {
    name: 'Animation Check',
    requirements: [
      'Character/model is in expected pose',
      'Animation appears mid-motion (not T-pose)',
      'Limbs positioned correctly',
    ],
    minimumScore: 60,
  },
};

export function registerVlmTools(registerTool, callPlugin) {
  pluginCaller = callPlugin;

  // Main verify tool - generic, takes criteria key or custom requirements
  registerTool('vlm.verify', {
    description: 'Verify current viewport using Gemini Flash vision. Pass a criteria key (gui-basic, scene-basic, etc.) or custom requirements.',
    inputSchema: {
      type: 'object',
      properties: {
        criteria: {
          type: 'string',
          description: 'Criteria key: gui-basic, gui-shop, gui-inventory, scene-basic, scene-lighting, animation',
        },
        requirements: {
          type: 'array',
          items: { type: 'string' },
          description: 'Custom requirements list (overrides criteria key)',
        },
        minimumScore: {
          type: 'number',
          description: 'Minimum passing score 0-100 (default: 70)',
        },
      },
    },
  }, async ({ criteria, requirements, minimumScore = 70 }) => {
    await updatePluginStatus('running', 'Checking...');

    try {
      // Get requirements from criteria key or use custom
      let reqs = requirements;
      let name = 'Custom Verification';

      if (!reqs && criteria && CRITERIA[criteria]) {
        reqs = CRITERIA[criteria].requirements;
        name = CRITERIA[criteria].name;
        minimumScore = CRITERIA[criteria].minimumScore;
      }

      if (!reqs || reqs.length === 0) {
        await updatePluginStatus('done');
        return { error: 'No requirements specified. Use criteria key or provide requirements array.' };
      }

      // Capture viewport
      const capture = await callPlugin('studio.captureViewport', {});
      if (!capture?.base64) {
        await updatePluginStatus('done');
        return { error: 'Failed to capture viewport' };
      }

      // Call Gemini
      const apiKey = process.env.GOOGLE_AI_API_KEY || process.env.GEMINI_API_KEY;
      if (!apiKey) {
        await updatePluginStatus('done');
        return { error: 'GEMINI_API_KEY not set' };
      }

      const prompt = `You are a QA expert verifying a Roblox Studio screenshot.

**Verification: ${name}**

**Requirements:**
${reqs.map((r, i) => `${i + 1}. ${r}`).join('\n')}

**Task:** Analyze screenshot, check each requirement, give score 0-100.

**Response (JSON only):**
{
  "passed": true/false,
  "score": <0-100>,
  "feedback": "<2 sentence summary>",
  "issues": ["<issue 1>", "<issue 2>"]
}

Minimum passing score: ${minimumScore}`;

      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${apiKey}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contents: [{
              parts: [
                { text: prompt },
                { inline_data: { mime_type: 'image/png', data: capture.base64 } },
              ],
            }],
            generationConfig: { temperature: 0.2, maxOutputTokens: 1024 },
          }),
        }
      );

      if (!response.ok) {
        await updatePluginStatus('done');
        return { error: `Gemini API error: ${response.status}` };
      }

      const data = await response.json();
      let text = data.candidates?.[0]?.content?.parts?.[0]?.text || '';

      // Parse JSON (strip markdown if present)
      text = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

      let result;
      try {
        result = JSON.parse(text);
      } catch {
        await updatePluginStatus('done');
        return { error: 'Failed to parse Gemini response', raw: text };
      }

      lastVerification = {
        passed: result.passed && result.score >= minimumScore,
        score: result.score,
        timestamp: Date.now(),
      };

      await updatePluginStatus('done');

      return {
        passed: result.passed && result.score >= minimumScore,
        score: result.score,
        feedback: result.feedback,
        issues: result.issues || [],
        criteria: criteria || 'custom',
      };

    } catch (err) {
      await updatePluginStatus('done');
      return { error: err.message };
    }
  });

  // Simple snapshot for before/after comparison
  registerTool('vlm.snapshot', {
    description: 'Take a snapshot of current viewport. Returns base64 for later comparison.',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    const capture = await callPlugin('studio.captureViewport', {});
    if (!capture?.base64) {
      return { error: 'Failed to capture viewport' };
    }
    return { base64: capture.base64, timestamp: Date.now() };
  });

  // Compare two snapshots
  registerTool('vlm.compare', {
    description: 'Compare before/after snapshots to verify a change.',
    inputSchema: {
      type: 'object',
      properties: {
        before: { type: 'string', description: 'Base64 of before image' },
        expectedChange: { type: 'string', description: 'What should be different' },
      },
      required: ['before', 'expectedChange'],
    },
  }, async ({ before, expectedChange }) => {
    await updatePluginStatus('running', 'Comparing...');

    try {
      // Capture current as "after"
      const capture = await callPlugin('studio.captureViewport', {});
      if (!capture?.base64) {
        await updatePluginStatus('done');
        return { error: 'Failed to capture viewport' };
      }

      const apiKey = process.env.GOOGLE_AI_API_KEY || process.env.GEMINI_API_KEY;
      if (!apiKey) {
        await updatePluginStatus('done');
        return { error: 'GEMINI_API_KEY not set' };
      }

      const prompt = `Compare BEFORE and AFTER screenshots.

Expected change: ${expectedChange}

Is the change visible? Response (JSON only):
{
  "passed": true/false,
  "feedback": "<what changed or didn't change>"
}`;

      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${apiKey}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contents: [{
              parts: [
                { text: 'BEFORE:' },
                { inline_data: { mime_type: 'image/png', data: before } },
                { text: 'AFTER:' },
                { inline_data: { mime_type: 'image/png', data: capture.base64 } },
                { text: prompt },
              ],
            }],
            generationConfig: { temperature: 0.2, maxOutputTokens: 512 },
          }),
        }
      );

      if (!response.ok) {
        await updatePluginStatus('done');
        return { error: `Gemini API error: ${response.status}` };
      }

      const data = await response.json();
      let text = data.candidates?.[0]?.content?.parts?.[0]?.text || '';
      text = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

      let result;
      try {
        result = JSON.parse(text);
      } catch {
        await updatePluginStatus('done');
        return { error: 'Failed to parse response', raw: text };
      }

      await updatePluginStatus('done');
      return { passed: result.passed, feedback: result.feedback };

    } catch (err) {
      await updatePluginStatus('done');
      return { error: err.message };
    }
  });

  console.error('[MCP] VLM verification tools registered (3 tools)');
}

export function getLastVerification() {
  return lastVerification;
}
