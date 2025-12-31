/**
 * Open Cloud API Client
 *
 * Handles DataStore and Place operations via Roblox Open Cloud APIs.
 * API keys should be configured in .env file (never exposed to plugin).
 */

const BASE_URL = 'https://apis.roblox.com';

// Get API key from environment
function getApiKey() {
  const key = process.env.ROBLOX_OPEN_CLOUD_KEY;
  if (!key) {
    throw new Error('ROBLOX_OPEN_CLOUD_KEY not configured in .env');
  }
  return key;
}

/**
 * Make authenticated request to Open Cloud API
 */
async function request(method, path, body = null) {
  const apiKey = getApiKey();

  const options = {
    method,
    headers: {
      'x-api-key': apiKey,
      'Content-Type': 'application/json',
    },
  };

  if (body) {
    options.body = JSON.stringify(body);
  }

  const response = await fetch(`${BASE_URL}${path}`, options);

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Open Cloud API error ${response.status}: ${errorText}`);
  }

  // Some endpoints return no content
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

// ============ DataStore Operations ============

/**
 * Read a DataStore entry
 */
export async function datastoreRead(universeId, datastoreName, key, scope = 'global') {
  const path = `/datastores/v1/universes/${universeId}/standard-datastores/datastore/entries/entry`;
  const params = new URLSearchParams({
    datastoreName,
    entryKey: key,
    scope,
  });

  return await request('GET', `${path}?${params}`);
}

/**
 * Write a DataStore entry
 */
export async function datastoreWrite(universeId, datastoreName, key, value, scope = 'global') {
  const path = `/datastores/v1/universes/${universeId}/standard-datastores/datastore/entries/entry`;
  const params = new URLSearchParams({
    datastoreName,
    entryKey: key,
    scope,
  });

  // Value needs to be sent as-is (JSON encoded by caller)
  const options = {
    method: 'POST',
    headers: {
      'x-api-key': getApiKey(),
      'Content-Type': 'application/json',
      'roblox-entry-userids': '[]', // Required header
    },
    body: JSON.stringify(value),
  };

  const response = await fetch(`${BASE_URL}${path}?${params}`, options);

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`DataStore write error ${response.status}: ${errorText}`);
  }

  return { success: true };
}

/**
 * List DataStore entries
 */
export async function datastoreList(universeId, datastoreName, prefix = '', limit = 100) {
  const path = `/datastores/v1/universes/${universeId}/standard-datastores/datastore/entries`;
  const params = new URLSearchParams({
    datastoreName,
    prefix,
    limit: String(limit),
  });

  return await request('GET', `${path}?${params}`);
}

// ============ Place Operations ============

/**
 * Get place info
 */
export async function placeGetInfo(universeId, placeId) {
  const path = `/universes/v1/${universeId}/places/${placeId}`;
  return await request('GET', path);
}

/**
 * Publish place
 * Note: This requires uploading the place file, which is complex.
 * For now, return a placeholder.
 */
export async function placePublish(universeId, placeId, versionType = 'Saved') {
  // Publishing requires uploading .rbxl file
  // This would need integration with Rojo or direct place export
  return {
    success: false,
    error: 'Place publishing requires place file upload - use Roblox Studio or Rojo'
  };
}

// ============ Universe Operations ============

/**
 * Get universe info
 */
export async function universeGetInfo(universeId) {
  const path = `/universes/v1/${universeId}`;
  return await request('GET', path);
}

export default {
  datastoreRead,
  datastoreWrite,
  datastoreList,
  placeGetInfo,
  placePublish,
  universeGetInfo,
};
