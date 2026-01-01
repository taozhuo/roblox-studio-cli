import * as fs from 'fs';
import * as path from 'path';

const TAURI_PORT = 4850;
const TAURI_BASE_URL = `http://127.0.0.1:${TAURI_PORT}`;

/**
 * Studio Tools - Plugin-level Studio features
 *
 * Tools for accessing Studio-only APIs:
 * - Active script info
 * - Open script at line
 * - Open documents
 * - Debugger/breakpoints
 * - Viewport capture (via Tauri helper)
 * - Speech recognition/TTS (via Tauri helper)
 */

/**
 * Call the Tauri helper app
 */
async function callTauri(endpoint, options = {}) {
  const url = `${TAURI_BASE_URL}${endpoint}`;
  try {
    const response = await fetch(url, options);
    return response;
  } catch (error) {
    throw new Error(`Tauri helper not running. Start DetAI Desktop app. (${error.message})`);
  }
}

export function registerStudioTools(registerTool, callPlugin) {
  // studio.getPlaceInfo - Get current place ID and name
  registerTool('studio.getPlaceInfo', {
    description: 'Get information about the current place being edited, including PlaceId, name, and whether it is published.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.getPlaceInfo', params);
  });

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

  // ============ Viewport Capture Tools ============

  // studio.captureViewport - Capture Roblox Studio viewport screenshot
  registerTool('studio.captureViewport', {
    description: 'Capture a screenshot of the Roblox Studio viewport using ScreenCaptureKit. Requires DetAI Desktop helper app to be running.',
    inputSchema: {
      type: 'object',
      properties: {
        outputPath: {
          type: 'string',
          description: 'Optional output path for the screenshot. Defaults to detai-repo/viewport.png'
        }
      },
      required: []
    }
  }, async (params) => {
    try {
      const outputPath = params.outputPath || path.join(process.cwd(), 'detai-repo', 'viewport.png');

      // Ensure directory exists
      const dir = path.dirname(outputPath);
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }

      // Call Tauri helper for screenshot
      const response = await callTauri('/capture');

      if (!response.ok) {
        const error = await response.json();
        return {
          success: false,
          error: error.error || 'Capture failed',
          code: error.code || 'UNKNOWN',
          hint: 'Make sure DetAI Desktop is running and has screen recording permission'
        };
      }

      // Get PNG data and save to file
      const arrayBuffer = await response.arrayBuffer();
      const buffer = Buffer.from(arrayBuffer);
      fs.writeFileSync(outputPath, buffer);

      return {
        success: true,
        path: outputPath,
        size: buffer.length,
        message: 'Viewport captured successfully via ScreenCaptureKit'
      };
    } catch (error) {
      return {
        success: false,
        error: error.message,
        hint: 'Make sure DetAI Desktop app is running'
      };
    }
  });

  // ============ Camera Tools ============

  // studio.camera.get - Get camera position and orientation
  registerTool('studio.camera.get', {
    description: 'Get the current camera position, orientation (look vector), field of view, and viewport size. Useful for understanding what the user is looking at.',
    inputSchema: {
      type: 'object',
      properties: {},
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.camera.get', params);
  });

  // studio.camera.raycast - Raycast from camera center
  registerTool('studio.camera.raycast', {
    description: 'Cast a ray from the camera center in the look direction to find what the user is looking at. Returns the hit part, model, position, and distance.',
    inputSchema: {
      type: 'object',
      properties: {
        maxDistance: {
          type: 'number',
          description: 'Maximum raycast distance in studs (default: 1000)'
        }
      },
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.camera.raycast', params);
  });

  // studio.camera.getModelsInView - Get models in front of camera
  registerTool('studio.camera.getModelsInView', {
    description: 'Get all models and parts in front of the camera using a spatial query. Useful for understanding what objects are visible in the viewport.',
    inputSchema: {
      type: 'object',
      properties: {
        distance: {
          type: 'number',
          description: 'How far in front of camera to query (default: 100 studs)'
        },
        radius: {
          type: 'number',
          description: 'Radius of the query sphere (default: 50 studs)'
        }
      },
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.camera.getModelsInView', params);
  });

  // studio.camera.screenRaycast - Raycast at screen position
  registerTool('studio.camera.screenRaycast', {
    description: 'Cast a ray from a specific screen position (pixel coordinates) to find what object is at that location. Defaults to center of screen.',
    inputSchema: {
      type: 'object',
      properties: {
        x: {
          type: 'number',
          description: 'Screen X coordinate (pixels from left). Defaults to center.'
        },
        y: {
          type: 'number',
          description: 'Screen Y coordinate (pixels from top). Defaults to center.'
        },
        maxDistance: {
          type: 'number',
          description: 'Maximum raycast distance (default: 1000)'
        }
      },
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.camera.screenRaycast', params);
  });

  // studio.camera.set - Move camera to position
  registerTool('studio.camera.set', {
    description: 'Move the camera to a specific position and optionally look at a target point. Use this to navigate around the scene.',
    inputSchema: {
      type: 'object',
      properties: {
        position: {
          type: 'object',
          description: 'Camera position {x, y, z}',
          properties: {
            x: { type: 'number' },
            y: { type: 'number' },
            z: { type: 'number' }
          }
        },
        lookAt: {
          type: 'object',
          description: 'Point to look at {x, y, z}',
          properties: {
            x: { type: 'number' },
            y: { type: 'number' },
            z: { type: 'number' }
          }
        }
      },
      required: ['position']
    }
  }, async (params) => {
    return await callPlugin('studio.camera.set', params);
  });

  // studio.camera.focusOn - Focus camera on an instance
  registerTool('studio.camera.focusOn', {
    description: 'Move the camera to look at a specific instance (Model or Part). The camera will position itself at a distance and orient to face the target.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: "Full path to the instance (e.g., 'game/Workspace/MyModel')"
        },
        distance: {
          type: 'number',
          description: 'Distance from target (default: 20 studs)'
        }
      },
      required: ['path']
    }
  }, async (params) => {
    return await callPlugin('studio.camera.focusOn', params);
  });

  // studio.camera.scanViewport - Scan viewport with grid of raycasts
  registerTool('studio.camera.scanViewport', {
    description: 'Scan the viewport with a grid of raycasts to understand what is visible. Returns spatial positions (left, center, right, etc.) with model names and distances. This is auto-included in context, but can be called manually for a fresh scan.',
    inputSchema: {
      type: 'object',
      properties: {
        gridSize: {
          type: 'number',
          description: 'Grid size (default: 3 for 3x3 = 9 rays)'
        },
        maxDistance: {
          type: 'number',
          description: 'Max raycast distance (default: 500)'
        }
      },
      required: []
    }
  }, async (params) => {
    return await callPlugin('studio.camera.scanViewport', params);
  });

}
