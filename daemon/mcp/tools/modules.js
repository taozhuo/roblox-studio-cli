/**
 * MCP Tool: Bakable Modules
 * Install and manage _G.Bakable automation modules in Roblox Studio
 */

import { readFile } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MODULES_PATH = join(__dirname, '../../../bakable-repo/modules');

let pluginCaller = null;

export function setPluginCaller(caller) {
    pluginCaller = caller;
}

// Available modules and their dependencies
const MODULE_INFO = {
    bootstrap: { deps: [], file: 'bootstrap.luau' },
    Catalog: { deps: ['bootstrap'], file: 'catalog.luau' },
    Placer: { deps: ['bootstrap'], file: 'placer.luau' },
    Scatterer: { deps: ['bootstrap', 'Placer'], file: 'scatterer.luau' },
    Zone: { deps: ['bootstrap'], file: 'zone.luau' },
    Camera: { deps: ['bootstrap'], file: 'camera.luau' },
    InventoryUI: { deps: ['bootstrap'], file: 'inventory-ui.luau' },
};

// Topological sort for dependency order
function resolveDependencies(modules) {
    const resolved = [];
    const seen = new Set();

    function visit(name) {
        if (seen.has(name)) return;
        seen.add(name);

        const info = MODULE_INFO[name];
        if (!info) throw new Error(`Unknown module: ${name}`);

        for (const dep of info.deps) {
            visit(dep);
        }
        resolved.push(name);
    }

    for (const mod of modules) {
        visit(mod);
    }

    return resolved;
}

export const tools = [
    {
        name: 'studio.modules.install',
        description: `Install Bakable automation modules into _G.Bakable namespace.

Available modules:
- Catalog: Asset cataloging with sizes, categories, groundOffset
- Placer: Place models with proper Y offset, batch/grid/line placement
- Scatterer: Scatter objects by density in zones
- Zone: Create floor parts, perimeters, paths
- Camera: Position camera for screenshots
- InventoryUI: Visual asset inspection grid

Dependencies are automatically resolved. Bootstrap is always installed first.

Example: install(["Catalog", "Placer", "Scatterer"])`,
        inputSchema: {
            type: 'object',
            properties: {
                modules: {
                    type: 'array',
                    items: { type: 'string' },
                    description: 'Module names to install (e.g., ["Catalog", "Placer"]). Use "all" to install everything.',
                },
            },
            required: ['modules'],
        },
        handler: async ({ modules }) => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            // Handle "all"
            if (modules.includes('all')) {
                modules = Object.keys(MODULE_INFO).filter(m => m !== 'bootstrap');
            }

            // Resolve dependencies
            let toInstall;
            try {
                toInstall = resolveDependencies(modules);
            } catch (err) {
                return { error: err.message };
            }

            const results = [];
            const installed = [];

            for (const modName of toInstall) {
                const info = MODULE_INFO[modName];
                const filePath = join(MODULES_PATH, info.file);

                try {
                    const code = await readFile(filePath, 'utf-8');
                    const result = await pluginCaller('studio.eval', { code });

                    if (result.error) {
                        results.push({ module: modName, error: result.error });
                    } else {
                        results.push({ module: modName, ok: true });
                        installed.push(modName);
                    }
                } catch (err) {
                    results.push({ module: modName, error: err.message });
                }
            }

            return {
                ok: installed.length === toInstall.length,
                installed,
                failed: toInstall.length - installed.length,
                results,
            };
        },
    },
    {
        name: 'studio.modules.list',
        description: 'List currently installed Bakable modules in Studio.',
        inputSchema: {
            type: 'object',
            properties: {},
        },
        handler: async () => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            const code = `
if not _G.Bakable then
    return { installed = false, modules = {} }
end
return {
    installed = true,
    version = _G.Bakable.version,
    modules = _G.Bakable.list and _G.Bakable.list() or {},
}`;

            try {
                return await pluginCaller('studio.eval', { code });
            } catch (err) {
                return { error: err.message };
            }
        },
    },
    {
        name: 'studio.modules.reset',
        description: 'Uninstall all Bakable modules and reset _G.Bakable.',
        inputSchema: {
            type: 'object',
            properties: {},
        },
        handler: async () => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            const code = `
if _G.Bakable and _G.Bakable.reset then
    _G.Bakable.reset()
end
_G.Bakable = nil
return { ok = true }`;

            try {
                return await pluginCaller('studio.eval', { code });
            } catch (err) {
                return { error: err.message };
            }
        },
    },
    {
        name: 'studio.modules.available',
        description: 'List all available Bakable modules that can be installed.',
        inputSchema: {
            type: 'object',
            properties: {},
        },
        handler: async () => {
            const available = Object.entries(MODULE_INFO)
                .filter(([name]) => name !== 'bootstrap')
                .map(([name, info]) => ({
                    name,
                    dependencies: info.deps.filter(d => d !== 'bootstrap'),
                }));

            return {
                modules: available,
                total: available.length,
            };
        },
    },
];

export default tools;
