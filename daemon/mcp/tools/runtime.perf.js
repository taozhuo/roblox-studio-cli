/**
 * Runtime Performance Tools - Performance Panel
 *
 * Tools for performance monitoring and spans.
 */

export function registerPerfTools(registerTool, callPlugin) {
  // runtime.perf.span - Record performance span
  registerTool('runtime.perf.span', {
    description: 'Record a performance span (start/end)',
    inputSchema: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Span name' },
        action: {
          type: 'string',
          enum: ['start', 'end'],
          description: 'Start or end the span'
        },
        metadata: { type: 'object', description: 'Additional metadata' }
      },
      required: ['name', 'action']
    }
  }, async (params) => {
    return await callPlugin('runtime.perf.span', params);
  });

  // runtime.perf.dumpWindow - Dump performance data
  registerTool('runtime.perf.dumpWindow', {
    description: 'Dump performance data for a time window',
    inputSchema: {
      type: 'object',
      properties: {
        startTime: { type: 'number', description: 'Start timestamp' },
        endTime: { type: 'number', description: 'End timestamp' },
        includeFrameTimes: {
          type: 'boolean',
          description: 'Include frame time data'
        }
      }
    }
  }, async (params) => {
    return await callPlugin('runtime.perf.dumpWindow', params);
  });

  // runtime.perf.getStats - Get current performance stats
  registerTool('runtime.perf.getStats', {
    description: 'Get current performance statistics',
    inputSchema: {
      type: 'object',
      properties: {}
    }
  }, async (params) => {
    return await callPlugin('runtime.perf.getStats', params);
  });
}
