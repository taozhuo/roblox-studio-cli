/**
 * Studio Logs Tools - Console Panel
 *
 * Tools for accessing Studio log output.
 */

export function registerLogsTools(registerTool, callPlugin) {
  // studio.logs.getHistory - Get recent logs (supports cursor-based incremental fetching)
  registerTool('studio.logs.getHistory', {
    description: 'Get log history from Studio. Use cursor for incremental fetching (only new logs since last call).',
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
        },
        cursor: {
          type: 'number',
          description: 'Log ID to start after. Pass the cursor from previous response to get only NEW logs. Omit for latest logs.'
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
