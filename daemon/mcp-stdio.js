#!/usr/bin/env node
/**
 * MCP stdio entry point for Claude Code
 *
 * This starts the MCP server with stdio transport, allowing Claude Code
 * to use the Roblox Studio DevTools as an MCP server.
 *
 * Note: The HTTP daemon must also be running for Studio tools to work.
 * Cloud tools work independently via Open Cloud API.
 */

import 'dotenv/config';
import { startMCPServer } from './mcp/server.js';
import { setPluginCaller, registerAllTools } from './mcp/tools/index.js';

// For Studio tools, we need to communicate with the HTTP daemon
const DAEMON_URL = process.env.DETAI_DAEMON_URL || 'http://127.0.0.1:4849';

// Plugin caller that forwards to HTTP daemon
async function callPluginViaHttp(tool, params) {
  const response = await fetch(`${DAEMON_URL}/devtools/call`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ tool, params }),
  });

  const data = await response.json();

  if (!data.success) {
    throw new Error(data.error || 'Tool call failed');
  }

  return data.result;
}

async function main() {
  // Set up plugin caller to use HTTP daemon
  setPluginCaller(callPluginViaHttp);

  // Register all tools
  await registerAllTools();

  // Start MCP server with stdio
  await startMCPServer();
}

main().catch(console.error);
