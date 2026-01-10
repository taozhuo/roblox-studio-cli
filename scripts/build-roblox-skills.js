#!/usr/bin/env node
/**
 * Build Roblox Skills from Creator Docs
 *
 * Reorganizes the creator-docs into Claude Agent Skills format:
 * - Each domain becomes a skill (scripting, ui, physics, etc.)
 * - SKILL.md provides overview + links to reference files
 * - Reference files organized by subtopic
 */

import fs from 'fs/promises';
import path from 'path';

const DOCS_PATH = 'docs/roblox-creator-docs/content/en-us';
const SKILLS_PATH = '.claude/skills';

// Skill definitions - map docs folders to skills
const SKILL_DEFINITIONS = {
  'roblox-scripting': {
    name: 'roblox-scripting',
    description: 'Luau scripting for Roblox: variables, functions, tables, modules, events, coroutines. Use when writing or debugging Roblox Lua code.',
    sources: ['scripting', 'luau'],
    keywords: ['script', 'lua', 'luau', 'function', 'module', 'event', 'coroutine']
  },
  'roblox-ui': {
    name: 'roblox-ui',
    description: 'Roblox UI/GUI development: ScreenGui, Frame, TextLabel, TextButton, UIListLayout, tweening UI. Use when creating or modifying user interfaces.',
    sources: ['ui', 'input'],
    keywords: ['gui', 'ui', 'screengu', 'frame', 'button', 'textlabel', 'layout']
  },
  'roblox-physics': {
    name: 'roblox-physics',
    description: 'Roblox physics and parts: BasePart, Model, constraints, welds, motors, collision. Use when working with 3D objects and physics.',
    sources: ['physics', 'workspace'],
    keywords: ['part', 'model', 'weld', 'constraint', 'collision', 'physics', 'anchor']
  },
  'roblox-networking': {
    name: 'roblox-networking',
    description: 'Roblox networking: RemoteEvent, RemoteFunction, client-server communication, replication. Use when syncing data between client and server.',
    sources: ['scripting/networking'],
    keywords: ['remote', 'replicate', 'client', 'server', 'network', 'fireserver', 'fireclient']
  },
  'roblox-data': {
    name: 'roblox-data',
    description: 'Roblox data persistence: DataStoreService, MemoryStoreService, saving player data. Use when saving or loading persistent data.',
    sources: ['cloud-services/data-stores', 'cloud-services/memory-stores'],
    keywords: ['datastore', 'save', 'load', 'persist', 'memorystore', 'getasync', 'setasync']
  },
  'roblox-animation': {
    name: 'roblox-animation',
    description: 'Roblox animation: TweenService, AnimationController, keyframes, easing. Use when animating objects or characters.',
    sources: ['animation'],
    keywords: ['tween', 'animate', 'animation', 'keyframe', 'easing', 'lerp']
  },
  'roblox-audio': {
    name: 'roblox-audio',
    description: 'Roblox audio: Sound, SoundService, audio effects, 3D sound. Use when working with sounds and music.',
    sources: ['audio', 'sound'],
    keywords: ['sound', 'audio', 'music', 'play', 'volume', 'soundservice']
  },
  'roblox-characters': {
    name: 'roblox-characters',
    description: 'Roblox characters and avatars: Humanoid, R6/R15, character customization. Use when working with player characters.',
    sources: ['characters', 'avatar'],
    keywords: ['humanoid', 'character', 'avatar', 'r15', 'r6', 'walkspeed', 'health']
  },
  'roblox-services': {
    name: 'roblox-services',
    description: 'Core Roblox services: Players, Workspace, ReplicatedStorage, ServerStorage, RunService. Use when accessing game services.',
    sources: ['reference/engine/classes'],
    keywords: ['service', 'players', 'workspace', 'runservice', 'replicatedstorage']
  }
};

async function fileExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function findMarkdownFiles(dir, basePath = '') {
  const files = [];
  try {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      const relativePath = path.join(basePath, entry.name);
      if (entry.isDirectory()) {
        files.push(...await findMarkdownFiles(fullPath, relativePath));
      } else if (entry.name.endsWith('.md') && !entry.name.startsWith('_')) {
        files.push({ fullPath, relativePath });
      }
    }
  } catch (e) {
    // Directory doesn't exist
  }
  return files;
}

function extractTitle(content) {
  const titleMatch = content.match(/^title:\s*(.+)$/m) || content.match(/^#\s+(.+)$/m);
  return titleMatch ? titleMatch[1].trim().replace(/["']/g, '') : null;
}

function extractDescription(content) {
  const descMatch = content.match(/^description:\s*(.+)$/m);
  return descMatch ? descMatch[1].trim().replace(/["']/g, '') : null;
}

function cleanContent(content) {
  // Remove YAML frontmatter
  let cleaned = content.replace(/^---[\s\S]*?---\n*/, '');
  // Remove HTML comments
  cleaned = cleaned.replace(/<!--[\s\S]*?-->/g, '');
  // Remove empty links
  cleaned = cleaned.replace(/\[([^\]]+)\]\(\)/g, '$1');
  // Simplify image references
  cleaned = cleaned.replace(/!\[([^\]]*)\]\([^)]+\)/g, '[Image: $1]');
  return cleaned.trim();
}

async function buildSkill(skillId, skillDef) {
  console.log(`\nBuilding skill: ${skillId}`);

  const skillDir = path.join(SKILLS_PATH, skillId);
  await fs.mkdir(skillDir, { recursive: true });

  // Collect all relevant docs
  const allDocs = [];
  for (const source of skillDef.sources) {
    const sourceDir = path.join(DOCS_PATH, source);
    const files = await findMarkdownFiles(sourceDir);
    for (const file of files) {
      try {
        const content = await fs.readFile(file.fullPath, 'utf-8');
        const title = extractTitle(content) || path.basename(file.relativePath, '.md');
        const desc = extractDescription(content);
        allDocs.push({
          ...file,
          title,
          description: desc,
          content: cleanContent(content),
          category: source
        });
      } catch (e) {
        console.error(`  Error reading ${file.fullPath}:`, e.message);
      }
    }
  }

  console.log(`  Found ${allDocs.length} docs`);

  if (allDocs.length === 0) {
    console.log(`  Skipping - no docs found`);
    return null;
  }

  // Group docs by category for reference files
  const categories = {};
  for (const doc of allDocs) {
    const cat = doc.category.split('/')[0];
    if (!categories[cat]) categories[cat] = [];
    categories[cat].push(doc);
  }

  // Build SKILL.md
  let skillMd = `---
name: ${skillDef.name}
description: ${skillDef.description}
---

# ${skillId.replace('roblox-', '').charAt(0).toUpperCase() + skillId.replace('roblox-', '').slice(1)} Reference

`;

  // Add quick reference section with most important topics
  skillMd += `## Quick Reference\n\n`;
  const topDocs = allDocs.slice(0, 10);
  for (const doc of topDocs) {
    skillMd += `- **${doc.title}**: ${doc.description || 'See reference'}\n`;
  }

  // Add category sections with links to reference files
  skillMd += `\n## Detailed Reference\n\n`;
  for (const [cat, docs] of Object.entries(categories)) {
    const refFileName = `${cat.replace(/\//g, '-')}.md`;
    skillMd += `### ${cat.charAt(0).toUpperCase() + cat.slice(1)}\n`;
    skillMd += `See [${refFileName}](${refFileName}) for:\n`;
    for (const doc of docs.slice(0, 5)) {
      skillMd += `- ${doc.title}\n`;
    }
    if (docs.length > 5) {
      skillMd += `- ...and ${docs.length - 5} more\n`;
    }
    skillMd += '\n';

    // Build reference file
    let refContent = `# ${cat.charAt(0).toUpperCase() + cat.slice(1)} Reference\n\n`;
    refContent += `## Contents\n`;
    for (const doc of docs) {
      refContent += `- [${doc.title}](#${doc.title.toLowerCase().replace(/[^a-z0-9]+/g, '-')})\n`;
    }
    refContent += '\n---\n\n';

    for (const doc of docs) {
      refContent += `## ${doc.title}\n\n`;
      // Truncate very long docs
      const maxLen = 2000;
      if (doc.content.length > maxLen) {
        refContent += doc.content.slice(0, maxLen) + '\n\n[Content truncated - see full docs]\n\n';
      } else {
        refContent += doc.content + '\n\n';
      }
      refContent += '---\n\n';
    }

    await fs.writeFile(path.join(skillDir, refFileName), refContent);
    console.log(`  Created ${refFileName} (${docs.length} docs)`);
  }

  // Write SKILL.md
  await fs.writeFile(path.join(skillDir, 'SKILL.md'), skillMd);
  console.log(`  Created SKILL.md`);

  return { skillId, docCount: allDocs.length };
}

async function main() {
  console.log('Building Roblox Skills from Creator Docs\n');
  console.log(`Source: ${DOCS_PATH}`);
  console.log(`Output: ${SKILLS_PATH}`);

  // Check if docs exist
  if (!await fileExists(DOCS_PATH)) {
    console.error(`\nError: Docs not found at ${DOCS_PATH}`);
    console.error('Run: git clone --depth 1 https://github.com/Roblox/creator-docs.git docs/roblox-creator-docs');
    process.exit(1);
  }

  // Create skills directory
  await fs.mkdir(SKILLS_PATH, { recursive: true });

  // Build each skill
  const results = [];
  for (const [skillId, skillDef] of Object.entries(SKILL_DEFINITIONS)) {
    const result = await buildSkill(skillId, skillDef);
    if (result) results.push(result);
  }

  console.log('\n========================================');
  console.log('Skills built:');
  for (const r of results) {
    console.log(`  ${r.skillId}: ${r.docCount} docs`);
  }
  console.log(`\nTotal: ${results.length} skills`);
  console.log(`Location: ${SKILLS_PATH}`);
}

main().catch(console.error);
