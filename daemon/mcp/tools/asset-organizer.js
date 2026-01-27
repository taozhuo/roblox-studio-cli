/**
 * MCP Tools: Asset Organizer
 * Scan, display, identify (via Gemini), and catalog assets
 */

import { readFile } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { identifyAssets } from '../../services/gemini.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const MODULES_PATH = join(__dirname, '../../../bakable-repo/modules');

let pluginCaller = null;

export function setPluginCaller(caller) {
    pluginCaller = caller;
}

// Helper to install a module if not already installed
// Bakable table is provided directly by the eval sandbox
async function ensureModule(moduleName) {
    const checkCode = `return Bakable.${moduleName} ~= nil`;
    const checkResult = await pluginCaller('studio.eval', { code: checkCode });

    if (checkResult.result === true || checkResult.result === 'true') {
        return { alreadyInstalled: true };
    }

    // Install bootstrap first if needed (initializes Bakable.version, etc.)
    if (moduleName !== 'bootstrap') {
        const bootstrapCheck = await pluginCaller('studio.eval', {
            code: 'return Bakable.version ~= nil'
        });
        if (bootstrapCheck.result !== true && bootstrapCheck.result !== 'true') {
            const bootstrapCode = await readFile(join(MODULES_PATH, 'bootstrap.luau'), 'utf-8');
            await pluginCaller('studio.eval', { code: bootstrapCode });
        }
    }

    // Install the module
    const fileMap = {
        bootstrap: 'bootstrap.luau',
        AssetOrganizer: 'asset-organizer.luau',
    };

    const fileName = fileMap[moduleName];
    if (!fileName) {
        throw new Error(`Unknown module: ${moduleName}`);
    }

    const code = await readFile(join(MODULES_PATH, fileName), 'utf-8');
    await pluginCaller('studio.eval', { code });

    return { installed: true };
}

export const tools = [
    {
        name: 'studio.assets.renameDuplicates',
        description: `Rename duplicate models in a folder BEFORE any other operations.

Run this FIRST before dumpTree() if a folder has multiple models with the same name.
This actually renames them in Studio (Model, Model → Model_1, Model_2).

After renaming, paths will be unique and dumpTree/selectAssets will work correctly.`,
        inputSchema: {
            type: 'object',
            properties: {
                folderPath: {
                    type: 'string',
                    description: 'Path to folder (e.g., "Workspace/Farm Pack/Buildings/Barns")'
                },
                maxDepth: {
                    type: 'number',
                    description: 'Max recursion depth (default 10)',
                    default: 10
                }
            },
            required: ['folderPath']
        },
        handler: async ({ folderPath, maxDepth = 10 }) => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                await ensureModule('AssetOrganizer');

                const code = `
                    local HttpService = game:GetService("HttpService")
                    local result = Bakable.AssetOrganizer.renameDuplicates("${folderPath}", ${maxDepth})
                    return HttpService:JSONEncode(result)
                `;
                const result = await pluginCaller('studio.eval', { code });

                if (typeof result.result === 'string') {
                    try {
                        return JSON.parse(result.result);
                    } catch {
                        return result;
                    }
                }
                return result.result || result;
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.dumpTree',
        description: `Dump full tree structure of a folder for analysis.

Returns hierarchical structure with:
- name, class, path for each node
- size for Models and Parts
- childClasses summary
- childCount

Use this to analyze the asset pack structure, then call selectAssets() with paths you want to show in the grid.`,
        inputSchema: {
            type: 'object',
            properties: {
                folderPath: {
                    type: 'string',
                    description: 'Path to folder (e.g., "Workspace/Farm Pack")'
                },
                maxDepth: {
                    type: 'number',
                    description: 'Max recursion depth (default 6)',
                    default: 6
                }
            },
            required: ['folderPath']
        },
        handler: async ({ folderPath, maxDepth = 6 }) => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                // Inline code - no module needed for simple tree query
                const code = `
local HttpService = game:GetService("HttpService")

local function getSize(inst)
    if inst:IsA("Model") then
        local ok, cf, size = pcall(inst.GetBoundingBox, inst)
        if ok then return {X = math.floor(size.X + 0.5), Y = math.floor(size.Y + 0.5), Z = math.floor(size.Z + 0.5)} end
    elseif inst:IsA("BasePart") then
        local s = inst.Size
        return {X = math.floor(s.X + 0.5), Y = math.floor(s.Y + 0.5), Z = math.floor(s.Z + 0.5)}
    end
    return nil
end

local function countClasses(inst)
    local c = {}
    for _, ch in ipairs(inst:GetChildren()) do c[ch.ClassName] = (c[ch.ClassName] or 0) + 1 end
    return c
end

local function dumpNode(inst, path, depth, maxD)
    local node = {name = inst.Name, class = inst.ClassName, path = path, childCount = #inst:GetChildren()}
    local size = getSize(inst)
    if size then node.size = size end
    if depth < maxD and node.childCount > 0 then
        node.childClasses = countClasses(inst)
        node.children = {}
        for _, ch in ipairs(inst:GetChildren()) do
            table.insert(node.children, dumpNode(ch, path .. "/" .. ch.Name, depth + 1, maxD))
        end
    end
    return node
end

local function dumpTree(folderPath, maxDepth)
    local current = game
    for part in string.gmatch(folderPath, "[^/]+") do
        current = current:FindFirstChild(part)
        if not current then return {error = "Path not found: " .. folderPath} end
    end
    return dumpNode(current, folderPath, 0, maxDepth)
end

return HttpService:JSONEncode(dumpTree("${folderPath}", ${maxDepth}))
`;
                const result = await pluginCaller('studio.eval', { code });

                if (typeof result.result === 'string') {
                    try {
                        return JSON.parse(result.result);
                    } catch {
                        return { raw: result.result };
                    }
                }
                return result.result || result;
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.selectAssets',
        description: `Select specific asset paths to show in the grid.

After analyzing dumpTree() output, call this with the paths you've determined are "real placeable assets".

Paths will be disambiguated (_1, _2) if names collide.`,
        inputSchema: {
            type: 'object',
            properties: {
                paths: {
                    type: 'array',
                    items: { type: 'string' },
                    description: 'Array of full paths to show (e.g., ["Workspace/Farm Pack/Buildings/Barns/Model", ...])'
                }
            },
            required: ['paths']
        },
        handler: async ({ paths }) => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                await ensureModule('AssetOrganizer');

                const pathsJson = JSON.stringify(paths);
                const code = `
                    local HttpService = game:GetService("HttpService")
                    local paths = HttpService:JSONDecode('${pathsJson.replace(/'/g, "\\'")}')
                    local result = Bakable.AssetOrganizer.selectAssets(paths)
                    return HttpService:JSONEncode(result)
                `;
                const result = await pluginCaller('studio.eval', { code });

                if (typeof result.result === 'string') {
                    try {
                        return JSON.parse(result.result);
                    } catch {
                        return result;
                    }
                }
                return result.result || result;
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.wrapInModel',
        description: `Wrap a single Part/MeshPart in a Model.

Use when you find a standalone MeshPart that should be a placeable asset.
Creates a wrapper Model with the Part as PrimaryPart.`,
        inputSchema: {
            type: 'object',
            properties: {
                path: {
                    type: 'string',
                    description: 'Path to the Part/MeshPart to wrap'
                },
                modelName: {
                    type: 'string',
                    description: 'Name for the wrapper Model (optional, defaults to part name)'
                }
            },
            required: ['path']
        },
        handler: async ({ path, modelName }) => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                await ensureModule('AssetOrganizer');

                const nameArg = modelName ? `"${modelName}"` : 'nil';
                const code = `
                    local HttpService = game:GetService("HttpService")
                    local result = Bakable.AssetOrganizer.wrapInModel("${path}", ${nameArg})
                    return HttpService:JSONEncode(result)
                `;
                const result = await pluginCaller('studio.eval', { code });

                if (typeof result.result === 'string') {
                    try {
                        return JSON.parse(result.result);
                    } catch {
                        return result;
                    }
                }
                return result.result || result;
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.scan',
        description: `[LEGACY] Auto-scan for leaf models.

Prefer using dumpTree() + selectAssets() for more control.

This automatically finds Models whose children are Parts/MeshParts.`,
        inputSchema: {
            type: 'object',
            properties: {
                folderPath: {
                    type: 'string',
                    description: 'Path to folder (e.g., "Workspace/Farm Pack")'
                }
            },
            required: ['folderPath']
        },
        handler: async ({ folderPath }) => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                await ensureModule('AssetOrganizer');

                const code = `
                    local HttpService = game:GetService("HttpService")
                    local result = Bakable.AssetOrganizer.scan("${folderPath}")
                    return HttpService:JSONEncode(result)
                `;
                const result = await pluginCaller('studio.eval', { code });

                if (typeof result.result === 'string') {
                    try {
                        return JSON.parse(result.result);
                    } catch {
                        return result;
                    }
                }
                return result.result || result;
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.show',
        description: `Show the asset organizer UI grid for the current page.

Displays 9 assets per page with:
- Parent folder name
- Asset name (disambiguated)
- Size in studs
- 3D viewport preview (camera faces -Z)

Use after scanning. Take a screenshot for Gemini identification.`,
        inputSchema: {
            type: 'object',
            properties: {
                page: {
                    type: 'number',
                    description: 'Page number (optional, defaults to current page)'
                }
            }
        },
        handler: async ({ page }) => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                const code = page
                    ? `return Bakable.AssetOrganizer.show(${page})`
                    : `return Bakable.AssetOrganizer.show()`;
                const result = await pluginCaller('studio.eval', { code });

                if (typeof result.result === 'string') {
                    try {
                        return JSON.parse(result.result);
                    } catch {
                        return result;
                    }
                }
                return result.result || result;
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.nextPage',
        description: 'Go to next page in asset organizer UI.',
        inputSchema: { type: 'object', properties: {} },
        handler: async () => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                const result = await pluginCaller('studio.eval', {
                    code: 'return Bakable.AssetOrganizer.next()'
                });
                if (typeof result.result === 'string') {
                    try { return JSON.parse(result.result); } catch { return result; }
                }
                return result.result || result;
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.prevPage',
        description: 'Go to previous page in asset organizer UI.',
        inputSchema: { type: 'object', properties: {} },
        handler: async () => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                const result = await pluginCaller('studio.eval', {
                    code: 'return Bakable.AssetOrganizer.prev()'
                });
                if (typeof result.result === 'string') {
                    try { return JSON.parse(result.result); } catch { return result; }
                }
                return result.result || result;
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.getPageAssets',
        description: 'Get asset info for current page (for Gemini identification prompt).',
        inputSchema: { type: 'object', properties: {} },
        handler: async () => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                const code = `
                    local HttpService = game:GetService("HttpService")
                    local assets = Bakable.AssetOrganizer.getPageAssets()
                    return HttpService:JSONEncode(assets)
                `;
                const result = await pluginCaller('studio.eval', { code });

                if (typeof result.result === 'string') {
                    try { return JSON.parse(result.result); } catch { return result; }
                }
                return result.result || result;
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.identify',
        description: `Send screenshot to Gemini to identify assets on current page.

Takes a screenshot of the asset organizer grid and sends to Gemini 3 Flash.
Gemini identifies each asset and returns:
- identifiedName: descriptive name
- rotationOffset: degrees to rotate for correct orientation
- comment: placement notes

Requires GEMINI_API_KEY environment variable.`,
        inputSchema: {
            type: 'object',
            properties: {
                screenshot: {
                    type: 'string',
                    description: 'Base64 encoded screenshot of the asset grid'
                }
            },
            required: ['screenshot']
        },
        handler: async ({ screenshot }) => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            if (!process.env.GEMINI_API_KEY) {
                return { error: 'GEMINI_API_KEY not configured' };
            }

            try {
                // Get page assets info
                const code = `
                    local HttpService = game:GetService("HttpService")
                    local assets = Bakable.AssetOrganizer.getPageAssets()
                    return HttpService:JSONEncode(assets)
                `;
                const assetsResult = await pluginCaller('studio.eval', { code });

                let pageAssets;
                if (typeof assetsResult.result === 'string') {
                    pageAssets = JSON.parse(assetsResult.result);
                } else {
                    pageAssets = assetsResult.result;
                }

                if (!pageAssets || pageAssets.length === 0) {
                    return { error: 'No assets on current page. Show a page first.' };
                }

                // Call Gemini
                const result = await identifyAssets(screenshot, pageAssets);
                return result;

            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.applyIdentifications',
        description: `Apply Gemini identifications to rename assets in Studio.

Takes the identifications array from studio.assets.identify and:
- Renames models to their identified names
- Stores rotation offset and comments for catalog`,
        inputSchema: {
            type: 'object',
            properties: {
                identifications: {
                    type: 'array',
                    description: 'Array of { index, identifiedName, rotationOffset, comment }',
                    items: {
                        type: 'object',
                        properties: {
                            index: { type: 'number' },
                            identifiedName: { type: 'string' },
                            rotationOffset: { type: ['number', 'null'] },
                            comment: { type: 'string' }
                        }
                    }
                }
            },
            required: ['identifications']
        },
        handler: async ({ identifications }) => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                const code = `
                    local HttpService = game:GetService("HttpService")
                    local identifications = HttpService:JSONDecode('${JSON.stringify(identifications).replace(/'/g, "\\'")}')
                    return Bakable.AssetOrganizer.applyIdentifications(identifications)
                `;
                const result = await pluginCaller('studio.eval', { code });

                if (typeof result.result === 'string') {
                    try { return JSON.parse(result.result); } catch { return result; }
                }
                return result.result || result;
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.exportCatalog',
        description: 'Export the full asset catalog as JSON string.',
        inputSchema: { type: 'object', properties: {} },
        handler: async () => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                const result = await pluginCaller('studio.eval', {
                    code: 'return Bakable.AssetOrganizer.exportCatalog()'
                });
                return { catalog: result.result };
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.getCatalog',
        description: 'Get the asset catalog as a structured object.',
        inputSchema: { type: 'object', properties: {} },
        handler: async () => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                const code = `
                    local HttpService = game:GetService("HttpService")
                    local catalog = Bakable.AssetOrganizer.getCatalog()
                    return HttpService:JSONEncode(catalog)
                `;
                const result = await pluginCaller('studio.eval', { code });

                if (typeof result.result === 'string') {
                    try { return JSON.parse(result.result); } catch { return result; }
                }
                return result.result || result;
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.hide',
        description: 'Hide the asset organizer UI.',
        inputSchema: { type: 'object', properties: {} },
        handler: async () => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                const result = await pluginCaller('studio.eval', {
                    code: 'return Bakable.AssetOrganizer.hide()'
                });
                return result.result || result;
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.assets.reset',
        description: 'Reset asset organizer (clear scan data and UI).',
        inputSchema: { type: 'object', properties: {} },
        handler: async () => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            try {
                const result = await pluginCaller('studio.eval', {
                    code: 'return Bakable.AssetOrganizer.reset()'
                });
                return result.result || result;
            } catch (err) {
                return { error: err.message };
            }
        }
    }
];

export default tools;
