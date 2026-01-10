/**
 * Playtest Tools - Control Play/Run modes via keyboard simulation
 *
 * Note: Plugin can't access player character during Play mode.
 * Character control uses osascript keyboard simulation (macOS).
 */

import { spawn } from 'child_process';

// Key codes for macOS
const KEY_CODES = {
  F5: 96,   // Play mode (client+server)
  F8: 100,  // Run mode (server only)
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

  // Start Run mode (F8) - server only, no client
  registerTool('studio.playtest.run', {
    description: 'Start Run mode (F8) - server-only simulation. Use this to test server scripts. Do NOT use Play mode.',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    await sendKeystroke(KEY_CODES.F8);
    return { started: true, mode: 'run' };
  });

  // Stop playtest (Shift+F5)
  registerTool('studio.playtest.stop', {
    description: 'Stop Run mode and return to edit mode',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    await sendKeystroke(KEY_CODES.F5, ['shift down']);
    return { stopped: true };
  });

  console.error('[MCP] Playtest tools registered (3 tools)');
}
