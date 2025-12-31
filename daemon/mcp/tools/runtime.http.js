/**
 * Runtime HTTP Tools - Network Panel
 *
 * Tools for capturing HTTP requests made by scripts.
 */

export function registerHttpTools(registerTool, callPlugin) {
  // runtime.http.captureStart - Start HTTP capture
  registerTool('runtime.http.captureStart', {
    description: 'Start capturing HTTP requests made by scripts',
    inputSchema: {
      type: 'object',
      properties: {
        urlPattern: {
          type: 'string',
          description: 'Filter by URL pattern'
        },
        methods: {
          type: 'array',
          items: { type: 'string' },
          description: 'Filter by HTTP methods'
        }
      }
    }
  }, async (params) => {
    return await callPlugin('runtime.http.captureStart', params);
  });

  // runtime.http.captureStop - Stop HTTP capture
  registerTool('runtime.http.captureStop', {
    description: 'Stop HTTP request capture',
    inputSchema: {
      type: 'object',
      properties: {}
    }
  }, async (params) => {
    return await callPlugin('runtime.http.captureStop', params);
  });

  // runtime.http.getRecent - Get recent requests
  registerTool('runtime.http.getRecent', {
    description: 'Get recent captured HTTP requests',
    inputSchema: {
      type: 'object',
      properties: {
        limit: { type: 'number', description: 'Max requests to return' },
        since: { type: 'number', description: 'Unix timestamp' }
      }
    }
  }, async (params) => {
    return await callPlugin('runtime.http.getRecent', params);
  });
}
