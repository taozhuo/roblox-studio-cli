/**
 * Tool Registry - Registers all DevTools MCP tools
 *
 * Each tool module exports a register(registerTool, callPlugin) function
 * that registers its tools with the MCP server.
 */

import { registerTool } from '../server.js';

// Plugin communication helper - injected by daemon
let pluginCaller = null;

/**
 * Set the function used to call the plugin
 * @param {Function} caller - async function(tool, params) => result
 */
export function setPluginCaller(caller) {
  pluginCaller = caller;
}

/**
 * Call a tool on the plugin side
 * @param {string} tool - Tool name
 * @param {object} params - Tool parameters
 * @returns {Promise<any>} Tool result
 */
export async function callPlugin(tool, params) {
  if (!pluginCaller) {
    throw new Error('Plugin caller not set - daemon not initialized');
  }
  return await pluginCaller(tool, params);
}

/**
 * Register all tool modules
 */
export async function registerAllTools() {
  // Phase 2: Elements Panel
  const { registerSelectionTools } = await import('./studio.selection.js');
  const { registerInstancesTools } = await import('./studio.instances.js');
  registerSelectionTools(registerTool, callPlugin);
  registerInstancesTools(registerTool, callPlugin);

  // Phase 3: Console Panel
  const { registerLogsTools } = await import('./studio.logs.js');
  const { registerEvalTools } = await import('./studio.eval.js');
  registerLogsTools(registerTool, callPlugin);
  registerEvalTools(registerTool, callPlugin);

  // Phase 4: Sources Panel
  const { registerScriptsTools } = await import('./studio.scripts.js');
  registerScriptsTools(registerTool, callPlugin);

  // Phase 5: History Panel
  const { registerHistoryTools } = await import('./studio.history.js');
  registerHistoryTools(registerTool, callPlugin);

  // Studio Tools (Plugin-level features)
  const { registerStudioTools } = await import('./studio.studio.js');
  registerStudioTools(registerTool, callPlugin);

  // Playtest Tools (Play/Run control, character movement)
  const { registerPlaytestTools } = await import('./studio.playtest.js');
  registerPlaytestTools(registerTool, callPlugin);

  // Recording Tools (viewport capture, GIF/video creation)
  const { registerRecordingTools } = await import('./studio.recording.js');
  registerRecordingTools(registerTool, callPlugin);

  // GUI Tools (list/toggle ScreenGuis during Play mode)
  const { registerGuiTools } = await import('./studio.gui.js');
  registerGuiTools(registerTool, callPlugin);

  // Phase 6: Runtime Tools
  const { registerHttpTools } = await import('./runtime.http.js');
  const { registerPerfTools } = await import('./runtime.perf.js');
  const { registerMemoryTools } = await import('./runtime.memory.js');
  registerHttpTools(registerTool, callPlugin);
  registerPerfTools(registerTool, callPlugin);
  registerMemoryTools(registerTool, callPlugin);

  // Phase 7: Cloud Integration
  const { registerDatastoreTools } = await import('./cloud.datastore.js');
  const { registerPlaceTools } = await import('./cloud.place.js');
  registerDatastoreTools(registerTool, callPlugin);
  registerPlaceTools(registerTool, callPlugin);

  console.error('[MCP] All tools registered');
}
