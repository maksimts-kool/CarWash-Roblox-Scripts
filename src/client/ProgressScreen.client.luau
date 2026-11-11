-- Animates the ProgressScreen at the entrance (CarWash.ProgressScreen) on each
-- player's client, so the tweens stay smooth and use no network traffic.
-- The server (WashLine) picks which frame is visible: Select, Good or Occupied.

local TweenService = game:GetService("TweenService")

local BUBBLE_INTERVAL = 0.45
local TILE_SIZE = 100
local STATE_NAMES = {"Select", "Good", "Occupied"}

local gui = workspace:WaitForChild("CarWash"):WaitForChild("ProgressScreen"):WaitForChild("Screen"):WaitForChild("SurfaceGui")

local POP_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local activeTweens = {}
local animationId = 0

local function loopInfo(duration)
	return TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
end

local function spinInfo(duration)
	return TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
end

local function play(instance, info, goal)
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	table.insert(activeTweens, tween)
end

local function waitPath(root, ...)
	for _, name in {...} do
		root = root:WaitForChild(name)
	end
	return root
end

local function loadState(name)
	local frame = gui:WaitForChild(name)
	local badge = waitPath(frame, "StatusPanel", "Badge")
	local icon = badge:WaitForChild("Icon")
	local card = frame:WaitForChild("StatusCard")

	return {
		frame = frame,
		backdrop = frame:WaitForChild("Backdrop"),
		pattern = waitPath(frame, "Backdrop", "Pattern"),
		badgeScale = badge:WaitForChild("UIScale"),
		ring = badge:WaitForChild("UIStroke"),
		icon = icon,
		pip = icon:WaitForChild("StatusPip"),
		card = card,
		cardScale = card:WaitForChild("UIScale"),
		cardHome = card.Position,
	}
end

local STATE_ANIMATIONS = {
	Select = function(parts)
		local drop = parts.pip:WaitForChild("Drop")
		drop.Position = UDim2.fromOffset(33, 30)
		play(drop, loopInfo(0.8), {Position = UDim2.fromOffset(33, 36)})
	end,

	Good = function(parts)
		local scale = parts.pip:WaitForChild("UIScale")
		scale.Scale = 1
		play(scale, loopInfo(0.6), {Scale = 1.12})
	end,

	Occupied = function(parts)
		local minute = parts.pip:WaitForChild("MinutePivot")
		local hour = parts.pip:WaitForChild("HourPivot")
		minute.Rotation = 0
		hour.Rotation = 0
		play(minute, spinInfo(2), {Rotation = 360})
		play(hour, spinInfo(24), {Rotation = 360})
	end,
}

local function spawnBubble(backdrop)
	local size = math.random(12, 34)
	local x = math.random()

	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(0.5, 0.5)
	bubble.Position = UDim2.new(x, 0, 1, size)
	bubble.Size = UDim2.fromOffset(size, size)
	bubble.BackgroundColor3 = Color3.new(1, 1, 1)
	bubble.BackgroundTransparency = 0.55
	bubble.BorderSizePixel = 0
	bubble.ZIndex = 3

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = bubble

	bubble.Parent = backdrop

	local rise = TweenService:Create(
		bubble,
		TweenInfo.new(math.random(40, 70) / 10, Enum.EasingStyle.Linear),
		{Position = UDim2.new(x, 0, 0, -size), BackgroundTransparency = 0.9}
	)
	rise.Completed:Once(function()
		bubble:Destroy()
	end)
	rise:Play()
end

local function stopAnimations()
	animationId += 1

	for _, tween in activeTweens do
		tween:Cancel()
	end
	table.clear(activeTweens)
end

local function startState(name, parts)
	stopAnimations()
	local id = animationId

	-- Entrance
	parts.badgeScale.Scale = 0.6
	play(parts.badgeScale, POP_INFO, {Scale = 1})
	parts.cardScale.Scale = 0.85
	play(parts.cardScale, POP_INFO, {Scale = 1})
	parts.card.Position = parts.cardHome + UDim2.fromOffset(0, 40)
	play(parts.card, POP_INFO, {Position = parts.cardHome})

	-- Background
	parts.backdrop.ClipsDescendants = true
	parts.pattern.Size = UDim2.new(1, TILE_SIZE, 1, TILE_SIZE)
	parts.pattern.Position = UDim2.fromOffset(-TILE_SIZE, -TILE_SIZE)
	play(parts.pattern, spinInfo(6), {Position = UDim2.fromOffset(0, 0)})

	-- Badge
	parts.ring.Thickness = 12
	parts.ring.Transparency = 0.45
	play(parts.ring, loopInfo(1.2), {Thickness = 20, Transparency = 0.75})
	parts.icon.Position = UDim2.new(0.5, 0, 0.5, 2)
	play(parts.icon, loopInfo(0.9), {Position = UDim2.new(0.5, 0, 0.5, -2)})

	STATE_ANIMATIONS[name](parts)

	task.spawn(function()
		while animationId == id do
			spawnBubble(parts.backdrop)
			task.wait(BUBBLE_INTERVAL)
		end
	end)
end

for _, name in STATE_NAMES do
	local parts = loadState(name)

	parts.frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if parts.frame.Visible then
			startState(name, parts)
		end
	end)

	if parts.frame.Visible then
		startState(name, parts)
	end
end
