#!/usr/bin/env node

import { program } from 'commander';
import WebSocket from 'ws';
import chalk from 'chalk';
import { exec } from 'child_process';

const PORT = process.env.STUDIOCTL_PORT || 4848;
const TOKEN = process.env.STUDIOCTL_TOKEN || '';
const SERVER_URL = `ws://127.0.0.1:${PORT}`;

// Format timestamp
function timestamp() {
  return chalk.gray(new Date().toLocaleTimeString());
}

// Format log level
function formatLevel(level) {
  switch (level) {
    case 'Error': return chalk.red('[ERROR]');
    case 'Warning': return chalk.yellow('[WARN]');
    case 'Info': return chalk.blue('[INFO]');
    case 'Output': return chalk.white('[OUT]');
    default: return chalk.gray(`[${level}]`);
  }
}

// Connect to server and return promise
function connect(options = {}) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(SERVER_URL);
    let resolved = false;

    ws.on('open', () => {
      // Authenticate
      const auth = { role: 'cli' };
      if (TOKEN) auth.token = TOKEN;
      ws.send(JSON.stringify(auth));
    });

    ws.on('message', (data) => {
      const message = JSON.parse(data.toString());

      if (message.type === 'welcome' && !resolved) {
        resolved = true;
        resolve({ ws, studioConnected: message.studio === 'connected' });
      } else if (message.type === 'error' && !resolved) {
        resolved = true;
        reject(new Error(message.error));
      }

      // Call message handler if provided
      if (options.onMessage) {
        options.onMessage(message);
      }
    });

    ws.on('error', (err) => {
      if (!resolved) {
        resolved = true;
        reject(err);
      }
    });

    ws.on('close', () => {
      if (options.onClose) {
        options.onClose();
      }
    });

    // Timeout
    setTimeout(() => {
      if (!resolved) {
        resolved = true;
        ws.close();
        reject(new Error('Connection timeout'));
      }
    }, 5000);
  });
}

// Send command and wait for result
async function sendCommand(cmd, payload = {}) {
  return new Promise(async (resolve, reject) => {
    try {
      let resultReceived = false;

      const { ws, studioConnected } = await connect({
        onMessage: (message) => {
          if (message.type === 'result' && message.cmd === cmd) {
            resultReceived = true;
            ws.close();
            resolve(message);
          } else if (message.type === 'error' && message.cmd === cmd) {
            resultReceived = true;
            ws.close();
            reject(new Error(message.error));
          }
        }
      });

      if (!studioConnected) {
        ws.close();
        reject(new Error('Studio is not connected'));
        return;
      }

      // Send command with payload
      ws.send(JSON.stringify({ type: 'cmd', cmd, ...payload }));

      // Timeout for result
      setTimeout(() => {
        if (!resultReceived) {
          ws.close();
          reject(new Error('Command timeout - no response from Studio'));
        }
      }, 10000);

    } catch (err) {
      reject(err);
    }
  });
}

// CLI setup
program
  .name('studioctl')
  .description('Control Roblox Studio from the terminal')
  .version('0.1.0');

// Status command
program
  .command('status')
  .description('Check connection status')
  .action(async () => {
    try {
      const { ws, studioConnected } = await connect();
      ws.close();

      console.log(chalk.green('✓ Server is running'));
      if (studioConnected) {
        console.log(chalk.green('✓ Studio is connected'));
      } else {
        console.log(chalk.yellow('⚠ Studio is not connected'));
      }
    } catch (err) {
      console.log(chalk.red('✗ Server is not running'));
      console.log(chalk.gray(`  Start with: npm run server`));
      process.exit(1);
    }
  });

// Run command
program
  .command('run')
  .description('Start server simulation (RunService:Run)')
  .action(async () => {
    try {
      console.log(timestamp(), 'Starting simulation...');
      const result = await sendCommand('run');

      if (result.ok) {
        console.log(timestamp(), chalk.green('✓ Simulation started'));
      } else {
        console.log(timestamp(), chalk.red('✗ Failed:'), result.info);
        process.exit(1);
      }
    } catch (err) {
      console.log(timestamp(), chalk.red('✗ Error:'), err.message);
      process.exit(1);
    }
  });

// Stop command
program
  .command('stop')
  .description('Stop simulation (RunService:Stop)')
  .action(async () => {
    try {
      console.log(timestamp(), 'Stopping simulation...');
      const result = await sendCommand('stop');

      if (result.ok) {
        console.log(timestamp(), chalk.green('✓ Simulation stopped'));
      } else {
        console.log(timestamp(), chalk.red('✗ Failed:'), result.info);
        process.exit(1);
      }
    } catch (err) {
      console.log(timestamp(), chalk.red('✗ Error:'), err.message);
      process.exit(1);
    }
  });

// Pause command
program
  .command('pause')
  .description('Pause simulation (RunService:Pause)')
  .action(async () => {
    try {
      console.log(timestamp(), 'Pausing simulation...');
      const result = await sendCommand('pause');

      if (result.ok) {
        console.log(timestamp(), chalk.green('✓ Simulation paused'));
      } else {
        console.log(timestamp(), chalk.red('✗ Failed:'), result.info);
        process.exit(1);
      }
    } catch (err) {
      console.log(timestamp(), chalk.red('✗ Error:'), err.message);
      process.exit(1);
    }
  });

// Ping command
program
  .command('ping')
  .description('Ping Studio plugin')
  .action(async () => {
    try {
      const start = Date.now();
      const result = await sendCommand('ping');
      const latency = Date.now() - start;

      if (result.ok) {
        console.log(chalk.green('✓ pong'), chalk.gray(`(${latency}ms)`));
      } else {
        console.log(chalk.red('✗ Failed'));
        process.exit(1);
      }
    } catch (err) {
      console.log(chalk.red('✗ Error:'), err.message);
      process.exit(1);
    }
  });

// Logs command
program
  .command('logs')
  .description('Stream logs from Studio')
  .option('-f, --follow', 'Keep streaming (default)', true)
  .action(async (options) => {
    try {
      console.log(timestamp(), 'Connecting to log stream...');

      const { ws, studioConnected } = await connect({
        onMessage: (message) => {
          if (message.type === 'log') {
            console.log(
              timestamp(),
              formatLevel(message.level),
              message.text
            );
          } else if (message.type === 'status') {
            if (message.studio === 'connected') {
              console.log(timestamp(), chalk.green('● Studio connected'));
            } else {
              console.log(timestamp(), chalk.yellow('○ Studio disconnected'));
            }
          } else if (message.type === 'result') {
            console.log(
              timestamp(),
              chalk.cyan(`[CMD:${message.cmd}]`),
              message.ok ? chalk.green('OK') : chalk.red('FAIL'),
              message.info || ''
            );
          }
        },
        onClose: () => {
          console.log(timestamp(), chalk.gray('Connection closed'));
          process.exit(0);
        }
      });

      if (studioConnected) {
        console.log(timestamp(), chalk.green('● Studio is connected'));
      } else {
        console.log(timestamp(), chalk.yellow('○ Waiting for Studio...'));
      }

      console.log(timestamp(), chalk.gray('Streaming logs (Ctrl+C to exit)'));

      // Keep process alive
      process.on('SIGINT', () => {
        console.log('\n' + timestamp(), chalk.gray('Closing...'));
        ws.close();
        process.exit(0);
      });

    } catch (err) {
      console.log(chalk.red('✗ Error:'), err.message);
      process.exit(1);
    }
  });

// Open command
program
  .command('open')
  .description('Open a place file in Roblox Studio')
  .argument('<file>', 'Path to .rbxl or .rbxlx file')
  .action(async (file) => {
    console.log(timestamp(), 'Opening in Roblox Studio:', file);

    exec(`open -a "RobloxStudio" "${file}"`, (err) => {
      if (err) {
        console.log(chalk.red('✗ Failed to open Studio:'), err.message);
        process.exit(1);
      }
      console.log(timestamp(), chalk.green('✓ Studio launched'));
    });
  });

// Exec command
program
  .command('exec')
  .description('Execute Lua code in Studio')
  .argument('<code>', 'Lua code to execute')
  .action(async (code) => {
    try {
      console.log(timestamp(), 'Executing code...');
      const result = await sendCommand('exec', { code });

      if (result.ok) {
        console.log(timestamp(), chalk.green('✓ Executed'));
        if (result.info && result.info !== 'nil') {
          console.log(chalk.cyan('Result:'), result.info);
        }
      } else {
        console.log(timestamp(), chalk.red('✗ Failed:'), result.info);
        process.exit(1);
      }
    } catch (err) {
      console.log(timestamp(), chalk.red('✗ Error:'), err.message);
      process.exit(1);
    }
  });

// List scripts command
program
  .command('list-scripts')
  .description('List all scripts in the place')
  .option('-t, --type <type>', 'Filter by type: server, local, module')
  .action(async (options) => {
    try {
      const result = await sendCommand('list-scripts', { filter: options.type });

      if (result.ok) {
        const scripts = JSON.parse(result.info);
        if (scripts.length === 0) {
          console.log(chalk.yellow('No scripts found'));
        } else {
          console.log(chalk.cyan(`Found ${scripts.length} script(s):\n`));
          for (const s of scripts) {
            const typeColor = s.type === 'server' ? chalk.blue : s.type === 'local' ? chalk.green : chalk.magenta;
            console.log(`  ${typeColor(`[${s.type}]`)} ${s.path}`);
          }
        }
      } else {
        console.log(chalk.red('✗ Failed:'), result.info);
        process.exit(1);
      }
    } catch (err) {
      console.log(chalk.red('✗ Error:'), err.message);
      process.exit(1);
    }
  });

// Get source command
program
  .command('get-source')
  .description('Get script source code')
  .argument('<path>', 'Script path (e.g., ServerScriptService.MyScript)')
  .action(async (path) => {
    try {
      const result = await sendCommand('get-source', { path });

      if (result.ok) {
        console.log(result.info);
      } else {
        console.log(chalk.red('✗ Failed:'), result.info);
        process.exit(1);
      }
    } catch (err) {
      console.log(chalk.red('✗ Error:'), err.message);
      process.exit(1);
    }
  });

// Set source command
program
  .command('set-source')
  .description('Set script source code')
  .argument('<path>', 'Script path (e.g., ServerScriptService.MyScript)')
  .option('-c, --code <code>', 'Source code')
  .option('-f, --file <file>', 'Read code from file')
  .action(async (path, options) => {
    try {
      let source = options.code;

      if (options.file) {
        const fs = await import('fs');
        source = fs.default.readFileSync(options.file, 'utf-8');
      }

      if (!source) {
        console.log(chalk.red('✗ No source provided. Use -c or -f'));
        process.exit(1);
      }

      console.log(timestamp(), `Updating ${path}...`);
      const result = await sendCommand('set-source', { path, source });

      if (result.ok) {
        console.log(timestamp(), chalk.green('✓ Source updated'));
      } else {
        console.log(timestamp(), chalk.red('✗ Failed:'), result.info);
        process.exit(1);
      }
    } catch (err) {
      console.log(timestamp(), chalk.red('✗ Error:'), err.message);
      process.exit(1);
    }
  });

// Patch command
program
  .command('patch')
  .description('Find and replace in script')
  .argument('<path>', 'Script path')
  .requiredOption('--find <pattern>', 'Pattern to find')
  .option('--replace <text>', 'Replacement text', '')
  .action(async (path, options) => {
    try {
      console.log(timestamp(), `Patching ${path}...`);
      const result = await sendCommand('patch', {
        path,
        find: options.find,
        replace: options.replace
      });

      if (result.ok) {
        const info = JSON.parse(result.info);
        console.log(timestamp(), chalk.green(`✓ Replaced ${info.replaced} occurrence(s)`));
      } else {
        console.log(timestamp(), chalk.red('✗ Failed:'), result.info);
        process.exit(1);
      }
    } catch (err) {
      console.log(timestamp(), chalk.red('✗ Error:'), err.message);
      process.exit(1);
    }
  });

// Insert script command
program
  .command('insert-script')
  .description('Insert a new script')
  .argument('<name>', 'Script name')
  .option('-p, --parent <path>', 'Parent path', 'ServerScriptService')
  .option('-c, --code <code>', 'Script source code', '')
  .option('-f, --file <file>', 'Read code from file')
  .option('-t, --type <type>', 'Script type: server, local, module', 'server')
  .action(async (name, options) => {
    try {
      let source = options.code;

      if (options.file) {
        const fs = await import('fs');
        source = fs.default.readFileSync(options.file, 'utf-8');
      }

      console.log(timestamp(), `Inserting ${options.type} script: ${name}`);
      const result = await sendCommand('insert-script', {
        name,
        parent: options.parent,
        source,
        scriptType: options.type
      });

      if (result.ok) {
        console.log(timestamp(), chalk.green(`✓ Created ${result.info}`));
      } else {
        console.log(timestamp(), chalk.red('✗ Failed:'), result.info);
        process.exit(1);
      }
    } catch (err) {
      console.log(timestamp(), chalk.red('✗ Error:'), err.message);
      process.exit(1);
    }
  });

// Get instance command
program
  .command('get-instance')
  .description('Get instance info and children')
  .argument('<path>', 'Instance path')
  .action(async (path) => {
    try {
      const result = await sendCommand('get-instance', { path });

      if (result.ok) {
        const info = JSON.parse(result.info);
        console.log(chalk.cyan('Path:'), info.path);
        console.log(chalk.cyan('Class:'), info.className);
        if (info.children.length > 0) {
          console.log(chalk.cyan('\nChildren:'));
          for (const child of info.children) {
            console.log(`  ${chalk.gray(child.className)} ${child.name}`);
          }
        }
      } else {
        console.log(chalk.red('✗ Failed:'), result.info);
        process.exit(1);
      }
    } catch (err) {
      console.log(chalk.red('✗ Error:'), err.message);
      process.exit(1);
    }
  });

program.parse();
