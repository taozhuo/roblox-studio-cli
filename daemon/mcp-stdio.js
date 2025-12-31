#!/usr/bin/env node

/**
 * MCP Server Entry Point (stdio transport)
 * Run this as a separate process for Claude Agent SDK integration
 */

import 'dotenv/config';
import { startMCPServer } from './mcp/server.js';
import { setPluginCaller, registerAllTools } from './mcp/tools/index.js';

// Plugin caller that makes HTTP requests to the main daemon
async function httpPluginCaller(tool, params) {
  const port = process.env.DETAI_PORT || 4849;
  const response = await fetch(`http://127.0.0.1:${port}/devtools/call`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ tool, params })
  });
  const data = await response.json();
  if (!data.success) {
    throw new Error(data.error || 'Plugin call failed');
  }
  return data.result;
}

// Set up plugin caller and register tools, then start server
async function main() {
  setPluginCaller(httpPluginCaller);
  await registerAllTools();  // Wait for all tools to register
  console.error('[MCP] All tools registered');
  await startMCPServer();
}

main().catch(err => {
  console.error('[MCP] Failed to start:', err);
  process.exit(1);
});
