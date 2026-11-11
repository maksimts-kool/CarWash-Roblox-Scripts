-- Draws the Wash Time and Dry Time screens on each player's client.
-- RunContext is Client so the countdown and tweens stay smooth and use no network traffic.
--
-- WashController sets these attributes on CarWash.TimerWash and CarWash.TimerDryer:
--   State      "Idle" | "Waiting" | "Running" | "Done"
--   EndsAt     server time (workspace:GetServerTimeNow()) the countdown reaches zero
--   Total      length of the countdown in seconds, for the dial and progress bar
--   Stage      what the machine is doing now ("Triple Foam", "Drying", ...)
--   StageIndex / StageCount   "Step 2 of 6" on the wash screen
--   StageEndsAt / StageTotal  timing of the current step; the progress bar
--              fills for that step only (without them it follows the whole countdown)
--   Program    the wash the customer paid for, shown in the footer

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CarWash = script.Parent

local TILE_SIZE = 100
-- Dial tick looks. A lit tick is solid white. An unlit tick is either "off"
-- (steps still to come: a dark shade of the screen's accent colour) or the
-- lighter "track" of the step running now, in the same shade, which fills up
-- with white as the step goes.
local LIT_COLOR = Color3.new(1, 1, 1)
local OFF_SHADE = 0.35 -- how far the accent colour is darkened for off ticks
local OFF_TRANSPARENCY = 0.3
local TRACK_TRANSPARENCY = 0.65
local PULSE_SPEED = 6 -- the tick that's filling right now pulses this fast
-- The mark between two steps on the dial, in Shell yellow so it stands out
-- from the white ticks and the blue background.
local SEPARATOR_COLOR = Color3.fromRGB(255, 205, 0)
local SEPARATOR_WIDTH = 5
local SEPARATOR_LENGTH = 34
local EFFECT_INTERVAL = 0.45

local POP_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TICK_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SEPARATOR_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- The screens dim while the wash isn't in use and light up to the brightness
-- set on their SurfaceGui when a car is on its way.
local IDLE_DIM = 0.25 -- share of the full brightness while idle
local DIM_INFO = TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Backdrop gradient and accent colour for each state.
local THEMES = {
	Idle = { from = rgb(0, 70, 170), to = rgb(40, 150, 235), accent = rgb(0, 70, 170) },
	Waiting = { from = rgb(255, 140, 0), to = rgb(255, 205, 70), accent = rgb(190, 95, 0) },
	Wash = { from = rgb(0, 120, 215), to = rgb(60, 210, 255), accent = rgb(0, 105, 200) },
	Dry = { from = rgb(225, 60, 0), to = rgb(255, 165, 40), accent = rgb(205, 60, 0) },
	Done = { from = rgb(0, 120, 90), to = rgb(0, 208, 153), accent = rgb(0, 150, 90) },
}

-- What each screen says when WashController doesn't give a Stage.
local TEXT = {
	Wash = {
		Idle = { stage = "Ready", hint = "Waiting for next car" },
		Waiting = { stage = "Drive forward", hint = "Onto the conveyor" },
		Running = { stage = "Washing", hint = "Stay in your car" },
		Done = { stage = "Wash complete", hint = "Drying next" },
	},
	Dry = {
		Idle = { stage = "Ready", hint = "Waiting for next car" },
		Waiting = { stage = "Ready", hint = "Wash in progress" },
		Running = { stage = "Drying", hint = "Keep windows closed" },
		Done = { stage = "Drive safely!", hint = "Thanks for visiting" },
	},
}

local function waitPath(root, ...)
	for _, name in { ... } do
		root = root:WaitForChild(name)
	end
	return root
end

local function loopInfo(duration)
	return TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
end

local function spinInfo(duration)
	return TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
end

local Screen = {}
Screen.__index = Screen

function Screen.new(model, kind)
	local gui = waitPath(model, "Screen", "Screen", "SurfaceGui")
	local body = gui:WaitForChild("Body")
	local dial = body:WaitForChild("Dial")
	local disc = dial:WaitForChild("Disc")
	local card = body:WaitForChild("StatusCard")
	local backdrop = body:WaitForChild("Backdrop")

	local self = setmetatable({
		model = model,
		kind = kind,
		gui = gui,
		brightness = gui.Brightness,
		backdrop = backdrop,
		gradient = backdrop:WaitForChild("UIGradient"),
		pattern = backdrop:WaitForChild("Pattern"),
		effects = backdrop:WaitForChild("Effects"),
		dialScale = dial:WaitForChild("UIScale"),
		discStroke = disc:WaitForChild("UIStroke"),
		count = disc:WaitForChild("Count"),
		countScale = waitPath(disc, "Count", "UIScale"),
		unit = disc:WaitForChild("Unit"),
		check = disc:WaitForChild("Check"),
		checkScale = waitPath(disc, "Check", "UIScale"),
		card = card,
		cardScale = card:WaitForChild("UIScale"),
		cardHome = card.Position,
		stage = card:WaitForChild("Stage"),
		hint = card:WaitForChild("Hint"),
		fill = waitPath(card, "Progress", "Fill"),
		program = waitPath(body, "Footer", "Program"),
		pivots = {},
		segments = {}, -- the tick bars, one list per step
		separators = {},
		tickLevels = {},
		tweens = {},
		animationId = 0,
	}, Screen)

	local tickFolder = dial:WaitForChild("Ticks")
	for i = 1, #tickFolder:GetChildren() do
		self.pivots[i] = tickFolder:WaitForChild(("Tick%02d"):format(i))
	end
	self.separatorFolder = Instance.new("Frame")
	self.separatorFolder.Name = "Separators"
	self.separatorFolder.Size = UDim2.fromScale(1, 1)
	self.separatorFolder.BackgroundTransparency = 1
	self.separatorFolder.ZIndex = 5
	self.separatorFolder.Parent = dial
	self:setTickStyles(THEMES.Idle)
	self:layoutTicks(1)

	return self
end

-- Splits the evenly spaced ring into one group of ticks per step, and puts a
-- coloured separator mark on the boundary between two steps.
function Screen:layoutTicks(segmentCount)
	segmentCount = math.clamp(segmentCount or 1, 1, #self.pivots)
	if self.segmentCount == segmentCount then
		return
	end
	self.segmentCount = segmentCount

	local total = #self.pivots
	local spacing = 360 / total
	table.clear(self.segments)
	table.clear(self.tickLevels)
	for segment = 1, segmentCount do
		-- ticks first..last belong to this step (groups differ by one tick at most)
		local first = math.floor((segment - 1) * total / segmentCount) + 1
		local last = math.floor(segment * total / segmentCount)
		local bars = {}
		for index = first, last do
			local pivot = self.pivots[index]
			pivot.Visible = true
			pivot.Rotation = (index - 1) * spacing
			table.insert(bars, pivot.Bar)
		end
		table.insert(self.segments, bars)

		local separator = self:separator(segment)
		if segment < segmentCount then
			-- halfway between this step's last tick and the next step's first
			separator.Rotation = (last - 0.5) * spacing
			separator.Visible = true
			separator.Mark.BackgroundTransparency = 1
			TweenService:Create(separator.Mark, SEPARATOR_INFO, { BackgroundTransparency = 0 }):Play()
		else
			separator.Visible = false
		end
	end
	for segment = segmentCount + 1, #self.separators do
		self.separators[segment].Visible = false
	end
end

-- The separator after step `index`, made the first time it's needed.
function Screen:separator(index)
	local separator = self.separators[index]
	if separator then
		return separator
	end
	separator = Instance.new("Frame")
	separator.Name = ("Separator%02d"):format(index)
	separator.Size = UDim2.fromScale(1, 1)
	separator.BackgroundTransparency = 1
	separator.Visible = false
	separator.ZIndex = 5

	local mark = Instance.new("Frame")
	mark.Name = "Mark"
	mark.AnchorPoint = Vector2.new(0.5, 0)
	mark.Position = UDim2.new(0.5, 0, 0, -4)
	mark.Size = UDim2.fromOffset(SEPARATOR_WIDTH, SEPARATOR_LENGTH)
	mark.BackgroundColor3 = SEPARATOR_COLOR
	mark.BorderSizePixel = 0
	mark.ZIndex = 6
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = mark
	mark.Parent = separator

	separator.Parent = self.separatorFolder
	self.separators[index] = separator
	return separator
end

-- Calls fn(bar, segment, tick, flatIndex) for every visible tick, in ring order.
function Screen:eachTick(fn)
	local flat = 0
	for segment, bars in self.segments do
		for tick, bar in bars do
			flat += 1
			fn(bar, segment, tick, flat)
		end
	end
	return flat
end

-- Off and track looks for the current theme, set when the state changes.
function Screen:setTickStyles(theme)
	local shade = theme.accent:Lerp(Color3.new(0, 0, 0), OFF_SHADE)
	self.offStyle = { id = 1, color = shade, transparency = OFF_TRANSPARENCY }
	self.trackStyle = { id = 2, color = shade, transparency = TRACK_TRANSPARENCY }
	table.clear(self.tickLevels)
end

-- Blends a tick from its unlit style (level 0) to solid white (level 1);
-- only touches the bar when that changes.
function Screen:paintTick(bar, flat, level, style)
	level = math.floor(math.clamp(level, 0, 1) * 20 + 0.5) / 20
	local key = style.id * 100 + level * 20
	if self.tickLevels[flat] ~= key then
		self.tickLevels[flat] = key
		bar.BackgroundColor3 = style.color:Lerp(LIT_COLOR, level)
		bar.BackgroundTransparency = style.transparency * (1 - level)
	end
end

-- Finished steps solid white, the current step filling up over its pale track
-- with the tick that's filling now pulsing, the steps still to come off.
function Screen:showSteps(current, currentDone, now)
	local pulse = 0.35 + 0.35 * math.sin(now * PULSE_SPEED)
	self:eachTick(function(bar, segment, tick, flat)
		if segment < current then
			self:paintTick(bar, flat, 1, self.offStyle)
		elseif segment > current then
			self:paintTick(bar, flat, 0, self.offStyle)
		else
			local level = currentDone * #self.segments[segment] - (tick - 1)
			if level > 0 and level < 1 then
				level = math.max(level, pulse)
			end
			self:paintTick(bar, flat, level, self.trackStyle)
		end
	end)
end

function Screen:lightAll(level, style)
	self:eachTick(function(bar, _, _, flat)
		self:paintTick(bar, flat, level, style)
	end)
end

-- A lit tail chasing around the dial, for screens waiting on something.
function Screen:chaseTicks(now)
	local count = self:eachTick(function() end)
	local head = (now * 24) % count
	self:eachTick(function(bar, _, _, flat)
		local behind = (head - (flat - 1)) % count
		self:paintTick(bar, flat, 1 - behind / 10, self.offStyle)
	end)
end

function Screen:play(instance, info, goal)
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	table.insert(self.tweens, tween)
	return tween
end

function Screen:stopTweens()
	self.animationId += 1
	for _, tween in self.tweens do
		tween:Cancel()
	end
	table.clear(self.tweens)
	self.effects:ClearAllChildren()
end

function Screen:readState()
	local model = self.model
	return {
		state = model:GetAttribute("State") or "Idle",
		endsAt = model:GetAttribute("EndsAt"),
		total = model:GetAttribute("Total"),
		stage = model:GetAttribute("Stage"),
		stageIndex = model:GetAttribute("StageIndex"),
		stageCount = model:GetAttribute("StageCount"),
		stageEndsAt = model:GetAttribute("StageEndsAt"),
		stageTotal = model:GetAttribute("StageTotal"),
		program = model:GetAttribute("Program"),
	}
end

function Screen:themeFor(state)
	if state == "Running" then
		return THEMES[self.kind]
	end
	return THEMES[state] or THEMES.Idle
end

-- Bubbles rising on the wash screen, hot air streaks blowing across the dryer one.
function Screen:spawnEffect(state)
	local effect = Instance.new("Frame")
	effect.BackgroundColor3 = Color3.new(1, 1, 1)
	effect.BorderSizePixel = 0
	effect.ZIndex = 3

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = effect

	local goal, seconds
	if self.kind == "Dry" and state == "Running" then
		local y = math.random()
		local width = math.random(60, 140)
		effect.Size = UDim2.fromOffset(width, math.random(4, 8))
		effect.Position = UDim2.new(0, -width, y, 0)
		effect.BackgroundTransparency = 0.5
		goal = { Position = UDim2.new(1, width, y, 0), BackgroundTransparency = 0.9 }
		seconds = math.random(8, 16) / 10
	else
		local size = math.random(12, 34)
		local x = math.random()
		effect.AnchorPoint = Vector2.new(0.5, 0.5)
		effect.Size = UDim2.fromOffset(size, size)
		effect.Position = UDim2.new(x, 0, 1, size)
		effect.BackgroundTransparency = 0.55
		goal = { Position = UDim2.new(x, 0, 0, -size), BackgroundTransparency = 0.9 }
		seconds = math.random(40, 70) / 10
	end

	effect.Parent = self.effects
	local tween = TweenService:Create(effect, TweenInfo.new(seconds, Enum.EasingStyle.Linear), goal)
	tween.Completed:Once(function()
		effect:Destroy()
	end)
	tween:Play()
end

-- Runs when the state changes: colours, texts, entrance pop and looping animations.
function Screen:enterState(info)
	self:stopTweens()
	local id = self.animationId
	local state = info.state
	local theme = self:themeFor(state)

	self:play(self.gui, DIM_INFO, { Brightness = self.brightness * (if state == "Idle" then IDLE_DIM else 1) })

	self.gradient.Color = ColorSequence.new(theme.from, theme.to)
	self:setTickStyles(theme)
	self.count.TextColor3 = theme.accent
	self.stage.TextColor3 = theme.accent
	self.fill.BackgroundColor3 = theme.accent

	local running = state == "Running"
	local done = state == "Done"
	self.count.Visible = not done
	self.unit.Visible = running
	self.check.Visible = done
	if not running then
		self.count.Text = "--"
	end
	self.lastSecond = nil
	self.fill.Size = UDim2.fromScale(if done then 1 else 0, 1)

	-- Entrance
	self.cardScale.Scale = 0.85
	self:play(self.cardScale, POP_INFO, { Scale = 1 })
	self.card.Position = self.cardHome + UDim2.fromOffset(0, 40)
	self:play(self.card, POP_INFO, { Position = self.cardHome })
	self.dialScale.Scale = 0.9
	self:play(self.dialScale, POP_INFO, { Scale = 1 })
	if done then
		self.checkScale.Scale = 0.2
		self:play(self.checkScale, POP_INFO, { Scale = 1 })
	end

	-- Background
	self.pattern.Size = UDim2.new(1, TILE_SIZE, 1, TILE_SIZE)
	self.pattern.Position = UDim2.fromOffset(-TILE_SIZE, -TILE_SIZE)
	self:play(self.pattern, spinInfo(if running then 3 else 6), { Position = UDim2.fromOffset(0, 0) })

	-- The ring around the disc breathes; faster while the machine runs.
	self.discStroke.Thickness = 10
	self.discStroke.Transparency = 0.5
	self:play(self.discStroke, loopInfo(if running then 0.6 else 1.2), { Thickness = 16, Transparency = 0.8 })

	if state ~= "Idle" then
		task.spawn(function()
			while self.animationId == id do
				self:spawnEffect(state)
				task.wait(if self.kind == "Dry" and running then EFFECT_INTERVAL / 3 else EFFECT_INTERVAL)
			end
		end)
	end
end

function Screen:updateTexts(info)
	local text = TEXT[self.kind][info.state] or TEXT[self.kind].Idle
	local stage = text.stage
	local hint = text.hint

	if info.stage and info.state ~= "Idle" then
		stage = info.stage
	end
	if info.state == "Running" and info.stageIndex and info.stageCount and info.stageCount > 1 then
		hint = ("Step %d of %d"):format(info.stageIndex, info.stageCount)
	end

	if self.stage.Text ~= stage then
		self.stage.Text = stage
		-- small pop each time the wash moves to its next stage
		if info.state == "Running" then
			self.cardScale.Scale = 0.94
			self:play(self.cardScale, TICK_INFO, { Scale = 1 })
		end
	end
	self.hint.Text = hint
	self.program.Text = info.program or "Wash & Dry"
end

function Screen:update(now)
	local info = self:readState()
	if info.state ~= self.state then
		self.state = info.state
		self:enterState(info)
	end
	self:updateTexts(info)

	local running = info.state == "Running"
	-- One group of ticks per step while the wash runs; a single full ring otherwise.
	self:layoutTicks(if running then info.stageCount else 1)

	if running and info.endsAt and info.total and info.total > 0 then
		local remaining = math.max(info.endsAt - now, 0)
		local share = math.clamp(remaining / info.total, 0, 1)

		-- How far through the current step the car is. Without step timing
		-- (the dryer) the one step is the whole countdown.
		local stageShare = share
		if info.stageEndsAt and info.stageTotal and info.stageTotal > 0 then
			stageShare = math.clamp((info.stageEndsAt - now) / info.stageTotal, 0, 1)
		end
		local current = math.clamp(info.stageIndex or 1, 1, #self.segments)
		self:showSteps(current, 1 - stageShare, now)
		self.fill.Size = UDim2.fromScale(1 - stageShare, 1)

		local second = math.ceil(remaining)
		if second ~= self.lastSecond then
			self.lastSecond = second
			self.count.Text = tostring(second)
			self.countScale.Scale = 1.15
			TweenService:Create(self.countScale, TICK_INFO, { Scale = 1 }):Play()
		end
	elseif info.state == "Done" then
		self:lightAll(1, self.offStyle)
	elseif info.state == "Waiting" or running then
		-- Running without a countdown yet (or Waiting): a tail chases round the dial
		self:chaseTicks(now)
	else
		-- Idle: every tick dim, gently breathing together
		self:lightAll(0.2 + 0.1 * math.sin(now * 2), self.offStyle)
	end
end

local screens = {
	Screen.new(CarWash:WaitForChild("TimerWash"), "Wash"),
	Screen.new(CarWash:WaitForChild("TimerDryer"), "Dry"),
}

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	for _, screen in screens do
		screen:update(now)
	end
end)
