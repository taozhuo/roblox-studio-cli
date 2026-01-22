/**
 * MCP Tool: Map Planner
 *
 * Workflow:
 * 1. Nano Banana Pro: User intent + asset pack screenshot → Conceptual image
 * 2. Gemini 3 Flash: Asset catalog + conceptual image → Building plan
 * 3. Map builder subagent: Uses plan to generate Lua script
 */

import { generateMapPlan, generateConceptImage, generateFullMapPlan } from '../../services/gemini.js';

let pluginCaller = null;

export function setPluginCaller(caller) {
    pluginCaller = caller;
}

export const tools = [
    {
        name: 'studio.map.generateFullPlan',
        description: `Generate a complete map plan using the full AI workflow:

1. Nano Banana Pro (Gemini 3 Pro Image): Creates a conceptual map image from user intent (+ optional asset screenshot)
2. Gemini 3 Flash: Analyzes conceptual image + asset catalog to generate building plan

TWO MODES:
- With assets: Provide screenshot + catalog → plan uses those assets
- Without assets: Only provide description → plan uses basic Parts (classic Roblox stud style)

This is the RECOMMENDED tool for map generation. Returns both the conceptual image and building plan.`,
        inputSchema: {
            type: 'object',
            properties: {
                description: {
                    type: 'string',
                    description: 'User description of desired map (e.g., "medieval village with forest and river")'
                },
                screenshot: {
                    type: 'string',
                    description: 'Base64 encoded screenshot of asset pack overview (OPTIONAL - if not provided, builds from Parts)'
                },
                catalog: {
                    type: 'array',
                    description: 'Asset catalog with names and sizes (OPTIONAL)',
                    items: {
                        type: 'object',
                        properties: {
                            name: { type: 'string' },
                            category: { type: 'string' },
                            size: {
                                type: 'object',
                                properties: {
                                    x: { type: 'number' },
                                    y: { type: 'number' },
                                    z: { type: 'number' }
                                }
                            }
                        }
                    }
                },
                mapSize: {
                    type: 'number',
                    description: 'Map size in studs (default 400)',
                    default: 400
                },
                style: {
                    type: 'string',
                    description: 'Visual style (default: "classic Roblox stud style, blocky low-poly aesthetic with visible studs on parts")',
                    default: 'classic Roblox stud style, blocky low-poly aesthetic with visible studs on parts'
                }
            },
            required: ['description']
        },
        handler: async ({ description, screenshot = null, catalog = [], mapSize = 400, style }) => {
            if (!process.env.GEMINI_API_KEY) {
                return { error: 'GEMINI_API_KEY not configured in environment' };
            }

            try {
                const result = await generateFullMapPlan({
                    userIntent: description,
                    assetPackScreenshot: screenshot,
                    catalog,
                    mapSize,
                    style
                });
                return {
                    success: true,
                    buildMode: result.buildMode,
                    conceptImage: result.conceptImage,
                    conceptDescription: result.conceptDescription,
                    buildingPlan: result.buildingPlan,
                    parsedPlan: result.parsedPlan
                };
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.map.generateConceptImage',
        description: `Generate a conceptual map image using Nano Banana Pro (Gemini 3 Pro Image).

Takes user intent (+ optional asset screenshot) and generates a top-down conceptual map image.

TWO MODES:
- With assets: Provide screenshot → shows how those assets should be arranged
- Without assets: No screenshot → shows map layout for building from Parts

Use this if you want to preview the concept before generating the full building plan.`,
        inputSchema: {
            type: 'object',
            properties: {
                description: {
                    type: 'string',
                    description: 'User description of desired map'
                },
                screenshot: {
                    type: 'string',
                    description: 'Base64 encoded screenshot of asset pack overview (OPTIONAL)'
                },
                style: {
                    type: 'string',
                    description: 'Visual style (default: classic Roblox stud style)',
                    default: 'classic Roblox stud style, blocky low-poly aesthetic with visible studs on parts'
                },
                aspectRatio: {
                    type: 'string',
                    description: 'Image aspect ratio (default "1:1")',
                    default: '1:1'
                },
                imageSize: {
                    type: 'string',
                    description: 'Image size: "1K", "2K", or "4K" (default "1K")',
                    default: '1K'
                }
            },
            required: ['description']
        },
        handler: async ({ description, screenshot = null, style, aspectRatio = '1:1', imageSize = '1K' }) => {
            if (!process.env.GEMINI_API_KEY) {
                return { error: 'GEMINI_API_KEY not configured in environment' };
            }

            try {
                const result = await generateConceptImage(screenshot, description, { style, aspectRatio, imageSize });
                return {
                    success: true,
                    imageBase64: result.imageBase64,
                    description: result.description
                };
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.map.generatePlan',
        description: `Generate a building plan using Gemini 3 Flash (Step 2 only).

Takes an image (conceptual or screenshot) + asset catalog and generates a structured building manifest.

NOTE: Prefer studio.map.generateFullPlan which runs the complete workflow.`,
        inputSchema: {
            type: 'object',
            properties: {
                screenshot: {
                    type: 'string',
                    description: 'Base64 encoded image (conceptual image or asset screenshot)'
                },
                catalog: {
                    type: 'array',
                    description: 'Asset catalog with names and sizes',
                    items: {
                        type: 'object',
                        properties: {
                            name: { type: 'string' },
                            category: { type: 'string' },
                            size: {
                                type: 'object',
                                properties: {
                                    x: { type: 'number' },
                                    y: { type: 'number' },
                                    z: { type: 'number' }
                                }
                            }
                        }
                    }
                },
                description: {
                    type: 'string',
                    description: 'User description of desired map (e.g., "medieval village with forest and river")'
                },
                mapSize: {
                    type: 'number',
                    description: 'Map size in studs (default 400)',
                    default: 400
                }
            },
            required: ['screenshot', 'catalog', 'description']
        },
        handler: async ({ screenshot, catalog, description, mapSize = 400 }) => {
            if (!process.env.GEMINI_API_KEY) {
                return { error: 'GEMINI_API_KEY not configured in environment' };
            }

            try {
                const result = await generateMapPlan(screenshot, catalog, description, mapSize);
                return {
                    success: true,
                    plan: result.raw,
                    parsed: result.parsed
                };
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.map.catalogAssets',
        description: `Catalog all models in an asset folder with their sizes and categories.
Returns an array of assets with name, category, size, and footprint.
Use this before calling studio.map.generatePlan.`,
        inputSchema: {
            type: 'object',
            properties: {
                folderPath: {
                    type: 'string',
                    description: 'Path to asset folder (e.g., "Workspace/AssetPack")'
                }
            },
            required: ['folderPath']
        },
        handler: async ({ folderPath }) => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            // Use eval to catalog assets
            const code = `
local function guessCategory(name)
    local lower = name:lower()
    if lower:match("tree") or lower:match("pine") or lower:match("oak") or lower:match("palm") then return "tree" end
    if lower:match("rock") or lower:match("stone") or lower:match("boulder") then return "rock" end
    if lower:match("house") or lower:match("building") or lower:match("cabin") or lower:match("shop") then return "building" end
    if lower:match("fence") or lower:match("wall") or lower:match("gate") then return "fence" end
    if lower:match("bush") or lower:match("plant") or lower:match("flower") or lower:match("grass") then return "vegetation" end
    if lower:match("bench") or lower:match("table") or lower:match("chair") then return "furniture" end
    if lower:match("lamp") or lower:match("light") or lower:match("torch") then return "lighting" end
    if lower:match("road") or lower:match("path") or lower:match("tile") then return "path" end
    if lower:match("water") or lower:match("pond") or lower:match("river") then return "water" end
    if lower:match("cactus") or lower:match("mushroom") then return "vegetation" end
    if lower:match("cart") or lower:match("truck") or lower:match("vehicle") then return "vehicle" end
    if lower:match("stall") or lower:match("market") or lower:match("booth") then return "structure" end
    return "prop"
end

local folder = game
for _, part in ("${folderPath}"):split("/") do
    folder = folder:FindFirstChild(part)
    if not folder then return { error = "Folder not found: " .. part } end
end

local catalog = {}
for _, item in folder:GetChildren() do
    if item:IsA("Model") then
        local cf, size = item:GetBoundingBox()
        local pivot = item:GetPivot()
        local bottomY = cf.Position.Y - size.Y/2
        local groundOffset = pivot.Position.Y - bottomY

        table.insert(catalog, {
            name = item.Name,
            category = guessCategory(item.Name),
            size = {
                x = math.floor(size.X * 10) / 10,
                y = math.floor(size.Y * 10) / 10,
                z = math.floor(size.Z * 10) / 10
            },
            footprint = math.floor(size.X) .. "x" .. math.floor(size.Z),
            groundOffset = math.floor(groundOffset * 10) / 10
        })
    elseif item:IsA("BasePart") then
        table.insert(catalog, {
            name = item.Name,
            category = guessCategory(item.Name),
            size = {
                x = math.floor(item.Size.X * 10) / 10,
                y = math.floor(item.Size.Y * 10) / 10,
                z = math.floor(item.Size.Z * 10) / 10
            },
            footprint = math.floor(item.Size.X) .. "x" .. math.floor(item.Size.Z),
            groundOffset = 0
        })
    end
end

table.sort(catalog, function(a, b) return a.category < b.category end)

return {
    folder = "${folderPath}",
    count = #catalog,
    assets = catalog
}`;

            try {
                const result = await pluginCaller('studio.eval', { code });
                return result;
            } catch (err) {
                return { error: err.message };
            }
        }
    },
    {
        name: 'studio.map.positionCameraForOverview',
        description: `Position camera for bird's eye view of an asset folder.
Use this before capturing a screenshot for map planning.`,
        inputSchema: {
            type: 'object',
            properties: {
                folderPath: {
                    type: 'string',
                    description: 'Path to asset folder (e.g., "Workspace/AssetPack")'
                },
                angle: {
                    type: 'number',
                    description: 'Camera angle in degrees (0 = directly above, 45 = angled)',
                    default: 30
                }
            },
            required: ['folderPath']
        },
        handler: async ({ folderPath, angle = 30 }) => {
            if (!pluginCaller) {
                return { error: 'Plugin not connected' };
            }

            const code = `
local folder = game
for _, part in ("${folderPath}"):split("/") do
    folder = folder:FindFirstChild(part)
    if not folder then return { error = "Folder not found: " .. part } end
end

local minX, minZ = math.huge, math.huge
local maxX, maxZ = -math.huge, -math.huge
local maxY = 0

for _, item in folder:GetDescendants() do
    if item:IsA("BasePart") then
        local pos = item.Position
        local size = item.Size
        minX = math.min(minX, pos.X - size.X/2)
        maxX = math.max(maxX, pos.X + size.X/2)
        minZ = math.min(minZ, pos.Z - size.Z/2)
        maxZ = math.max(maxZ, pos.Z + size.Z/2)
        maxY = math.max(maxY, pos.Y + size.Y/2)
    end
end

if minX == math.huge then
    return { error = "No parts found in folder" }
end

local centerX = (minX + maxX) / 2
local centerZ = (minZ + maxZ) / 2
local width = maxX - minX
local depth = maxZ - minZ
local viewSize = math.max(width, depth)

local angleRad = math.rad(${angle})
local camHeight = viewSize * (0.8 + math.cos(angleRad) * 0.5)
local camOffset = viewSize * math.sin(angleRad) * 0.5

local camera = workspace.CurrentCamera
camera.CFrame = CFrame.lookAt(
    Vector3.new(centerX + camOffset, camHeight, centerZ + camOffset),
    Vector3.new(centerX, maxY/2, centerZ)
)

return {
    bounds = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ, maxY = maxY },
    center = { x = centerX, z = centerZ },
    viewSize = viewSize,
    cameraHeight = camHeight
}`;

            try {
                const result = await pluginCaller('studio.eval', { code });
                return result;
            } catch (err) {
                return { error: err.message };
            }
        }
    }
];

export default tools;
