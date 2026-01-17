-- Create an Obby Platformer along the drawn path
-- The path goes from around (-26, 0, 70) through a long journey to (139, 0, 8) and back

-- Sample key points along the path for platform placement
local pathPoints = {
    Vector3.new(-26.0, 0.0, 70.6),
    Vector3.new(-42.0, 0.0, 64.9),
    Vector3.new(-53.3, 0.0, 56.8),
    Vector3.new(-67.3, 0.0, 35.2),
    Vector3.new(-79.6, 0.0, 21.5),
    Vector3.new(-95.0, 0.0, 8.9),
    Vector3.new(-119.0, 0.0, -11.6),
    Vector3.new(-134.2, 0.0, -32.2),
    Vector3.new(-144.0, 0.0, -48.1),
    Vector3.new(-167.4, 0.0, -83.1),
    Vector3.new(-179.3, 0.0, -104.5),
    Vector3.new(-181.6, 0.0, -123.1),
    Vector3.new(-165.2, 0.0, -138.6),
    Vector3.new(-126.4, 0.0, -145.2),
    Vector3.new(-93.6, 0.0, -145.7),
    Vector3.new(-50.9, 0.0, -131.5),
    Vector3.new(-11.6, 0.0, -114.6),
    Vector3.new(23.7, 0.0, -99.8),
    Vector3.new(51.0, 0.0, -82.7),
    Vector3.new(79.5, 0.0, -74.4),
    Vector3.new(105.3, 0.0, -71.1),
    Vector3.new(120.0, 0.0, -51.4),
    Vector3.new(129.3, 0.0, -15.5),
    Vector3.new(139.3, 0.0, 5.5),
    Vector3.new(131.4, 0.0, 31.0),
    Vector3.new(115.0, 0.0, 52.2),
    Vector3.new(100.3, 0.0, 67.6),
    Vector3.new(83.4, 0.0, 74.8),
    Vector3.new(61.5, 0.0, 82.7),
    Vector3.new(33.3, 0.0, 83.5),
    Vector3.new(8.5, 0.0, 81.0),
    Vector3.new(-14.2, 0.0, 74.3),
}

-- Create a folder for the obby
local obbyFolder = Instance.new("Folder")
obbyFolder.Name = "ObbyPlatformer"
obbyFolder.Parent = workspace

-- Colors for platforms (rainbow gradient)
local colors = {
    BrickColor.new("Bright green"),
    BrickColor.new("Lime green"),
    BrickColor.new("Bright yellow"),
    BrickColor.new("Bright orange"),
    BrickColor.new("Bright red"),
    BrickColor.new("Magenta"),
    BrickColor.new("Bright violet"),
    BrickColor.new("Bright blue"),
    BrickColor.new("Cyan"),
    BrickColor.new("Teal"),
}

-- Create platforms along the path
local baseHeight = 5 -- Starting height
local heightVariation = 0 -- Will increase gradually

for i, point in ipairs(pathPoints) do
    -- Create platform
    local platform = Instance.new("Part")
    platform.Name = "Platform_" .. i

    -- Vary the size for more interesting gameplay
    local sizeVariant = (i % 3)
    if sizeVariant == 0 then
        platform.Size = Vector3.new(6, 1, 6)
    elseif sizeVariant == 1 then
        platform.Size = Vector3.new(5, 1, 5)
    else
        platform.Size = Vector3.new(4, 1, 4)
    end

    -- Gradually increase height to make it more challenging
    heightVariation = math.sin(i / #pathPoints * math.pi) * 15
    local platformY = baseHeight + heightVariation + (i * 0.5)

    platform.Position = Vector3.new(point.X, platformY, point.Z)
    platform.Anchored = true
    platform.Material = Enum.Material.Neon
    platform.BrickColor = colors[(i % #colors) + 1]
    platform.Parent = obbyFolder

    -- Add platform number label
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Size = UDim2.new(0, 50, 0, 50)
    billboardGui.StudsOffset = Vector3.new(0, 3, 0)
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = platform

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Text = tostring(i)
    textLabel.TextColor3 = Color3.new(1, 1, 1)
    textLabel.TextScaled = true
    textLabel.Font = Enum.Font.GothamBold
    textLabel.Parent = billboardGui
end

-- Create start platform (larger, green)
local startPlatform = Instance.new("Part")
startPlatform.Name = "StartPlatform"
startPlatform.Size = Vector3.new(12, 2, 12)
startPlatform.Position = Vector3.new(-26, 3, 70)
startPlatform.Anchored = true
startPlatform.Material = Enum.Material.Grass
startPlatform.BrickColor = BrickColor.new("Bright green")
startPlatform.Parent = obbyFolder

-- Add START sign
local startSign = Instance.new("Part")
startSign.Name = "StartSign"
startSign.Size = Vector3.new(6, 4, 0.5)
startSign.Position = Vector3.new(-26, 8, 64)
startSign.Anchored = true
startSign.Material = Enum.Material.SmoothPlastic
startSign.BrickColor = BrickColor.new("Bright green")
startSign.Parent = obbyFolder

local startGui = Instance.new("SurfaceGui")
startGui.Face = Enum.NormalId.Front
startGui.Parent = startSign

local startText = Instance.new("TextLabel")
startText.Size = UDim2.new(1, 0, 1, 0)
startText.BackgroundTransparency = 1
startText.Text = "START"
startText.TextColor3 = Color3.new(1, 1, 1)
startText.TextScaled = true
startText.Font = Enum.Font.GothamBold
startText.Parent = startGui

-- Create finish platform (larger, gold)
local finishPlatform = Instance.new("Part")
finishPlatform.Name = "FinishPlatform"
finishPlatform.Size = Vector3.new(12, 2, 12)
finishPlatform.Position = Vector3.new(-14, 20, 74)
finishPlatform.Anchored = true
finishPlatform.Material = Enum.Material.Neon
finishPlatform.BrickColor = BrickColor.new("Bright yellow")
finishPlatform.Parent = obbyFolder

-- Add FINISH sign
local finishSign = Instance.new("Part")
finishSign.Name = "FinishSign"
finishSign.Size = Vector3.new(6, 4, 0.5)
finishSign.Position = Vector3.new(-14, 25, 68)
finishSign.Anchored = true
finishSign.Material = Enum.Material.SmoothPlastic
finishSign.BrickColor = BrickColor.new("Bright yellow")
finishSign.Parent = obbyFolder

local finishGui = Instance.new("SurfaceGui")
finishGui.Face = Enum.NormalId.Front
finishGui.Parent = finishSign

local finishText = Instance.new("TextLabel")
finishText.Size = UDim2.new(1, 0, 1, 0)
finishText.BackgroundTransparency = 1
finishText.Text = "FINISH!"
finishText.TextColor3 = Color3.new(0, 0, 0)
finishText.TextScaled = true
finishText.Font = Enum.Font.GothamBold
finishText.Parent = finishGui

-- Add some bonus checkpoint platforms (pink, for shortcuts)
local bonusPositions = {
    Vector3.new(-100, 12, -50),
    Vector3.new(-50, 15, -100),
    Vector3.new(50, 18, -60),
    Vector3.new(100, 15, 0),
    Vector3.new(50, 12, 60)
}

for i, pos in ipairs(bonusPositions) do
    local bonusPlatform = Instance.new("Part")
    bonusPlatform.Name = "BonusPlatform_" .. i
    bonusPlatform.Size = Vector3.new(4, 1, 4)
    bonusPlatform.Position = pos
    bonusPlatform.Anchored = true
    bonusPlatform.Material = Enum.Material.Neon
    bonusPlatform.BrickColor = BrickColor.new("Hot pink")
    bonusPlatform.Parent = obbyFolder
end

print("✅ Obby Platformer created with " .. #pathPoints .. " platforms!")
print("📍 Start at the green platform near (-26, 3, 70)")
print("🏁 Finish at the golden platform near (-14, 20, 74)")
print("🌈 Platforms are color-coded and numbered for easy navigation!")
print("💗 5 bonus pink platforms added for extra challenge!")
