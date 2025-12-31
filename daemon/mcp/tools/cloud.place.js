/**
 * Cloud Place Tools - Application Panel
 *
 * Tools for place publishing via Open Cloud API.
 * These are handled by the daemon directly (not plugin).
 */

import openCloud from '../../cloud/opencloud.js';

export function registerPlaceTools(registerTool, callPlugin) {
  // cloud.place.publish - Publish place
  registerTool('cloud.place.publish', {
    description: 'Publish place to Roblox via Open Cloud API',
    inputSchema: {
      type: 'object',
      properties: {
        universeId: { type: 'string', description: 'Universe ID' },
        placeId: { type: 'string', description: 'Place ID' },
        versionType: {
          type: 'string',
          enum: ['Saved', 'Published'],
          description: 'Version type (default: Saved)'
        }
      },
      required: ['universeId', 'placeId']
    }
  }, async (params) => {
    try {
      const result = await openCloud.placePublish(
        params.universeId,
        params.placeId,
        params.versionType || 'Saved'
      );
      return result;
    } catch (err) {
      return { success: false, error: err.message };
    }
  });

  // cloud.place.getInfo - Get place info
  registerTool('cloud.place.getInfo', {
    description: 'Get place information via Open Cloud API',
    inputSchema: {
      type: 'object',
      properties: {
        universeId: { type: 'string', description: 'Universe ID' },
        placeId: { type: 'string', description: 'Place ID' }
      },
      required: ['universeId', 'placeId']
    }
  }, async (params) => {
    try {
      const result = await openCloud.placeGetInfo(
        params.universeId,
        params.placeId
      );
      return { success: true, place: result };
    } catch (err) {
      return { success: false, error: err.message };
    }
  });

  // cloud.universe.getInfo - Get universe info
  registerTool('cloud.universe.getInfo', {
    description: 'Get universe information via Open Cloud API',
    inputSchema: {
      type: 'object',
      properties: {
        universeId: { type: 'string', description: 'Universe ID' }
      },
      required: ['universeId']
    }
  }, async (params) => {
    try {
      const result = await openCloud.universeGetInfo(params.universeId);
      return { success: true, universe: result };
    } catch (err) {
      return { success: false, error: err.message };
    }
  });
}
