--!strict
--[[
    UI Theme Constants for DetAI Plugin
]]

local Theme = {}

-- Colors
Theme.Colors = {
    -- Background
    Background = Color3.fromRGB(30, 30, 30),
    BackgroundLight = Color3.fromRGB(40, 40, 40),
    BackgroundDark = Color3.fromRGB(20, 20, 20),
    Surface = Color3.fromRGB(45, 45, 45),

    -- Text
    Text = Color3.fromRGB(220, 220, 220),
    TextMuted = Color3.fromRGB(150, 150, 150),
    TextDim = Color3.fromRGB(100, 100, 100),

    -- Accent
    Primary = Color3.fromRGB(0, 162, 255),
    PrimaryHover = Color3.fromRGB(30, 180, 255),
    Success = Color3.fromRGB(40, 200, 100),
    Warning = Color3.fromRGB(255, 180, 0),
    Error = Color3.fromRGB(255, 80, 80),

    -- Status
    Connected = Color3.fromRGB(40, 200, 100),
    Disconnected = Color3.fromRGB(150, 150, 150),
    Syncing = Color3.fromRGB(255, 180, 0),

    -- Borders
    Border = Color3.fromRGB(60, 60, 60),
    BorderFocus = Color3.fromRGB(0, 162, 255),

    -- Cards
    CardBackground = Color3.fromRGB(50, 50, 50),
    CardHover = Color3.fromRGB(60, 60, 60),

    -- Scrollbar
    ScrollbarTrack = Color3.fromRGB(30, 30, 30),
    ScrollbarThumb = Color3.fromRGB(80, 80, 80)
}

-- Fonts
Theme.Fonts = {
    Default = Enum.Font.Gotham,
    Bold = Enum.Font.GothamBold,
    Code = Enum.Font.Code
}

-- Sizes
Theme.Sizes = {
    -- Text
    TextSmall = 11,
    TextNormal = 13,
    TextLarge = 15,
    TextTitle = 18,

    -- Spacing
    PaddingSmall = 4,
    PaddingNormal = 8,
    PaddingLarge = 12,

    -- Components
    ButtonHeight = 28,
    InputHeight = 28,
    HeaderHeight = 36,
    TabHeight = 32,

    -- Borders
    BorderRadius = 4,
    BorderWidth = 1
}

-- Create styled button
function Theme.createButton(props: {
    parent: GuiObject,
    text: string,
    position: UDim2?,
    size: UDim2?,
    color: Color3?,
    onClick: (() -> ())?
}): TextButton
    local button = Instance.new("TextButton")
    button.Name = props.text:gsub("%s+", "")
    button.Text = props.text
    button.Font = Theme.Fonts.Default
    button.TextSize = Theme.Sizes.TextNormal
    button.TextColor3 = Theme.Colors.Text
    button.BackgroundColor3 = props.color or Theme.Colors.Primary
    button.BorderSizePixel = 0
    button.Size = props.size or UDim2.new(0, 100, 0, Theme.Sizes.ButtonHeight)
    button.Position = props.position or UDim2.new(0, 0, 0, 0)
    button.Parent = props.parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.Sizes.BorderRadius)
    corner.Parent = button

    if props.onClick then
        button.MouseButton1Click:Connect(props.onClick)
    end

    -- Hover effect
    button.MouseEnter:Connect(function()
        button.BackgroundColor3 = (props.color or Theme.Colors.Primary):Lerp(Color3.new(1, 1, 1), 0.1)
    end)
    button.MouseLeave:Connect(function()
        button.BackgroundColor3 = props.color or Theme.Colors.Primary
    end)

    return button
end

-- Create styled label
function Theme.createLabel(props: {
    parent: GuiObject,
    text: string,
    position: UDim2?,
    size: UDim2?,
    font: Enum.Font?,
    textSize: number?,
    textColor: Color3?,
    textXAlignment: Enum.TextXAlignment?
}): TextLabel
    local label = Instance.new("TextLabel")
    label.Name = "Label"
    label.Text = props.text
    label.Font = props.font or Theme.Fonts.Default
    label.TextSize = props.textSize or Theme.Sizes.TextNormal
    label.TextColor3 = props.textColor or Theme.Colors.Text
    label.BackgroundTransparency = 1
    label.Size = props.size or UDim2.new(1, 0, 0, 20)
    label.Position = props.position or UDim2.new(0, 0, 0, 0)
    label.TextXAlignment = props.textXAlignment or Enum.TextXAlignment.Left
    label.Parent = props.parent

    return label
end

-- Create text input
function Theme.createInput(props: {
    parent: GuiObject,
    placeholder: string?,
    position: UDim2?,
    size: UDim2?,
    text: string?
}): TextBox
    local input = Instance.new("TextBox")
    input.Name = "Input"
    input.Text = props.text or ""
    input.PlaceholderText = props.placeholder or ""
    input.Font = Theme.Fonts.Default
    input.TextSize = Theme.Sizes.TextNormal
    input.TextColor3 = Theme.Colors.Text
    input.PlaceholderColor3 = Theme.Colors.TextDim
    input.BackgroundColor3 = Theme.Colors.BackgroundDark
    input.BorderSizePixel = 0
    input.Size = props.size or UDim2.new(1, 0, 0, Theme.Sizes.InputHeight)
    input.Position = props.position or UDim2.new(0, 0, 0, 0)
    input.TextXAlignment = Enum.TextXAlignment.Left
    input.ClearTextOnFocus = false
    input.Parent = props.parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, Theme.Sizes.BorderRadius)
    corner.Parent = input

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.Parent = input

    return input
end

-- Create scrolling frame
function Theme.createScrollFrame(props: {
    parent: GuiObject,
    position: UDim2?,
    size: UDim2?
}): ScrollingFrame
    local scroll = Instance.new("ScrollingFrame")
    scroll.Name = "ScrollFrame"
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.Size = props.size or UDim2.new(1, 0, 1, 0)
    scroll.Position = props.position or UDim2.new(0, 0, 0, 0)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ScrollBarThickness = 6
    scroll.ScrollBarImageColor3 = Theme.Colors.ScrollbarThumb
    scroll.Parent = props.parent

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, Theme.Sizes.PaddingSmall)
    layout.Parent = scroll

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, Theme.Sizes.PaddingNormal)
    padding.PaddingBottom = UDim.new(0, Theme.Sizes.PaddingNormal)
    padding.PaddingLeft = UDim.new(0, Theme.Sizes.PaddingNormal)
    padding.PaddingRight = UDim.new(0, Theme.Sizes.PaddingNormal)
    padding.Parent = scroll

    return scroll
end

return Theme
