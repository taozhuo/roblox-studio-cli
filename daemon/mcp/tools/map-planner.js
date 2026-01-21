/**
 * MCP Tool: Map Planner
 * Uses Gemini 3 Flash to generate map building plans from asset pack screenshots
 */

import { generateMapPlan } from '../../services/gemini.js';

let pluginCaller = null;

export function setPluginCaller(caller) {
    pluginCaller = caller;
}

export const tools = [
    {
        name: 'studio.map.generatePlan',
        description: `Generate a detailed map building plan using Gemini 3 Flash vision AI.

Takes a screenshot of the asset pack and generates a structured building manifest with:
- Zone definitions and coordinates
- Asset placement rules and densities
- Landmark positions
- Path/road layouts

Requires:
1. Capture viewport screenshot first (studio.captureViewport)
2. Generate asset catalog (studio.map.catalogAssets)
3. User's map description

Returns a detailed procedural generation manifest.`,
        inputSchema: {
            type: 'object',
            properties: {
                screenshot: {
                    type: 'string',
                    description: 'Base64 encoded screenshot of asset pack overview'
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
