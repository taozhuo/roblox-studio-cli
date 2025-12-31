/**
 * Studio Instances Tools - Elements Panel
 *
 * Tools for querying and manipulating the instance tree.
 */

export function registerInstancesTools(registerTool, callPlugin) {
  // studio.instances.tree - Query instance tree
  registerTool('studio.instances.tree', {
    description: 'Query instance tree with optional filters',
    inputSchema: {
      type: 'object',
      properties: {
        root: {
          type: 'string',
          description: "Root path to start from (default: 'game')"
        },
        depth: {
          type: 'number',
          description: 'Max depth to traverse (default: 3)'
        },
        classFilter: {
          type: 'array',
          items: { type: 'string' },
          description: 'Only include these class types'
        },
        namePattern: {
          type: 'string',
          description: 'Lua pattern to match names'
        }
      }
    }
  }, async (params) => {
    return await callPlugin('studio.instances.tree', params);
  });

  // studio.instances.getProps - Get instance properties
  registerTool('studio.instances.getProps', {
    description: 'Get properties of an instance',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Instance path'
        },
        properties: {
          type: 'array',
          items: { type: 'string' },
          description: 'Specific properties to get (optional)'
        }
      },
      required: ['path']
    }
  }, async (params) => {
    return await callPlugin('studio.instances.getProps', params);
  });

  // studio.instances.setProps - Set instance properties
  registerTool('studio.instances.setProps', {
    description: 'Set properties on an instance',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Instance path' },
        properties: {
          type: 'object',
          description: 'Property name to value mapping'
        }
      },
      required: ['path', 'properties']
    }
  }, async (params) => {
    return await callPlugin('studio.instances.setProps', params);
  });

  // studio.instances.create - Create new instance
  registerTool('studio.instances.create', {
    description: 'Create a new instance',
    inputSchema: {
      type: 'object',
      properties: {
        className: { type: 'string', description: 'Class name to create' },
        parent: { type: 'string', description: 'Parent path' },
        name: { type: 'string', description: 'Instance name' },
        properties: { type: 'object', description: 'Initial properties' }
      },
      required: ['className', 'parent']
    }
  }, async (params) => {
    return await callPlugin('studio.instances.create', params);
  });

  // studio.instances.delete - Delete instance
  registerTool('studio.instances.delete', {
    description: 'Delete an instance',
    inputSchema: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Instance path to delete' }
      },
      required: ['path']
    }
  }, async (params) => {
    return await callPlugin('studio.instances.delete', params);
  });
}
