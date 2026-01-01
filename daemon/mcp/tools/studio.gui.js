/**
 * GUI Tools - List and toggle ScreenGuis during Play mode
 */

export function registerGuiTools(registerTool, callPlugin) {
  registerTool('studio.gui.list', {
    description: 'List all ScreenGuis in PlayerGui during Play mode',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    return await callPlugin('studio.gui.list', {});
  });

  registerTool('studio.gui.toggle', {
    description: 'Toggle a ScreenGui on/off by name',
    inputSchema: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Name of the ScreenGui' },
        enabled: { type: 'boolean', description: 'Set enabled state (omit to toggle)' },
      },
      required: ['name'],
    },
  }, async (params) => {
    return await callPlugin('studio.gui.toggle', params);
  });

  registerTool('studio.gui.showOnly', {
    description: 'Show only one ScreenGui, hide all others',
    inputSchema: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Name of the ScreenGui to show' },
      },
      required: ['name'],
    },
  }, async (params) => {
    return await callPlugin('studio.gui.showOnly', params);
  });

  registerTool('studio.gui.hideAll', {
    description: 'Hide all ScreenGuis',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    return await callPlugin('studio.gui.hideAll', {});
  });

  console.error('[MCP] GUI tools registered (4 tools)');
}
