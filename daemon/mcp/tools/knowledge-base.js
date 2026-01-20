/**
 * Knowledge Base - SQLite FTS5 powered documentation search
 *
 * Features:
 * - Full-text search with ranking
 * - Fuzzy matching via FTS5 prefix/phrase queries
 * - Persistent index (survives restarts)
 * - Fast search (~1ms for 10k docs)
 */

import Database from 'better-sqlite3';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import yaml from 'js-yaml';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DB_PATH = path.join(__dirname, '../../../data/knowledge-base.db');
const DOCS_PATH = path.join(__dirname, '../../../docs/roblox-creator-docs/content/en-us');

let db = null;

/**
 * Initialize the database connection
 */
export function getDb() {
  if (db) return db;

  // Ensure data directory exists
  const dataDir = path.dirname(DB_PATH);
  fs.mkdir(dataDir, { recursive: true }).catch(() => {});

  db = new Database(DB_PATH);

  // Create FTS5 virtual table if not exists
  db.exec(`
    CREATE VIRTUAL TABLE IF NOT EXISTS docs USING fts5(
      title,
      path,
      category,
      content,
      source,
      tokenize='porter unicode61'
    );

    CREATE TABLE IF NOT EXISTS docs_meta (
      key TEXT PRIMARY KEY,
      value TEXT
    );
  `);

  return db;
}

/**
 * Index a single document
 */
export function indexDoc(doc) {
  const db = getDb();
  const stmt = db.prepare(`
    INSERT INTO docs (title, path, category, content, source)
    VALUES (?, ?, ?, ?, ?)
  `);
  stmt.run(doc.title, doc.path, doc.category, doc.content, doc.source || 'roblox');
}

/**
 * Clear all docs from a source
 */
export function clearSource(source) {
  const db = getDb();
  db.prepare(`DELETE FROM docs WHERE source = ?`).run(source);
}

/**
 * Search documents using FTS5
 *
 * @param {string} query - Search query
 * @param {object} options - Search options
 * @returns {Array} Search results with snippets
 */
export function search(query, options = {}) {
  const db = getDb();
  const { source, category, limit = 10 } = options;

  // Build FTS5 query - support prefix matching with *
  let ftsQuery = query
    .split(/\s+/)
    .filter(Boolean)
    .map(term => `"${term}"*`)  // Prefix match each term
    .join(' ');

  if (!ftsQuery) return [];

  let sql = `
    SELECT
      title,
      path,
      category,
      source,
      snippet(docs, 3, '>>>', '<<<', '...', 64) as snippet,
      rank
    FROM docs
    WHERE docs MATCH ?
  `;

  const params = [ftsQuery];

  if (source) {
    sql += ` AND source = ?`;
    params.push(source);
  }

  if (category) {
    sql += ` AND category LIKE ?`;
    params.push(`%${category}%`);
  }

  sql += ` ORDER BY rank LIMIT ?`;
  params.push(limit);

  try {
    return db.prepare(sql).all(...params);
  } catch (e) {
    // If FTS query syntax error, try simple LIKE fallback
    console.error('[KB] FTS error, falling back to LIKE:', e.message);
    return db.prepare(`
      SELECT title, path, category, source, substr(content, 1, 200) as snippet
      FROM docs
      WHERE title LIKE ? OR content LIKE ?
      LIMIT ?
    `).all(`%${query}%`, `%${query}%`, limit);
  }
}

/**
 * Read full document content by path
 */
export function readDoc(docPath) {
  const db = getDb();
  const row = db.prepare(`SELECT * FROM docs WHERE path = ?`).get(docPath);
  return row;
}

/**
 * Get index statistics
 */
export function getStats() {
  const db = getDb();
  const total = db.prepare(`SELECT COUNT(*) as count FROM docs`).get();
  const bySource = db.prepare(`
    SELECT source, COUNT(*) as count
    FROM docs
    GROUP BY source
  `).all();
  const lastIndexed = db.prepare(`
    SELECT value FROM docs_meta WHERE key = 'last_indexed'
  `).get();

  return {
    total: total.count,
    bySource,
    lastIndexed: lastIndexed?.value
  };
}

/**
 * Index Roblox creator docs from local clone
 */
export async function indexRobloxDocs(progressCallback) {
  const db = getDb();

  // Clear existing Roblox docs
  clearSource('roblox');

  let indexed = 0;
  let errors = 0;

  async function walkDir(dir, category = '') {
    try {
      const entries = await fs.readdir(dir, { withFileTypes: true });

      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);

        if (entry.isDirectory()) {
          await walkDir(fullPath, category ? `${category}/${entry.name}` : entry.name);
        } else if (entry.name.endsWith('.md')) {
          try {
            const content = await fs.readFile(fullPath, 'utf-8');

            // Extract title from frontmatter or first heading
            const titleMatch = content.match(/^title:\s*["']?(.+?)["']?\s*$/m) ||
                              content.match(/^#\s+(.+)$/m);
            const title = titleMatch ? titleMatch[1].trim() : entry.name.replace('.md', '');

            // Remove frontmatter for cleaner content
            const cleanContent = content.replace(/^---[\s\S]*?---\n*/, '');

            const relativePath = `${category}/${entry.name}`;

            indexDoc({
              title,
              path: relativePath,
              category: category.split('/')[0] || 'general',
              content: cleanContent,
              source: 'roblox'
            });

            indexed++;

            if (progressCallback && indexed % 100 === 0) {
              progressCallback({ indexed, errors });
            }
          } catch (e) {
            errors++;
          }
        } else if (entry.name.endsWith('.yaml')) {
          // Handle YAML API reference files
          try {
            const content = await fs.readFile(fullPath, 'utf-8');
            const data = yaml.load(content);

            if (data && data.name) {
              // Build searchable content from YAML structure
              let searchContent = `${data.name}\n`;
              if (data.summary) searchContent += `${data.summary}\n`;
              if (data.description) searchContent += `${data.description}\n`;

              // Add methods
              if (data.methods) {
                for (const method of data.methods) {
                  searchContent += `${method.name}\n`;
                  if (method.summary) searchContent += `${method.summary}\n`;
                  if (method.description) searchContent += `${method.description}\n`;
                }
              }

              // Add properties
              if (data.properties) {
                for (const prop of data.properties) {
                  searchContent += `${prop.name}\n`;
                  if (prop.summary) searchContent += `${prop.summary}\n`;
                  if (prop.description) searchContent += `${prop.description}\n`;
                }
              }

              // Add events
              if (data.events) {
                for (const event of data.events) {
                  searchContent += `${event.name}\n`;
                  if (event.summary) searchContent += `${event.summary}\n`;
                }
              }

              const relativePath = `${category}/${entry.name}`;
              const typeLabel = data.type === 'class' ? 'Class' :
                               data.type === 'datatype' ? 'DataType' :
                               data.type === 'enum' ? 'Enum' :
                               data.type === 'library' ? 'Library' : '';

              indexDoc({
                title: typeLabel ? `${typeLabel}: ${data.name}` : data.name,
                path: relativePath,
                category: category.split('/')[0] || 'reference',
                content: searchContent,
                source: 'roblox'
              });

              indexed++;

              if (progressCallback && indexed % 100 === 0) {
                progressCallback({ indexed, errors });
              }
            }
          } catch (e) {
            errors++;
          }
        }
      }
    } catch (e) {
      // Directory might not exist
      if (category === '') {
        throw new Error(`Docs directory not found: ${dir}`);
      }
    }
  }

  await walkDir(DOCS_PATH);

  // Update last indexed timestamp
  db.prepare(`
    INSERT OR REPLACE INTO docs_meta (key, value) VALUES ('last_indexed', ?)
  `).run(new Date().toISOString());

  return { indexed, errors };
}

/**
 * Get list of categories
 */
export function getCategories() {
  const db = getDb();
  return db.prepare(`
    SELECT DISTINCT category, COUNT(*) as count
    FROM docs
    GROUP BY category
    ORDER BY count DESC
  `).all();
}

/**
 * Close database connection
 */
export function close() {
  if (db) {
    db.close();
    db = null;
  }
}
