#!/usr/bin/env node
/**
 * Build Roblox API Reference Skill from YAML class definitions
 *
 * Creates a structured skill for querying the Roblox API
 */

import fs from 'fs/promises';
import path from 'path';
import yaml from 'js-yaml';

const CLASSES_PATH = 'docs/roblox-creator-docs/content/en-us/reference/engine/classes';
const SKILL_PATH = '.claude/skills/roblox-api';

// Group classes by category
const CLASS_CATEGORIES = {
  'services': ['Players', 'Workspace', 'ReplicatedStorage', 'ServerStorage', 'RunService',
               'TweenService', 'UserInputService', 'DataStoreService', 'HttpService',
               'SoundService', 'Lighting', 'StarterGui', 'StarterPlayer', 'Teams',
               'Chat', 'MarketplaceService', 'GamePassService', 'BadgeService',
               'MemoryStoreService', 'MessagingService', 'PolicyService', 'LocalizationService'],
  'gui': ['ScreenGui', 'Frame', 'TextLabel', 'TextButton', 'TextBox', 'ImageLabel',
          'ImageButton', 'ScrollingFrame', 'ViewportFrame', 'UIListLayout', 'UIGridLayout',
          'UIPadding', 'UICorner', 'UIStroke', 'UIGradient', 'UIScale', 'UIAspectRatioConstraint',
          'BillboardGui', 'SurfaceGui', 'CanvasGroup'],
  'parts': ['Part', 'MeshPart', 'UnionOperation', 'Model', 'Folder', 'SpawnLocation',
            'Seat', 'VehicleSeat', 'TrussPart', 'WedgePart', 'CornerWedgePart', 'Terrain'],
  'physics': ['Weld', 'WeldConstraint', 'Motor6D', 'HingeConstraint', 'SpringConstraint',
              'RopeConstraint', 'RodConstraint', 'AlignPosition', 'AlignOrientation',
              'BodyPosition', 'BodyVelocity', 'BodyForce', 'BodyGyro', 'VectorForce'],
  'effects': ['ParticleEmitter', 'Beam', 'Trail', 'Fire', 'Smoke', 'Sparkles',
              'PointLight', 'SpotLight', 'SurfaceLight', 'Atmosphere', 'Sky', 'Clouds'],
  'animation': ['Animation', 'AnimationController', 'Animator', 'AnimationTrack', 'Keyframe'],
  'sound': ['Sound', 'SoundGroup', 'SoundEffect', 'DistortionSoundEffect', 'ReverbSoundEffect'],
  'characters': ['Humanoid', 'HumanoidDescription', 'Accessory', 'Shirt', 'Pants', 'CharacterMesh'],
  'networking': ['RemoteEvent', 'RemoteFunction', 'BindableEvent', 'BindableFunction',
                 'UnreliableRemoteEvent']
};

async function parseYamlClass(filePath) {
  try {
    const content = await fs.readFile(filePath, 'utf-8');
    return yaml.load(content);
  } catch (e) {
    return null;
  }
}

async function main() {
  console.log('Building Roblox API Reference Skill\n');

  await fs.mkdir(SKILL_PATH, { recursive: true });

  // Get all class files
  const files = await fs.readdir(CLASSES_PATH);
  const yamlFiles = files.filter(f => f.endsWith('.yaml'));
  console.log(`Found ${yamlFiles.length} class definitions`);

  // Parse all classes
  const classes = {};
  for (const file of yamlFiles) {
    const cls = await parseYamlClass(path.join(CLASSES_PATH, file));
    if (cls && cls.name) {
      classes[cls.name] = cls;
    }
  }

  // Build SKILL.md
  let skillMd = `---
name: roblox-api
description: Roblox Engine API reference: classes, properties, methods, events. Use when looking up how to use Roblox classes or their members.
---

# Roblox API Reference

Query the Roblox Engine API. For runtime queries, use \`roblox.api.getClass\` and \`roblox.api.getProperties\` tools (powered by ReflectionService).

## Class Categories

`;

  // Add category sections
  for (const [category, classNames] of Object.entries(CLASS_CATEGORIES)) {
    skillMd += `### ${category.charAt(0).toUpperCase() + category.slice(1)}\n`;
    skillMd += `See [${category}.md](${category}.md) for: `;
    skillMd += classNames.slice(0, 5).join(', ');
    if (classNames.length > 5) skillMd += `, +${classNames.length - 5} more`;
    skillMd += '\n\n';

    // Build category reference file
    let refContent = `# ${category.charAt(0).toUpperCase() + category.slice(1)} Classes\n\n`;
    refContent += `## Contents\n`;
    for (const name of classNames) {
      refContent += `- [${name}](#${name.toLowerCase()})\n`;
    }
    refContent += '\n---\n\n';

    for (const name of classNames) {
      const cls = classes[name];
      if (!cls) {
        refContent += `## ${name}\n\nClass not found in docs.\n\n---\n\n`;
        continue;
      }

      refContent += `## ${name}\n\n`;
      if (cls.summary) refContent += `${cls.summary.trim()}\n\n`;

      // Properties
      if (cls.properties && cls.properties.length > 0) {
        refContent += `**Properties:**\n`;
        for (const prop of cls.properties.slice(0, 10)) {
          const type = prop.type || 'unknown';
          refContent += `- \`${prop.name}\`: ${type}`;
          if (prop.summary) refContent += ` - ${prop.summary.trim().split('\n')[0]}`;
          refContent += '\n';
        }
        if (cls.properties.length > 10) {
          refContent += `- ...and ${cls.properties.length - 10} more\n`;
        }
        refContent += '\n';
      }

      // Methods
      if (cls.methods && cls.methods.length > 0) {
        refContent += `**Methods:**\n`;
        for (const method of cls.methods.slice(0, 10)) {
          refContent += `- \`${method.name}\``;
          if (method.summary) refContent += ` - ${method.summary.trim().split('\n')[0]}`;
          refContent += '\n';
        }
        if (cls.methods.length > 10) {
          refContent += `- ...and ${cls.methods.length - 10} more\n`;
        }
        refContent += '\n';
      }

      // Events
      if (cls.events && cls.events.length > 0) {
        refContent += `**Events:**\n`;
        for (const event of cls.events.slice(0, 5)) {
          refContent += `- \`${event.name}\``;
          if (event.summary) refContent += ` - ${event.summary.trim().split('\n')[0]}`;
          refContent += '\n';
        }
        refContent += '\n';
      }

      refContent += '---\n\n';
    }

    await fs.writeFile(path.join(SKILL_PATH, `${category}.md`), refContent);
    console.log(`  Created ${category}.md (${classNames.length} classes)`);
  }

  // Write SKILL.md
  await fs.writeFile(path.join(SKILL_PATH, 'SKILL.md'), skillMd);
  console.log('  Created SKILL.md');

  console.log('\nDone! API reference skill created.');
}

main().catch(console.error);
