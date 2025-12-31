/**
 * Studio History Tools - History Panel
 *
 * Tools for undo/redo operations.
 */

export function registerHistoryTools(registerTool, callPlugin) {
  // studio.history.begin - Begin undo waypoint
  registerTool('studio.history.begin', {
    description: 'Begin a change recording waypoint for undo',
    inputSchema: {
      type: 'object',
      properties: {
        label: { type: 'string', description: 'Label for this change' }
      },
      required: ['label']
    }
  }, async (params) => {
    return await callPlugin('studio.history.begin', params);
  });

  // studio.history.end - End waypoint
  registerTool('studio.history.end', {
    description: 'End change recording and commit to undo stack',
    inputSchema: {
      type: 'object',
      properties: {
        commit: {
          type: 'boolean',
          description: 'Commit changes (false to cancel)'
        }
      }
    }
  }, async (params) => {
    return await callPlugin('studio.history.end', params);
  });

  // studio.history.undo - Undo
  registerTool('studio.history.undo', {
    description: 'Undo the last change',
    inputSchema: {
      type: 'object',
      properties: {}
    }
  }, async (params) => {
    return await callPlugin('studio.history.undo', params);
  });

  // studio.history.redo - Redo
  registerTool('studio.history.redo', {
    description: 'Redo the last undone change',
    inputSchema: {
      type: 'object',
      properties: {}
    }
  }, async (params) => {
    return await callPlugin('studio.history.redo', params);
  });
}
