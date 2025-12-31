/**
 * Studio Scripts Tools - Sources Panel
 *
 * Tools for reading and writing scripts.
 */

export function registerScriptsTools(registerTool, callPlugin) {
  // studio.scripts.list - List all scripts
  registerTool('studio.scripts.list', {
    description: 'List all scripts in the game',
    inputSchema: {
      type: 'object',
      properties: {
        containers: {
          type: 'array',
          items: { type: 'string' },
          description: 'Containers to search (default: all)'
        }
      }
    }
  }, async (params) => {
    return await callPlugin('studio.scripts.list', params);
  });

  // studio.scripts.read - Read script content
  registerTool('studio.scripts.read', {
    description: 'Read content of a script',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Script instance path' }
      },
      required: ['path']
    }
  }, async (params) => {
    return await callPlugin('studio.scripts.read', params);
  });

  // studio.scripts.write - Write script content
  registerTool('studio.scripts.write', {
    description: 'Write content to a script',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Script instance path' },
        content: { type: 'string', description: 'New script content' }
      },
      required: ['path', 'content']
    }
  }, async (params) => {
    return await callPlugin('studio.scripts.write', params);
  });

  // studio.scripts.create - Create new script
  registerTool('studio.scripts.create', {
    description: 'Create a new script',
    inputSchema: {
      type: 'object',
      properties: {
        parent: { type: 'string', description: 'Parent path' },
        name: { type: 'string', description: 'Script name' },
        className: {
          type: 'string',
          enum: ['Script', 'LocalScript', 'ModuleScript'],
          description: 'Script type (default: ModuleScript)'
        },
        content: { type: 'string', description: 'Initial content' }
      },
      required: ['parent', 'name']
    }
  }, async (params) => {
    return await callPlugin('studio.scripts.create', params);
  });
}
