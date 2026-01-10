/**
 * Roblox API Tools - Query class info and properties
 *
 * Uses ReflectionService in the plugin (always up-to-date)
 */

export function registerApiTools(registerTool, callPlugin) {
  // roblox.api.getClass - Get class info
  registerTool('roblox.api.getClass', {
    description: 'Get Roblox class info (superclass, subclasses). Use roblox.api.getProperties for property list.',
    inputSchema: {
      type: 'object',
      properties: {
        className: {
          type: 'string',
          description: 'Class name (e.g., Frame, Part, ScreenGui, TextButton)'
        }
      },
      required: ['className']
    }
  }, async ({ className }) => {
    return await callPlugin('roblox.api.getClass', { className });
  });

  // roblox.api.getProperties - Get class properties
  registerTool('roblox.api.getProperties', {
    description: 'Get all properties of a Roblox class with their types. Use this to know what properties you can set.',
    inputSchema: {
      type: 'object',
      properties: {
        className: {
          type: 'string',
          description: 'Class name (e.g., Frame, Part, TextLabel)'
        }
      },
      required: ['className']
    }
  }, async ({ className }) => {
    return await callPlugin('roblox.api.getProperties', { className });
  });

  // roblox.api.searchClasses - Search for classes
  registerTool('roblox.api.searchClasses', {
    description: 'Search for Roblox classes by name pattern',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Search query (e.g., "Button", "GUI", "Part")'
        }
      },
      required: ['query']
    }
  }, async ({ query }) => {
    return await callPlugin('roblox.api.searchClasses', { query });
  });
}
