/**
 * MCP Server for Roblox Studio DevTools
 *
 * Exposes Studio APIs as MCP tools that Claude Code can use.
 * Forwards tool calls to the Roblox Studio plugin via HTTP.
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';

// Tool registry - will be populated by tool modules
const tools = new Map();
const toolSchemas = [];

/**
 * Register a tool with the MCP server
 */
export function registerTool(name, schema, handler) {
  tools.set(name, handler);
  toolSchemas.push({
    name,
    description: schema.description,
    inputSchema: schema.inputSchema
  });
}

/**
 * Call a tool registered in the server
 */
export async function callTool(name, params) {
  const handler = tools.get(name);
  if (!handler) {
    throw new Error(`Unknown tool: ${name}`);
  }
  return await handler(params);
}

/**
 * Get all registered tool schemas
 */
export function getToolSchemas() {
  return toolSchemas;
}

/**
 * Create and configure the MCP server
 */
export function createMCPServer(options = {}) {
  const { pluginUrl = 'http://127.0.0.1:4849' } = options;

  const server = new Server(
    {
      name: 'roblox-studio-devtools',
      version: '0.1.0',
    },
    {
      capabilities: {
        tools: {},
      },
    }
  );

  // Handle list tools request
  server.setRequestHandler(ListToolsRequestSchema, async () => {
    return {
      tools: toolSchemas
    };
  });

  // Handle tool calls
  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params;

    try {
      const result = await callTool(name, args || {});
      return {
        content: [
          {
            type: 'text',
            text: typeof result === 'string' ? result : JSON.stringify(result, null, 2)
          }
        ]
      };
    } catch (error) {
      return {
        content: [
          {
            type: 'text',
            text: `Error: ${error.message}`
          }
        ],
        isError: true
      };
    }
  });

  return server;
}

/**
 * Start the MCP server with stdio transport
 */
export async function startMCPServer(options = {}) {
  const server = createMCPServer(options);
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('[MCP] Roblox Studio DevTools server started');
  return server;
}

// Export for use by tool modules
export { tools, toolSchemas };
