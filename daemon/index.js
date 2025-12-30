#!/usr/bin/env node

import 'dotenv/config';

/**
 * DetAI Local Daemon
 * Hybrid HTTP + WebSocket server for Roblox Studio integration
 * - HTTP for heavy operations (sync, agent runs)
 * - WebSocket for live streaming (logs, progress, notifications)
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
    console.log(`[DetAI] Loaded manifest: ${manifest.scripts.length} scripts, revision ${manifest.revision}`);
  } catch (err) {
    console.log('[DetAI] No existing manifest, starting fresh');
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
  console.log('[DetAI:WS] New connection - auto-accepting');

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
      console.log('[DetAI:WS] Received:', msg.type);
    } catch (err) {
      console.error('[DetAI:WS] Message parse error:', err);
    }
  });

  ws.on('close', () => {
    wsClients.delete(ws);
    console.log('[DetAI:WS] Client disconnected');
  });

  ws.on('error', (err) => {
    console.error('[DetAI:WS] Error:', err);
    wsClients.delete(ws);
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

// ============ Health Check (no auth) ============

app.get('/health', (req, res) => {
  res.json({
    ok: true,
    version: '0.3',
    agentSdkEnabled: true,
    wsEnabled: true
  });
});

// ============ Plugin Log Endpoint ============

app.post('/log', (req, res) => {
  const { level, message } = req.body;
  console.log(`[Studio:${level || 'info'}] ${message}`);
  res.json({ ok: true });
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
    console.error('[DetAI] Failed to write exec.result.txt:', e);
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

    console.log(`[DetAI] Receiving snapshot: ${scripts.length} scripts`);

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

    console.log(`[DetAI] Snapshot written, revision: ${manifest.revision}`);
    res.json({ ok: true, revision: manifest.revision, scriptCount: scripts.length });

  } catch (err) {
    console.error('[DetAI] pushSnapshot error:', err);
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
    console.error('[DetAI] pullChanges error:', err);
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

    console.log(`[DetAI:${runId}] Starting agent task: ${task.substring(0, 100)}...`);

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
      console.error(`[DetAI:${runId}] Agent error:`, err);
      const run = agentRuns.get(runId);
      if (run) {
        run.state = 'error';
        run.error = err.message;
        broadcastRunDone(runId, { success: false, summary: err.message });
      }
    });

    res.json({ ok: true, runId, startedAt });

  } catch (err) {
    console.error('[DetAI] agent/run error:', err);
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
    console.log(`[DetAI:${runId}] Cancel requested`);
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
    console.log(`[DetAI:${runId}] ${message}`);
    // Broadcast log via WebSocket
    broadcastRunLog(runId, log);
  };

  addLog(`Task: ${task}`);
  addLog(`Working directory: ${workDir}`);

  let fullPrompt = task;
  if (scope?.focusFiles?.length > 0) {
    fullPrompt += `\n\nFocus on these files: ${scope.focusFiles.join(', ')}`;
  }
  if (context?.notes) {
    fullPrompt += `\n\nNotes: ${context.notes}`;
  }
  if (context?.selection?.length > 0) {
    fullPrompt += `\n\nSelected instances: ${context.selection.join(', ')}`;
  }

  // System prompt for Roblox Studio interaction
  const systemPrompt = `You are a Roblox Studio AI assistant. You can execute Lua code directly in Roblox Studio.

TO EXECUTE CODE IN ROBLOX STUDIO:
1. Write Lua code to "exec.lua" - it will be automatically executed in Studio
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
1. Write code to exec.lua
2. Wait briefly, then READ exec.result.txt to verify execution
3. If there was an error, fix the code and try again
4. Report success/failure to the user

IMPORTANT:
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
        allowedTools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep'],
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

      // Check for tool usage in assistant messages
      if (message.type === 'assistant' && message.message?.content) {
        for (const block of message.message.content) {
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
    console.log(`[DetAI:${runId}] ${message}`);
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

  console.log(`[DetAI] Starting file watcher on: ${srcPath}`);

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
      console.log(`[DetAI] New file detected: ${filePath}`);
    }
  });
}

async function handleFileChange(absolutePath) {
  try {
    const relativePath = path.relative(REPO_PATH, absolutePath);
    const scriptInfo = manifest.scripts.find(s => s.filePath === relativePath);

    if (!scriptInfo) {
      console.log(`[DetAI] Changed file not in manifest: ${relativePath}`);
      return;
    }

    const text = await fs.readFile(absolutePath, 'utf-8');
    const newHash = computeHash(text);

    if (newHash === scriptInfo.hash) {
      return;
    }

    console.log(`[DetAI] File changed: ${relativePath}`);

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
    console.error('[DetAI] handleFileChange error:', err);
  }
}

// ============ Start Server ============

async function start() {
  await ensureDir(REPO_PATH);
  await loadManifest();

  if (manifest.scripts.length > 0) {
    startWatcher();
  }

  server.listen(PORT, '127.0.0.1', () => {
    console.log(`\n[DetAI] ========================================`);
    console.log(`[DetAI] Daemon running on http://127.0.0.1:${PORT}`);
    console.log(`[DetAI] WebSocket endpoint: ws://127.0.0.1:${PORT}/ws`);
    console.log(`[DetAI] Repo path: ${path.resolve(REPO_PATH)}`);
    console.log(`[DetAI] ========================================`);
    console.log(`[DetAI] AUTH TOKEN: ${AUTH_TOKEN}`);
    console.log(`[DetAI] ========================================\n`);
  });
}

start().catch(console.error);
