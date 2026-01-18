---
name: map-building-guide
description: Best practices for building different types of Roblox game maps
---

# Map Building Best Practices

## Universal Rules

### 1. Always Plan Before Building
- Define map bounds first (e.g., -500 to 500 studs)
- Create zone layout on paper/mentally before placing
- Know your asset sizes before placement

### 2. Ground Level Convention
- Set ground level Y = 0
- All model Y positions = groundLevel + (modelHeight / 2)
- Exception: Models with pivot at bottom use Y = 0

### 3. Spacing Rules
- Minimum 5 studs between buildings
- Paths minimum 10 studs wide (player is ~4 studs wide)
- Leave 20+ studs around spawn area

### 4. Orientation
- Buildings face paths/roads
- Use 90-degree rotations (0, 90, 180, 270)
- Front of building = negative Z direction by convention

---

## Simulator Maps

### Layout Pattern
```
[Spawn] → [Starter Zone] → [Mid Zone] → [End Zone]
   ↓
[Shop Area]
```

### Zones
1. **Spawn Area** (center, -50 to 50)
   - Open space, no obstacles
   - Clear path to first activity
   - Leaderboard/stats display nearby

2. **Starter Zone** (50-150 studs from spawn)
   - Easy activities, basic resources
   - Tutorial elements
   - Visible from spawn

3. **Progression Zones** (150+ studs)
   - Increasingly valuable resources
   - Unlock requirements visible
   - Distinct visual themes per zone

4. **Shop/Rebirth Area**
   - Near spawn but not blocking
   - All NPCs in one area
   - Clear signage

### Best Practices
- Linear progression path
- Each zone visually distinct (colors, props)
- Boundaries visible but not ugly walls
- Teleport pads for large maps

---

## Tycoon Maps

### Layout Pattern
```
[Spawn/Claim Pad] → [Base Plate] → [Expansion Areas]
         ↓
    [Droppers/Collectors]
```

### Structure
1. **Claim Pad** (entrance)
   - 20x20 studs minimum
   - Clear "CLAIM" button/pad
   - One per player slot

2. **Base Plate**
   - 100x100 to 200x200 studs
   - Flat, single color
   - Grid-aligned for building

3. **Dropper Line**
   - Linear flow: Dropper → Conveyor → Collector
   - 10 stud spacing between droppers
   - Upgrades extend the line

### Best Practices
- Tycoons should be separated (50+ studs apart)
- Each tycoon identical layout
- Central hub for purchases
- Clear ownership boundaries

---

## Obby Maps

### Layout Pattern
```
[Start] → [Stage 1] → [Stage 2] → ... → [End/Win]
              ↓ (checkpoint)
```

### Structure
1. **Stages** (10-20 studs each)
   - One main challenge per stage
   - Checkpoint at stage start
   - Kill brick = return to checkpoint

2. **Difficulty Curve**
   - Stage 1-5: Easy (wide platforms, slow)
   - Stage 6-15: Medium (smaller, moving)
   - Stage 16+: Hard (precision, speed)

3. **Checkpoints**
   - Every 3-5 stages minimum
   - Visible spawn point
   - Safe landing area (10x10 studs)

### Best Practices
- Fall = respawn, not death (unless intended)
- No invisible obstacles
- Test every jump is possible
- Skip stage option for stuck players

---

## RPG/Adventure Maps

### Layout Pattern
```
        [Dungeon]
            ↑
[Town] ← [Hub] → [Forest]
            ↓
        [Beach]
```

### Zones
1. **Hub/Town** (center)
   - Safe zone, no enemies
   - All NPCs, shops, quests
   - Fast travel point

2. **Adventure Zones** (branching from hub)
   - Increasing difficulty from hub
   - Unique enemy types per zone
   - Boss arena at zone end

3. **Dungeons** (instanced or separate)
   - Linear path to boss
   - Puzzle elements
   - Treasure rooms

### Best Practices
- Natural barriers (mountains, water) for zone edges
- Landmarks for navigation
- Mob spawn points away from paths
- Safe spots every 50-100 studs

---

## Horror Maps

### Layout Pattern
```
[Safe Start] → [Tension Build] → [First Scare] → [Chase] → [Escape]
```

### Atmosphere
1. **Lighting**
   - Dark ambient (0.1-0.3 brightness)
   - Flickering lights
   - Limited player flashlight

2. **Sound Zones**
   - Ambient creepy sounds
   - Sudden loud sounds for scares
   - Silence before jumpscares

3. **Pacing**
   - 30 seconds safe exploration
   - Tension building (sounds, shadows)
   - Jump scare or chase sequence
   - Brief safe moment, repeat

### Best Practices
- Never fully dark (players need some visibility)
- Multiple paths (not pure linear)
- Hiding spots for chase sequences
- Jumpscare cooldowns (don't spam)

---

---

## Placement Rules

### Y Position Formula
```
Y = groundLevel + (modelHeight / 2)
```
- Ground level is typically Y = 0
- Get model height from bounding box
- Models with pivot at bottom: Y = groundLevel

### Spacing Formula
```
spacing = max(model1.footprint, model2.footprint) / 2 + buffer
```
- Buildings: 5 stud buffer minimum
- Trees: 2 stud buffer
- Props: 1 stud buffer

### Rotation Convention
- Buildings face roads (front = -Z direction)
- Use only 0, 90, 180, 270 degrees
- Trees/props: random rotation acceptable

---

## Ground Building & Z-Fighting

**Z-fighting** occurs when two surfaces occupy the same position, causing visual flickering.

### Option 1: Remove Baseplate (Recommended)
If building custom ground/terrain:
```lua
local baseplate = workspace:FindFirstChild("Baseplate")
if baseplate then baseplate:Destroy() end
```

### Option 2: Offset Ground
If keeping baseplate, offset custom ground:
```lua
groundPart.Position = Vector3.new(x, 0.1, z)
```

### Option 3: Use Terrain Instead
For natural ground, use Roblox Terrain:
```lua
workspace.Terrain:FillBlock(cframe, size, Enum.Material.Grass)
```

### When to Remove Baseplate
- Building flat ground with parts
- Creating tiled floors
- Custom terrain with part-based ground
- Any surface at Y = 0

### When to Keep Baseplate
- Only placing models on it (houses, trees)
- Using it as the actual ground
- Quick prototyping

---

## Common Mistakes to Avoid

1. **Don't guess positions** - Always calculate from bounding boxes
2. **Don't skip planning** - Use map-builder before placing
3. **Don't forget validation** - Run placement-validator after building
4. **Don't ignore model sizes** - Catalog assets first
5. **Don't place without undo points** - Use history.begin/end
6. **Don't cause Z-fighting** - Remove baseplate or offset ground

---

## Performance Tips

### Part Count
- < 10,000 parts: Smooth on all devices
- 10,000-50,000: May lag on mobile
- > 50,000: Optimize or use streaming

### Optimization
- Use MeshParts over many Parts
- Enable StreamingEnabled for large maps
- Group distant objects
- Reduce unique materials

### Testing
- Test on mobile device
- Check with 10+ players
- Profile with MicroProfiler
