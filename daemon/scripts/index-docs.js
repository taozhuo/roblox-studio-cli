#!/usr/bin/env node
/**
 * Index Roblox Documentation
 *
 * Usage:
 *   node daemon/scripts/index-docs.js
 *   npm run index-docs
 *
 * Prerequisites:
 *   git clone https://github.com/Roblox/creator-docs docs/roblox-creator-docs
 */

import { indexRobloxDocs, getStats, close } from '../mcp/tools/knowledge-base.js';

async function main() {
  console.log('📚 Indexing Roblox documentation...\n');

  const startTime = Date.now();

  try {
    const result = await indexRobloxDocs((progress) => {
      process.stdout.write(`\r   Indexed: ${progress.indexed} docs`);
    });

    const elapsed = ((Date.now() - startTime) / 1000).toFixed(2);

    console.log(`\n\n✅ Indexing complete!`);
    console.log(`   Documents indexed: ${result.indexed}`);
    console.log(`   Errors: ${result.errors}`);
    console.log(`   Time: ${elapsed}s\n`);

    // Show stats
    const stats = getStats();
    console.log('📊 Index stats:');
    console.log(`   Total documents: ${stats.total}`);
    console.log(`   Last indexed: ${stats.lastIndexed}`);
    console.log('');

  } catch (e) {
    console.error('\n❌ Indexing failed:', e.message);

    if (e.message.includes('not found')) {
      console.log('\n💡 To fix this, clone the Roblox docs:\n');
      console.log('   git clone https://github.com/Roblox/creator-docs docs/roblox-creator-docs\n');
    }

    process.exit(1);
  } finally {
    close();
  }
}

main();
