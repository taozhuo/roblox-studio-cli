/**
 * Roblox Docs Tools - Search and read creator documentation
 */

import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DOCS_PATH = path.join(__dirname, '../../../docs/roblox-creator-docs/content/en-us');

// Simple index cache
let docsIndex = null;

async function buildIndex() {
  if (docsIndex) return docsIndex;

  docsIndex = [];

  async function walkDir(dir, category = '') {
    try {
      const entries = await fs.readdir(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          await walkDir(fullPath, category ? `${category}/${entry.name}` : entry.name);
        } else if (entry.name.endsWith('.md')) {
          const content = await fs.readFile(fullPath, 'utf-8');
          // Extract title from frontmatter or first heading
          const titleMatch = content.match(/^title:\s*(.+)$/m) || content.match(/^#\s+(.+)$/m);
          const title = titleMatch ? titleMatch[1].trim() : entry.name.replace('.md', '');

          docsIndex.push({
            path: fullPath,
            relativePath: `${category}/${entry.name}`,
            title,
            category,
            // Store first 500 chars for preview
            preview: content.slice(0, 500).replace(/---[\s\S]*?---/, '').trim()
          });
        }
      }
    } catch (e) {
      // Directory might not exist
    }
  }

  await walkDir(DOCS_PATH);
  console.log(`[MCP] Indexed ${docsIndex.length} Roblox docs`);
  return docsIndex;
}

export function registerDocsTools(registerTool) {
  // roblox.docs.search - Search documentation by keyword
  registerTool('roblox.docs.search', {
    description: 'Search Roblox Creator documentation by keyword. Returns matching docs with titles and paths.',
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Search query (e.g., "TweenService", "DataStore", "RemoteEvent")'
        },
        category: {
          type: 'string',
          description: 'Optional category filter (e.g., "reference", "tutorials", "scripting")'
        },
        limit: {
          type: 'number',
          description: 'Max results (default: 10)'
        }
      },
      required: ['query']
    }
  }, async ({ query, category, limit = 10 }) => {
    const index = await buildIndex();
    if (index.length === 0) {
      return { error: 'Docs not found. Clone https://github.com/Roblox/creator-docs to docs/roblox-creator-docs/' };
    }

    const queryLower = query.toLowerCase();
    const results = index
      .filter(doc => {
        if (category && !doc.category.toLowerCase().includes(category.toLowerCase())) {
          return false;
        }
        return doc.title.toLowerCase().includes(queryLower) ||
               doc.relativePath.toLowerCase().includes(queryLower) ||
               doc.preview.toLowerCase().includes(queryLower);
      })
      .slice(0, limit)
      .map(doc => ({
        title: doc.title,
        path: doc.relativePath,
        category: doc.category,
        preview: doc.preview.slice(0, 200) + '...'
      }));

    return { results, total: results.length };
  });

  // roblox.docs.read - Read a specific doc file
  registerTool('roblox.docs.read', {
    description: 'Read a Roblox documentation file by path. Use roblox.docs.search first to find paths.',
    inputSchema: {
      type: 'object',
      properties: {
        docPath: {
          type: 'string',
          description: 'Doc path from search results (e.g., "reference/engine/classes/TweenService.md")'
        }
      },
      required: ['docPath']
    }
  }, async ({ docPath }) => {
    const fullPath = path.join(DOCS_PATH, docPath);
    try {
      const content = await fs.readFile(fullPath, 'utf-8');
      // Remove frontmatter for cleaner output
      const cleaned = content.replace(/^---[\s\S]*?---\n*/, '');
      return { content: cleaned };
    } catch (e) {
      return { error: `Doc not found: ${docPath}` };
    }
  });

  // roblox.docs.categories - List available doc categories
  registerTool('roblox.docs.categories', {
    description: 'List available documentation categories',
    inputSchema: {
      type: 'object',
      properties: {}
    }
  }, async () => {
    const index = await buildIndex();
    const categories = [...new Set(index.map(d => d.category.split('/')[0]).filter(Boolean))];
    return { categories };
  });
}
