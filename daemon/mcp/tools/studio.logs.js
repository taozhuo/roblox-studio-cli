/**
 * Studio Logs Tools - Console Panel
 *
 * Tools for accessing Studio log output.
 */

export function registerLogsTools(registerTool, callPlugin) {
  // studio.logs.getHistory - Get recent logs
  registerTool('studio.logs.getHistory', {
    description: 'Get recent log history from Studio',
    inputSchema: {
      type: 'object',
      properties: {
        limit: {
          type: 'number',
          description: 'Max number of logs to return (default: 100)'
        },
        levels: {
          type: 'array',
          items: { type: 'string', enum: ['print', 'warn', 'error', 'info'] },
          description: 'Filter by log levels'
        },
        pattern: {
          type: 'string',
          description: 'Filter by pattern match'
        }
      }
    }
  }, async (params) => {
    return await callPlugin('studio.logs.getHistory', params);
  });

  // studio.logs.clear - Clear log history
  registerTool('studio.logs.clear', {
    description: 'Clear the log history buffer',
    inputSchema: {
      type: 'object',
      properties: {}
    }
  }, async (params) => {
    return await callPlugin('studio.logs.clear', params);
  });
}
