/**
 * Gemini API integration for map planning
 *
 * Workflow:
 * 1. Nano Banana Pro: User intent + asset pack screenshot → Conceptual image
 * 2. Gemini 3 Flash: Asset catalog + conceptual image → Building plan
 * 3. Map builder subagent: Uses plan to generate Lua script
 */

const GEMINI_3_FLASH_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent';
const NANO_BANANA_PRO_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3-pro-image-preview:generateContent';

/**
 * Build the prompt for Gemini to generate a map plan
 */
function buildMapPlanPrompt(catalog, userRequest, mapSize) {
    return `You are a Roblox map designer. Analyze this asset pack screenshot and catalog.

ASSET CATALOG:
${JSON.stringify(catalog, null, 2)}

USER REQUEST:
${userRequest}

MAP SIZE: ${mapSize}x${mapSize} studs

Generate a detailed "Procedural Generation Manifest" with:

1. GLOBAL SPECIFICATIONS
- Total size, style description
- Perimeter treatment (fence type, if any)
- Path/road system layout

2. ZONE DEFINITIONS
For each zone provide:
- Name and theme
- Region coordinates (assume center is 0,0, so X and Z range from -${mapSize/2} to ${mapSize/2})
- Floor color (use BrickColor names like "Bright green", "Dark green", "Bright yellow", "Medium stone grey")
- Dominant assets from the catalog (use EXACT names from catalog)
- Density rules (e.g., "1 tree per 15x15 stud area" = density 0.0044)
- Rotation type: "upright" (Y-axis only) for trees/buildings, "chaos" (random) for rocks

3. ASSET PLACEMENT LOGIC
- Scatter algorithm for natural areas (random placement with density)
- Grid algorithm for organized areas (spacing, alignment)
- Focal rules (benches face paths, buildings face roads)

4. HERO STRUCTURES (Landmarks)
- Exact coordinates for key buildings/features
- Rotation and facing direction
- Surrounding decoration rules

5. VISUAL SUMMARY
- One-line description per zone for quick verification

IMPORTANT:
- Use ONLY asset names that exist in the catalog
- Provide coordinates as {x, z} pairs (Y is calculated from ground)
- Density is items per square stud (e.g., 1 per 400 sq studs = 0.0025)
- Format as structured text that can be parsed programmatically
- Be specific with coordinates and numbers`;
}

/**
 * Call Gemini API with image and prompt
 * @param {string} imageBase64 - Base64 encoded screenshot
 * @param {Object} catalog - Asset catalog with sizes
 * @param {string} userRequest - User's map description
 * @param {number} mapSize - Map size in studs
 * @returns {Promise<Object>} - Gemini response with map plan
 */
export async function generateMapPlan(imageBase64, catalog, userRequest, mapSize = 400) {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        throw new Error('GEMINI_API_KEY not set in environment');
    }

    const prompt = buildMapPlanPrompt(catalog, userRequest, mapSize);

    const requestBody = {
        contents: [{
            parts: [
                {
                    inline_data: {
                        mime_type: 'image/png',
                        data: imageBase64
                    }
                },
                {
                    text: prompt
                }
            ]
        }],
        generationConfig: {
            temperature: 0.7,
            maxOutputTokens: 8192
        }
    };

    console.log('[Gemini] Sending map plan request...');
    console.log('[Gemini] Assets:', catalog.length, 'items');
    console.log('[Gemini] Map size:', mapSize);
    console.log('[Gemini] Request:', userRequest.substring(0, 100) + '...');

    const response = await fetch(`${GEMINI_3_FLASH_URL}?key=${apiKey}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(requestBody)
    });

    if (!response.ok) {
        const error = await response.text();
        console.error('[Gemini] API error:', error);
        throw new Error(`Gemini API error: ${response.status} - ${error}`);
    }

    const data = await response.json();
    console.log('[Gemini] Response received');

    // Extract text from response
    const text = data.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) {
        throw new Error('No text in Gemini response');
    }

    return {
        raw: text,
        parsed: parseMapPlan(text, mapSize)
    };
}

/**
 * Parse Gemini's text response into structured map plan
 * This is a best-effort parser - Gemini's output may vary
 */
function parseMapPlan(text, mapSize) {
    const plan = {
        size: mapSize,
        zones: [],
        landmarks: [],
        paths: [],
        perimeter: null,
        raw: text
    };

    // Try to extract zones
    const zoneMatches = text.matchAll(/Zone\s*[A-Z]?:?\s*([^\n]+)\nRegion:\s*([^\n]+)/gi);
    for (const match of zoneMatches) {
        const zoneName = match[1].trim();
        const regionText = match[2].trim();

        // Try to parse region coordinates
        const coords = regionText.match(/X\s*[><=]+\s*(-?\d+).*Z\s*[><=]+\s*(-?\d+)/i);

        plan.zones.push({
            name: zoneName,
            regionText: regionText,
            coords: coords ? { x: parseInt(coords[1]), z: parseInt(coords[2]) } : null
        });
    }

    // Try to extract landmarks
    const landmarkMatches = text.matchAll(/Place\s+(\w+)\s+at\s*\(?\s*(-?\d+)\s*,?\s*Y?\s*,?\s*(-?\d+)\s*\)?/gi);
    for (const match of landmarkMatches) {
        plan.landmarks.push({
            name: match[1],
            position: { x: parseInt(match[2]), z: parseInt(match[3]) }
        });
    }

    return plan;
}

/**
 * Generate a conceptual map image using Nano Banana Pro
 * @param {string|null} assetPackScreenshot - Base64 encoded screenshot of asset pack (optional)
 * @param {string} userIntent - User's description of desired map
 * @param {Object} options - Generation options
 * @returns {Promise<Object>} - Contains base64 image and text description
 */
export async function generateConceptImage(assetPackScreenshot, userIntent, options = {}) {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        throw new Error('GEMINI_API_KEY not set');
    }

    const {
        aspectRatio = '1:1',
        imageSize = '1K',
        style = 'classic Roblox stud style, blocky low-poly aesthetic with visible studs on parts'
    } = options;

    // Build prompt based on whether we have an asset pack screenshot
    const hasAssets = !!assetPackScreenshot;

    const prompt = hasAssets
        ? `You are a Roblox map concept artist. Look at this asset pack screenshot showing the available 3D models.

USER REQUEST: ${userIntent}

Generate a TOP-DOWN conceptual map image showing how these assets should be arranged. The image should be:
- Bird's eye view (looking straight down)
- Clear zones and regions visible
- Show placement of key landmarks
- Use ${style}
- Make it look like a game map blueprint/plan

This conceptual image will be used by another AI to generate the actual building instructions.`
        : `You are a Roblox map concept artist creating a map in ${style}.

USER REQUEST: ${userIntent}

Generate a TOP-DOWN conceptual map image. The image should be:
- Bird's eye view (looking straight down)
- Clear zones and regions visible
- Show placement of key structures and landmarks
- Use ${style} - blocky, colorful, with visible studs on surfaces
- Make it look like a Roblox game map blueprint

NOTE: No pre-made assets are available. The map will be built from basic Parts (blocks, cylinders, wedges) with classic Roblox studs. Design accordingly - keep shapes simple and blocky.

This conceptual image will be used by another AI to generate Luau code that builds the map from scratch.`;

    // Build request parts
    const parts = [];
    if (hasAssets) {
        parts.push({
            inline_data: {
                mime_type: 'image/png',
                data: assetPackScreenshot
            }
        });
    }
    parts.push({ text: prompt });

    const requestBody = {
        contents: [{ parts }],
        generationConfig: {
            responseModalities: ['TEXT', 'IMAGE'],
            imageConfig: {
                aspectRatio: aspectRatio,
                imageSize: imageSize
            },
            temperature: 0.8,
            maxOutputTokens: 2048
        }
    };

    console.log('[Nano Banana Pro] Generating conceptual map image...');
    console.log('[Nano Banana Pro] Style:', style);
    console.log('[Nano Banana Pro] Has asset pack:', hasAssets);
    console.log('[Nano Banana Pro] User intent:', userIntent.substring(0, 100) + '...');

    const response = await fetch(`${NANO_BANANA_PRO_URL}?key=${apiKey}`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(requestBody)
    });

    if (!response.ok) {
        const error = await response.text();
        console.error('[Nano Banana Pro] API error:', error);
        throw new Error(`Nano Banana Pro API error: ${response.status} - ${error}`);
    }

    const data = await response.json();
    console.log('[Nano Banana Pro] Response received');

    // Extract image and text from response
    const parts = data.candidates?.[0]?.content?.parts || [];
    let imageBase64 = null;
    let description = null;

    for (const part of parts) {
        if (part.inline_data?.data) {
            imageBase64 = part.inline_data.data;
        }
        if (part.text) {
            description = part.text;
        }
    }

    if (!imageBase64) {
        throw new Error('No image in Nano Banana Pro response');
    }

    return {
        imageBase64,
        description,
        mimeType: 'image/png'
    };
}

/**
 * Full map generation workflow:
 * 1. Nano Banana Pro: user intent + optional asset screenshot → conceptual image
 * 2. Gemini 3 Flash: catalog + conceptual image → building plan
 *
 * If no asset pack is provided, map builder will build from basic Parts (classic Roblox stud style)
 * or search toolbox for assets (future feature).
 *
 * @param {Object} options
 * @param {string} options.userIntent - User's description of desired map
 * @param {string|null} options.assetPackScreenshot - Screenshot of assets (optional)
 * @param {Array} options.catalog - Asset catalog (optional, defaults to empty)
 * @param {number} options.mapSize - Map size in studs (default 400)
 * @param {string} options.style - Visual style (default: classic Roblox stud)
 */
export async function generateFullMapPlan(options) {
    // Handle both old signature (screenshot, catalog, intent, size) and new options object
    let config;
    if (typeof options === 'object' && options !== null && 'userIntent' in options) {
        config = options;
    } else {
        // Backwards compatibility: old positional args
        const [assetPackScreenshot, catalog, userIntent, mapSize] = arguments;
        config = { assetPackScreenshot, catalog, userIntent, mapSize };
    }

    const {
        userIntent,
        assetPackScreenshot = null,
        catalog = [],
        mapSize = 400,
        style = 'classic Roblox stud style, blocky low-poly aesthetic with visible studs on parts'
    } = config;

    const hasAssets = !!assetPackScreenshot && catalog.length > 0;

    console.log('[Map Planner] Starting full workflow...');
    console.log('[Map Planner] Mode:', hasAssets ? 'Asset-based' : 'Build from parts (classic stud)');
    console.log('[Map Planner] Style:', style);

    // Step 1: Generate conceptual image with Nano Banana Pro
    console.log('[Map Planner] Step 1: Generating conceptual image with Nano Banana Pro...');
    const conceptResult = await generateConceptImage(assetPackScreenshot, userIntent, { style });

    // Step 2: Generate building plan with Gemini 3 Flash using the conceptual image
    console.log('[Map Planner] Step 2: Generating building plan with Gemini 3 Flash...');
    const planResult = await generateMapPlan(conceptResult.imageBase64, catalog, userIntent, mapSize);

    return {
        conceptImage: conceptResult.imageBase64,
        conceptDescription: conceptResult.description,
        buildingPlan: planResult.raw,
        parsedPlan: planResult.parsed,
        catalog,
        mapSize,
        style,
        buildMode: hasAssets ? 'assets' : 'parts'
    };
}

export default {
    generateMapPlan,
    generateConceptImage,
    generateFullMapPlan
};
