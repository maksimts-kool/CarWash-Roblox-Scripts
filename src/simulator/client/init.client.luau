-- Car Wash Simulator HUD logic.
--
-- The GUI itself is StarterGui.SimHud: edit its layout, colours and fonts
-- there. Its layout is all in Scale, made on a MacBook (1440 x 841 below the
-- top bar): every top-level panel has a UIAspectRatioConstraint so it keeps
-- its shape and fits any screen. One-line texts are TextScaled (padded to
-- their text height); texts that wrap and outlines have BaseTextSize /
-- BaseThickness attributes (see sizeToScreen below). Keep new pieces in
-- Scale too (no pixel Offsets).
-- This script only fills it in and animates it:
--   TopLeft                  Stats (cash, level + XP bar, rating) and the
--                            UpgradesButton
--   Side                     the right-hand column, so the top and bottom of
--                            the screen stay clear:
--     Objective + Waypoint   what to do next, and an arrow on the target
--     Job                    the current job's facts: customer, car, wash, reward
--     Toasts                 notifications (cloned from Templates.Toast)
--
-- Every fact or instruction shows in ONE place only: the objective says what
-- to do, the job panel holds the job's facts, buttons are actions, toasts are
-- for things nothing else shows. While the drive-up kiosk is in use (player
-- attribute "KioskUi"), its screen gives the instructions and the objective
-- and job panel step aside.
--   Reward / Shop / Dim      the job result card and the upgrades shop
--
-- Data comes from the player attributes ServerScriptService.Simulator sets
-- (Level, XP, XPNext, Rating, Jobs, Job*, WashBudget, Upg_*) and the JobCar
-- ObjectValue; actions go through ReplicatedStorage.SimRemotes. Texts that
-- describe things (upgrade names, icons) come from ReplicatedStorage.SimConfig.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local SimConfig = require(ReplicatedStorage:WaitForChild("SimConfig"))
local Remotes = ReplicatedStorage:WaitForChild("SimRemotes")
local Icons = SimConfig.Icons

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("SimHud")
local World = workspace:WaitForChild("Simulator")
local CarWash = workspace:WaitForChild("CarWash")

local TARGETS = {
	board = World:WaitForChild("JobBoard"):WaitForChild("Panel"),
	pickup = World:WaitForChild("Pickup"):WaitForChild("Zone"),
	kiosk = CarWash:WaitForChild("Selections"):WaitForChild("Screen"),
	gate = CarWash:WaitForChild("GateEN"):WaitForChild("CloseSensor"),
}
-- The tunnel, from the entry gate to past the exit gate (world X / Z).
local TUNNEL = { minX = 327, maxX = 353, minZ = -632, maxZ = -486 }

-- Colours for states the script switches between (the rest is in the GUI).
local C = {
	text = Color3.fromRGB(240, 245, 255),
	muted = Color3.fromRGB(150, 165, 190),
	blue = Color3.fromRGB(0, 150, 255),
	green = Color3.fromRGB(0, 205, 120),
	gold = Color3.fromRGB(255, 205, 60),
	orange = Color3.fromRGB(255, 140, 40),
	purple = Color3.fromRGB(150, 100, 255),
	red = Color3.fromRGB(235, 70, 70),
}
local TOAST_COLORS = { story = C.purple, info = C.blue, good = C.green, warn = C.orange, job = C.gold }
local TOAST_ICONS = { story = "Story", info = "Info", good = "Check", warn = "Warning", job = "Customer" }
local TOAST_MAX = 3
local EMPTY_STAR = Color3.fromRGB(70, 80, 100)

local function tween(inst: Instance, seconds: number, goal, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function money(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return SimConfig.Currency .. formatted
end

---------------------------------------------------------------- the GUI
local Stats = gui.TopLeft.Stats
local Side = gui.Side
local Objective = Side.Objective
local Toasts = Side.Toasts
local Job = Side.Job
local Waypoint = gui.Waypoint
local Dim = gui.Dim
local Reward = gui.Reward
local Shop = gui.Shop
local Templates = gui.Templates

-- Two things Scale can't size: texts that wrap over several lines (objective
-- hint, toasts, the reward quote; TextScaled would blow a short text up to
-- fill its box) and outlines. Labels with a BaseTextSize attribute and
-- UIStrokes with a BaseThickness attribute get that size times the screen's
-- scale, the same factor the panels' UIAspectRatioConstraints give them, so
-- they grow and shrink with everything else.
local DESIGN_SCREEN = Vector2.new(1440, 841)

local function screenScale(): number
	local screen = gui.AbsoluteSize
	return math.min(screen.X / DESIGN_SCREEN.X, screen.Y / DESIGN_SCREEN.Y)
end

local function sizeToScreen(item: Instance)
	if item:IsA("TextLabel") then
		local base = item:GetAttribute("BaseTextSize")
		if typeof(base) == "number" then
			item.TextSize = math.max(1, math.floor(base * screenScale())) -- down, so it never outgrows its box
		end
	elseif item:IsA("UIStroke") then
		local base = item:GetAttribute("BaseThickness")
		if typeof(base) == "number" then
			item.Thickness = base * screenScale()
		end
	end
end
local function sizeAllToScreen()
	for _, child in gui:GetDescendants() do
		sizeToScreen(child)
	end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeAllToScreen)
gui.DescendantAdded:Connect(sizeToScreen)
sizeAllToScreen()

---------------------------------------------------------------- stats
local cashLabel = Stats.Cash.Amount
local cashValue: IntValue? = nil
local shownCash = 0

local function refreshCash()
	if not cashValue then
		return
	end
	local goal = cashValue.Value
	local from = shownCash
	shownCash = goal
	local counter = Instance.new("NumberValue")
	counter.Value = from
	counter.Changed:Connect(function(v)
		cashLabel.Text = money(v)
	end)
	tween(counter, 0.6, { Value = goal }).Completed:Once(function()
		counter:Destroy()
	end)
	if goal > from then
		cashLabel.TextColor3 = Color3.new(1, 1, 1)
		tween(cashLabel, 0.6, { TextColor3 = C.green })
	end
end

local function refreshLevel()
	local level = player:GetAttribute("Level") or 1
	local xp = player:GetAttribute("XP") or 0
	local nextXp = player:GetAttribute("XPNext") or SimConfig.xpToNext(level)
	Stats.Level.Level.Text = "Lv " .. level .. "  Washer"
	Stats.Level.XP.Text = `{math.floor(xp)} / {nextXp} XP`
	tween(Stats.Level.Bar.Fill, 0.5, { Size = UDim2.fromScale(math.clamp(xp / nextXp, 0, 1), 1) })
	local jobs = player:GetAttribute("Jobs") or 0
	local rating = player:GetAttribute("Rating") or 0
	Stats.Rating.Label.Text = if jobs > 0
		then `{string.format("%.1f", rating)} rating • {jobs} {if jobs == 1 then "job" else "jobs"}`
		else "No ratings yet"
end
for _, name in { "Level", "XP", "XPNext", "Jobs", "Rating" } do
	player:GetAttributeChangedSignal(name):Connect(refreshLevel)
end
refreshLevel()

---------------------------------------------------------------- notifications
local toastOrder = 0

-- Fades a notification in or out (the template's look is the "in" state).
local function fadeToast(frame: Frame, visible: boolean, seconds: number)
	tween(frame, seconds, { BackgroundTransparency = if visible then 0.12 else 1 })
	for _, child in frame:GetChildren() do
		if child:IsA("ImageLabel") then
			tween(child, seconds, { ImageTransparency = if visible then 0 else 1 })
		elseif child:IsA("TextLabel") then
			tween(child, seconds, { TextTransparency = if visible then 0 else 1 })
		elseif child:IsA("UIStroke") then
			tween(child, seconds, { Transparency = if visible then 0.45 else 1 })
		end
	end
end

-- A toast is as big as its message needs: measured in reference-screen
-- pixels, then turned into Scale of the Toasts column, so it still grows and
-- shrinks with the screen.
local TOAST = { padLeft = 12, padRight = 16, padY = 10, icon = 28, gap = 10, textSize = 17, maxTextWidth = 234 }
local TOASTS_SIZE = Vector2.new(300, 196) -- the Toasts column on the reference screen

local function fitToast(frame: Frame)
	local label = frame:FindFirstChild("Message") :: TextLabel
	local params = Instance.new("GetTextBoundsParams")
	params.Text = label.Text
	params.Font = label.FontFace
	params.Size = TOAST.textSize
	params.Width = TOAST.maxTextWidth
	local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
	if not ok then
		return -- keep the template's full size
	end
	local text = Vector2.new(math.ceil(bounds.X) + 2, math.ceil(bounds.Y))
	local width = TOAST.padLeft + TOAST.icon + TOAST.gap + text.X + TOAST.padRight
	local height = math.max(TOAST.icon, text.Y) + 2 * TOAST.padY
	local inner = Vector2.new(width - TOAST.padLeft - TOAST.padRight, height - 2 * TOAST.padY)
	frame.Size = UDim2.fromScale(width / TOASTS_SIZE.X, height / TOASTS_SIZE.Y)
	local pad = frame:FindFirstChildOfClass("UIPadding") :: UIPadding
	pad.PaddingLeft = UDim.new(TOAST.padLeft / width, 0)
	pad.PaddingRight = UDim.new(TOAST.padRight / width, 0)
	pad.PaddingTop = UDim.new(TOAST.padY / height, 0)
	pad.PaddingBottom = UDim.new(TOAST.padY / height, 0)
	local list = frame:FindFirstChildOfClass("UIListLayout") :: UIListLayout
	list.Padding = UDim.new(TOAST.gap / inner.X, 0)
	local icon = frame:FindFirstChild("Icon") :: ImageLabel
	icon.Size = UDim2.fromScale(TOAST.icon / inner.X, TOAST.icon / inner.Y)
	label.Size = UDim2.fromScale(text.X / inner.X, text.Y / inner.Y)
end

local function toast(message: string, kind: string?)
	toastOrder += 1
	local frame = Templates.Toast:Clone()
	frame.LayoutOrder = toastOrder
	frame.Message.Text = message
	fitToast(frame)
	frame.Icon.Image = Icons[TOAST_ICONS[kind or "info"] or "Info"] or ""
	frame.UIStroke.Color = TOAST_COLORS[kind or "info"] or C.blue
	-- start invisible and a little small, then fade in
	frame.BackgroundTransparency = 1
	frame.Icon.ImageTransparency = 1
	frame.Message.TextTransparency = 1
	frame.UIStroke.Transparency = 1
	frame.Scale.Scale = 0.92
	frame.Visible = true
	frame.Parent = Toasts
	tween(frame.Scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Quad)
	fadeToast(frame, true, 0.2)

	local life = if kind == "story" or kind == "job" then 7 else 4
	task.delay(life, function()
		if frame.Parent then
			fadeToast(frame, false, 0.3)
			task.wait(0.32)
			frame:Destroy()
		end
	end)

	-- keep only the newest few
	local list = {}
	for _, child in Toasts:GetChildren() do
		if child:IsA("Frame") then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #list - TOAST_MAX do
		list[i]:Destroy()
	end
end
Remotes:WaitForChild("Notify").OnClientEvent:Connect(toast)

---------------------------------------------------------------- job panel
local cancelArmed = false
Job.Cancel.MouseButton1Click:Connect(function()
	if not cancelArmed then
		cancelArmed = true
		Job.Cancel.Text = "Sure? Tap again"
		Job.Cancel.TextColor3 = C.red
		task.delay(3, function()
			cancelArmed = false
			Job.Cancel.Text = "Cancel"
			Job.Cancel.TextColor3 = C.muted
		end)
		return
	end
	cancelArmed = false
	Job.Cancel.Text = "Cancel"
	Job.Cancel.TextColor3 = C.muted
	Remotes.CancelJob:FireServer()
end)

---------------------------------------------------------------- objective + waypoint
-- The waypoint is just an icon and a distance: the objective names the place.
local function setWaypoint(target: Instance?, iconName: string?)
	if not target then
		Waypoint.Enabled = false
		Waypoint.Adornee = nil
		return
	end
	Waypoint.Adornee = target
	Waypoint.Icon.Image = Icons[iconName or ""] or ""
	Waypoint.Enabled = true
end

local function setObjective(iconName: string, title: string, sub: string, target: Instance?, targetIcon: string?)
	Objective.Visible = true
	Objective.Icon.Image = Icons[iconName] or ""
	if Objective.Title.Text ~= title then
		Objective.Title.Text = title
		local border = Objective:FindFirstChildOfClass("UIStroke")
		if border then
			border.Color = C.gold
			tween(border, 1, { Color = C.blue })
		end
	end
	Objective.Subtitle.Text = sub
	setWaypoint(target, targetIcon or iconName)
end

local pickedUpCar: Instance? = nil

local function seatOf(model: Instance): BasePart?
	return model:FindFirstChildWhichIsA("VehicleSeat", true)
end

local function inTunnel(position: Vector3): boolean
	return position.X > TUNNEL.minX and position.X < TUNNEL.maxX and position.Z > TUNNEL.minZ and position.Z < TUNNEL.maxZ
end

local function update()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	local active = player:GetAttribute("JobActive")
	local carValue = player:FindFirstChild("JobCar") :: ObjectValue?
	local car = carValue and carValue.Value
	local atKiosk = player:GetAttribute("KioskUi") == true
	Job.Visible = active == true and car ~= nil and not atKiosk

	if atKiosk then
		-- the kiosk screen and its buttons say what to do
		Objective.Visible = false
		setWaypoint(nil)
	elseif not active or not car then
		pickedUpCar = nil
		setObjective("JobBoard", "Head to the Job Board", "Customers drop off dirty cars. Wash them, deliver them, get paid.", TARGETS.board)
	else
		local wants = player:GetAttribute("JobWants") or "Small"
		local wantsName = SimConfig.ProgramNames[wants] or wants
		local vip = player:GetAttribute("JobVip")
		local budget = player:GetAttribute("WashBudget") or 0

		Job.Customer.Text = player:GetAttribute("JobCustomer") or ""
		Job.Customer.TextColor3 = if vip then C.gold else C.text
		Job.CustomerIcon.Image = Icons[if vip then "Crown" else "Customer"]
		Job.Car.Text = player:GetAttribute("JobCarName") or ""
		Job.Wash.Text = if budget > 0 then `{wantsName} · {money(budget)} handed over` else `{wantsName} · paid`
		Job.Wash.TextColor3 = if budget > 0 then C.green else C.muted
		Job.Reward.Text = `{money(player:GetAttribute("JobPay") or 0)}+ reward`
		local endsAt = player:GetAttribute("JobEndsAt")
		if endsAt then
			local left = math.max(0, endsAt - workspace:GetServerTimeNow())
			Job.Timer.Text = string.format("%d:%02d", left // 60, left % 60)
			Job.Timer.TextColor3 = if left < 60 then C.red else C.muted
		end

		local seat = seatOf(car)
		local seated = humanoid ~= nil and humanoid.SeatPart ~= nil and humanoid.SeatPart:IsDescendantOf(car)
		if seated then
			pickedUpCar = car
		end
		local washed = car:GetAttribute("LastWashProgram")
		local pickedUp = pickedUpCar == car or washed ~= nil
		local phase = CarWash:GetAttribute("WashPhase")
		local carInTunnel = seat ~= nil and inTunnel(seat.Position)

		-- objective texts never repeat the job panel's facts (who, which car,
		-- which wash, how much)
		if washed then
			if seated then
				setObjective("Pickup", "Deliver to Customer Pickup", "Stop on the green pad.", TARGETS.pickup)
			elseif carInTunnel then
				setObjective("CarWash", "Almost done!", "The exit gate opens in a moment.", seat, "Car")
			else
				setObjective("Car", "Get back in the car", "Then head for Customer Pickup.", seat)
			end
		elseif carInTunnel and (phase == "Washing" or phase == "Drying" or phase == "Exit") then
			setObjective("CarWash", "Sit back and relax", if phase == "Drying" then "Drying off..." else "Watch the dirt come off.", nil)
		elseif phase == "Ready" then
			setObjective("CarWash", "The gate is open", "Roll slowly onto the conveyor.", if seated then TARGETS.gate else seat, if seated then "CarWash" else "Car")
		elseif seated then
			setObjective("CarWash", "Drive to the car wash", "Stop beside the pay kiosk, you can pay from your seat.", TARGETS.kiosk, "Kiosk")
		elseif pickedUp and seat and (seat.Position - TARGETS.kiosk.Position).Magnitude < 30 then
			setObjective("Kiosk", "Pay at the kiosk", "Hold your Debit Card to the reader, then get back in the car.", TARGETS.kiosk)
		else
			setObjective("Car", "Get in the car", "It's parked in the Drop-Off lot.", seat)
		end
	end

	if Waypoint.Enabled and root and Waypoint.Adornee then
		local adornee = Waypoint.Adornee :: BasePart
		local distance = (adornee.Position - root.Position).Magnitude
		Waypoint.Distance.Text = math.floor(distance) .. " studs"
		Waypoint.Enabled = distance > 8
	end
end

local bob = 0
RunService.Heartbeat:Connect(function(dt)
	bob += dt
	Waypoint.Arrow.Position = UDim2.new(0.5, 0, 0, 60 + math.sin(bob * 5) * 3)
end)
task.spawn(function()
	while true do
		local ok, err = pcall(update)
		if not ok then
			warn("SimHud:", err)
		end
		task.wait(0.2)
	end
end)

---------------------------------------------------------------- windows (reward card, shop)
local openModal: Frame? = nil
local DIM_TRANSPARENCY = Dim.BackgroundTransparency

local function showModal(frame: Frame)
	if openModal and openModal ~= frame then
		openModal.Visible = false
	end
	openModal = frame
	-- the window is sized in Scale with an aspect ratio, so it already fits
	-- every screen; this UIScale is only for the pop-in
	local scale = frame:FindFirstChild("Scale") :: UIScale
	scale.Scale = 0.85
	frame.Visible = true
	Dim.BackgroundTransparency = 1
	Dim.Visible = true
	tween(Dim, 0.25, { BackgroundTransparency = DIM_TRANSPARENCY })
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function hideModal(frame: Frame)
	frame.Visible = false
	if openModal == frame then
		openModal = nil
		tween(Dim, 0.2, { BackgroundTransparency = 1 }).Completed:Once(function()
			if not openModal then
				Dim.Visible = false
			end
		end)
	end
end

---------------------------------------------------------------- reward card
local rewardId = 0
Reward.Next.MouseButton1Click:Connect(function()
	hideModal(Reward)
end)

Remotes:WaitForChild("Reward").OnClientEvent:Connect(function(result)
	rewardId += 1
	local myId = rewardId
	Reward.Title.Text = if result.vip then "VIP JOB COMPLETE!" else "JOB COMPLETE!"
	Reward.Crown.Visible = result.vip == true
	local shiny = result.condition == "Showroom Shine" or result.condition == "Shiny"
	Reward.ShineLeft.Visible = shiny
	Reward.ShineRight.Visible = shiny
	Reward.Who.Text = `{result.customer}'s {result.carName}`
	Reward.Condition.Text = `{result.condition} • {result.score}/100`
	Reward.Quote.Text = `"{result.comment}"` .. (if #result.notes > 0 then "\n" .. table.concat(result.notes, " ") else "")

	local rows = Reward.Breakdown
	rows.Base.Value.Text = money(result.base)
	rows.Tip.Value.Text = "+" .. money(result.tip)
	rows.XP.Value.Text = "+" .. result.xp
	rows.Total.Value.Text = money(result.total)

	if result.levelUp then
		local unlocked = if result.unlocked and #result.unlocked > 0 then "  Unlocked: " .. table.concat(result.unlocked, ", ") else ""
		Reward.LevelUp.Text = `LEVEL {result.levelUp}!{unlocked}`
		Reward.Party.Visible = true
	else
		Reward.LevelUp.Text = ""
		Reward.Party.Visible = false
	end

	for i = 1, 5 do
		local star = Reward.Stars["Star" .. i]
		star.ImageColor3 = EMPTY_STAR
		star.ImageTransparency = 0.5
		star.UIScale.Scale = 1
	end
	showModal(Reward)
	for i = 1, result.stars do
		task.delay(0.25 + i * 0.18, function()
			if rewardId ~= myId then
				return
			end
			local star = Reward.Stars["Star" .. i]
			star.ImageColor3 = Color3.new(1, 1, 1)
			star.ImageTransparency = 0
			star.UIScale.Scale = 1.6
			tween(star.UIScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end
	task.delay(12, function()
		if rewardId == myId and Reward.Visible then
			hideModal(Reward)
		end
	end)
end)

---------------------------------------------------------------- upgrades shop
local shopRows = {}
for i, upgrade in SimConfig.Upgrades do
	-- a row per upgrade: the one built in StarterGui, or a copy of the template
	local row = Shop.List:FindFirstChild(upgrade.id)
	if not row then
		row = Templates.UpgradeRow:Clone()
		row.Name = upgrade.id
		row.Visible = true
		row.Parent = Shop.List
	end
	row.LayoutOrder = i
	row.Icon.Image = Icons[upgrade.id] or row.Icon.Image
	row.Title.Text = upgrade.name
	row.Desc.Text = upgrade.desc
	shopRows[upgrade.id] = { row = row, upgrade = upgrade }

	local busy = false
	row.Buy.MouseButton1Click:Connect(function()
		local level = player:GetAttribute("Upg_" .. upgrade.id) or 0
		if busy or level >= upgrade.max then
			return
		end
		busy = true
		local ok, message = Remotes.BuyUpgrade:InvokeServer(upgrade.id)
		if ok then
			-- the row's pips fill in; a little pop says it worked
			local pop = row:FindFirstChild("Pop") :: UIScale?
			if pop then
				pop.Scale = 1.06
				tween(pop, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		elseif message and message ~= "" then
			toast(message, "warn")
		end
		busy = false
	end)
end
-- rows for upgrades that no longer exist
for _, row in Shop.List:GetChildren() do
	if row:IsA("Frame") and not shopRows[row.Name] then
		row.Visible = false
	end
end

local function refreshShop()
	local cash = if cashValue then cashValue.Value else 0
	for id, entry in shopRows do
		local row, upgrade = entry.row, entry.upgrade
		local level = player:GetAttribute("Upg_" .. id) or 0
		row.Pips.Text = string.rep("● ", level) .. string.rep("○ ", upgrade.max - level)
		if level >= upgrade.max then
			row.Buy.Text = "MAX"
			row.Buy.BackgroundColor3 = C.muted
		else
			local cost = upgrade.cost(level)
			row.Buy.Text = money(cost)
			row.Buy.BackgroundColor3 = if cash >= cost then C.green else C.red
		end
	end
end
for _, upgrade in SimConfig.Upgrades do
	player:GetAttributeChangedSignal("Upg_" .. upgrade.id):Connect(refreshShop)
end

gui.TopLeft.UpgradesButton.MouseButton1Click:Connect(function()
	if Shop.Visible then
		hideModal(Shop)
	else
		refreshShop()
		showModal(Shop)
	end
end)
Shop.Close.MouseButton1Click:Connect(function()
	hideModal(Shop)
end)

---------------------------------------------------------------- cash
task.spawn(function()
	local leaderstats = player:WaitForChild("leaderstats")
	local value = leaderstats:WaitForChild("Cash") :: IntValue
	cashValue = value
	shownCash = value.Value
	cashLabel.Text = money(shownCash)
	value.Changed:Connect(function()
		refreshCash()
		refreshShop()
	end)
	refreshShop()
end)
