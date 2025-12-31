/**
 * Studio Selection Tools - Elements Panel
 *
 * Tools for getting/setting the current selection in Roblox Studio.
 */

export function registerSelectionTools(registerTool, callPlugin) {
  // studio.selection.get - Get currently selected instances
  registerTool('studio.selection.get', {
    description: 'Get currently selected instances in Roblox Studio',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.selection.get', params);
  });

  // studio.selection.set - Set selection to specific instances
  registerTool('studio.selection.set', {
    description: 'Set selection to specific instances by path',
    inputSchema: {
      type: 'object',
      properties: {
        paths: {
          type: 'array',
          items: { type: 'string' },
          description: "Array of instance paths (e.g., 'Workspace/Part1')"
        }
      },
      required: ['paths']
    }
  }, async (params) => {
    return await callPlugin('studio.selection.set', params);
  });

  // studio.pointer.get - Get current mouse position in 3D space
  registerTool('studio.pointer.get', {
    description: 'Get where the mouse is currently pointing in 3D space (raycast from camera). Returns position, surface normal, and the instance being pointed at.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.pointer.get', params);
  });

  // studio.pointer.capture - Capture current mouse position for "put it here" commands
  registerTool('studio.pointer.capture', {
    description: 'Capture the current mouse pointer position. Use this when user says "here" or "at this spot". Returns the 3D position and what instance is being pointed at.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.pointer.capture', params);
  });

  // studio.pointer.getLast - Get last captured pointer position
  registerTool('studio.pointer.getLast', {
    description: 'Get the last captured pointer position. Use this to recall where the user previously pointed.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.pointer.getLast', params);
  });

  // ============ Path Drawing Tools ============

  // studio.path.start - Start recording a path
  registerTool('studio.path.start', {
    description: 'Start recording a path. User clicks in the viewport will add points. Use this when user wants to draw a line/path like "make a river here" or "draw a fence along here".',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.path.start', params);
  });

  // studio.path.stop - Stop recording and get path
  registerTool('studio.path.stop', {
    description: 'Stop recording the path and return all captured points. Returns array of 3D positions.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.path.stop', params);
  });

  // studio.path.get - Get current path points
  registerTool('studio.path.get', {
    description: 'Get the currently recorded path points without stopping recording.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.path.get', params);
  });

  // studio.path.clear - Clear path
  registerTool('studio.path.clear', {
    description: 'Clear all path points and stop recording if active.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.path.clear', params);
  });

  // studio.path.addPoint - Add single point
  registerTool('studio.path.addPoint', {
    description: 'Add a single point to the path. Can provide a position or use current mouse position.',
    inputSchema: {
      type: 'object',
      properties: {
        position: {
          type: 'object',
          properties: {
            x: { type: 'number' },
            y: { type: 'number' },
            z: { type: 'number' }
          },
          description: 'Optional 3D position. If not provided, uses current mouse position.'
        }
      },
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.path.addPoint', params);
  });
}
