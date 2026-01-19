/**
 * Input Recording/Replay Tools
 *
 * Records player inputs (keyboard, mouse) during playtest
 * and replays them for automated testing.
 */

export function registerInputTools(registerTool, callPlugin) {
  // Start recording inputs
  registerTool('studio.input.startRecording', {
    description: 'Start recording player inputs (WASD, mouse, jumps). Must be in Play mode.',
    inputSchema: {
      type: 'object',
      properties: {
        includeMouseMovement: {
          type: 'boolean',
          description: 'Include mouse movement (can be verbose)',
          default: false
        }
      }
    },
  }, async (params) => {
    return await callPlugin('studio.input.startRecording', params);
  });

  // Stop recording and get inputs
  registerTool('studio.input.stopRecording', {
    description: 'Stop recording inputs and return the recorded sequence.',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    return await callPlugin('studio.input.stopRecording', {});
  });

  // Replay recorded inputs
  registerTool('studio.input.replay', {
    description: 'Replay a recorded input sequence. Must be in Play mode.',
    inputSchema: {
      type: 'object',
      properties: {
        sequence: {
          type: 'array',
          description: 'Input sequence from stopRecording',
          items: { type: 'object' }
        },
        speed: {
          type: 'number',
          description: 'Playback speed multiplier (1.0 = normal)',
          default: 1.0
        }
      },
      required: ['sequence']
    },
  }, async (params) => {
    return await callPlugin('studio.input.replay', params);
  });

  // Export as TestService code
  registerTool('studio.input.exportTest', {
    description: 'Export recorded inputs as Luau TestService code.',
    inputSchema: {
      type: 'object',
      properties: {
        sequence: {
          type: 'array',
          description: 'Input sequence from stopRecording',
          items: { type: 'object' }
        },
        testName: {
          type: 'string',
          description: 'Name for the test function',
          default: 'ReplayInputTest'
        }
      },
      required: ['sequence']
    },
  }, async (params) => {
    return await callPlugin('studio.input.exportTest', params);
  });

  // Get current recording status
  registerTool('studio.input.getStatus', {
    description: 'Get input recording status.',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    return await callPlugin('studio.input.getStatus', {});
  });

  console.error('[MCP] Input tools registered (5 tools)');
}
