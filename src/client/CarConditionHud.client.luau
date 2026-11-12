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

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0, 0.5)
panel.Position = UDim2.new(0, 12, 0.4, 0)
panel.Size = UDim2.fromOffset(200, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = rgb(18, 20, 26)
panel.BackgroundTransparency = 0.2
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = rgb(255, 255, 255)
stroke.Transparency = 0.85
stroke.Parent = panel

local padding = Instance.new("UIPadding")
for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
	(padding :: any)[side] = UDim.new(0, 10)
end
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6)
layout.Parent = panel

local function label(parent, text, font, size, color, order)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = UDim2.new(1, 0, 0, size + 2)
	l.LayoutOrder = order or 0
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
	row.Size = UDim2.new(1, 0, 0, 16)
	row.LayoutOrder = 2 + index
	row.Parent = panel

	local name = label(row, bar.label, Enum.Font.GothamMedium, 12, rgb(220, 222, 228))
	name.Size = UDim2.new(0, 44, 1, 0)

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, 48, 0.5, 0)
	track.Size = UDim2.new(1, -86, 0, 8)
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
	pct.Size = UDim2.new(0, 34, 1, 0)
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
