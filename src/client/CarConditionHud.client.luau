-- A small panel showing the condition of the car you're sitting in: its
-- Condition name and Dirt / Soap / Water / Shine bars, read from the attributes
-- the server's CarCondition puts on every "WashableCar". Hidden on foot.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TAG = "WashableCar"
local EASE_RATE = 6

local player = Players.LocalPlayer

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local BARS = {
	{ key = "Dirt", label = "Dirt", color = rgb(160, 115, 70) },
	{ key = "Soap", label = "Soap", color = rgb(255, 160, 225) },
	{ key = "Wet", label = "Water", color = rgb(70, 170, 255) },
	{ key = "Shine", label = "Shine", color = rgb(255, 210, 80) },
}

local CONDITION_COLORS = {
	["Very Dirty"] = rgb(185, 120, 65),
	Dirty = rgb(200, 150, 95),
	Dusty = rgb(215, 190, 150),
	Soapy = rgb(255, 160, 225),
	Wet = rgb(90, 180, 255),
	["Wet & Dirty"] = rgb(140, 160, 180),
	Drying = rgb(160, 220, 255),
	Clean = rgb(120, 230, 140),
	Shiny = rgb(255, 220, 100),
	["Showroom Shine"] = rgb(255, 240, 170),
}

------------------------------------------------------------------------------
-- Build the panel

local gui = Instance.new("ScreenGui")
gui.Name = "CarConditionHud"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 5

-- Everything is sized in Scale so the panel looks the same on every screen.
-- The numbers are pixels on the reference screen (a MacBook: 1440 x 841
-- below the top bar), divided by the size of whatever they sit in.
local SCREEN = Vector2.new(1440, 841)
local PANEL = Vector2.new(200, 149) -- 10px padding around CONTENT
local CONTENT = Vector2.new(180, 129)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.Position = UDim2.fromScale(12 / SCREEN.X, 0.4)
panel.Size = UDim2.fromScale(PANEL.X / SCREEN.X, PANEL.Y / SCREEN.Y)
panel.BackgroundColor3 = rgb(18, 20, 26)
panel.BackgroundTransparency = 0.2
panel.Parent = gui

local aspect = Instance.new("UIAspectRatioConstraint")
aspect.AspectRatio = PANEL.X / PANEL.Y
aspect.AspectType = Enum.AspectType.FitWithinMaxSize
aspect.Parent = panel

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(10 / PANEL.Y, 0)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = rgb(255, 255, 255)
stroke.Transparency = 0.85
stroke.Parent = panel

-- outlines can't be sized in Scale: 2px on the reference screen, scaled
-- like the panel
local function sizeStroke()
	local screen = gui.AbsoluteSize
	stroke.Thickness = 2 * math.min(screen.X / SCREEN.X, screen.Y / SCREEN.Y)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeStroke)
sizeStroke()

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(10 / PANEL.X, 0)
padding.PaddingRight = UDim.new(10 / PANEL.X, 0)
padding.PaddingTop = UDim.new(10 / PANEL.Y, 0)
padding.PaddingBottom = UDim.new(10 / PANEL.Y, 0)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(6 / CONTENT.Y, 0)
layout.Parent = panel

-- TextScaled makes text as tall as the label's inner area, so pad that area
-- down to the text's reference size: it then matches the reference screen
-- and grows or shrinks with the panel.
local function textHeight(l: TextLabel, size: number, boxHeight: number)
	local pad = l:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	local edge = UDim.new((boxHeight - size) / 2 / boxHeight, 0)
	pad.PaddingTop = edge
	pad.PaddingBottom = edge
	pad.Parent = l
end

local function label(parent, text, font, size, color, order)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = font
	l.TextScaled = true
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = UDim2.fromScale(1, (size + 2) / CONTENT.Y)
	l.LayoutOrder = order or 0
	textHeight(l, size, size + 2)
	l.Parent = parent
	return l
end

label(panel, "CAR CONDITION", Enum.Font.GothamBold, 11, rgb(170, 175, 185), 1)
local status = label(panel, "Clean", Enum.Font.GothamBlack, 20, CONDITION_COLORS.Clean, 2)

local fills = {}
local percents = {}
for index, bar in BARS do
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 16 / CONTENT.Y)
	row.LayoutOrder = 2 + index
	row.Parent = panel

	local name = label(row, bar.label, Enum.Font.GothamMedium, 12, rgb(220, 222, 228))
	name.Size = UDim2.fromScale(44 / CONTENT.X, 1)
	textHeight(name, 12, 16)

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.fromScale(48 / CONTENT.X, 0.5)
	track.Size = UDim2.fromScale((CONTENT.X - 86) / CONTENT.X, 0.5)
	track.BackgroundColor3 = rgb(255, 255, 255)
	track.BackgroundTransparency = 0.85
	track.Parent = row
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = bar.color
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	fills[bar.key] = fill

	local pct = label(row, "0%", Enum.Font.GothamMedium, 12, rgb(170, 175, 185))
	pct.TextXAlignment = Enum.TextXAlignment.Right
	pct.AnchorPoint = Vector2.new(1, 0)
	pct.Position = UDim2.fromScale(1, 0)
	pct.Size = UDim2.fromScale(34 / CONTENT.X, 1)
	textHeight(pct, 12, 16)
	percents[bar.key] = pct
end

gui.Parent = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------------
-- Follow the car you're in

local function carOf(seat: Instance?): Instance?
	local node = seat
	while node and node ~= workspace do
		if CollectionService:HasTag(node, TAG) then
			return node
		end
		node = node.Parent
	end
	return nil
end

local shown = {}
local lastCar = nil

RunService.Heartbeat:Connect(function(deltaTime)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local car = humanoid and carOf(humanoid.SeatPart)
	gui.Enabled = car ~= nil
	if not car then
		lastCar = nil
		return
	end

	local snap = car ~= lastCar -- just got in: no sliding bars
	lastCar = car
	local blend = 1 - math.exp(-EASE_RATE * deltaTime)
	for _, bar in BARS do
		local target = car:GetAttribute(bar.key) or 0
		shown[bar.key] = if snap then target else (shown[bar.key] or 0) + (target - (shown[bar.key] or 0)) * blend
		fills[bar.key].Size = UDim2.fromScale(math.clamp(shown[bar.key], 0, 1), 1)
		percents[bar.key].Text = `{math.floor(target * 100 + 0.5)}%`
	end

	local condition = car:GetAttribute("Condition") or "Clean"
	status.Text = condition
	local color = CONDITION_COLORS[condition] or rgb(255, 255, 255)
	status.TextColor3 = if snap then color else status.TextColor3:Lerp(color, blend)
end)
