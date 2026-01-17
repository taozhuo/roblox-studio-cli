#!/usr/bin/env node

import 'dotenv/config';

/**
 * Bakable Local Daemon
 * Hybrid HTTP + WebSocket server for Roblox Studio integration
 * - HTTP for heavy operations (sync, agent runs)
 * - WebSocket for live streaming (logs, progress, notifications)
 * - MCP server for DevTools integration with Claude Code
 */

import express from 'express';
import cors from 'cors';
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import { watch } from 'chokidar';
import crypto from 'crypto';
import fs from 'fs/promises';
import path from 'path';
import { spawn } from 'child_process';
import { query } from '@anthropic-ai/claude-agent-sdk';
import os from 'os';

// MCP imports
import { registerTool, callTool, getToolSchemas } from './mcp/server.js';
import { setPluginCaller, registerAllTools } from './mcp/tools/index.js';

const PORT = process.env.DETAI_PORT || 4849;
const REPO_PATH = process.env.DETAI_REPO || './detai-repo';

// Generate auth token on startup
const AUTH_TOKEN = process.env.DETAI_TOKEN || crypto.randomUUID();

// State
let manifest = {
  version: '0.3',
  projectId: '',
  revision: 0,
  scripts: []
};

let pendingChanges = [];
let watcher = null;

// Agent runs state
const agentRuns = new Map();

// WebSocket clients
const wsClients = new Set();

// Current session (pushed from plugin)
let currentSession = null;

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' }));

// Create HTTP server
const server = createServer(app);

// Create WebSocket server
const wss = new WebSocketServer({ server, path: '/ws' });

// ============ Utility Functions ============

function computeHash(text) {
  return crypto.createHash('sha1').update(text).digest('hex').substring(0, 16);
}

async function ensureDir(dirPath) {
  try {
    await fs.mkdir(dirPath, { recursive: true });
  } catch (err) {
    if (err.code !== 'EEXIST') throw err;
  }
}

async function loadManifest() {
  const manifestPath = path.join(REPO_PATH, 'detai.manifest.json');
  try {
    const data = await fs.readFile(manifestPath, 'utf-8');
    manifest = JSON.parse(data);
    console.log(`[Bakable] Loaded manifest: ${manifest.scripts.length} scripts, revision ${manifest.revision}`);
  } catch (err) {
    console.log('[Bakable] No existing manifest, starting fresh');
  }
}

async function saveManifest() {
  const manifestPath = path.join(REPO_PATH, 'detai.manifest.json');
  await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2));
}

function isPathAllowed(filePath) {
  const resolvedPath = path.resolve(filePath);
  const repoResolved = path.resolve(REPO_PATH);
  return resolvedPath.startsWith(repoResolved);
}

// ============ WebSocket Broadcast ============

function broadcast(event) {
  const message = JSON.stringify(event);
  for (const client of wsClients) {
    if (client.readyState === 1) { // WebSocket.OPEN
      client.send(message);
    }
  }
}

function broadcastRunLog(runId, log) {
  broadcast({
    type: 'run.log',
    runId,
    timestamp: log.timestamp,
    message: log.message
  });
}

function broadcastRunProgress(runId, state, filesChanged) {
  broadcast({
    type: 'run.progress',
    runId,
    state,
    filesChanged: filesChanged || []
  });
}

function broadcastRunDone(runId, result) {
  broadcast({
    type: 'run.done',
    runId,
    success: result?.success || false,
    summary: result?.summary || '',
    filesChanged: result?.filesChanged || [],
    costUsd: result?.costUsd || 0
  });
}

function broadcastRepoChanged(revision, files) {
  broadcast({
    type: 'repo.changed',
    revision,
    files
  });
}

function broadcastStudioExec(code) {
  // Send via WebSocket
  broadcast({
    type: 'studio.exec',
    code
  });
  // Also queue for HTTP polling fallback
  pendingExec = code;
}

// ============ WebSocket Server ============

wss.on('connection', (ws, req) => {
  console.log('[Bakable:WS] New connection - auto-accepting');

  // Auto-accept all connections (localhost only anyway)
  wsClients.add(ws);
  ws.send(JSON.stringify({
    type: 'welcome',
    version: '0.3',
    revision: manifest.revision
  }));

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString());
      console.log('[Bakable:WS] Received:', msg.type);
    } catch (err) {
      console.error('[Bakable:WS] Message parse error:', err);
    }
  });

  ws.on('close', () => {
    wsClients.delete(ws);
    console.log('[Bakable:WS] Client disconnected');
    // Clear session when no clients connected
    if (wsClients.size === 0) {
      currentSession = null;
    }
  });

  ws.on('error', (err) => {
    console.error('[Bakable:WS] Error:', err);
    wsClients.delete(ws);
    if (wsClients.size === 0) {
      currentSession = null;
    }
  });
});

// ============ Auth Middleware ============

function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing auth token' });
  }

  const token = authHeader.substring(7);
  if (token !== AUTH_TOKEN) {
    return res.status(401).json({ error: 'Invalid auth token' });
  }

  next();
}

// ============ Session/Place tracking (pushed from plugin) ============

// Plugin pushes session info when connected
app.post('/session/update', (req, res) => {
  const { placeId, gameId, placeName, isPublished, sessionKey } = req.body;
  currentSession = { placeId, gameId, placeName, isPublished, sessionKey };
  console.log(`[Bakable] Session updated: ${placeName}${isPublished ? ` (ID: ${placeId})` : ' (unpublished)'}`);
  res.json({ ok: true });
});

// ============ Health Check (no auth) ============

app.get('/health', (req, res) => {
  res.json({
    ok: true,
    version: '0.3',
    agentSdkEnabled: true,
    wsEnabled: true,
    pluginConnected: wsClients.size > 0,
    session: currentSession
  });
});

// Session endpoint - get current session
app.get('/session', (req, res) => {
  if (currentSession) {
    res.json(currentSession);
  } else {
    res.status(503).json({ error: 'No session info - plugin not connected yet' });
  }
});

// ============ Chat Endpoint using Claude Agent SDK with MCP ============

// MCP server configuration for Roblox Studio tools
const mcpServers = {
  'roblox-studio': {
    type: 'stdio',
    command: 'node',
    args: [path.join(path.dirname(new URL(import.meta.url).pathname), 'mcp-stdio.js')],
    env: {
      DETAI_PORT: String(PORT)
    }
  }
};

// Helper to gather Studio context (selection, path, pointer, viewport)
async function gatherStudioContext() {
  const context = {};
  const CONTEXT_TIMEOUT = 3000; // 3 second timeout for context calls

  try {
    // Get selection (quick timeout)
    const selection = await callPluginTool('studio.selection.get', {}, CONTEXT_TIMEOUT);
    if (selection && !selection.error) {
      context.selection = selection;
    }
  } catch (e) {
    console.log('[Bakable] Context: selection timeout/error');
  }

  try {
    // Get path data (quick timeout)
    const path = await callPluginTool('studio.path.get', {}, CONTEXT_TIMEOUT);
    if (path && !path.error && path.points?.length > 0) {
      context.path = path;
    }
  } catch (e) {
    console.log('[Bakable] Context: path timeout/error');
  }

  try {
    // Get last pointer position (quick timeout)
    const pointer = await callPluginTool('studio.pointer.getLast', {}, CONTEXT_TIMEOUT);
    if (pointer && !pointer.error && pointer.position) {
      context.pointer = pointer;
    }
  } catch (e) {
    console.log('[Bakable] Context: pointer timeout/error');
  }

  // Note: viewport scan is on-demand via studio.camera.scanViewport tool
  // AI calls it when needed, not auto-included (reduces latency)

  return context;
}

// Streaming chat endpoint using Server-Sent Events (SSE)
app.post('/chat/stream', async (req, res) => {
  // Set SSE headers with CORS
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.flushHeaders();

  const sendEvent = (type, data) => {
    res.write(`data: ${JSON.stringify({ type, ...data })}\n\n`);
  };

  let fullText = '';

  try {
    // Note: If ANTHROPIC_API_KEY not set, Claude Agent SDK uses Claude Code auth
    const { message, images, sessionId, yoloMode = true } = req.body;
    if (!message && (!images || images.length === 0)) {
      sendEvent('error', { message: 'Message required' });
      res.end();
      return;
    }

    console.log('[Bakable] Session:', sessionId || '(new session)', '| YOLO:', yoloMode, '| Images:', images?.length || 0);

    // Gather Studio context automatically
    sendEvent('status', { message: 'Getting context...' });
    const studioContext = await gatherStudioContext();

    // Build context string
    let contextStr = '';
    if (studioContext.selection?.items?.length > 0) {
      contextStr += `\n\nCURRENT SELECTION: ${studioContext.selection.items.map(i => i.path).join(', ')}`;
    }
    if (studioContext.path?.points?.length > 0) {
      // Include all path points so Claude can accurately follow the drawn path
      contextStr += `\n\nDRAWN PATH (${studioContext.path.points.length} points):\n${JSON.stringify(studioContext.path.points)}`;
    }
    if (studioContext.pointer?.position) {
      const p = studioContext.pointer.position;
      contextStr += `\n\nMARKED POSITION: (${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)})`;
    }

    // Build prompt - use async generator for images (streaming input mode)
    let prompt;
    if (images && images.length > 0) {
      console.log('[Bakable] Images received:', images.length, 'images');
      console.log('[Bakable] First image media_type:', images[0].media_type);
      console.log('[Bakable] First image data length:', images[0].data?.length || 0);

      // Build content array with text FIRST, then images (required order for SDK)
      const contentBlocks = [
        { type: 'text', text: (message || 'What do you see in this image?') + contextStr },
        ...images.map(img => ({
          type: 'image',
          source: {
            type: 'base64',
            media_type: img.media_type,
            data: img.data
          }
        }))
      ];

      // Use async generator for streaming input mode (required for images)
      async function* messageGenerator() {
        yield {
          type: 'user',
          message: {
            role: 'user',
            content: contentBlocks
          }
        };
      }

      prompt = messageGenerator();
      console.log('[Bakable] Using streaming input mode for images');
    } else {
      prompt = message + contextStr;
    }

    const systemPrompt = `You are Bakable, an AI assistant for Roblox Studio game development.

CONTEXT (auto-provided):
- SELECTION: Currently selected instances
- PATH: User-drawn path points
- POINTER: User-marked position

TOOLS:
- studio.eval - Execute Luau code in Studio (create, delete, modify anything)
- studio.instances.tree/getProps/setProps - Query tree, get/set properties
- studio.camera.focusOn - Move camera to look at something

Context (selection, path, pointer) is AUTO-PROVIDED - don't call tools to get it.

ROBLOX SCRIPT PLACEMENT:
- Server Scripts → ServerScriptService (runs on server only)
- ModuleScripts → ReplicatedStorage (shared) or ServerStorage (server-only)
- GUI → StarterGui (ScreenGui) or in a Part (BillboardGui/SurfaceGui)

When creating scripts, ALWAYS use className="Script" for ServerScriptService. Default to ServerScriptService for game logic.

TESTING (PLAYTEST WORKFLOW):
1. Create your script first (in ServerScriptService for server code)
2. Start Run mode with studio.playtest.run
3. Check status with studio.playtest.getStatus - look at isEdit/isRunMode
4. Check logs with studio.logs.getHistory (NOT studio.logs.get)
5. Stop with studio.playtest.stop when done

IMPORTANT:
- Run mode is server-only (F8) - cleaner for testing server scripts
- After stopping, isEdit should be true
- If stuck in run mode, call studio.playtest.stop again
- Do NOT use LocalScripts for testing - use server scripts

Be direct. Execute code. Use Run mode to test.`;

    console.log('[Bakable] Stream request:', (message || '(image only)').substring(0, 50) + '...');
    sendEvent('status', { message: 'Starting...' });

    // Build SDK options - use resume for session continuity
    const sdkOptions = {
      systemPrompt,
      model: 'sonnet',
      cwd: REPO_PATH,
      permissionMode: yoloMode ? 'bypassPermissions' : 'default',
      allowDangerouslySkipPermissions: yoloMode,
      mcpServers,
      settingSources: ['user', 'project'],  // Enable skills from .claude/skills/
    };

    // Resume existing session if sessionId provided
    if (sessionId) {
      sdkOptions.resume = sessionId;
      console.log('[Bakable] Resuming session:', sessionId);
    }

    const response = query({
      prompt,
      options: sdkOptions
    });

    let capturedSessionId = sessionId;

    // Send keepalive pings every 15 seconds to prevent connection timeout
    const keepaliveInterval = setInterval(() => {
      sendEvent('ping', {});
    }, 15000);

    try {
    for await (const event of response) {
      console.log('[Bakable] Event:', event.type);

      // Capture session_id from first message
      if (event.session_id && !capturedSessionId) {
        capturedSessionId = event.session_id;
        console.log('[Bakable] New session created:', capturedSessionId);
        sendEvent('session', { sessionId: capturedSessionId });
      }

      if (event.type === 'assistant' && event.message?.content) {
        for (const block of event.message.content) {
          if (block.type === 'text') {
            fullText += block.text;
            sendEvent('text', { content: block.text });
          } else if (block.type === 'tool_use') {
            // Stream tool calls with friendly names
            let toolName = block.name;

            // Handle MCP tools (mcp__roblox-studio__studio_eval -> studio.eval)
            if (toolName.startsWith('mcp__')) {
              toolName = toolName.replace('mcp__roblox-studio__', '').replace(/_/g, '.');
            }

            const friendlyNames = {
              // Claude Code built-in tools
              'Bash': 'Running command',
              'Read': 'Reading file',
              'Write': 'Writing file',
              'Edit': 'Editing file',
              'Glob': 'Finding files',
              'Grep': 'Searching code',
              'TodoRead': 'Reading todos',
              'TodoWrite': 'Updating todos',
              'WebFetch': 'Fetching URL',
              'WebSearch': 'Searching web',
              // MCP Roblox Studio tools
              'studio.eval': 'Running Lua code',
              'studio.selection.set': 'Selecting instances',
              'studio.instances.tree': 'Reading instance tree',
              'studio.instances.getProps': 'Reading properties',
              'studio.instances.setProps': 'Setting properties',
              'studio.scripts.list': 'Listing scripts',
              'studio.scripts.read': 'Reading script',
              'studio.scripts.write': 'Writing script',
              'studio.scripts.create': 'Creating script',
              'studio.path.start': 'Recording path',
              'studio.path.stop': 'Stopping path',
              'studio.path.clear': 'Clearing path',
              'studio.path.addPoint': 'Adding path point',
              'studio.pointer.get': 'Getting pointer',
              'studio.pointer.capture': 'Capturing pointer',
              'studio.history.begin': 'Starting undo point',
              'studio.history.end': 'Saving undo point',
              'studio.history.undo': 'Undoing',
              'studio.history.redo': 'Redoing',
              'studio.logs.getHistory': 'Getting logs',
              'studio.logs.clear': 'Clearing logs',
              'studio.camera.get': 'Getting camera',
              'studio.camera.getModelsInView': 'Finding models',
              'studio.camera.set': 'Moving camera',
              'studio.camera.focusOn': 'Focusing camera',
              'studio.camera.focusOnSelection': 'Focusing on selection',
              'studio.camera.scanViewport': 'Scanning viewport',
              'studio.captureViewport': 'Capturing screenshot',
              'studio.getPlaceInfo': 'Getting place info',
              'studio.getActiveScript': 'Getting active script',
              'studio.getActiveScriptSource': 'Reading active script',
              'studio.getStudioInfo': 'Getting Studio info',
              'studio.openScript': 'Opening script',
              'studio.getOpenDocuments': 'Getting open docs',
              'studio.debug.getBreakpoints': 'Getting breakpoints',
              'studio.debug.addBreakpoint': 'Adding breakpoint',
              'studio.debug.removeBreakpoint': 'Removing breakpoint',
              'studio.debug.clearAllBreakpoints': 'Clearing breakpoints',
              // Runtime tools
              'runtime.http.captureStart': 'Starting HTTP capture',
              'runtime.http.captureStop': 'Stopping HTTP capture',
              'runtime.http.getRecent': 'Getting HTTP logs',
              'runtime.memory.sample': 'Sampling memory',
              'runtime.memory.getStats': 'Getting memory stats',
              'runtime.memory.instanceCount': 'Counting instances',
              'runtime.perf.span': 'Creating perf span',
              'runtime.perf.dumpWindow': 'Dumping perf data',
              'runtime.perf.getStats': 'Getting perf stats',
              // Playtest tools
              'studio.playtest.getStatus': 'Checking playtest status',
              'studio.playtest.run': 'Starting Run mode',
              'studio.playtest.stop': 'Stopping playtest',
              // Recording tools
              'studio.recording.start': 'Starting recording',
              'studio.recording.stop': 'Stopping recording',
              'studio.recording.status': 'Checking recording status',
              'studio.recording.createGif': 'Creating GIF',
              'studio.recording.createVideo': 'Creating video',
              'studio.recording.clear': 'Clearing frames',
              // Cloud tools
              'cloud.datastore.read': 'Reading DataStore',
              'cloud.datastore.write': 'Writing DataStore',
              'cloud.datastore.list': 'Listing DataStore keys',
              'cloud.place.publish': 'Publishing place',
              'cloud.place.getInfo': 'Getting place info',
              'cloud.universe.getInfo': 'Getting universe info',
            };
            const displayName = friendlyNames[toolName] || toolName;
            console.log('[Bakable] Tool:', displayName);
            sendEvent('tool_start', { tool: displayName, input: block.input });
          }
        }
      }

      if (event.type === 'user' && event.message?.content) {
        // Tool results come back as user messages
        for (const block of event.message.content) {
          if (block.type === 'tool_result') {
            sendEvent('tool_end', { toolUseId: block.tool_use_id });
          }
        }
      }

      if (event.type === 'result') {
        // Don't send result text - it's already streamed via assistant events
        // Just log for debugging
        console.log('[Bakable] Result received, total text length:', fullText.length);
        // Break out of loop - we're done
        break;
      }
    }
    } finally {
      clearInterval(keepaliveInterval);
    }

    sendEvent('done', { fullText });
    res.end();

  } catch (err) {
    // Ignore "process exited" errors if we already have content - SDK quirk
    if (err.message?.includes('process exited') && fullText?.length > 0) {
      console.log('[Bakable] Ignoring exit error after successful response');
      sendEvent('done', { fullText });
      res.end();
      return;
    }
    // Log full error details
    console.error('[Bakable] Stream error:', err.message);
    console.error('[Bakable] Error stack:', err.stack);
    console.error('[Bakable] Full text so far:', fullText?.length || 0, 'chars');
    sendEvent('error', { message: err.message || 'Unknown error' });
    res.end();
  }
});

// Non-streaming fallback
app.post('/chat', async (req, res) => {
  try {
    // Note: If ANTHROPIC_API_KEY not set, Claude Agent SDK uses Claude Code auth
    const { message, history = [] } = req.body;

    if (!message) {
      return res.status(400).json({ error: 'Message required' });
    }

    // Gather context
    const studioContext = await gatherStudioContext();
    let contextStr = '';
    if (studioContext.selection?.items?.length > 0) {
      contextStr += `\n\nCURRENT SELECTION: ${studioContext.selection.items.map(i => i.path).join(', ')}`;
    }
    if (studioContext.path?.points?.length > 0) {
      // Include all path points so Claude can accurately follow the drawn path
      contextStr += `\n\nDRAWN PATH (${studioContext.path.points.length} points):\n${JSON.stringify(studioContext.path.points)}`;
    }
    if (studioContext.pointer?.position) {
      const p = studioContext.pointer.position;
      contextStr += `\n\nMARKED POSITION: (${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)})`;
    }

    let prompt = message + contextStr;
    if (history.length > 0) {
      const historyContext = history.map(h =>
        `${h.role === 'assistant' ? 'Assistant' : 'User'}: ${h.content}`
      ).join('\n\n');
      prompt = `Previous conversation:\n${historyContext}\n\nUser: ${message}${contextStr}`;
    }

    const systemPrompt = `You are Bakable, an AI assistant specialized in game development with FULL ACCESS to Roblox Studio.

CONTEXT is provided automatically - you already have selection, path, and pointer data in the user's message. Use it directly.

You have MCP tools available to interact with Roblox Studio:
- studio.eval - Execute Luau code directly in Studio (create, delete, modify)
- studio.scripts.read/write - Read or write script content

ROBLOX SCRIPT PLACEMENT:
- Server Scripts → ServerScriptService (runs on server only)
- Local Scripts → StarterPlayerScripts or StarterGui (runs on client)
- ModuleScripts → ReplicatedStorage (shared) or ServerStorage (server-only)
- GUI → StarterGui (ScreenGui) or in a Part (BillboardGui/SurfaceGui)

When creating scripts, ALWAYS place them in the correct service. Default to ServerScriptService for game logic.

When the user asks you to do something in Roblox Studio, USE THESE TOOLS.
Be proactive. Execute code. Make changes. You have full control.`;

    console.log('[Bakable] Chat request:', message.substring(0, 50) + '...');

    const response = query({
      prompt,
      options: {
        systemPrompt,
        model: 'sonnet',
        cwd: REPO_PATH,
        permissionMode: 'bypassPermissions',
        allowDangerouslySkipPermissions: true,
        mcpServers
      }
    });

    let assistantMessage = '';
    let toolResults = [];

    for await (const event of response) {
      if (event.type === 'assistant' && event.message?.content) {
        for (const block of event.message.content) {
          if (block.type === 'text') {
            assistantMessage += block.text;
          } else if (block.type === 'tool_use') {
            toolResults.push({
              tool: block.name,
              input: block.input
            });
          }
        }
      }
      if (event.type === 'result' && event.result) {
        assistantMessage += event.result;
      }
    }

    if (!assistantMessage) {
      assistantMessage = 'No response generated';
    }

    res.json({
      ok: true,
      response: assistantMessage,
      toolsUsed: toolResults.length > 0 ? toolResults : undefined
    });

  } catch (err) {
    console.error('[Bakable] Chat error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ============ Plugin Log Endpoint ============

app.post('/log', (req, res) => {
  const { level, message } = req.body;
  console.log(`[Studio:${level || 'info'}] ${message}`);
  res.json({ ok: true });
});

// ============ DevTools MCP Endpoints ============

// Pending DevTools call for plugin to respond
let pendingDevToolsCall = null;
let devToolsCallResolve = null;
let devToolsCallTimeout = null;

// Call plugin via WebSocket and wait for response
async function callPluginTool(tool, params, timeout = 30000) {
  return new Promise((resolve, reject) => {
    // Set up pending call
    const callId = crypto.randomUUID();
    pendingDevToolsCall = { callId, tool, params };
    devToolsCallResolve = resolve;

    // Set timeout (shorter for context gathering)
    devToolsCallTimeout = setTimeout(() => {
      pendingDevToolsCall = null;
      devToolsCallResolve = null;
      reject(new Error(`DevTools call timed out: ${tool}`));
    }, timeout);

    // Broadcast to plugin
    broadcast({
      type: 'devtools.call',
      callId,
      tool,
      params
    });
  });
}

// Plugin responds to DevTools calls here
app.post('/devtools/result', (req, res) => {
  const { callId, success, result, error } = req.body;

  if (pendingDevToolsCall && pendingDevToolsCall.callId === callId) {
    clearTimeout(devToolsCallTimeout);
    const resolve = devToolsCallResolve;
    pendingDevToolsCall = null;
    devToolsCallResolve = null;
    devToolsCallTimeout = null;

    if (success) {
      resolve(result);
    } else {
      resolve({ error: error || 'Unknown error' });
    }
  }

  res.json({ ok: true });
});

// Direct DevTools call endpoint (for testing/direct access)
app.post('/devtools/call', async (req, res) => {
  const { tool, params } = req.body;

  if (!tool) {
    return res.status(400).json({ error: 'Missing tool name' });
  }

  try {
    const result = await callPluginTool(tool, params || {});
    res.json({ success: true, result });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// List available DevTools
app.get('/devtools/tools', (req, res) => {
  res.json({ tools: getToolSchemas() });
});

// ============ Execution Result Endpoint ============
// Plugin posts execution results here so Claude can see them

let lastExecResult = null;

app.post('/exec/result', async (req, res) => {
  const { success, result, error, code } = req.body;
  lastExecResult = { success, result, error, code, timestamp: Date.now() };

  console.log(`[Studio:exec] ${success ? 'SUCCESS' : 'ERROR'}: ${result || error}`);

  // Write to file so Claude can read it
  try {
    const resultPath = path.join(REPO_PATH, 'exec.result.txt');
    const content = success
      ? `EXECUTION SUCCESS at ${new Date().toISOString()}\n\nResult: ${result || 'OK'}`
      : `EXECUTION ERROR at ${new Date().toISOString()}\n\nError: ${error}`;
    await fs.writeFile(resultPath, content);
  } catch (e) {
    console.error('[Bakable] Failed to write exec.result.txt:', e);
  }

  res.json({ ok: true });
});

app.get('/exec/result', (req, res) => {
  res.json(lastExecResult || { success: false, error: 'No execution yet' });
});

// Pending exec for polling fallback when WS unavailable
let pendingExec = null;

app.get('/exec/pending', (req, res) => {
  if (pendingExec) {
    const code = pendingExec;
    pendingExec = null; // Clear after sending
    res.json({ code });
  } else {
    res.json({ code: null });
  }
});

// Called by broadcastStudioExec to also queue for polling
function queueExecForPolling(code) {
  pendingExec = code;
}

// ============ Sync Endpoints ============

app.post('/sync/pushSnapshot', async (req, res) => {
  try {
    const { projectId, scripts } = req.body;

    if (!scripts || !Array.isArray(scripts)) {
      return res.status(400).json({ error: 'Invalid scripts array' });
    }

    console.log(`[Bakable] Receiving snapshot: ${scripts.length} scripts`);

    await ensureDir(REPO_PATH);
    await ensureDir(path.join(REPO_PATH, 'src'));

    manifest.projectId = projectId || 'untitled';
    manifest.revision += 1;
    manifest.scripts = [];

    for (const script of scripts) {
      const filePath = path.join(REPO_PATH, script.filePath);
      const dir = path.dirname(filePath);

      await ensureDir(dir);
      await fs.writeFile(filePath, script.text || '');

      manifest.scripts.push({
        detaiId: script.detaiId,
        robloxPath: script.robloxPath,
        className: script.className,
        filePath: script.filePath,
        hash: computeHash(script.text || ''),
        lastSyncRevision: manifest.revision
      });
    }

    await saveManifest();

    if (!watcher) {
      startWatcher();
    }

    pendingChanges = [];

    console.log(`[Bakable] Snapshot written, revision: ${manifest.revision}`);
    res.json({ ok: true, revision: manifest.revision, scriptCount: scripts.length });

  } catch (err) {
    console.error('[Bakable] pushSnapshot error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.post('/sync/pullChanges', async (req, res) => {
  try {
    const { sinceRevision } = req.body;

    const changes = pendingChanges.filter(c => c.revision > sinceRevision);

    res.json({
      revision: manifest.revision,
      changes: changes.map(c => ({
        detaiId: c.detaiId,
        filePath: c.filePath,
        hash: c.hash,
        text: c.text
      }))
    });

  } catch (err) {
    console.error('[Bakable] pullChanges error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ============ Agent Endpoints ============

app.post('/agent/run', async (req, res) => {
  try {
    const { task, scope, context, repoRoot } = req.body;

    if (!task) {
      return res.status(400).json({ error: 'Task instruction required' });
    }

    const workDir = repoRoot || path.resolve(REPO_PATH);
    const runId = `run_${crypto.randomUUID().substring(0, 8)}`;
    const startedAt = Date.now();

    console.log(`[Bakable:${runId}] Starting agent task: ${task.substring(0, 100)}...`);

    agentRuns.set(runId, {
      state: 'running',
      task,
      scope,
      context,
      workDir,
      startedAt,
      logs: [],
      filesChanged: [],
      result: null,
      error: null
    });

    // Broadcast start event
    broadcastRunProgress(runId, 'running', []);

    runAgentTask(runId, task, workDir, scope, context).catch(err => {
      console.error(`[Bakable:${runId}] Agent error:`, err);
      const run = agentRuns.get(runId);
      if (run) {
        run.state = 'error';
        run.error = err.message;
        broadcastRunDone(runId, { success: false, summary: err.message });
      }
    });

    res.json({ ok: true, runId, startedAt });

  } catch (err) {
    console.error('[Bakable] agent/run error:', err);
    res.status(500).json({ error: err.message });
  }
});

app.get('/agent/status', (req, res) => {
  const { runId } = req.query;

  if (!runId) {
    return res.status(400).json({ error: 'runId required' });
  }

  const run = agentRuns.get(runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  res.json({
    runId,
    state: run.state,
    startedAt: run.startedAt,
    filesChanged: run.filesChanged,
    summary: run.result?.summary || null,
    error: run.error
  });
});

app.get('/agent/logs', (req, res) => {
  const { runId, cursor } = req.query;

  if (!runId) {
    return res.status(400).json({ error: 'runId required' });
  }

  const run = agentRuns.get(runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  const startIdx = cursor ? parseInt(cursor, 10) : 0;
  const lines = run.logs.slice(startIdx);

  res.json({
    runId,
    lines,
    nextCursor: run.logs.length.toString(),
    state: run.state
  });
});

app.post('/agent/cancel', (req, res) => {
  const { runId } = req.body;

  if (!runId) {
    return res.status(400).json({ error: 'runId required' });
  }

  const run = agentRuns.get(runId);
  if (!run) {
    return res.status(404).json({ error: 'Run not found' });
  }

  if (run.state === 'running') {
    run.state = 'cancelled';
    run.cancelRequested = true;
    console.log(`[Bakable:${runId}] Cancel requested`);
    broadcastRunProgress(runId, 'cancelled', run.filesChanged);
  }

  res.json({ ok: true, runId, state: run.state });
});

// ============ Agent Task Runner ============

async function runAgentTask(runId, task, workDir, scope, context) {
  const run = agentRuns.get(runId);
  if (!run) return;

  const addLog = (message) => {
    const log = { timestamp: Date.now(), message };
    run.logs.push(log);
    console.log(`[Bakable:${runId}] ${message}`);
    // Broadcast log via WebSocket
    broadcastRunLog(runId, log);
  };

  addLog(`Task: ${task}`);
  addLog(`Working directory: ${workDir}`);

  let fullPrompt = task;
  if (scope?.focusFiles?.length > 0) {
    fullPrompt += `\n\nFocus on these files: ${scope.focusFiles.join(', ')}`;
  }

  // Add path data prominently if user drew a path
  if (context?.path?.points?.length > 0) {
    const points = context.path.points;
    fullPrompt += `\n\n=== USER DREW A PATH (${points.length} points) ===\n`;
    fullPrompt += `IMPORTANT: Use these EXACT coordinates when placing objects!\n`;
    points.forEach((pt, i) => {
      fullPrompt += `Point ${i + 1}: Vector3.new(${pt.position.x.toFixed(1)}, ${pt.position.y.toFixed(1)}, ${pt.position.z.toFixed(1)})\n`;
    });
    fullPrompt += `Use these points to create objects along the path or within the area they define.\n`;
  }

  // Add pointer data if user marked a position
  if (context?.pointer?.position) {
    const pos = context.pointer.position;
    fullPrompt += `\n\n=== USER MARKED A POSITION ===\n`;
    fullPrompt += `Position: Vector3.new(${pos.x.toFixed(1)}, ${pos.y.toFixed(1)}, ${pos.z.toFixed(1)})\n`;
    if (context.pointer.instance?.path) {
      fullPrompt += `On instance: ${context.pointer.instance.path}\n`;
    }
    fullPrompt += `Use this EXACT position when the user says "here" or "at this spot".\n`;
  }

  if (context?.notes) {
    fullPrompt += `\n\nNotes: ${context.notes}`;
  }
  if (context?.selection?.length > 0) {
    fullPrompt += `\n\nSelected instances: ${context.selection.join(', ')}`;
  }
  if (context?.apiReference) {
    fullPrompt += `\n\n${context.apiReference}`;
  }

  // System prompt for Roblox Studio interaction
  const systemPrompt = `You are a Roblox Studio AI assistant. You can execute Lua code directly in Roblox Studio.

IMPORTANT: Your working directory is "${workDir}". Only write files here using relative paths like "exec.lua", NOT absolute paths.

TO EXECUTE CODE IN ROBLOX STUDIO:
1. Write Lua code to "exec.lua" (just the filename, NOT a full path) - it will be automatically executed in Studio
2. After writing, READ "exec.result.txt" to check if execution succeeded or failed

Example - to make SpawnLocation neon material:
Write to exec.lua:
\`\`\`lua
local spawn = workspace:FindFirstChild("SpawnLocation")
if spawn then
    spawn.Material = Enum.Material.Neon
    print("Made SpawnLocation neon")
end
\`\`\`

Example - to create a new Part:
Write to exec.lua:
\`\`\`lua
local part = Instance.new("Part")
part.Name = "MyPart"
part.Size = Vector3.new(4, 1, 4)
part.Position = Vector3.new(0, 10, 0)
part.Anchored = true
part.Material = Enum.Material.Neon
part.BrickColor = BrickColor.new("Bright blue")
part.Parent = workspace
print("Created part:", part.Name)
\`\`\`

WORKFLOW:
1. Write code to "exec.lua" (relative path only!)
2. Wait briefly, then READ "exec.result.txt" to verify execution
3. If there was an error, fix the code and try again
4. Report success/failure to the user

IMPORTANT:
- NEVER use absolute paths like /Users/... - only use relative filenames
- Always check exec.result.txt after writing exec.lua to confirm execution
- The code runs in Studio's context with full access to game services
- Use print() to show results to the user
- If execution fails, read the error and fix your code
- The selected instances are: ${context?.selection?.join(', ') || 'none'}`;

  const fullPromptWithSystem = `${systemPrompt}\n\nUser request: ${fullPrompt}`;

  addLog(`Full prompt: ${fullPromptWithSystem.substring(0, 200)}...`);

  // Use Claude Agent SDK - full Claude Code experience
  try {
    const { query } = await import('@anthropic-ai/claude-agent-sdk');

    addLog('Using Claude Agent SDK...');

    const changedFiles = new Set();

    for await (const message of query({
      prompt: fullPromptWithSystem,
      options: {
        cwd: workDir,
        allowedTools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Task', 'TodoWrite', 'WebSearch', 'WebFetch', 'AskUserQuestion', 'NotebookEdit', 'LSP', 'MCPSearch', 'EnterPlanMode', 'ExitPlanMode', 'KillShell', 'TaskOutput', 'Skill'],
        permissionMode: 'acceptEdits',
        model: 'claude-opus-4-5-20251101'
      }
    })) {
      if (run.cancelRequested) {
        addLog('Run cancelled');
        run.state = 'cancelled';
        broadcastRunDone(runId, { success: false, summary: 'Cancelled by user' });
        return;
      }

      // Check for text and tool usage in assistant messages
      if (message.type === 'assistant' && message.message?.content) {
        const content = message.message.content;
        // Check if this message has tool calls (intermediate) or is text-only (final)
        const hasToolUse = content.some(b => b.type === 'tool_use');

        for (const block of content) {
          // Only log intermediate text (before tool calls), not final responses
          // Final response text is sent via run.done
          if (block.type === 'text' && block.text && hasToolUse) {
            const text = block.text.substring(0, 200);
            addLog(`Claude: ${text}${block.text.length > 200 ? '...' : ''}`);
          }

          if (block.type === 'tool_use') {
            const toolName = block.name;
            const toolInput = block.input || {};
            addLog(`Tool: ${toolName}`);

            if (toolName === 'Write' || toolName === 'Edit') {
              const filePath = toolInput.file_path;
              if (filePath) {
                changedFiles.add(filePath);
                addLog(`Writing: ${filePath}`);
                run.filesChanged = Array.from(changedFiles);
                broadcastRunProgress(runId, 'running', run.filesChanged);

                // Check if exec.lua was written - send to Studio for execution
                if (filePath.endsWith('exec.lua')) {
                  // Small delay to ensure file is written
                  await new Promise(r => setTimeout(r, 100));
                  try {
                    const execPath = path.resolve(workDir, 'exec.lua');
                    const code = await fs.readFile(execPath, 'utf-8');
                    addLog(`Executing in Studio: ${code.substring(0, 100)}...`);
                    broadcastStudioExec(code);
                  } catch (e) {
                    addLog(`Failed to read exec.lua: ${e.message}`);
                  }
                }
              }
            }
          }
        }
      }

      // Capture result
      if (message.type === 'result' || 'result' in message) {
        const resultText = message.result || message.text || 'Task completed';
        addLog(`Completed: ${resultText.substring(0, 100)}...`);

        run.state = 'done';
        run.filesChanged = Array.from(changedFiles);
        run.result = {
          success: true,
          summary: resultText,
          turns: message.num_turns || 1,
          costUsd: message.total_cost_usd || 0,
          filesChanged: run.filesChanged
        };
        broadcastRunDone(runId, run.result);
      }
    }
  } catch (err) {
    addLog(`Error: ${err.message}`);
    run.state = 'error';
    run.error = err.message;
    broadcastRunDone(runId, { success: false, summary: err.message });
  }
}

async function runAgentViaCLI(runId, task, workDir, scope, context) {
  const run = agentRuns.get(runId);
  if (!run) return;

  const addLog = (message) => {
    const log = { timestamp: Date.now(), message };
    run.logs.push(log);
    console.log(`[Bakable:${runId}] ${message}`);
    broadcastRunLog(runId, log);
  };

  const systemPrompt = `You are a Roblox Studio development assistant. You can create and modify Lua scripts that will be synced to Roblox Studio.

AVAILABLE ACTIONS:
- Write Lua scripts to the src/ folder - these will sync to Roblox Studio
- Scripts in src/ServerScriptService/ become ServerScripts
- Scripts in src/StarterPlayer/StarterPlayerScripts/ become LocalScripts
- Scripts in src/ReplicatedStorage/ become ModuleScripts
- Read and modify existing scripts in src/

WORKFLOW:
1. Write .lua files to the appropriate src/ subfolder
2. The user will use /pull in Studio to see changes
3. The user will use /apply to sync changes to Studio

When asked to create something in Roblox, write the Lua script to the correct location.`;

  let prompt = `${systemPrompt}\n\nUSER REQUEST: ${task}`;
  if (scope?.focusFiles?.length > 0) {
    prompt += `\n\nFocus on: ${scope.focusFiles.join(', ')}`;
  }

  addLog(`Running via CLI with Roblox context...`);

  return new Promise((resolve) => {
    const proc = spawn('claude', ['-p', prompt], {
      cwd: workDir,
      shell: true,
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let output = '';

    proc.stdout.on('data', (data) => {
      const text = data.toString();
      output += text;
      addLog(`stdout: ${text.substring(0, 200)}`);
    });

    proc.stderr.on('data', (data) => {
      addLog(`stderr: ${data.toString().substring(0, 200)}`);
    });

    proc.on('close', (code) => {
      addLog(`CLI exited with code ${code}`);

      if (code === 0) {
        run.state = 'done';
        run.result = {
          success: true,
          summary: output.substring(0, 500),
          turns: 1,
          costUsd: 0,
          filesChanged: []
        };
        broadcastRunDone(runId, run.result);
      } else {
        run.state = 'error';
        run.error = `CLI exited with code ${code}`;
        broadcastRunDone(runId, { success: false, summary: run.error });
      }

      resolve();
    });

    proc.on('error', (err) => {
      addLog(`CLI error: ${err.message}`);
      run.state = 'error';
      run.error = err.message;
      broadcastRunDone(runId, { success: false, summary: err.message });
      resolve();
    });
  });
}

// ============ File Watcher ============

function startWatcher() {
  const srcPath = path.join(REPO_PATH, 'src');

  console.log(`[Bakable] Starting file watcher on: ${srcPath}`);

  watcher = watch(srcPath, {
    ignored: /(^|[\/\\])\../,
    persistent: true,
    ignoreInitial: true
  });

  watcher.on('change', async (filePath) => {
    await handleFileChange(filePath);
  });

  watcher.on('add', async (filePath) => {
    if (filePath.endsWith('.lua')) {
      console.log(`[Bakable] New file detected: ${filePath}`);
    }
  });
}

async function handleFileChange(absolutePath) {
  try {
    const relativePath = path.relative(REPO_PATH, absolutePath);
    const scriptInfo = manifest.scripts.find(s => s.filePath === relativePath);

    if (!scriptInfo) {
      console.log(`[Bakable] Changed file not in manifest: ${relativePath}`);
      return;
    }

    const text = await fs.readFile(absolutePath, 'utf-8');
    const newHash = computeHash(text);

    if (newHash === scriptInfo.hash) {
      return;
    }

    console.log(`[Bakable] File changed: ${relativePath}`);

    scriptInfo.hash = newHash;
    manifest.revision += 1;

    await saveManifest();

    const change = {
      detaiId: scriptInfo.detaiId,
      filePath: relativePath,
      hash: newHash,
      text: text,
      revision: manifest.revision
    };

    pendingChanges.push(change);

    if (pendingChanges.length > 1000) {
      pendingChanges = pendingChanges.slice(-1000);
    }

    // Broadcast file change via WebSocket
    broadcastRepoChanged(manifest.revision, [relativePath]);

  } catch (err) {
    console.error('[Bakable] handleFileChange error:', err);
  }
}

// ============ Playtest Control (macOS) ============

// Send keystroke to Roblox Studio via osascript
async function sendKeystrokeToStudio(keyCode, modifiers = []) {
  return new Promise((resolve, reject) => {
    let modString = '';
    if (modifiers.length > 0) {
      modString = ` using {${modifiers.join(', ')}}`;
    }

    const script = `
      tell application "Roblox Studio" to activate
      delay 0.2
      tell application "System Events"
        key code ${keyCode}${modString}
      end tell
    `;

    const proc = spawn('osascript', ['-e', script]);
    let stderr = '';

    proc.stderr.on('data', (data) => {
      stderr += data.toString();
    });

    proc.on('close', (code) => {
      if (code === 0) {
        resolve({ success: true });
      } else {
        reject(new Error(stderr || `osascript exited with code ${code}`));
      }
    });
  });
}

// Key codes for macOS
const KEY_CODES = {
  F5: 96,
  F6: 97,
  F7: 98,
  F8: 99,
  W: 13,
  A: 0,
  S: 1,
  D: 2,
  SPACE: 49,
  SHIFT: 56,
  ESCAPE: 53,
};

// Start Play mode (F5)
app.post('/playtest/play', async (req, res) => {
  try {
    await sendKeystrokeToStudio(KEY_CODES.F5);
    res.json({ success: true, action: 'play', note: 'Sent F5 to start Play mode' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Stop playtest (Shift+F5 or just F5 toggle)
app.post('/playtest/stop', async (req, res) => {
  try {
    // Shift+F5 is the standard stop shortcut
    await sendKeystrokeToStudio(KEY_CODES.F5, ['shift down']);
    res.json({ success: true, action: 'stop', note: 'Sent Shift+F5 to stop' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Send keyboard input (for character control during playtest)
app.post('/playtest/input', async (req, res) => {
  const { key, duration = 100 } = req.body;

  if (!key || !KEY_CODES[key.toUpperCase()]) {
    return res.status(400).json({
      error: 'Invalid key',
      validKeys: Object.keys(KEY_CODES)
    });
  }

  try {
    const keyCode = KEY_CODES[key.toUpperCase()];

    // For movement keys, we need to hold them
    const script = `
      tell application "Roblox Studio" to activate
      delay 0.1
      tell application "System Events"
        key down (key code ${keyCode})
        delay ${duration / 1000}
        key up (key code ${keyCode})
      end tell
    `;

    await new Promise((resolve, reject) => {
      const proc = spawn('osascript', ['-e', script]);
      proc.on('close', (code) => {
        if (code === 0) resolve();
        else reject(new Error(`osascript failed with code ${code}`));
      });
    });

    res.json({ success: true, key, duration });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ============ Start Server ============

async function start() {
  await ensureDir(REPO_PATH);
  await loadManifest();

  // Initialize MCP DevTools
  setPluginCaller(callPluginTool);
  try {
    await registerAllTools();
    console.log('[Bakable] MCP DevTools initialized');
  } catch (err) {
    console.error('[Bakable] Failed to initialize MCP tools:', err.message);
  }

  if (manifest.scripts.length > 0) {
    startWatcher();
  }

  server.listen(PORT, '127.0.0.1', () => {
    console.log(`\n[Bakable] ========================================`);
    console.log(`[Bakable] Daemon running on http://127.0.0.1:${PORT}`);
    console.log(`[Bakable] WebSocket endpoint: ws://127.0.0.1:${PORT}/ws`);
    console.log(`[Bakable] MCP DevTools: ${getToolSchemas().length} tools available`);
    console.log(`[Bakable] Repo path: ${path.resolve(REPO_PATH)}`);
    console.log(`[Bakable] ========================================`);
    console.log(`[Bakable] AUTH TOKEN: ${AUTH_TOKEN}`);
    console.log(`[Bakable] ========================================\n`);
  });
}

start().catch(console.error);
