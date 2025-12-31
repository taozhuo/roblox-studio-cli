/**
 * Studio Tools - Plugin-level Studio features
 *
 * Tools for accessing Studio-only APIs:
 * - Active script info
 * - Open script at line
 * - Open documents
 * - Debugger/breakpoints
 */

export function registerStudioTools(registerTool, callPlugin) {
  // studio.getActiveScript - Get currently active script in editor
  registerTool('studio.getActiveScript', {
    description: 'Get the currently active/focused script in the Studio editor. Returns script name, path, and line count.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.getActiveScript', params);
  });

  // studio.getActiveScriptSource - Get source of active script
  registerTool('studio.getActiveScriptSource', {
    description: 'Get the source code of the currently active script. Can optionally specify a line range.',
    inputSchema: {
      type: 'object',
      properties: {
        startLine: {
          type: 'number',
          description: 'Starting line number (1-based, default: 1)'
        },
        endLine: {
          type: 'number',
          description: 'Ending line number (default: all lines)'
        }
      },
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.getActiveScriptSource', params);
  });

  // studio.getStudioInfo - Get Studio theme and settings
  registerTool('studio.getStudioInfo', {
    description: 'Get Studio information like current theme and locale.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.getStudioInfo', params);
  });

  // studio.openScript - Open a script at a specific line
  registerTool('studio.openScript', {
    description: 'Open a script in the Studio editor at a specific line number. Useful for jumping to errors.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: "Full path to the script (e.g., 'game/ServerScriptService/MainScript')"
        },
        line: {
          type: 'number',
          description: 'Line number to jump to (default: 1)'
        }
      },
      required: ['path']
    }
  }, async (params) => {
    return await callPlugin('studio.openScript', params);
  });

  // studio.getOpenDocuments - Get all open script documents
  registerTool('studio.getOpenDocuments', {
    description: 'Get a list of all currently open script documents in Studio.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.getOpenDocuments', params);
  });

  // ============ Debugger Tools ============

  // studio.debug.getBreakpoints - Get all breakpoints
  registerTool('studio.debug.getBreakpoints', {
    description: 'Get all breakpoints currently set in the Studio debugger.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.debug.getBreakpoints', params);
  });

  // studio.debug.addBreakpoint - Add a breakpoint
  registerTool('studio.debug.addBreakpoint', {
    description: 'Add a breakpoint to a script at a specific line. Can also create logpoints with conditions.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: "Full path to the script (e.g., 'game/ServerScriptService/MainScript')"
        },
        line: {
          type: 'number',
          description: 'Line number for the breakpoint'
        },
        condition: {
          type: 'string',
          description: 'Optional condition expression for conditional breakpoint'
        },
        isLogpoint: {
          type: 'boolean',
          description: 'If true, creates a logpoint instead of breakpoint'
        },
        logMessage: {
          type: 'string',
          description: 'Message to log for logpoints'
        }
      },
      required: ['path', 'line']
    }
  }, async (params) => {
    return await callPlugin('studio.debug.addBreakpoint', params);
  });

  // studio.debug.removeBreakpoint - Remove a breakpoint
  registerTool('studio.debug.removeBreakpoint', {
    description: 'Remove a breakpoint from a script at a specific line.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: "Full path to the script"
        },
        line: {
          type: 'number',
          description: 'Line number of the breakpoint to remove'
        }
      },
      required: ['path', 'line']
    }
  }, async (params) => {
    return await callPlugin('studio.debug.removeBreakpoint', params);
  });

  // studio.debug.clearAllBreakpoints - Clear all breakpoints
  registerTool('studio.debug.clearAllBreakpoints', {
    description: 'Remove all breakpoints from the Studio debugger.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.debug.clearAllBreakpoints', params);
  });
}
