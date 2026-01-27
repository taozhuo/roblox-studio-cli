/**
 * Luau LSP Tools - Language server features for Luau/Roblox code
 *
 * Provides: hover, goToDefinition, findReferences, documentSymbol, diagnostics
 */

import { spawn } from 'child_process';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs/promises';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.join(__dirname, '../../..');
const LSP_BIN = path.join(ROOT_DIR, 'bin/luau-lsp');
const TYPES_FILE = path.join(ROOT_DIR, 'types/globalTypes.d.luau');
const DOCS_FILE = path.join(ROOT_DIR, 'types/api-docs.json');

let lspProcess = null;
let requestId = 0;
let pendingRequests = new Map();
let initialized = false;
let buffer = '';

/**
 * Start the LSP server process
 */
async function ensureLspRunning() {
  if (lspProcess && !lspProcess.killed) {
    return;
  }

  // Check if binary exists
  try {
    await fs.access(LSP_BIN);
  } catch {
    throw new Error(`luau-lsp not found at ${LSP_BIN}. Run: scripts/install-luau-lsp.sh`);
  }

  const args = ['lsp', '--stdio'];

  // Add type definitions if available
  try {
    await fs.access(TYPES_FILE);
    args.push(`--definitions=@roblox=${TYPES_FILE}`);
  } catch {}

  try {
    await fs.access(DOCS_FILE);
    args.push(`--docs=${DOCS_FILE}`);
  } catch {}

  lspProcess = spawn(LSP_BIN, args, {
    cwd: ROOT_DIR,
    stdio: ['pipe', 'pipe', 'pipe']
  });

  lspProcess.stdout.on('data', (data) => {
    buffer += data.toString();
    processBuffer();
  });

  lspProcess.stderr.on('data', (data) => {
    console.error('[luau-lsp]', data.toString());
  });

  lspProcess.on('exit', (code) => {
    console.error('[luau-lsp] exited with code', code);
    lspProcess = null;
    initialized = false;
  });

  // Initialize
  await sendRequest('initialize', {
    processId: process.pid,
    capabilities: {},
    rootUri: `file://${ROOT_DIR}`,
    initializationOptions: {
      platform: { type: 'roblox' }
    }
  });

  sendNotification('initialized', {});
  initialized = true;
}

function processBuffer() {
  while (true) {
    const headerEnd = buffer.indexOf('\r\n\r\n');
    if (headerEnd === -1) return;

    const header = buffer.slice(0, headerEnd);
    const contentLengthMatch = header.match(/Content-Length: (\d+)/);
    if (!contentLengthMatch) {
      buffer = buffer.slice(headerEnd + 4);
      continue;
    }

    const contentLength = parseInt(contentLengthMatch[1]);
    const messageStart = headerEnd + 4;
    const messageEnd = messageStart + contentLength;

    if (buffer.length < messageEnd) return;

    const message = buffer.slice(messageStart, messageEnd);
    buffer = buffer.slice(messageEnd);

    try {
      const json = JSON.parse(message);
      if (json.id !== undefined && pendingRequests.has(json.id)) {
        const { resolve, reject } = pendingRequests.get(json.id);
        pendingRequests.delete(json.id);
        if (json.error) {
          reject(new Error(json.error.message));
        } else {
          resolve(json.result);
        }
      }
    } catch (e) {
      console.error('[luau-lsp] parse error:', e);
    }
  }
}

function sendRequest(method, params) {
  return new Promise((resolve, reject) => {
    const id = ++requestId;
    pendingRequests.set(id, { resolve, reject });

    const message = JSON.stringify({ jsonrpc: '2.0', id, method, params });
    const packet = `Content-Length: ${Buffer.byteLength(message)}\r\n\r\n${message}`;
    lspProcess.stdin.write(packet);

    // Timeout after 10s
    setTimeout(() => {
      if (pendingRequests.has(id)) {
        pendingRequests.delete(id);
        reject(new Error('LSP request timeout'));
      }
    }, 10000);
  });
}

function sendNotification(method, params) {
  const message = JSON.stringify({ jsonrpc: '2.0', method, params });
  const packet = `Content-Length: ${Buffer.byteLength(message)}\r\n\r\n${message}`;
  lspProcess.stdin.write(packet);
}

/**
 * Open a document in the LSP
 */
async function openDocument(filePath) {
  const uri = `file://${filePath}`;
  const content = await fs.readFile(filePath, 'utf-8');

  sendNotification('textDocument/didOpen', {
    textDocument: {
      uri,
      languageId: 'luau',
      version: 1,
      text: content
    }
  });

  return uri;
}

export function registerLspTools(registerTool) {

  // luau.lsp.hover - Get type info and documentation
  registerTool('luau.lsp.hover', {
    description: 'Get type information and documentation for a symbol at a position in Luau code',
    inputSchema: {
      type: 'object',
      properties: {
        filePath: {
          type: 'string',
          description: 'Absolute path to the Luau file'
        },
        line: {
          type: 'number',
          description: 'Line number (1-based)'
        },
        character: {
          type: 'number',
          description: 'Character offset (1-based)'
        }
      },
      required: ['filePath', 'line', 'character']
    }
  }, async ({ filePath, line, character }) => {
    try {
      await ensureLspRunning();
      const uri = await openDocument(filePath);

      const result = await sendRequest('textDocument/hover', {
        textDocument: { uri },
        position: { line: line - 1, character: character - 1 }
      });

      if (!result) {
        return { hover: null, message: 'No information available' };
      }

      return {
        contents: result.contents?.value || result.contents,
        range: result.range
      };
    } catch (e) {
      return { error: e.message };
    }
  });

  // luau.lsp.definition - Go to definition
  registerTool('luau.lsp.definition', {
    description: 'Find where a symbol is defined',
    inputSchema: {
      type: 'object',
      properties: {
        filePath: { type: 'string', description: 'Absolute path to the Luau file' },
        line: { type: 'number', description: 'Line number (1-based)' },
        character: { type: 'number', description: 'Character offset (1-based)' }
      },
      required: ['filePath', 'line', 'character']
    }
  }, async ({ filePath, line, character }) => {
    try {
      await ensureLspRunning();
      const uri = await openDocument(filePath);

      const result = await sendRequest('textDocument/definition', {
        textDocument: { uri },
        position: { line: line - 1, character: character - 1 }
      });

      if (!result || (Array.isArray(result) && result.length === 0)) {
        return { definitions: [], message: 'No definition found' };
      }

      const locations = Array.isArray(result) ? result : [result];
      return {
        definitions: locations.map(loc => ({
          uri: loc.uri || loc.targetUri,
          range: loc.range || loc.targetRange
        }))
      };
    } catch (e) {
      return { error: e.message };
    }
  });

  // luau.lsp.references - Find all references
  registerTool('luau.lsp.references', {
    description: 'Find all references to a symbol',
    inputSchema: {
      type: 'object',
      properties: {
        filePath: { type: 'string', description: 'Absolute path to the Luau file' },
        line: { type: 'number', description: 'Line number (1-based)' },
        character: { type: 'number', description: 'Character offset (1-based)' },
        includeDeclaration: { type: 'boolean', description: 'Include the declaration (default: true)' }
      },
      required: ['filePath', 'line', 'character']
    }
  }, async ({ filePath, line, character, includeDeclaration = true }) => {
    try {
      await ensureLspRunning();
      const uri = await openDocument(filePath);

      const result = await sendRequest('textDocument/references', {
        textDocument: { uri },
        position: { line: line - 1, character: character - 1 },
        context: { includeDeclaration }
      });

      return {
        references: (result || []).map(loc => ({
          uri: loc.uri,
          range: loc.range
        })),
        count: result?.length || 0
      };
    } catch (e) {
      return { error: e.message };
    }
  });

  // luau.lsp.symbols - Get document symbols
  registerTool('luau.lsp.symbols', {
    description: 'List all symbols (functions, variables, types) in a Luau file',
    inputSchema: {
      type: 'object',
      properties: {
        filePath: { type: 'string', description: 'Absolute path to the Luau file' }
      },
      required: ['filePath']
    }
  }, async ({ filePath }) => {
    try {
      await ensureLspRunning();
      const uri = await openDocument(filePath);

      const result = await sendRequest('textDocument/documentSymbol', {
        textDocument: { uri }
      });

      const flattenSymbols = (symbols, parent = null) => {
        let flat = [];
        for (const sym of symbols || []) {
          flat.push({
            name: sym.name,
            kind: symbolKindToString(sym.kind),
            range: sym.range || sym.location?.range,
            parent: parent
          });
          if (sym.children) {
            flat = flat.concat(flattenSymbols(sym.children, sym.name));
          }
        }
        return flat;
      };

      return { symbols: flattenSymbols(result) };
    } catch (e) {
      return { error: e.message };
    }
  });

  // luau.lsp.diagnostics - Get type errors and warnings
  registerTool('luau.lsp.diagnostics', {
    description: 'Get type errors, warnings, and lints for a Luau file',
    inputSchema: {
      type: 'object',
      properties: {
        filePath: { type: 'string', description: 'Absolute path to the Luau file' }
      },
      required: ['filePath']
    }
  }, async ({ filePath }) => {
    try {
      // Use analyze subcommand for diagnostics (simpler than LSP)
      const args = ['analyze', filePath];

      try {
        await fs.access(TYPES_FILE);
        args.push(`--definitions=@roblox=${TYPES_FILE}`);
      } catch {}

      return new Promise((resolve) => {
        const proc = spawn(LSP_BIN, args, { cwd: ROOT_DIR });
        let output = '';
        let errors = '';

        proc.stdout.on('data', (d) => output += d);
        proc.stderr.on('data', (d) => errors += d);

        proc.on('close', (code) => {
          const diagnostics = [];
          const lines = (output + errors).split('\n').filter(Boolean);

          for (const line of lines) {
            const match = line.match(/^(.+?)\((\d+),(\d+)\): (\w+): (.+)$/);
            if (match) {
              diagnostics.push({
                file: match[1],
                line: parseInt(match[2]),
                character: parseInt(match[3]),
                severity: match[4],
                message: match[5]
              });
            }
          }

          resolve({
            diagnostics,
            count: diagnostics.length,
            hasErrors: diagnostics.some(d => d.severity === 'TypeError' || d.severity === 'SyntaxError')
          });
        });
      });
    } catch (e) {
      return { error: e.message };
    }
  });
}

function symbolKindToString(kind) {
  const kinds = {
    1: 'File', 2: 'Module', 3: 'Namespace', 4: 'Package', 5: 'Class',
    6: 'Method', 7: 'Property', 8: 'Field', 9: 'Constructor', 10: 'Enum',
    11: 'Interface', 12: 'Function', 13: 'Variable', 14: 'Constant',
    15: 'String', 16: 'Number', 17: 'Boolean', 18: 'Array', 19: 'Object',
    20: 'Key', 21: 'Null', 22: 'EnumMember', 23: 'Struct', 24: 'Event',
    25: 'Operator', 26: 'TypeParameter'
  };
  return kinds[kind] || 'Unknown';
}
