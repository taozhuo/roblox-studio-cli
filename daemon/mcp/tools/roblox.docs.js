/**
 * Roblox Docs Tools - Search and read creator documentation
 *
 * Uses SQLite FTS5 for fast, fuzzy full-text search.
 * Run `npm run index-docs` to build/rebuild the index.
 */

import * as kb from './knowledge-base.js';

export function registerDocsTools(registerTool) {
  // roblox.docs.search - Search documentation by keyword
  registerTool('roblox.docs.search', {
    description: `Search Roblox Creator documentation using full-text search.

Supports:
- Prefix matching: "Tween" matches "TweenService", "TweenInfo"
- Multiple terms: "remote event fire" finds docs mentioning all terms
- Ranked results: most relevant docs first

Run 'npm run index-docs' to build/update the search index.`,
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'Search query (e.g., "TweenService", "DataStore GetAsync", "RemoteEvent")'
        },
        category: {
          type: 'string',
          description: 'Optional category filter (e.g., "reference", "tutorials", "cloud")'
        },
        limit: {
          type: 'number',
          description: 'Max results (default: 10)'
        }
      },
      required: ['query']
    }
  }, async ({ query, category, limit = 10 }) => {
    try {
      const results = kb.search(query, {
        source: 'roblox',
        category,
        limit
      });

      if (results.length === 0) {
        const stats = kb.getStats();
        if (stats.total === 0) {
          return {
            error: 'Index is empty. Run: npm run index-docs',
            hint: 'First clone docs: git clone https://github.com/Roblox/creator-docs docs/roblox-creator-docs'
          };
        }
        return { results: [], message: 'No matching documents found' };
      }

      return {
        results: results.map(r => ({
          title: r.title,
          path: r.path,
          category: r.category,
          snippet: r.snippet?.replace(/>>>/g, '**').replace(/<<</g, '**') || ''
        })),
        total: results.length
      };
    } catch (e) {
      return { error: e.message };
    }
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
    try {
      const doc = kb.readDoc(docPath);
      if (!doc) {
        return { error: `Doc not found: ${docPath}` };
      }
      return {
        title: doc.title,
        category: doc.category,
        content: doc.content
      };
    } catch (e) {
      return { error: e.message };
    }
  });

  // roblox.docs.categories - List available doc categories
  registerTool('roblox.docs.categories', {
    description: 'List available documentation categories with document counts',
    inputSchema: {
      type: 'object',
      properties: {}
    }
  }, async () => {
    try {
      const categories = kb.getCategories();
      const stats = kb.getStats();

      return {
        categories,
        total: stats.total,
        lastIndexed: stats.lastIndexed
      };
    } catch (e) {
      return { error: e.message };
    }
  });

  // roblox.docs.reindex - Rebuild the search index
  registerTool('roblox.docs.reindex', {
    description: 'Rebuild the documentation search index. Use this after updating the docs repo.',
    inputSchema: {
      type: 'object',
      properties: {}
    }
  }, async () => {
    try {
      console.log('[MCP] Reindexing Roblox docs...');
      const result = await kb.indexRobloxDocs();
      console.log(`[MCP] Indexed ${result.indexed} docs`);
      return {
        success: true,
        indexed: result.indexed,
        errors: result.errors
      };
    } catch (e) {
      return { error: e.message };
    }
  });
}
