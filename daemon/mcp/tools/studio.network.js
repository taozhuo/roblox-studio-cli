/**
 * Replication/Network Debugging Tools
 *
 * Monitor network ownership, RemoteEvent traffic, and replication.
 */

export function registerNetworkTools(registerTool, callPlugin) {
  // Get network ownership of parts
  registerTool('studio.network.getOwnership', {
    description: 'Get network ownership of BaseParts. Returns which player (or server) owns physics simulation.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Instance path to check (or parent to list all). Defaults to workspace.'
        },
        recursive: {
          type: 'boolean',
          description: 'Check descendants recursively',
          default: false
        }
      }
    },
  }, async (params) => {
    return await callPlugin('studio.network.getOwnership', params);
  });

  // Set network ownership
  registerTool('studio.network.setOwnership', {
    description: 'Set network ownership of a BasePart. Pass null for playerName to set to server.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Instance path to the BasePart'
        },
        playerName: {
          type: 'string',
          description: 'Player name to give ownership, or null for server'
        },
        auto: {
          type: 'boolean',
          description: 'Set to auto ownership mode',
          default: false
        }
      },
      required: ['path']
    },
  }, async (params) => {
    return await callPlugin('studio.network.setOwnership', params);
  });

  // Start capturing RemoteEvent traffic
  registerTool('studio.network.startRemoteCapture', {
    description: 'Start capturing RemoteEvent/RemoteFunction calls. Must be in Play mode.',
    inputSchema: {
      type: 'object',
      properties: {
        filter: {
          type: 'string',
          description: 'Filter remotes by name pattern (optional)'
        },
        maxEvents: {
          type: 'number',
          description: 'Max events to capture before auto-stop',
          default: 1000
        }
      }
    },
  }, async (params) => {
    return await callPlugin('studio.network.startRemoteCapture', params);
  });

  // Stop capturing and get results
  registerTool('studio.network.stopRemoteCapture', {
    description: 'Stop capturing RemoteEvent traffic and return captured events.',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    return await callPlugin('studio.network.stopRemoteCapture', {});
  });

  // Get capture status and recent events
  registerTool('studio.network.getRemoteHistory', {
    description: 'Get recent RemoteEvent/RemoteFunction calls from capture.',
    inputSchema: {
      type: 'object',
      properties: {
        limit: {
          type: 'number',
          description: 'Max events to return',
          default: 100
        }
      }
    },
  }, async (params) => {
    return await callPlugin('studio.network.getRemoteHistory', params);
  });

  // Measure round-trip latency
  registerTool('studio.network.measureLatency', {
    description: 'Measure server-client round-trip latency. Must be in Play mode with a client.',
    inputSchema: {
      type: 'object',
      properties: {
        samples: {
          type: 'number',
          description: 'Number of samples to take',
          default: 5
        }
      }
    },
  }, async (params) => {
    return await callPlugin('studio.network.measureLatency', params);
  });

  // List all RemoteEvents/RemoteFunctions in game
  registerTool('studio.network.listRemotes', {
    description: 'List all RemoteEvents and RemoteFunctions in the game.',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    return await callPlugin('studio.network.listRemotes', {});
  });

  console.error('[MCP] Network tools registered (7 tools)');
}
