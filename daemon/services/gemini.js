/**
 * Gemini API integration for map planning
 * Uses Gemini 2.5 Pro vision to analyze asset packs and generate map blueprints
 */

const GEMINI_API_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent';

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

    const response = await fetch(`${GEMINI_API_URL}?key=${apiKey}`, {
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
 * Generate a conceptual map image (sends to Gemini image generation)
 * Note: This uses a different model/endpoint for image generation
 */
export async function generateConceptImage(mapPlan, style = 'isometric pixel art') {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        throw new Error('GEMINI_API_KEY not set');
    }

    // For now, just return the plan - image generation would use Imagen or similar
    console.log('[Gemini] Concept image generation not yet implemented');
    return {
        message: 'Concept image generation requires Imagen API',
        plan: mapPlan
    };
}

export default {
    generateMapPlan,
    generateConceptImage
};
