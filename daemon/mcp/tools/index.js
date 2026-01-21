/**
 * Tool Registry - Registers all DevTools MCP tools
 *
 * Each tool module exports a register(registerTool, callPlugin) function
 * that registers its tools with the MCP server.
 *
 * CONSOLIDATED: Reduced from 110 to ~60 essential tools.
 * Many tools were redundant - they can be done via studio.eval more flexibly.
 *
 * Removed (use studio.eval instead):
 * - studio.query.* (14 tools) - jq/grep/sed queries
 * - studio.animation.* (8 tools) - animation state inspection
 * - studio.network.* (7 tools) - replication debugging
 * - studio.input.* (5 tools) - input recording
 * - studio.gui.* (4 tools) - GUI toggling
 * - runtime.* (9 tools) - perf/memory/http inspection
 * - studio.instances.* (3 tools) - tree/props queries
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
  // ========== ESSENTIAL TOOLS (cannot be replaced by eval) ==========

  // Selection Tools - get/set selected instances in Studio
  const { registerSelectionTools } = await import('./studio.selection.js');
  registerSelectionTools(registerTool, callPlugin);

  // Eval Tool - CORE: execute Luau code in Studio
  const { registerEvalTools } = await import('./studio.eval.js');
  registerEvalTools(registerTool, callPlugin);

  // Logs Tools - get output/error history from Studio
  const { registerLogsTools } = await import('./studio.logs.js');
  registerLogsTools(registerTool, callPlugin);

  // Scripts Tools - read/write script source code
  const { registerScriptsTools } = await import('./studio.scripts.js');
  registerScriptsTools(registerTool, callPlugin);

  // History Tools - undo/redo support
  const { registerHistoryTools } = await import('./studio.history.js');
  registerHistoryTools(registerTool, callPlugin);

  // Studio Tools - plugin-level features (getStudioInfo, openScript, etc.)
  const { registerStudioTools } = await import('./studio.studio.js');
  registerStudioTools(registerTool, callPlugin);

  // Playtest Tools - F5/F8 control (cannot be done via eval)
  const { registerPlaytestTools } = await import('./studio.playtest.js');
  registerPlaytestTools(registerTool, callPlugin);

  // Recording Tools - viewport capture, GIF/video creation
  const { registerRecordingTools } = await import('./studio.recording.js');
  registerRecordingTools(registerTool, callPlugin);

  // Cloud Integration - Open Cloud API (external to Studio)
  const { registerDatastoreTools } = await import('./cloud.datastore.js');
  const { registerPlaceTools } = await import('./cloud.place.js');
  registerDatastoreTools(registerTool, callPlugin);
  registerPlaceTools(registerTool, callPlugin);

  // VLM Verification Tools - Gemini Flash vision verification
  const { registerVlmTools } = await import('./vlm.verify.js');
  registerVlmTools(registerTool, callPlugin);

  // Roblox API Tools - class/property docs via ReflectionService
  const { registerApiTools } = await import('./roblox.api.js');
  registerApiTools(registerTool, callPlugin);

  // Roblox Docs Tools - search creator documentation (external)
  const { registerDocsTools } = await import('./roblox.docs.js');
  registerDocsTools(registerTool);

  // Map Planner - Gemini 3 Flash vision for map building plans
  const mapPlannerTools = await import('./map-planner.js');
  mapPlannerTools.setPluginCaller(callPlugin);
  for (const tool of mapPlannerTools.tools) {
    registerTool(tool.name, tool.description, tool.inputSchema, tool.handler);
  }

  console.error('[MCP] Essential tools registered (~60 tools, down from 110)');

  // ========== REMOVED (use studio.eval instead) ==========
  // studio.instances.* - Use eval: game:FindFirstChild(), :GetDescendants(), etc.
  // studio.query.* - Use eval: for loops, string.match, filtering
  // studio.gui.* - Use eval: PlayerGui:GetChildren(), gui.Enabled = false
  // studio.input.* - Use eval: UserInputService, ContextActionService
  // studio.network.* - Use eval: game:GetService("NetworkClient"), etc.
  // studio.animation.* - Use eval: Animator:GetPlayingAnimationTracks()
  // runtime.http/perf/memory - Use eval: HttpService, stats(), collectgarbage()
}
