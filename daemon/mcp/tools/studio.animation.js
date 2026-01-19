/**
 * Animation State Inspection Tools
 *
 * Inspect and control animations on Humanoids/Animators during playtest.
 */

export function registerAnimationTools(registerTool, callPlugin) {
  // Get playing animations
  registerTool('studio.animation.getPlaying', {
    description: 'Get currently playing animations on a Humanoid or Animator.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Path to Humanoid, Animator, or Model containing one. Defaults to local character.'
        }
      }
    },
  }, async (params) => {
    return await callPlugin('studio.animation.getPlaying', params);
  });

  // Get all animation tracks
  registerTool('studio.animation.getTracks', {
    description: 'Get all loaded AnimationTracks on an Animator.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Path to Humanoid or Animator. Defaults to local character.'
        }
      }
    },
  }, async (params) => {
    return await callPlugin('studio.animation.getTracks', params);
  });

  // Get detailed track info
  registerTool('studio.animation.getTrackInfo', {
    description: 'Get detailed info about a specific animation track (weight, speed, position, length).',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Path to Humanoid or Animator'
        },
        animationId: {
          type: 'string',
          description: 'Animation asset ID or name to find'
        }
      },
      required: ['animationId']
    },
  }, async (params) => {
    return await callPlugin('studio.animation.getTrackInfo', params);
  });

  // Play an animation
  registerTool('studio.animation.play', {
    description: 'Play an animation on a Humanoid/Animator.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Path to Humanoid or Animator'
        },
        animationId: {
          type: 'string',
          description: 'Animation asset ID (rbxassetid://...)'
        },
        fadeTime: {
          type: 'number',
          description: 'Fade in time in seconds',
          default: 0.1
        },
        weight: {
          type: 'number',
          description: 'Animation weight (0-1)',
          default: 1
        },
        speed: {
          type: 'number',
          description: 'Playback speed',
          default: 1
        }
      },
      required: ['animationId']
    },
  }, async (params) => {
    return await callPlugin('studio.animation.play', params);
  });

  // Stop an animation
  registerTool('studio.animation.stop', {
    description: 'Stop a playing animation.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Path to Humanoid or Animator'
        },
        animationId: {
          type: 'string',
          description: 'Animation asset ID or name to stop. If omitted, stops all.'
        },
        fadeTime: {
          type: 'number',
          description: 'Fade out time in seconds',
          default: 0.1
        }
      }
    },
  }, async (params) => {
    return await callPlugin('studio.animation.stop', params);
  });

  // Set track time position
  registerTool('studio.animation.setTrackTime', {
    description: 'Scrub an animation to a specific time position.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Path to Humanoid or Animator'
        },
        animationId: {
          type: 'string',
          description: 'Animation asset ID or name'
        },
        time: {
          type: 'number',
          description: 'Time position in seconds'
        }
      },
      required: ['animationId', 'time']
    },
  }, async (params) => {
    return await callPlugin('studio.animation.setTrackTime', params);
  });

  // Adjust track speed
  registerTool('studio.animation.setTrackSpeed', {
    description: 'Set playback speed of an animation track. Use 0 to pause.',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Path to Humanoid or Animator'
        },
        animationId: {
          type: 'string',
          description: 'Animation asset ID or name'
        },
        speed: {
          type: 'number',
          description: 'Playback speed (0 = paused, 1 = normal, -1 = reverse)'
        }
      },
      required: ['animationId', 'speed']
    },
  }, async (params) => {
    return await callPlugin('studio.animation.setTrackSpeed', params);
  });

  // List available animations in game
  registerTool('studio.animation.listAnimations', {
    description: 'List all Animation instances in the game (in ReplicatedStorage, StarterPlayer, etc.).',
    inputSchema: { type: 'object', properties: {} },
  }, async () => {
    return await callPlugin('studio.animation.listAnimations', {});
  });

  console.error('[MCP] Animation tools registered (8 tools)');
}
