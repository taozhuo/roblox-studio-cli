import { WebSocketServer } from 'ws';
import { createServer } from 'http';

const PORT = process.env.STUDIOCTL_PORT || 4848;
const TOKEN = process.env.STUDIOCTL_TOKEN || '';

const server = createServer();
const wss = new WebSocketServer({ server });

// State
let studioSocket = null;
const cliSockets = new Set();

// Broadcast to all CLI clients
function broadcastToCLIs(message) {
  const data = typeof message === 'string' ? message : JSON.stringify(message);
  for (const ws of cliSockets) {
    if (ws.readyState === 1) {
      ws.send(data);
    }
  }
}

// Send to Studio
function sendToStudio(message) {
  if (studioSocket && studioSocket.readyState === 1) {
    const data = typeof message === 'string' ? message : JSON.stringify(message);
    studioSocket.send(data);
    return true;
  }
  return false;
}

// Log with timestamp
function log(msg) {
  console.log(`[${new Date().toISOString()}] ${msg}`);
}

wss.on('connection', (ws) => {
  let role = null;
  let authenticated = !TOKEN; // If no token, auto-authenticate

  ws.on('message', (data) => {
    let message;
    try {
      message = JSON.parse(data.toString());
    } catch (e) {
      log(`Invalid JSON: ${data.toString().slice(0, 100)}`);
      return;
    }

    // Handle role identification
    if (message.role && !role) {
      // Check token if required
      if (TOKEN && message.token !== TOKEN) {
        ws.send(JSON.stringify({ type: 'error', error: 'unauthorized' }));
        ws.close();
        return;
      }
      authenticated = true;

      if (message.role === 'studio') {
        if (studioSocket) {
          log('Another Studio tried to connect, rejecting');
          ws.send(JSON.stringify({ type: 'error', error: 'studio_already_connected' }));
          ws.close();
          return;
        }
        role = 'studio';
        studioSocket = ws;
        log('Studio connected');
        broadcastToCLIs({ type: 'status', studio: 'connected' });
        ws.send(JSON.stringify({ type: 'welcome', role: 'studio' }));
      } else if (message.role === 'cli') {
        role = 'cli';
        cliSockets.add(ws);
        log(`CLI connected (total: ${cliSockets.size})`);
        ws.send(JSON.stringify({
          type: 'welcome',
          role: 'cli',
          studio: studioSocket ? 'connected' : 'disconnected'
        }));
      }
      return;
    }

    if (!authenticated) {
      ws.send(JSON.stringify({ type: 'error', error: 'not_authenticated' }));
      return;
    }

    // Route messages based on role
    if (role === 'cli') {
      // CLI sends commands to Studio
      if (message.type === 'cmd') {
        log(`CLI -> Studio: ${message.cmd}`);
        if (!sendToStudio(message)) {
          ws.send(JSON.stringify({
            type: 'error',
            error: 'studio_not_connected',
            cmd: message.cmd
          }));
        }
      }
    } else if (role === 'studio') {
      // Studio sends logs/results to all CLIs
      if (message.type === 'log') {
        const preview = message.text?.slice(0, 80) || '';
        log(`[Log:${message.level}] ${preview}`);
      } else if (message.type === 'result') {
        log(`[Result] ${message.cmd}: ${message.ok ? 'OK' : 'FAIL'}`);
      }
      broadcastToCLIs(message);
    }
  });

  ws.on('close', () => {
    if (role === 'studio') {
      log('Studio disconnected');
      studioSocket = null;
      broadcastToCLIs({ type: 'status', studio: 'disconnected' });
    } else if (role === 'cli') {
      cliSockets.delete(ws);
      log(`CLI disconnected (remaining: ${cliSockets.size})`);
    }
  });

  ws.on('error', (err) => {
    log(`Socket error (${role || 'unknown'}): ${err.message}`);
  });
});

server.listen(PORT, '127.0.0.1', () => {
  log('='.repeat(50));
  log('studioctl-server started');
  log(`WebSocket: ws://127.0.0.1:${PORT}`);
  log(TOKEN ? 'Token authentication: ENABLED' : 'Token authentication: disabled');
  log('='.repeat(50));
});
