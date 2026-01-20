/**
 * Studio Query Tools - jq/grep/sed-like tools for instances and scripts
 *
 * Provides bash-like query capabilities:
 * - studio.query.run: jq-like DSL for instance queries
 * - studio.query.find: Structured query API
 * - studio.query.grep: Search script source
 * - studio.query.sed: Find/replace in scripts
 * - studio.query.count: Count instances
 * - studio.query.countByClass: Count by ClassName
 */

export function registerQueryTools(registerTool, callPlugin) {
  // studio.query.run - Execute jq-like DSL query
  registerTool('studio.query.run', {
    description: `Execute jq-like query on instance tree.

Syntax: Segment | Segment | ...

Segments:
  ..              - All descendants
  .[]             - Direct children
  .Path.To.Inst   - Navigate to path
  ClassName       - Filter by class (Part, Model, Script)
  .Prop == value  - Filter by property (==, !=, >, <, >=, <=, ~)
  {Prop1, Prop2}  - Select specific properties
  limit(N)        - Limit results
  count           - Return count only
  keys            - Return class counts

Examples:
  ".. | Part"                           - All Parts
  ".. | BasePart | .Anchored == false"  - Unanchored parts
  ".. | Part | .Transparency > 0.5"     - Transparent parts
  ".. | .Name ~ '^Spawn'"               - Name matches pattern
  ".Workspace.Map | .. | Model"         - Models under Map
  ".. | Part | {Name, Position, Size}"  - Select props
  ".. | Part | limit(10)"               - First 10`,
    inputSchema: {
      type: 'object',
      properties: {
        query: {
          type: 'string',
          description: 'jq-like query string'
        },
        root: {
          type: 'string',
          description: 'Root path to start from (default: game)'
        },
        limit: {
          type: 'number',
          description: 'Max results to return (default: 1000)'
        }
      },
      required: ['query']
    }
  }, async (params) => {
    return await callPlugin('studio.query.run', params);
  });

  // studio.query.find - Structured query API
  registerTool('studio.query.find', {
    description: 'Structured query for instances with class, conditions, and property selection',
    inputSchema: {
      type: 'object',
      properties: {
        class: {
          type: 'string',
          description: 'ClassName to filter (e.g., "Part", "BasePart", "Model")'
        },
        where: {
          type: 'array',
          items: {
            type: 'array',
            items: [
              { type: 'string', description: 'Property name' },
              { type: 'string', description: 'Operator (==, !=, >, <, >=, <=, ~, contains)' },
              { description: 'Value to compare' }
            ]
          },
          description: 'Array of conditions: [["Prop", "op", value], ...]'
        },
        select: {
          type: 'array',
          items: { type: 'string' },
          description: 'Properties to return (default: path, name, className)'
        },
        root: {
          type: 'string',
          description: 'Root path to start from'
        },
        limit: {
          type: 'number',
          description: 'Max results (default: 1000)'
        }
      }
    }
  }, async (params) => {
    return await callPlugin('studio.query.find', params);
  });

  // studio.query.grep - Search script source
  registerTool('studio.query.grep', {
    description: 'Search for pattern in all script source code (like grep)',
    inputSchema: {
      type: 'object',
      properties: {
        pattern: {
          type: 'string',
          description: 'Lua pattern or literal string to search for'
        },
        ignoreCase: {
          type: 'boolean',
          description: 'Case insensitive search (default: false)'
        },
        lines: {
          type: 'boolean',
          description: 'Include matching line numbers and content (default: false)'
        },
        limit: {
          type: 'number',
          description: 'Max scripts to return (default: 100)'
        }
      },
      required: ['pattern']
    }
  }, async (params) => {
    return await callPlugin('studio.query.grep', params);
  });

  // studio.query.sed - Find/replace in scripts
  registerTool('studio.query.sed', {
    description: 'Find and replace pattern in all scripts (like sed). Use dryRun to preview changes.',
    inputSchema: {
      type: 'object',
      properties: {
        pattern: {
          type: 'string',
          description: 'Lua pattern to find'
        },
        replacement: {
          type: 'string',
          description: 'Replacement string (can use %1, %2 for captures)'
        },
        dryRun: {
          type: 'boolean',
          description: 'Preview changes without modifying (default: false)'
        }
      },
      required: ['pattern', 'replacement']
    }
  }, async (params) => {
    return await callPlugin('studio.query.sed', params);
  });

  // studio.query.count - Count instances
  registerTool('studio.query.count', {
    description: 'Count instances, optionally filtered by class',
    inputSchema: {
      type: 'object',
      properties: {
        class: {
          type: 'string',
          description: 'ClassName to count (optional)'
        },
        root: {
          type: 'string',
          description: 'Root path to start from'
        }
      }
    }
  }, async (params) => {
    return await callPlugin('studio.query.count', params);
  });

  // studio.query.countByClass - Count grouped by ClassName
  registerTool('studio.query.countByClass', {
    description: 'Count instances grouped by ClassName (like sort | uniq -c)',
    inputSchema: {
      type: 'object',
      properties: {
        root: {
          type: 'string',
          description: 'Root path to start from'
        }
      }
    }
  }, async (params) => {
    return await callPlugin('studio.query.countByClass', params);
  });

  // ========== Tag Tools ==========

  // studio.query.findByTag - Find instances by CollectionService tag
  registerTool('studio.query.findByTag', {
    description: 'Find all instances with a specific CollectionService tag',
    inputSchema: {
      type: 'object',
      properties: {
        tag: {
          type: 'string',
          description: 'Tag name to search for'
        },
        select: {
          type: 'array',
          items: { type: 'string' },
          description: 'Properties to return'
        },
        limit: {
          type: 'number',
          description: 'Max results (default: 1000)'
        }
      },
      required: ['tag']
    }
  }, async (params) => {
    return await callPlugin('studio.query.findByTag', params);
  });

  // studio.query.getTags - Get tags on an instance
  registerTool('studio.query.getTags', {
    description: 'Get all CollectionService tags on an instance',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Instance path'
        }
      },
      required: ['path']
    }
  }, async (params) => {
    return await callPlugin('studio.query.getTags', params);
  });

  // studio.query.listAllTags - List all tags in game
  registerTool('studio.query.listAllTags', {
    description: 'List all unique CollectionService tags in the game with counts',
    inputSchema: {
      type: 'object',
      properties: {
        root: {
          type: 'string',
          description: 'Root path to start from'
        }
      }
    }
  }, async (params) => {
    return await callPlugin('studio.query.listAllTags', params);
  });

  // studio.query.addTag - Add tag to instances
  registerTool('studio.query.addTag', {
    description: 'Add a CollectionService tag to instance(s). Use path for single instance or query for multiple.',
    inputSchema: {
      type: 'object',
      properties: {
        tag: {
          type: 'string',
          description: 'Tag name to add'
        },
        path: {
          type: 'string',
          description: 'Instance path (for single instance)'
        },
        query: {
          type: 'string',
          description: 'Query DSL to match multiple instances'
        }
      },
      required: ['tag']
    }
  }, async (params) => {
    return await callPlugin('studio.query.addTag', params);
  });

  // studio.query.removeTag - Remove tag from instances
  registerTool('studio.query.removeTag', {
    description: 'Remove a CollectionService tag from instance(s). Use path for single, query for multiple, or neither to remove from all.',
    inputSchema: {
      type: 'object',
      properties: {
        tag: {
          type: 'string',
          description: 'Tag name to remove'
        },
        path: {
          type: 'string',
          description: 'Instance path (for single instance)'
        },
        query: {
          type: 'string',
          description: 'Query DSL to match multiple instances'
        }
      },
      required: ['tag']
    }
  }, async (params) => {
    return await callPlugin('studio.query.removeTag', params);
  });

  // ========== Attribute Tools ==========

  // studio.query.getAttributes - Get attributes on instance
  registerTool('studio.query.getAttributes', {
    description: 'Get all attributes on an instance',
    inputSchema: {
      type: 'object',
      properties: {
        path: {
          type: 'string',
          description: 'Instance path'
        }
      },
      required: ['path']
    }
  }, async (params) => {
    return await callPlugin('studio.query.getAttributes', params);
  });

  // studio.query.setAttribute - Set attribute on instances
  registerTool('studio.query.setAttribute', {
    description: 'Set an attribute on instance(s). Use path for single or query for multiple.',
    inputSchema: {
      type: 'object',
      properties: {
        name: {
          type: 'string',
          description: 'Attribute name'
        },
        value: {
          description: 'Attribute value (string, number, boolean, or nil to delete)'
        },
        path: {
          type: 'string',
          description: 'Instance path (for single instance)'
        },
        query: {
          type: 'string',
          description: 'Query DSL to match multiple instances'
        }
      },
      required: ['name']
    }
  }, async (params) => {
    return await callPlugin('studio.query.setAttribute', params);
  });

  // studio.query.listAttributes - List all attributes in game
  registerTool('studio.query.listAttributes', {
    description: 'List all unique attribute names in the game with counts',
    inputSchema: {
      type: 'object',
      properties: {
        root: {
          type: 'string',
          description: 'Root path to start from'
        }
      }
    }
  }, async (params) => {
    return await callPlugin('studio.query.listAttributes', params);
  });
}
