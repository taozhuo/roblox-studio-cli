# Demolition System Skill

Use this skill when the user asks you to:
- Create destructible objects, buildings, or structures
- Break models into pieces on impact/damage
- Implement explosion or physics-based destruction
- Add debris, rubble, or fragmentation effects
- Build health/damage systems for objects

## Core Concepts

### 1. Pre-Fractured vs Runtime Fracturing

**Pre-Fractured (Recommended for Roblox)**
- Model is already split into pieces in edit mode
- Pieces held together with WeldConstraints or hidden
- On destruction, welds break or pieces become visible
- Better performance, predictable results

**Runtime Fracturing (Advanced)**
- Use GeometryService:SubtractAsync() to cut meshes
- More dynamic but performance-heavy
- Limited to simple shapes

### 2. Basic Architecture

```
DestructibleModel/
├── Pieces/           -- Pre-fractured fragments
│   ├── Fragment1
│   ├── Fragment2
│   └── ...
├── IntactMesh        -- Optional: solid mesh shown when undamaged
└── DemolitionScript  -- Handles breaking logic
```

---

## MCP Tools for Demolition

### Create Destructible Object
Use `studio.eval` to set up a destructible model:

```lua
-- Create a simple destructible wall
local model = Instance.new("Model")
model.Name = "DestructibleWall"
model.Parent = workspace

-- Create pieces (pre-fractured)
local pieceSize = Vector3.new(2, 4, 1)
local rows, cols = 3, 5

for row = 0, rows - 1 do
    for col = 0, cols - 1 do
        local piece = Instance.new("Part")
        piece.Name = "Piece_" .. row .. "_" .. col
        piece.Size = pieceSize
        piece.Position = Vector3.new(col * pieceSize.X, row * pieceSize.Y + pieceSize.Y/2, 0)
        piece.Anchored = true
        piece.Material = Enum.Material.Concrete
        piece.BrickColor = BrickColor.new("Medium stone grey")
        piece.Parent = model

        -- Add health attribute
        piece:SetAttribute("Health", 100)
        piece:SetAttribute("MaxHealth", 100)
    end
end

model.PrimaryPart = model:FindFirstChild("Piece_0_0")
print("Created destructible wall with", rows * cols, "pieces")
```

### Apply Damage to Piece
```lua
local function damagepiece(piece, damage)
    local health = piece:GetAttribute("Health") or 100
    health = health - damage
    piece:SetAttribute("Health", health)

    if health <= 0 then
        -- Break the piece
        piece.Anchored = false
        piece.CanCollide = true

        -- Apply explosion force
        local force = Instance.new("BodyVelocity")
        force.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        force.Velocity = Vector3.new(
            math.random(-20, 20),
            math.random(10, 30),
            math.random(-20, 20)
        )
        force.Parent = piece
        game:GetService("Debris"):AddItem(force, 0.1)

        -- Cleanup after delay
        game:GetService("Debris"):AddItem(piece, 5)
    end
end
```

---

## Demolition Patterns

### Pattern 1: Explosion Destruction
Destroy all pieces within radius of explosion point.

```lua
local function explode(position, radius, damage)
    local model = workspace:FindFirstChild("DestructibleWall")
    if not model then return end

    for _, piece in model:GetDescendants() do
        if piece:IsA("BasePart") then
            local distance = (piece.Position - position).Magnitude
            if distance <= radius then
                -- Damage falls off with distance
                local falloff = 1 - (distance / radius)
                local actualDamage = damage * falloff

                -- Apply damage
                local health = piece:GetAttribute("Health") or 100
                health = health - actualDamage
                piece:SetAttribute("Health", health)

                if health <= 0 then
                    piece.Anchored = false

                    -- Push away from explosion
                    local direction = (piece.Position - position).Unit
                    local force = Instance.new("BodyVelocity")
                    force.MaxForce = Vector3.new(1e6, 1e6, 1e6)
                    force.Velocity = direction * (50 * falloff) + Vector3.new(0, 20, 0)
                    force.Parent = piece
                    game:GetService("Debris"):AddItem(force, 0.15)
                    game:GetService("Debris"):AddItem(piece, 8)
                end
            end
        end
    end
end

-- Example: explode at origin with radius 15, damage 150
explode(Vector3.new(0, 5, 0), 15, 150)
```

### Pattern 2: Projectile Impact
Break pieces on collision with fast-moving objects.

```lua
local function setupProjectileDestruction(projectile)
    projectile.Touched:Connect(function(hit)
        if hit:GetAttribute("Health") then
            local velocity = projectile.AssemblyLinearVelocity.Magnitude
            local damage = velocity * 0.5 -- Scale damage with speed

            local health = hit:GetAttribute("Health") - damage
            hit:SetAttribute("Health", health)

            if health <= 0 then
                hit.Anchored = false
                -- Inherit some projectile momentum
                hit.AssemblyLinearVelocity = projectile.AssemblyLinearVelocity * 0.3
                game:GetService("Debris"):AddItem(hit, 5)
            end

            projectile:Destroy()
        end
    end)
end
```

### Pattern 3: Chain Reaction / Structural Collapse
When a piece breaks, check if neighbors should also break.

```lua
local function checkStructuralIntegrity(model)
    local pieces = {}
    for _, p in model:GetDescendants() do
        if p:IsA("BasePart") and p.Anchored then
            table.insert(pieces, p)
        end
    end

    -- Find pieces with no support below them
    for _, piece in pieces do
        local ray = Ray.new(piece.Position, Vector3.new(0, -piece.Size.Y, 0))
        local hit = workspace:FindPartOnRay(ray, piece)

        local hasSupport = hit and hit:IsDescendantOf(model) and hit.Anchored
        local touchingGround = piece.Position.Y <= piece.Size.Y

        if not hasSupport and not touchingGround then
            -- No support - collapse!
            piece.Anchored = false
            game:GetService("Debris"):AddItem(piece, 8)
        end
    end
end
```

### Pattern 4: Weld-Based Destruction
Use WeldConstraints to hold pieces together, break welds on damage.

```lua
-- Setup: Weld all adjacent pieces
local function weldAdjacentPieces(model)
    local pieces = {}
    for _, p in model:GetDescendants() do
        if p:IsA("BasePart") then
            table.insert(pieces, p)
        end
    end

    for i, piece1 in pieces do
        for j = i + 1, #pieces do
            local piece2 = pieces[j]
            local distance = (piece1.Position - piece2.Position).Magnitude
            local threshold = (piece1.Size.Magnitude + piece2.Size.Magnitude) / 2

            if distance <= threshold then
                local weld = Instance.new("WeldConstraint")
                weld.Part0 = piece1
                weld.Part1 = piece2
                weld.Parent = piece1
            end
        end
    end
end

-- Destruction: Break welds when health depleted
local function breakPiece(piece)
    -- Destroy all welds connected to this piece
    for _, weld in piece:GetChildren() do
        if weld:IsA("WeldConstraint") then
            weld:Destroy()
        end
    end

    -- Also check other pieces for welds to this piece
    local model = piece:FindFirstAncestorOfClass("Model")
    if model then
        for _, other in model:GetDescendants() do
            if other:IsA("WeldConstraint") and (other.Part0 == piece or other.Part1 == piece) then
                other:Destroy()
            end
        end
    end

    piece.Anchored = false
    piece:SetAttribute("Broken", true)
end
```

---

## Visual Effects

### Dust/Debris Particles
```lua
local function addDestructionEffects(piece)
    local attachment = Instance.new("Attachment")
    attachment.Parent = piece

    local particles = Instance.new("ParticleEmitter")
    particles.Texture = "rbxassetid://1084137233" -- Smoke texture
    particles.Color = ColorSequence.new(Color3.fromRGB(150, 140, 130))
    particles.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 2)
    })
    particles.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.3),
        NumberSequenceKeypoint.new(1, 1)
    })
    particles.Lifetime = NumberRange.new(1, 2)
    particles.Rate = 50
    particles.Speed = NumberRange.new(5, 15)
    particles.SpreadAngle = Vector2.new(180, 180)
    particles.Parent = attachment

    -- Emit burst then stop
    task.delay(0.3, function()
        particles.Enabled = false
        game:GetService("Debris"):AddItem(attachment, 2)
    end)
end
```

### Sound Effects
```lua
local function playBreakSound(position)
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://287390459" -- Concrete break
    sound.Volume = 0.8
    sound.RollOffMaxDistance = 100
    sound.PlayOnRemove = true

    local part = Instance.new("Part")
    part.Anchored = true
    part.CanCollide = false
    part.Transparency = 1
    part.Size = Vector3.new(1, 1, 1)
    part.Position = position
    part.Parent = workspace

    sound.Parent = part
    sound:Play()
    game:GetService("Debris"):AddItem(part, sound.TimeLength + 0.1)
end
```

---

## Complete Demolition Script

```lua
-- ServerScriptService/DemolitionSystem
local Debris = game:GetService("Debris")

local DemolitionSystem = {}

function DemolitionSystem.setupDestructible(model)
    for _, piece in model:GetDescendants() do
        if piece:IsA("BasePart") then
            piece:SetAttribute("Health", 100)
            piece:SetAttribute("MaxHealth", 100)
            piece:SetAttribute("IsDestructible", true)
        end
    end
end

function DemolitionSystem.damage(piece, amount, sourcePosition)
    if not piece:GetAttribute("IsDestructible") then return end

    local health = piece:GetAttribute("Health") or 100
    health = math.max(0, health - amount)
    piece:SetAttribute("Health", health)

    if health <= 0 then
        DemolitionSystem.destroy(piece, sourcePosition)
    end
end

function DemolitionSystem.destroy(piece, sourcePosition)
    if piece:GetAttribute("Destroyed") then return end
    piece:SetAttribute("Destroyed", true)

    -- Break welds
    for _, child in piece:GetChildren() do
        if child:IsA("WeldConstraint") then
            child:Destroy()
        end
    end

    -- Unanchor
    piece.Anchored = false
    piece.CanCollide = true

    -- Apply force away from source
    if sourcePosition then
        local direction = (piece.Position - sourcePosition).Unit
        piece:ApplyImpulse(direction * piece:GetMass() * 50)
    end

    -- Cleanup
    Debris:AddItem(piece, 8)
end

function DemolitionSystem.explode(position, radius, damage)
    for _, piece in workspace:GetDescendants() do
        if piece:IsA("BasePart") and piece:GetAttribute("IsDestructible") then
            local distance = (piece.Position - position).Magnitude
            if distance <= radius then
                local falloff = 1 - (distance / radius)
                DemolitionSystem.damage(piece, damage * falloff, position)
            end
        end
    end
end

return DemolitionSystem
```

---

## Performance Tips

1. **Limit piece count**: Keep under 50-100 pieces per destructible object
2. **Use CanCollide groups**: Disable collision between debris pieces
3. **Aggressive cleanup**: Remove debris after 5-10 seconds
4. **LOD for debris**: Use simple shapes for small fragments
5. **Pool debris**: Reuse parts instead of creating new ones
6. **Network ownership**: Set debris network owner to nil for server control

---

## Common Issues

| Issue | Solution |
|-------|----------|
| Pieces fall through floor | Ensure CanCollide = true after unanchoring |
| Lag on explosion | Reduce piece count, use CanCollide groups |
| Welds not breaking | Check both Part0 and Part1 weld references |
| Debris floating | Apply downward impulse or let physics settle |
| Chain reactions too fast | Add small delay between structural checks |
