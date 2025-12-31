/**
 * Cloud DataStore Tools - Application Panel
 *
 * Tools for DataStore access via Open Cloud API.
 * These are handled by the daemon directly (not plugin).
 */

import openCloud from '../../cloud/opencloud.js';

export function registerDatastoreTools(registerTool, callPlugin) {
  // cloud.datastore.read - Read from DataStore
  registerTool('cloud.datastore.read', {
    description: 'Read from a DataStore via Open Cloud API',
    inputSchema: {
      type: 'object',
      properties: {
        universeId: { type: 'string', description: 'Universe ID' },
        datastoreName: { type: 'string', description: 'DataStore name' },
        key: { type: 'string', description: 'Entry key' },
        scope: { type: 'string', description: 'Scope (default: global)' }
      },
      required: ['universeId', 'datastoreName', 'key']
    }
  }, async (params) => {
    try {
      const result = await openCloud.datastoreRead(
        params.universeId,
        params.datastoreName,
        params.key,
        params.scope || 'global'
      );
      return { success: true, data: result };
    } catch (err) {
      return { success: false, error: err.message };
    }
  });

  // cloud.datastore.write - Write to DataStore
  registerTool('cloud.datastore.write', {
    description: 'Write to a DataStore via Open Cloud API',
    inputSchema: {
      type: 'object',
      properties: {
        universeId: { type: 'string', description: 'Universe ID' },
        datastoreName: { type: 'string', description: 'DataStore name' },
        key: { type: 'string', description: 'Entry key' },
        value: { description: 'Value to write (JSON-serializable)' },
        scope: { type: 'string', description: 'Scope (default: global)' }
      },
      required: ['universeId', 'datastoreName', 'key', 'value']
    }
  }, async (params) => {
    try {
      const result = await openCloud.datastoreWrite(
        params.universeId,
        params.datastoreName,
        params.key,
        params.value,
        params.scope || 'global'
      );
      return { success: true, ...result };
    } catch (err) {
      return { success: false, error: err.message };
    }
  });

  // cloud.datastore.list - List DataStore entries
  registerTool('cloud.datastore.list', {
    description: 'List entries in a DataStore',
    inputSchema: {
      type: 'object',
      properties: {
        universeId: { type: 'string', description: 'Universe ID' },
        datastoreName: { type: 'string', description: 'DataStore name' },
        prefix: { type: 'string', description: 'Key prefix filter' },
        limit: { type: 'number', description: 'Max entries to return' }
      },
      required: ['universeId', 'datastoreName']
    }
  }, async (params) => {
    try {
      const result = await openCloud.datastoreList(
        params.universeId,
        params.datastoreName,
        params.prefix || '',
        params.limit || 100
      );
      return { success: true, entries: result };
    } catch (err) {
      return { success: false, error: err.message };
    }
  });
}
