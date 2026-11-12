-- Fills in and animates the operator's control panel on each player's client.
--
-- The GUI itself is the SurfaceGui Workspace.CarWash.ControlBooth.Screen.Panel,
-- saved in the place in the pay terminal's style: edit its layout, colours and
-- fonts there. It is fixed-size (1320 x 780) and holds:
--   Root.Header        Status pill, Phase, Clock, EStop button
--   Root.Tunnel        the car position Bar (+ MarkLabels), WashLeft / Stage / DryLeft
--   Root.Machines      Lamps: one per machine, named by its key
--   Root.Tabs / Pages  Manual (Toggles, gate and line buttons), Washes (Cards,
--                      one per program), Settings (Rows, one per setting),
--                      Stats (Tiles, Counts, Log)
--   Root.Message       command results; Root.Lock  the screen non-operators see
--   Templates          Lamp, Toggle, ProgramCard, SettingRow, LogRow, Tick,
--                      MarkLabel: copied for anything the saved GUI has no row for
--
-- The server (ServerScriptService.CarWash.ControlPanel) publishes everything on
-- ReplicatedStorage.CarWashPanel's attributes and takes commands through
-- ReplicatedStorage.CarWashRemotes.ControlPanel. It checks every command
-- against the operator list; the player attribute "CarWashOperator" only
-- decides whether this client shows the console or the Lock screen. Changes
-- made here are local to this client, so each player sees their own screen.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local State = ReplicatedStorage:WaitForChild("CarWashPanel")
local Remote = ReplicatedStorage:WaitForChild("CarWashRemotes"):WaitForChild("ControlPanel") :: RemoteFunction
local CarWash = workspace:WaitForChild("CarWash")
local TimerWash = CarWash:WaitForChild("TimerWash")
local TimerDryer = CarWash:WaitForChild("TimerDryer")
local Screen = CarWash:WaitForChild("ControlBooth"):WaitForChild("Screen") :: BasePart
local Panel = Screen:WaitForChild("Panel")
local Root = Panel:WaitForChild("Root")
local Templates = Panel:WaitForChild("Templates")

local NEAR_DISTANCE = 90 -- refresh fast only while the camera is this close
local MESSAGE_SECONDS = 4

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Colours for states the script switches between (the rest is in the GUI).
local C = {
	ink = rgb(22, 32, 52),
	muted = rgb(84, 96, 118),
	off = rgb(160, 171, 190),
	line = rgb(150, 163, 184),
	tile = rgb(230, 236, 244),
	card = rgb(255, 255, 255),
	blue = rgb(0, 150, 235),
	green = rgb(0, 185, 110),
	greenTint = rgb(200, 240, 222),
	orange = rgb(255, 135, 0),
	red = rgb(225, 45, 45),
	redTint = rgb(253, 228, 228),
	navy = rgb(0, 35, 100),
	white = rgb(255, 255, 255),
}
local LOG_COLORS = { info = C.blue, good = C.green, warn = C.orange, alert = C.red }
local LINE_LOOK = {
	Idle = { text = "READY", color = C.green },
	Admitted = { text = "CAR ADMITTED", color = C.orange },
	Washing = { text = "WASHING", color = C.blue },
	Stopped = { text = "EMERGENCY STOP", color = C.red },
}

local Header = Root.Header
local Status = Header.Status
local EStopButton = Header.EStop :: TextButton
local Tunnel = Root.Tunnel
local Bar = Tunnel.Bar
local CarBlock = Bar.Car
local Lamps = Root.Machines.Lamps
local Pages = Root.Pages
local Manual = Pages.Manual
local Washes = Pages.Washes
local Settings = Pages.Settings
local Stats = Pages.Stats
local Message = Root.Message
local Lock = Root.Lock

------------------------------------------------------------------------------
-- Helpers

local function decode(name: string): any
	local raw = State:GetAttribute(name)
	if type(raw) ~= "string" then
		return nil
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok then value else nil
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	if seconds >= 3600 then
		return string.format("%d:%02d:%02d", seconds // 3600, seconds // 60 % 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function formatNumber(value: number): string
	if value == math.floor(value) then
		return tostring(value)
	end
	return (string.format("%.2f", value):gsub("0+$", ""))
end

-- The saved row named `name` in `container`, or a copy of the template.
local function rowFor(container: Instance, template: string, name: string, order: number): any
	local row = container:FindFirstChild(name)
	if not row then
		row = Templates[template]:Clone()
		row.Name = name
		row.Parent = container
	end
	row.Visible = true
	row.LayoutOrder = order
	return row
end

------------------------------------------------------------------------------
-- Commands

local messageId = 0
local function showMessage(text: string, ok: boolean)
	if text == "" then
		return
	end
	messageId += 1
	local myId = messageId
	Message.Text.Text = text
	Message.BackgroundColor3 = if ok then C.navy else C.orange
	Message.Visible = true
	task.delay(MESSAGE_SECONDS, function()
		if messageId == myId then
			Message.Visible = false
		end
	end)
end

local function send(action: string, ...: any)
	local args = table.pack(...)
	task.spawn(function()
		local ok, result, message = pcall(Remote.InvokeServer, Remote, action, table.unpack(args, 1, args.n))
		if ok then
			showMessage(message or "", result == true)
		else
			showMessage("No answer from the server", false)
		end
	end)
end

local function onClick(button: Instance, callback: () -> ())
	(button :: TextButton).MouseButton1Click:Connect(callback)
end

------------------------------------------------------------------------------
-- Tabs

local selectedTab = "Manual"
local function selectTab(name: string)
	selectedTab = name
	for _, tab in Root.Tabs:GetChildren() do
		if tab:IsA("TextButton") then
			local on = tab.Name == name
			tab.BackgroundColor3 = if on then C.blue else C.card
			tab.TextColor3 = if on then C.white else C.muted
		end
	end
	for _, page in Pages:GetChildren() do
		if page:IsA("GuiObject") then
			page.Visible = page.Name == name
		end
	end
end
for _, tab in Root.Tabs:GetChildren() do
	if tab:IsA("TextButton") then
		onClick(tab, function()
			selectTab(tab.Name)
		end)
	end
end

------------------------------------------------------------------------------
-- Building the lists from what the server says is there

type Mark = { key: string, tick: Frame, label: TextLabel }
local marks: { Mark } = {}
local lane = nil

local function laneFraction(z: number): number
	if not lane or lane.exitZ == lane.entryZ then
		return 0
	end
	return math.clamp((z - lane.entryZ) / (lane.exitZ - lane.entryZ), 0, 1)
end

local function buildLane()
	lane = decode("Lane")
	if not lane then
		return
	end
	local barW = Bar.Size.X.Offset
	for index, mark in lane.marks do
		local x = laneFraction(mark.z) * barW
		local tick = Templates.Tick:Clone()
		tick.Position = UDim2.fromOffset(x - 2, 0)
		tick.Size = UDim2.new(0, 4, 1, 0)
		tick.Visible = true
		tick.Parent = Bar
		local label = Templates.MarkLabel:Clone()
		label.Text = mark.short
		-- alternate above / higher above, so close marks don't overlap
		label.Position = UDim2.fromOffset(Bar.Position.X.Offset + x - 30, if index % 2 == 1 then 40 else 60)
		label.Visible = true
		label.Parent = Tunnel.MarkLabels
		table.insert(marks, { key = mark.key, tick = tick, label = label })
	end
end

type Toggle = { key: string, button: TextButton }
local toggles: { Toggle } = {}
local machineKeys: { string } = {}

local function buildMachines()
	rowFor(Lamps, "Lamp", "Conveyor", 1).Title.Text = "Conveyor"
	rowFor(Lamps, "Lamp", "EntryGate", 2).Title.Text = "Entry gate"
	rowFor(Lamps, "Lamp", "ExitGate", 3).Title.Text = "Exit gate"
	for index, machine in decode("Machines") or {} do
		table.insert(machineKeys, machine.key)
		rowFor(Lamps, "Lamp", machine.key, 3 + index).Title.Text = machine.label
		local toggle = rowFor(Manual.Toggles, "Toggle", machine.key, index)
		toggle.Title.Text = machine.label
		onClick(toggle, function()
			send("Machine", machine.key, not State:GetAttribute("M_" .. machine.key))
		end)
		table.insert(toggles, { key = machine.key, button = toggle })
	end
end

local programKeys: { string } = {}
local programNames: { [string]: string } = {}

local function buildPrograms()
	for index, program in decode("Programs") or {} do
		table.insert(programKeys, program.key)
		programNames[program.key] = program.name
		local card = rowFor(Washes.Cards, "ProgramCard", program.key, index)
		card.WashName.Text = program.name
		card.Stages.Text = `{program.stages} stages`
		onClick(card.Start, function()
			send("FreeWash", program.key)
		end)
	end
end

type SettingRow = { key: string, unit: string, row: Frame }
local settingRows: { SettingRow } = {}

local function buildSettings()
	for index, setting in decode("Settings") or {} do
		local row = rowFor(Settings.Rows, "SettingRow", setting.key, index)
		row.Label.Text = setting.label
		onClick(row.Minus, function()
			send("Adjust", setting.key, -1)
		end)
		onClick(row.Plus, function()
			send("Adjust", setting.key, 1)
		end)
		table.insert(settingRows, { key = setting.key, unit = setting.unit, row = row })
	end
end

local function rebuildLog()
	local list = Stats.Log
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local entries = decode("Log") or {}
	for index = #entries, 1, -1 do
		local entry = entries[index]
		local row = Templates.LogRow:Clone()
		row.LayoutOrder = #entries - index
		row.Dot.BackgroundColor3 = LOG_COLORS[entry.kind] or C.blue
		row.Time.Text = os.date("%H:%M:%S", math.floor(entry.t)) :: string
		row.Text.Text = entry.text
		row.Text.TextColor3 = if entry.kind == "alert" then C.red else C.ink
		row.Visible = true
		row.Parent = list
	end
end

------------------------------------------------------------------------------
-- Live state

local function setLamp(key: string, on: boolean, value: string, color: Color3?)
	local lamp = Lamps:FindFirstChild(key)
	if lamp then
		lamp.Dot.BackgroundColor3 = if on then color or C.green else C.off
		lamp.Value.Text = value
		lamp.Value.TextColor3 = if on then C.ink else C.muted
	end
end

local function refresh()
	local now = workspace:GetServerTimeNow()
	local blink = os.clock() % 1 < 0.5
	local line = State:GetAttribute("Line") or "Idle"
	local idle = line == "Idle"
	local stopped = line == "Stopped"
	local currency = State:GetAttribute("Currency") or ""

	-- header
	local look = LINE_LOOK[line] or LINE_LOOK.Idle
	Status.Text.Text = look.text
	Status.Text.TextColor3 = if stopped then C.red else C.ink
	Status.Dot.BackgroundColor3 = if stopped and not blink then C.off else look.color
	Status.UIStroke.Color = if stopped then C.red else C.line
	Status.BackgroundColor3 = if stopped then C.redTint else C.tile
	local admitted = State:GetAttribute("Admitted")
	Status.Sub.Text = if line == "Admitted" and admitted then `{programNames[admitted] or admitted}: drive in`
		elseif stopped then "Machines locked out"
		else ""
	Header.Phase.Text = `Phase: {CarWash:GetAttribute("WashPhase") or "Idle"}`
	Header.Clock.Text = os.date("%H:%M:%S") :: string
	EStopButton.Text = if stopped then "RESET E-STOP" else "EMERGENCY STOP"
	EStopButton.BackgroundColor3 = if stopped then C.orange else C.red

	-- tunnel
	Tunnel.Program.Text = TimerWash:GetAttribute("Program") or ""
	local front = CarWash:GetAttribute("CarFront")
	if lane and type(front) == "number" then
		local length = CarWash:GetAttribute("CarLength") or 14
		local direction = if lane.exitZ < lane.entryZ then -1 else 1
		local barW = Bar.Size.X.Offset
		local a, b = laneFraction(front), laneFraction(front - direction * length)
		local x0, x1 = math.min(a, b) * barW, math.max(a, b) * barW
		CarBlock.Position = UDim2.fromOffset(x0, CarBlock.Position.Y.Offset)
		CarBlock.Size = UDim2.fromOffset(math.max(x1 - x0, 8), CarBlock.Size.Y.Offset)
		CarBlock.BackgroundColor3 = if stopped then C.red else C.blue
		CarBlock.Visible = true
	else
		CarBlock.Visible = false
	end
	for _, mark in marks do
		local on = State:GetAttribute("M_" .. mark.key) == true
		mark.tick.BackgroundColor3 = if on then C.green else C.off
		mark.label.TextColor3 = if on then C.green else C.muted
	end
	Bar.UIStroke.Color = if stopped then C.red else C.line

	local washRunning = TimerWash:GetAttribute("State") == "Running"
	local dryRunning = TimerDryer:GetAttribute("State") == "Running"
	Tunnel.WashLeft.Value.Text = if washRunning then clock((TimerWash:GetAttribute("EndsAt") or now) - now) else "--"
	if washRunning then
		local index, count = TimerWash:GetAttribute("StageIndex"), TimerWash:GetAttribute("StageCount")
		Tunnel.Stage.Value.Text = `{TimerWash:GetAttribute("Stage") or ""}` .. (if index and count then ` ({index}/{count})` else "")
	else
		Tunnel.Stage.Value.Text = if dryRunning then "Drying" else "--"
	end
	Tunnel.DryLeft.Value.Text = if dryRunning then clock((TimerDryer:GetAttribute("EndsAt") or now) - now) else "--"

	-- lamps and machine tests
	local speed = State:GetAttribute("Conveyor") or 0
	setLamp("Conveyor", speed > 0, if speed > 0 then `{formatNumber(speed)} studs/s` else "STOPPED", C.blue)
	local entryOpen, exitOpen = State:GetAttribute("EntryOpen") == true, State:GetAttribute("ExitOpen") == true
	setLamp("EntryGate", entryOpen, if entryOpen then "OPEN" else "CLOSED", C.orange)
	setLamp("ExitGate", exitOpen, if exitOpen then "OPEN" else "CLOSED", C.orange)
	for _, toggle in toggles do
		local on = State:GetAttribute("M_" .. toggle.key) == true
		local value = if on then "ON" else "OFF"
		if toggle.key == "Dryers" then
			value = `{State:GetAttribute("DryersOn") or 0}/{State:GetAttribute("DryersTotal") or 0} ON`
		end
		setLamp(toggle.key, on, value)
		local button = toggle.button :: any
		button.State.Text = value
		button.State.TextColor3 = if on then C.green else C.muted
		button.BackgroundColor3 = if on then C.greenTint else C.tile
		button.BackgroundTransparency = if idle then 0 else 0.5
	end
	Manual.Note.Text = if idle then "Tap a machine to run it"
		elseif stopped then "Locked out until the e-stop is reset"
		else "Only while the line is idle"
	Manual.Note.TextColor3 = if idle then C.muted elseif stopped then C.red else C.orange

	-- washes
	for _, key in programKeys do
		local card = Washes.Cards:FindFirstChild(key)
		if card then
			local price = State:GetAttribute("Set_Price_" .. key)
			card.Price.Text = if type(price) == "number" then `{currency}{formatNumber(price)}` else ""
			card.Count.Text = `{State:GetAttribute("Count_" .. key) or 0} washed`
			card.Start.BackgroundTransparency = if idle then 0 else 0.5
		end
	end

	-- settings
	for _, setting in settingRows do
		local value = State:GetAttribute("Set_" .. setting.key)
		local text = "--"
		if type(value) == "number" then
			text = if setting.unit == currency then `{currency}{formatNumber(value)}` else `{formatNumber(value)} {setting.unit}`
		end
		(setting.row :: any).Value.Text = text
	end

	-- stats
	local tiles = Stats.Tiles
	local washed = State:GetAttribute("Stat_Washed") or 0
	tiles.Washed.Value.Text = tostring(washed)
	tiles.Revenue.Value.Text = `{currency}{formatNumber(State:GetAttribute("Stat_Revenue") or 0)}`
	tiles.AvgWash.Value.Text = if washed > 0 then clock((State:GetAttribute("Stat_WashSeconds") or 0) / washed) else "--"
	tiles.Free.Value.Text = tostring(State:GetAttribute("Stat_Comp") or 0)
	tiles.EStops.Value.Text = tostring(State:GetAttribute("Stat_EStops") or 0)
	tiles.Since.Value.Text = clock(now - (State:GetAttribute("StartedAt") or now))
	local counts = {}
	for _, key in programKeys do
		table.insert(counts, `{programNames[key]}: {State:GetAttribute("Count_" .. key) or 0}`)
	end
	Stats.Counts.Text = table.concat(counts, "   ")
end

local function updateAccess()
	local allowed = player:GetAttribute("CarWashOperator") == true
	Lock.Visible = not allowed
	Header.Subtitle.Text = if allowed then `Operator: {player.DisplayName}` else "Operator console"
end

------------------------------------------------------------------------------
-- Start

onClick(EStopButton, function()
	send(if State:GetAttribute("Line") == "Stopped" then "Reset" else "EStop")
end)
onClick(Manual.OpenEntry, function()
	send("Gate", "Entry", true)
end)
onClick(Manual.CloseEntry, function()
	send("Gate", "Entry", false)
end)
onClick(Manual.OpenExit, function()
	send("Gate", "Exit", true)
end)
onClick(Manual.CloseExit, function()
	send("Gate", "Exit", false)
end)
onClick(Manual.AllOff, function()
	send("AllOff")
end)
onClick(Manual.CancelAdmission, function()
	send("CancelAdmission")
end)
onClick(Settings.RestoreDefaults, function()
	send("ResetSettings")
end)
onClick(Stats.ResetStats, function()
	send("ResetStats")
end)

buildLane()
buildMachines()
buildPrograms()
buildSettings()
rebuildLog()
State:GetAttributeChangedSignal("Log"):Connect(rebuildLog)
player:GetAttributeChangedSignal("CarWashOperator"):Connect(updateAccess)
updateAccess()
selectTab(selectedTab)

-- a little press feedback on every button
for _, item in Root:GetDescendants() do
	if item:IsA("TextButton") then
		local scale = Instance.new("UIScale")
		scale.Parent = item
		item.MouseButton1Down:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 0.95 }):Play()
		end)
		item.MouseButton1Up:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end)
		item.MouseLeave:Connect(function()
			scale.Scale = 1
		end)
	end
end

local lastRefresh = 0
RunService.Heartbeat:Connect(function()
	local camera = workspace.CurrentCamera
	local near = camera ~= nil and (camera.CFrame.Position - Screen.Position).Magnitude < NEAR_DISTANCE
	local t = os.clock()
	if t - lastRefresh >= (if near then 0.1 else 1) then
		lastRefresh = t
		refresh()
	end
end)
