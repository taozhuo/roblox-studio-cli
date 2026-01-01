/**
 * Playtest Tools - Control Play/Run modes via keyboard simulation
 *
 * Note: Plugin can't access player character during Play mode.
 * Character control uses osascript keyboard simulation (macOS).
 */

import { spawn } from 'child_process';

// Key codes for macOS
const KEY_CODES = {
  F5: 96,
  W: 13,
  A: 0,
  S: 1,
  D: 2,
  SPACE: 49,
};

// Send keystroke to Roblox Studio via osascript
async function sendKeystroke(keyCode, modifiers = [], holdDuration = 0) {
  return new Promise((resolve, reject) => {
    let modString = '';
    if (modifiers.length > 0) {
      modString = ` using {${modifiers.join(', ')}}`;
    }

    let script;
    if (holdDuration > 0) {
      script = `
        tell application "Roblox Studio" to activate
        delay 0.1
        tell application "System Events"
          key down (key code ${keyCode})
          delay ${holdDuration / 1000}
          key up (key code ${keyCode})
        end tell
      `;
    } else {
      script = `
        tell application "Roblox Studio" to activate
        delay 0.1
        tell application "System Events"
          key code ${keyCode}${modString}
        end tell
      `;
    }

    const proc = spawn('osascript', ['-e', script]);
    proc.on('close', (code) => {
      if (code === 0) resolve({ success: true });
      else reject(new Error(`osascript failed`));
    });
  });
}

export function registerPlaytestTools(registerTool, callPlugin) {
  // Get playtest status
  registerTool('studio.playtest.getStatus', {
    description: 'Get current playtest status (running, edit mode, etc.)',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    return await callPlugin('studio.playtest.getStatus', {});
  });

  // Start Play mode (F5)
  registerTool('studio.playtest.play', {
    description: 'Start Play mode (F5) - full simulation with player character',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    await sendKeystroke(KEY_CODES.F5);
    return { started: true, mode: 'play' };
  });

  // Stop playtest (Shift+F5)
  registerTool('studio.playtest.stop', {
    description: 'Stop playtest and return to edit mode',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    await sendKeystroke(KEY_CODES.F5, ['shift down']);
    return { stopped: true };
  });

  // Send keyboard input (WASD, Space)
  registerTool('studio.playtest.sendInput', {
    description: 'Send keyboard input for character control (WASD movement, Space jump). Works during Play mode.',
    inputSchema: {
      type: 'object',
      properties: {
        key: {
          type: 'string',
          enum: ['W', 'A', 'S', 'D', 'SPACE'],
          description: 'W=forward, A=left, S=backward, D=right, SPACE=jump',
        },
        duration: {
          type: 'number',
          description: 'Hold duration in ms (default: 500)',
        },
      },
      required: ['key'],
    },
  }, async ({ key, duration = 500 }) => {
    const keyCode = KEY_CODES[key.toUpperCase()];
    if (!keyCode) throw new Error(`Invalid key: ${key}`);
    await sendKeystroke(keyCode, [], duration);
    return { sent: true, key, duration };
  });

  console.error('[MCP] Playtest tools registered (4 tools)');
}
