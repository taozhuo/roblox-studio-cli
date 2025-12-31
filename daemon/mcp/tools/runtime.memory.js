/**
 * Runtime Memory Tools - Memory Panel
 *
 * Tools for memory monitoring.
 */

export function registerMemoryTools(registerTool, callPlugin) {
  // runtime.memory.sample - Take memory sample
  registerTool('runtime.memory.sample', {
    description: 'Take a memory usage sample',
    inputSchema: {
      type: 'object',
      properties: {
        detailed: {
          type: 'boolean',
          description: 'Include per-category breakdown'
        }
      }
    }
  }, async (params) => {
    return await callPlugin('runtime.memory.sample', params);
  });

  // runtime.memory.getStats - Get memory statistics
  registerTool('runtime.memory.getStats', {
    description: 'Get current memory statistics from Stats service',
    inputSchema: {
      type: 'object',
      properties: {}
    }
  }, async (params) => {
    return await callPlugin('runtime.memory.getStats', params);
  });

  // runtime.memory.instanceCount - Count instances
  registerTool('runtime.memory.instanceCount', {
    description: 'Count instances by class (leak detection)',
    inputSchema: {
      type: 'object',
      properties: {
        classFilter: {
          type: 'array',
          items: { type: 'string' },
          description: 'Classes to count (optional)'
        }
      }
    }
  }, async (params) => {
    return await callPlugin('runtime.memory.instanceCount', params);
  });
}
