/**
 * Playtest Tools - Control Run mode via plugin API (StudioTestService)
 *
 * Uses StudioTestService.ExecuteRunModeAsync() and EndTest() for clean
 * programmatic control instead of keyboard simulation.
 */

export function registerPlaytestTools(registerTool, callPlugin) {
  // Get playtest status
  registerTool('studio.playtest.getStatus', {
    description: 'Get current playtest status (running, edit mode, etc.)',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    return await callPlugin('studio.playtest.getStatus', {});
  });

  // Start Run mode - server only, no client
  registerTool('studio.playtest.run', {
    description: 'Start Run mode - server-only simulation. Use this to test server scripts. Uses StudioTestService API.',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    return await callPlugin('studio.playtest.run', {});
  });

  // Stop playtest
  registerTool('studio.playtest.stop', {
    description: 'Stop Run mode and return to edit mode. Uses StudioTestService.EndTest() API.',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    return await callPlugin('studio.playtest.stop', {});
  });

  console.error('[MCP] Playtest tools registered (3 tools)');
}
