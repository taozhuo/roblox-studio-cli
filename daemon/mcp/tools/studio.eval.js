/**
 * Studio Eval Tools - Console Panel
 *
 * Tools for evaluating Luau code in Studio.
 */

export function registerEvalTools(registerTool, callPlugin) {
  // studio.eval - Execute Luau code
  registerTool('studio.eval', {
    description: 'Evaluate Luau code in Roblox Studio context',
    inputSchema: {
      type: 'object',
      properties: {
        code: {
          type: 'string',
          description: 'Luau code to execute'
        },
        timeout: {
          type: 'number',
          description: 'Timeout in milliseconds (default: 5000)'
        }
      },
      required: ['code']
    }
  }, async (params) => {
    return await callPlugin('studio.eval', params);
  });
}
