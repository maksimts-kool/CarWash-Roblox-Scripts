-- Animates the pay terminal's screen (CarWash.Selections.Screen) on each
-- player's client, so the tweens stay smooth and use no network traffic.
--
-- The server (Kiosk) decides what the screen shows: which page is visible
-- (Pages.Select / Confirm / Process), the texts, and on Pages.Process the
-- "State" attribute: "WaitingForCard" | "Processing" | "Paid" | "Proceed" | "Declined".
-- This script only moves and recolours things; it never changes what's chosen.

local TweenService = game:GetService("TweenService")

local function waitPath(root, ...)
	for _, name in { ... } do
		root = root:WaitForChild(name)
	end
	return root
end

local screenPart = waitPath(workspace, "CarWash", "Selections", "Screen")
local gui = screenPart:WaitForChild("SurfaceGui")
local beep = screenPart:FindFirstChild("Beep")

local backdrop = gui:WaitForChild("Backdrop")
local header = gui:WaitForChild("Header")
local footer = gui:WaitForChild("Footer")
local pages = gui:WaitForChild("Pages")
local selectPage = pages:WaitForChild("Select")
local confirmPage = pages:WaitForChild("Confirm")
local processPage = pages:WaitForChild("Process")

local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(22, 32, 52)
local MUTED = Color3.fromRGB(110, 122, 140)
local TRACK = Color3.fromRGB(205, 214, 226)
local GREEN = Color3.fromRGB(0, 185, 110)
local BLUE = Color3.fromRGB(0, 120, 230)
local RED = Color3.fromRGB(225, 55, 60)
local YELLOW = Color3.fromRGB(255, 205, 0)
local CONFETTI = { YELLOW, GREEN, BLUE, Color3.fromRGB(255, 135, 0), Color3.fromRGB(120, 80, 225) }

local TILE_SIZE = 100
local BUBBLE_INTERVAL = 0.5
local ATTRACT_INTERVAL = 10 -- the menu cards bounce in turn this often while nobody's choosing
local SHINE_INTERVAL = 3.5

local POP = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local SNAP = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local QUICK = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHINE = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local SETTLE = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function loopInfo(duration)
	return TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
end

local function spinInfo(duration)
	return TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
end

local function delayed(info, seconds)
	return TweenInfo.new(info.Time, info.EasingStyle, info.EasingDirection, info.RepeatCount, info.Reverses, seconds)
end

local function tween(instance, info, goal)
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

-- A set of tweens and loops that can be stopped together, e.g. everything
-- the visible page is doing. Starting the group again stops the old run.
local Group = {}
Group.__index = Group

function Group.new()
	return setmetatable({ tweens = {}, id = 0 }, Group)
end

function Group:stop()
	self.id += 1
	for _, t in self.tweens do
		t:Cancel()
	end
	table.clear(self.tweens)
end

function Group:play(instance, info, goal)
	local t = tween(instance, info, goal)
	table.insert(self.tweens, t)
	return t
end

-- Runs fn every `interval` seconds (after `first`) until the group stops.
function Group:every(interval, first, fn)
	local id = self.id
	task.spawn(function()
		task.wait(first)
		while self.id == id do
			fn()
			task.wait(interval)
		end
	end)
end

function Group:after(seconds, fn)
	local id = self.id
	task.delay(seconds, function()
		if self.id == id then
			fn()
		end
	end)
end

-- Remembers where things were placed in Studio, so entrances can start from
-- an offset and always land back home.
local homes = {}
local function home(instance)
	local position = homes[instance]
	if not position then
		position = instance.Position
		homes[instance] = position
	end
	return position
end

local function slideIn(group, instance, dx, dy, delay)
	local target = home(instance)
	instance.Position = target + UDim2.fromOffset(dx, dy)
	group:play(instance, delayed(SETTLE, delay or 0), { Position = target })
end

local function popIn(group, scale, from, delay)
	scale.Scale = from or 0.85
	group:play(scale, delayed(POP, delay or 0), { Scale = 1 })
end

local function sweep(shine)
	local gradient = shine:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Offset = Vector2.new(-1.2, 0)
		tween(gradient, SHINE, { Offset = Vector2.new(1.2, 0) })
	end
end

local function playBeep()
	if beep then
		beep:Play()
	end
end

---------------------------------------------------------------- background
-- Always running: the pattern drifts, the gradient sways and bubbles rise.
do
	local pattern = backdrop:WaitForChild("Pattern")
	local effects = backdrop:WaitForChild("Effects")
	local gradient = backdrop:WaitForChild("UIGradient")

	pattern.Size = UDim2.new(1, TILE_SIZE, 1, TILE_SIZE)
	pattern.Position = UDim2.fromOffset(-TILE_SIZE, -TILE_SIZE)
	tween(pattern, spinInfo(8), { Position = UDim2.fromOffset(0, 0) })
	gradient.Rotation = 115
	tween(gradient, loopInfo(9), { Rotation = 145 })

	local dot = footer:WaitForChild("Dot")
	tween(dot, loopInfo(0.8), { BackgroundTransparency = 0.6 })

	task.spawn(function()
		while true do
			local size = math.random(10, 30)
			local x = math.random()
			local bubble = Instance.new("Frame")
			bubble.Name = "Bubble"
			bubble.AnchorPoint = Vector2.new(0.5, 0.5)
			bubble.Position = UDim2.new(x, 0, 1, size)
			bubble.Size = UDim2.fromOffset(size, size)
			bubble.BackgroundColor3 = WHITE
			bubble.BackgroundTransparency = 0.75
			bubble.BorderSizePixel = 0
			bubble.ZIndex = 3
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = bubble
			local ring = Instance.new("UIStroke")
			ring.Color = WHITE
			ring.Transparency = 0.5
			ring.Thickness = 1.5
			ring.Parent = bubble
			bubble.Parent = effects

			local drift = x + (math.random() - 0.5) * 0.08
			local rise = TweenService:Create(
				bubble,
				TweenInfo.new(math.random(50, 90) / 10, Enum.EasingStyle.Linear),
				{ Position = UDim2.new(drift, 0, 0, -size), BackgroundTransparency = 0.95 }
			)
			rise.Completed:Once(function()
				bubble:Destroy()
			end)
			rise:Play()
			task.wait(BUBBLE_INTERVAL)
		end
	end)
end

---------------------------------------------------------------- header stepper
local stepper = waitPath(header, "Stepper")
local stepItems = {}
for i = 1, 3 do
	local item = stepper:WaitForChild("Step" .. i)
	local circle = item:WaitForChild("Circle")
	stepItems[i] = {
		circle = circle,
		stroke = circle:WaitForChild("UIStroke"),
		scale = circle:WaitForChild("UIScale"),
		num = circle:WaitForChild("Num"),
		check = circle:WaitForChild("Check"),
		label = item:WaitForChild("Label"),
		line = stepper:FindFirstChild("Line" .. i),
		status = nil,
	}
end

-- step: the page the customer is on (1 Choose, 2 Confirm, 3 Pay; 4 = all done).
local function showStepper(step)
	for i, item in stepItems do
		local status = if i < step then "done" elseif i == step then "active" else "todo"
		if item.status == status then
			continue
		end
		item.status = status

		if status == "done" then
			tween(item.circle, FADE, { BackgroundColor3 = GREEN, BackgroundTransparency = 0 })
			tween(item.stroke, FADE, { Transparency = 0 })
			item.num.Visible = false
			item.check.Visible = true
			popIn(Group.new(), item.check.UIScale, 0.2)
			tween(item.label, FADE, { TextTransparency = 0.1 })
		elseif status == "active" then
			tween(item.circle, FADE, { BackgroundColor3 = WHITE, BackgroundTransparency = 0 })
			tween(item.stroke, FADE, { Transparency = 0 })
			item.num.Visible = true
			item.num.TextColor3 = BLUE
			item.check.Visible = false
			tween(item.label, FADE, { TextTransparency = 0 })
			item.label.FontFace = Font.new(item.label.FontFace.Family, Enum.FontWeight.Bold)
		else
			tween(item.circle, FADE, { BackgroundColor3 = WHITE, BackgroundTransparency = 0.75 })
			tween(item.stroke, FADE, { Transparency = 0.4 })
			item.num.Visible = true
			item.num.TextColor3 = WHITE
			item.check.Visible = false
			tween(item.label, FADE, { TextTransparency = 0.35 })
			item.label.FontFace = Font.new(item.label.FontFace.Family, Enum.FontWeight.SemiBold)
		end
		if status ~= "todo" then
			popIn(Group.new(), item.scale, 0.6)
		end
		if item.line then
			tween(item.line, FADE, { BackgroundTransparency = if status == "done" then 0 else 0.7 })
		end
	end
end

local hint = footer:WaitForChild("Hint")
local function showHint(text)
	if hint.Text == text then
		return
	end
	hint.Text = text
	local target = home(hint)
	hint.Position = target + UDim2.fromOffset(12, 0)
	hint.TextTransparency = 1
	tween(hint, FADE, { Position = target, TextTransparency = 0 })
end

local function enterHeading(group, page)
	local title = page:WaitForChild("Title")
	local subtitle = page:WaitForChild("Subtitle")
	slideIn(group, title, -24, 0)
	title.TextTransparency = 1
	group:play(title, FADE, { TextTransparency = 0 })
	slideIn(group, subtitle, -24, 0, 0.08)
	subtitle.TextTransparency = 1
	group:play(subtitle, delayed(FADE, 0.08), { TextTransparency = 0.2 })
end

-- Small squash when a button is pressed, and a beep for whoever pressed it.
local function pressable(button, scale)
	button.MouseButton1Down:Connect(function()
		tween(scale, QUICK, { Scale = 0.95 })
	end)
	button.MouseButton1Up:Connect(function()
		tween(scale, SNAP, { Scale = 1 })
	end)
	button.MouseLeave:Connect(function()
		tween(scale, SNAP, { Scale = 1 })
	end)
	button.MouseButton1Click:Connect(playBeep)
end

---------------------------------------------------------------- Select page
local cardSlots = {}
for _, slot in waitPath(selectPage, "Cards"):GetChildren() do
	local card = slot:WaitForChild("Card")
	local choose = card:WaitForChild("Choose")
	local band = card:WaitForChild("Band")
	local parts = {
		slot = slot,
		scale = slot:WaitForChild("UIScale"),
		shadow = slot:WaitForChild("Shadow"),
		card = card,
		stroke = card:WaitForChild("UIStroke"),
		art = waitPath(band, "Art"),
		car = waitPath(band, "Art", "Car"),
		drops = waitPath(band, "Art", "Drops"),
		choose = choose,
		chooseScale = choose:WaitForChild("UIScale"),
		shine = choose:WaitForChild("Shine"),
		ribbon = slot:FindFirstChild("Ribbon"),
		hovered = false,
	}
	table.insert(cardSlots, parts)
end
table.sort(cardSlots, function(a, b)
	return a.slot.Position.X.Offset < b.slot.Position.X.Offset
end)

for _, parts in cardSlots do
	local function hover(on)
		parts.hovered = on
		tween(parts.scale, SNAP, { Scale = if on then 1.04 else 1 })
		tween(parts.stroke, FADE, { Thickness = if on then 4 else 0 })
		tween(parts.shadow, FADE, { BackgroundTransparency = if on then 0.55 else 0.7 })
		if on then
			sweep(parts.shine)
		end
	end
	parts.card.MouseEnter:Connect(function()
		hover(true)
	end)
	parts.card.MouseLeave:Connect(function()
		hover(false)
	end)
	parts.card.MouseButton1Click:Connect(playBeep)
	pressable(parts.choose, parts.chooseScale)
end

local selectGroup = Group.new()
local function enterSelect()
	selectGroup:stop()
	local group = selectGroup
	enterHeading(group, selectPage)
	showHint("Tap a wash to choose it")

	for i, parts in cardSlots do
		-- cards rise into place together, a beat apart, without overshooting
		local delay = 0.05 + (i - 1) * 0.07
		local slotHome = home(parts.slot)
		parts.slot.Position = slotHome + UDim2.fromOffset(0, 18)
		group:play(parts.slot, delayed(SETTLE, delay), { Position = slotHome })
		parts.scale.Scale = 0.97
		group:play(parts.scale, delayed(SETTLE, delay), { Scale = 1 })
		parts.stroke.Thickness = 0

		-- the car drives in from the edge of its (clipped) colour band
		local carHome = home(parts.car)
		parts.car.Position = carHome + UDim2.fromOffset(-60, 0)
		group:play(parts.car, delayed(TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), delay + 0.1), { Position = carHome })
		-- then sits on its springs, and the drops above it fall
		group:after(delay + 0.8, function()
			group:play(parts.car, loopInfo(1.4 + i * 0.15), { Position = carHome + UDim2.fromOffset(0, 2) })
			local dropsHome = home(parts.drops)
			group:play(parts.drops, loopInfo(1.1 + i * 0.1), { Position = dropsHome + UDim2.fromOffset(0, 3) })
		end)

		group:every(SHINE_INTERVAL, 1.2 + i * 0.35, function()
			sweep(parts.shine)
		end)
	end

	local ribbonParts = cardSlots[#cardSlots].ribbon
	if ribbonParts then
		local scale = ribbonParts:WaitForChild("UIScale")
		scale.Scale = 1
		group:every(4, 1.4, function()
			sweep(ribbonParts:WaitForChild("Shine"))
		end)
	end

	-- attract: every so often the cards bounce one after the other
	group:every(ATTRACT_INTERVAL, ATTRACT_INTERVAL, function()
		for i, parts in cardSlots do
			task.delay((i - 1) * 0.15, function()
				if parts.hovered or not selectPage.Visible then
					return
				end
				local target = home(parts.slot)
				local up = tween(parts.slot, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target + UDim2.fromOffset(0, -6) })
				up.Completed:Once(function()
					tween(parts.slot, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = target })
				end)
			end)
		end
	end)
end

---------------------------------------------------------------- Confirm page
local summary = confirmPage:WaitForChild("Summary")
local summaryCard = summary:WaitForChild("Card")
local side = confirmPage:WaitForChild("Side")
local payButton = side:WaitForChild("Confirm")
local payScale = payButton:WaitForChild("UIScale")
local payGlow = side:WaitForChild("PayGlow")
local backButton = side:WaitForChild("Cancel")
local totalPrice = waitPath(side, "Total", "Card", "Price")
local hintArrow = waitPath(side, "Hint", "Arrow")
pressable(payButton, payScale)
pressable(backButton, backButton:WaitForChild("UIScale"))
backButton.MouseEnter:Connect(function()
	tween(backButton, QUICK, { BackgroundTransparency = 0.7 })
end)
backButton.MouseLeave:Connect(function()
	tween(backButton, QUICK, { BackgroundTransparency = 0.82 })
end)

local confirmGroup = Group.new()
local function enterConfirm()
	confirmGroup:stop()
	local group = confirmGroup
	enterHeading(group, confirmPage)
	showHint("Press Pay, then tap your card on the reader")

	slideIn(group, summary, -20, 0, 0.05)
	popIn(group, summary:WaitForChild("UIScale"), 0.97, 0.05)
	slideIn(group, side, 20, 0, 0.12)
	popIn(group, side:WaitForChild("UIScale"), 0.97, 0.12)

	local car = waitPath(summaryCard, "Band", "Art", "Car")
	local carHome = home(car)
	car.Position = carHome + UDim2.fromOffset(-60, 0)
	group:play(car, delayed(TweenInfo.new(0.7, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), 0.2), { Position = carHome })
	group:after(0.9, function()
		group:play(car, loopInfo(1.3), { Position = carHome + UDim2.fromOffset(0, 2) })
	end)

	-- the stages tick in one by one
	local visibleIndex = 0
	local rows = summaryCard:WaitForChild("Features"):GetChildren()
	table.sort(rows, function(a, b)
		return a.Name < b.Name
	end)
	for _, row in rows do
		local scale = row:FindFirstChildOfClass("UIScale")
		if row:IsA("GuiObject") and row.Visible and scale then
			visibleIndex += 1
			popIn(group, scale, 0.4, 0.25 + visibleIndex * 0.06)
		end
	end

	popIn(group, totalPrice:WaitForChild("UIScale"), 0.7, 0.3)

	-- Pay: a soft ring pulses out of the button and a shine sweeps over it
	local glowHome = UDim2.fromOffset(292, 84)
	payGlow.Size = glowHome
	payGlow.BackgroundTransparency = 0.45
	group:play(payGlow, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1), {
		Size = glowHome + UDim2.fromOffset(28, 28),
		BackgroundTransparency = 1,
	})
	group:play(payScale, loopInfo(0.9), { Scale = 1.03 })
	group:every(2.4, 0.8, function()
		sweep(payButton:WaitForChild("Shine"))
	end)

	local arrowHome = home(hintArrow)
	group:play(hintArrow, loopInfo(0.5), { Position = arrowHome + UDim2.fromOffset(0, 5) })
end

---------------------------------------------------------------- Process page
local stepsSlot = processPage:WaitForChild("Steps")
local stepsCard = stepsSlot:WaitForChild("Card")
local statusSlot = processPage:WaitForChild("Status")
local statusCard = statusSlot:WaitForChild("Card")
local emblem = statusCard:WaitForChild("Emblem")
local disc = emblem:WaitForChild("Disc")
local discScale = disc:WaitForChild("UIScale")
local bankCard = disc:WaitForChild("BankCard")
local discCheck = disc:WaitForChild("Check")
local discCross = disc:WaitForChild("Cross")
local discSpinner = disc:WaitForChild("Spinner")
local waves = { emblem:WaitForChild("Wave1"), emblem:WaitForChild("Wave2"), emblem:WaitForChild("Wave3") }
local statusTitle = statusCard:WaitForChild("Title")
local amount = statusCard:WaitForChild("Amount")
local go = statusCard:WaitForChild("Go")
local chevrons = go:WaitForChild("Chevrons")

local rows = {}
for i, name in { "Selected", "Card", "Drive" } do
	local row = stepsCard:WaitForChild(name)
	local circle = row:WaitForChild("Circle")
	rows[i] = {
		row = row,
		scale = row:WaitForChild("UIScale"),
		circle = circle,
		circleScale = circle:WaitForChild("UIScale"),
		stroke = circle:WaitForChild("UIStroke"),
		num = circle:WaitForChild("Num"),
		check = circle:WaitForChild("Check"),
		cross = circle:WaitForChild("Cross"),
		spinner = circle:WaitForChild("Spinner"),
		title = row:WaitForChild("Title"),
		sub = row:WaitForChild("Sub"),
		line = stepsCard:FindFirstChild("Line" .. i),
		status = nil,
	}
end

-- What each step row shows for each payment state.
local ROW_STATUS = {
	WaitingForCard = { "done", "active", "pending" },
	Processing = { "done", "busy", "pending" },
	Paid = { "done", "done", "busy" },
	Proceed = { "done", "done", "done" },
	Declined = { "done", "failed", "pending" },
}

local FOOTER_HINTS = {
	WaitingForCard = "Tap your Debit Card on the reader below",
	Processing = "Talking to your bank, please wait",
	Paid = "Payment accepted. The gate opens shortly",
	Proceed = "Drive forward onto the conveyor",
	Declined = "Payment declined. Choose a wash to try again",
}

local processGroup = Group.new() -- page entrance
local stateGroup = Group.new() -- the loops of the current payment state
local rowGroups = { Group.new(), Group.new(), Group.new() }

local function shake(instance, strength)
	local target = home(instance)
	task.spawn(function()
		for i = 1, 6 do
			local dx = (if i % 2 == 0 then 1 else -1) * strength * (1 - i / 7)
			instance.Position = target + UDim2.fromOffset(dx, 0)
			task.wait(0.04)
		end
		instance.Position = target
	end)
end

local function showRow(index, status, animate)
	local r = rows[index]
	if r.status == status and animate then
		return
	end
	r.status = status
	local group = rowGroups[index]
	group:stop()

	local fillColor = if status == "done" then GREEN elseif status == "failed" then RED else WHITE
	local ringColor = if status == "done" then GREEN
		elseif status == "failed" then RED
		elseif status == "pending" then TRACK
		else BLUE
	local info = if animate then FADE else TweenInfo.new(0)
	tween(r.circle, info, { BackgroundColor3 = fillColor })
	tween(r.stroke, info, { Color = ringColor })

	r.num.Visible = status ~= "done" and status ~= "failed"
	r.num.TextColor3 = if status == "pending" then MUTED else BLUE
	r.check.Visible = status == "done"
	r.cross.Visible = status == "failed"
	r.spinner.Visible = status == "active" or status == "busy"
	tween(r.title, info, { TextTransparency = if status == "pending" then 0.45 else 0 })
	tween(r.sub, info, { TextTransparency = if status == "pending" then 0.4 else 0 })
	r.circleScale.Scale = 1

	if r.spinner.Visible then
		r.spinner.Rotation = 0
		group:play(r.spinner, spinInfo(if status == "busy" then 0.7 else 1.6), { Rotation = 360 })
		group:play(r.circleScale, loopInfo(0.7), { Scale = 1.07 })
	end
	if animate and status == "done" then
		popIn(group, r.check.UIScale, 0.1)
		popIn(group, r.circleScale, 0.7)
	elseif animate and status == "failed" then
		popIn(group, r.cross.UIScale, 0.1)
		shake(r.row, 10)
	end

	if r.line then
		local lineFill = r.line:WaitForChild("Fill")
		local full = UDim2.fromScale(1, if status == "done" then 1 else 0)
		if animate then
			tween(lineFill, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Size = full })
		else
			lineFill.Size = full
		end
	end
end

-- Bits of confetti thrown out of the emblem when the payment goes through.
local function burst()
	for i = 1, 18 do
		local piece = Instance.new("Frame")
		piece.Name = "Confetti"
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(0.5, 0.5)
		local w = math.random(5, 9)
		piece.Size = UDim2.fromOffset(w, w + math.random(0, 6))
		piece.Rotation = math.random(0, 360)
		piece.BackgroundColor3 = CONFETTI[(i % #CONFETTI) + 1]
		piece.BorderSizePixel = 0
		piece.ZIndex = 6
		piece.Parent = emblem
		local angle = (i / 18) * math.pi * 2 + math.random() * 0.3
		local distance = math.random(80, 130)
		local flight = TweenService:Create(piece, TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(angle) * distance, 0.5, math.sin(angle) * distance + 20),
			Rotation = piece.Rotation + math.random(-180, 180),
			BackgroundTransparency = 1,
		})
		flight.Completed:Once(function()
			piece:Destroy()
		end)
		flight:Play()
	end
end

local function resetWaves()
	for _, wave in waves do
		wave.Size = UDim2.fromOffset(110, 110)
		wave.UIStroke.Transparency = 1
	end
end

local function showEmblem(state, animate)
	stateGroup:stop()
	local group = stateGroup
	resetWaves()

	local color = if state == "Paid" or state == "Proceed" then GREEN elseif state == "Declined" then RED else BLUE
	tween(disc, if animate then FADE else TweenInfo.new(0), { BackgroundColor3 = color })
	tween(statusTitle, FADE, { TextColor3 = color })
	for _, wave in waves do
		wave.UIStroke.Color = color
	end
	discSpinner.UIStroke.Color = color

	bankCard.Visible = state == "WaitingForCard" or state == "Processing"
	discCheck.Visible = state == "Paid" or state == "Proceed"
	discCross.Visible = state == "Declined"
	discSpinner.Visible = state == "Processing"
	discScale.Scale = 1

	if state == "WaitingForCard" then
		-- contactless waves ripple out while the card leans in to "tap"
		for i, wave in waves do
			group:play(wave, delayed(TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1), (i - 1) * 0.6), {
				Size = UDim2.fromOffset(176, 176),
			})
			wave.UIStroke.Transparency = 0.2
			group:play(wave.UIStroke, delayed(TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1), (i - 1) * 0.6), {
				Transparency = 1,
			})
		end
		bankCard.Rotation = -16
		bankCard.Position = UDim2.fromScale(0.5, 0.5)
		group:play(bankCard, loopInfo(0.8), { Rotation = -4, Position = UDim2.new(0.5, 0, 0.5, -5) })
	elseif state == "Processing" then
		bankCard.Rotation = -8
		bankCard.Position = UDim2.fromScale(0.5, 0.5)
		discSpinner.Rotation = 0
		group:play(discSpinner, spinInfo(0.8), { Rotation = 360 })
		group:play(discScale, loopInfo(0.6), { Scale = 0.96 })
	elseif state == "Paid" or state == "Proceed" then
		if animate then
			popIn(group, discScale, 0.6)
			popIn(group, discCheck.UIScale, 0.1)
			burst()
			local ring = waves[1]
			ring.UIStroke.Transparency = 0
			group:play(ring, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(190, 190) })
			group:play(ring.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 })
		end
		group:after(0.6, function()
			group:play(discScale, loopInfo(1.2), { Scale = 1.05 })
		end)
	elseif state == "Declined" then
		if animate then
			popIn(group, discCross.UIScale, 0.1)
			shake(emblem, 12)
		end
	end

	-- "DRIVE IN" with chevrons marching towards the tunnel
	local proceed = state == "Proceed"
	if proceed and not go.Visible then
		go.Visible = true
		popIn(group, go:WaitForChild("UIScale"), 0.5)
	end
	go.Visible = proceed
	if proceed then
		for i, chevron in chevrons:GetChildren() do
			if chevron:IsA("GuiObject") then
				local x = chevron.Position.X.Offset
				group:play(chevron, delayed(TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), i * 0.12), {
					Position = UDim2.new(0, x + 6, 0.5, 0),
				})
			end
		end
	end
end

local currentState = nil
local function showPayment(animate)
	local state = processPage:GetAttribute("State") or "WaitingForCard"
	local changed = state ~= currentState
	currentState = state

	for i, status in ROW_STATUS[state] or ROW_STATUS.WaitingForCard do
		showRow(i, status, animate)
	end
	if changed or not animate then
		showEmblem(state, animate)
		if animate then
			local scale = statusTitle:WaitForChild("UIScale")
			popIn(Group.new(), scale, 0.8)
		end
	end
	showHint(FOOTER_HINTS[state] or FOOTER_HINTS.WaitingForCard)
	showStepper(if state == "Proceed" then 4 else 3)
end

local function enterProcess()
	processGroup:stop()
	local group = processGroup
	enterHeading(group, processPage)
	slideIn(group, stepsSlot, -20, 0, 0.05)
	popIn(group, stepsSlot:WaitForChild("UIScale"), 0.97, 0.05)
	slideIn(group, statusSlot, 20, 0, 0.12)
	popIn(group, statusSlot:WaitForChild("UIScale"), 0.97, 0.12)
	for i, r in rows do
		r.status = nil
		popIn(group, r.scale, 0.8, 0.2 + i * 0.08)
	end
	local amountScale = amount:WaitForChild("UIScale")
	popIn(group, amountScale, 0.6, 0.3)
	currentState = nil
	showPayment(false)
	-- the first step was done on the previous page: tick it in now
	rows[1].status = nil
	group:after(0.35, function()
		showRow(1, "done", true)
	end)
end

processPage:GetAttributeChangedSignal("State"):Connect(function()
	if processPage.Visible then
		showPayment(true)
	end
end)

---------------------------------------------------------------- page switching
local PAGES = {
	{ page = selectPage, step = 1, enter = enterSelect, group = selectGroup },
	{ page = confirmPage, step = 2, enter = enterConfirm, group = confirmGroup },
	{ page = processPage, step = 3, enter = enterProcess, group = processGroup },
}

local function onPageShown(entry)
	for _, other in PAGES do
		if other ~= entry then
			other.group:stop()
		end
	end
	if entry.page ~= processPage then
		stateGroup:stop()
		currentState = nil
	end
	showStepper(entry.step)
	entry.enter()
end

for _, entry in PAGES do
	entry.page:GetPropertyChangedSignal("Visible"):Connect(function()
		if entry.page.Visible then
			onPageShown(entry)
		end
	end)
	if entry.page.Visible then
		onPageShown(entry)
	end
end
