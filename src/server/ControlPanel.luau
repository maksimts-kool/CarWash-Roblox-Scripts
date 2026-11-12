-- The operator's control panel: the console booth at the entrance
-- (Workspace.CarWash.ControlBooth, parts saved in the place) with a touch
-- screen, a stack light and a big red emergency stop button. Only operators
-- (Config.ControlPanel) can use it.
--
-- The booth needs a part named "Screen" (the panel shows on its Front face)
-- and may have an "EStop" part (clicked to stop) and "Red" / "Amber" / "Green"
-- lamps, which this script lights. Move or restyle it freely in Studio.
--
-- The server publishes everything on ReplicatedStorage.CarWashPanel's
-- attributes and client/ControlPanel draws the screen from them:
--   Line, Admitted             WashLine.state(): Idle / Admitted / Washing / Stopped
--   M_<machine>                each machine on / off; DryersOn / DryersTotal
--   Conveyor                   belt speed; EntryOpen / ExitOpen
--   CarInTunnel                a car still has to drive out before a reset
--   Machines, Lane, Programs   what's there (JSON, set once)
--   Stat_*, StartedAt, Log     stats and the event log (JSON)
-- and the light modes as CarWash attributes LightsCeiling / LightsHexagons /
-- LightsArches ("Auto", "On" or "Off"), which client/LightShow and
-- client/ArchLights follow.
-- Commands come in through ReplicatedStorage.CarWashRemotes.ControlPanel
-- (a RemoteFunction: action, ... -> ok, message), checked against the
-- operator list here.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)
local Gates = require(script.Parent.Gates)
local Wash = require(script.Parent.Wash)
local WashLine = require(script.Parent.WashLine)
local Arches = require(script.Parent.Wash.Arches)
local Blasters = require(script.Parent.Wash.Blasters)
local Brushes = require(script.Parent.Wash.Brushes)
local Conveyor = require(script.Parent.Wash.Conveyor)
local Dryers = require(script.Parent.Wash.Dryers)
local TopBrush = require(script.Parent.Wash.TopBrush)

local CarWash = workspace:WaitForChild("CarWash")
local PanelConfig = Config.ControlPanel

local UPDATE_INTERVAL = 0.2
local COMMAND_COOLDOWN = 0.15

local ControlPanel = {}

------------------------------------------------------------------------------
-- What the panel shows and controls

type Machine = { key: string, label: string, short: string, z: number, get: () -> boolean, set: (boolean) -> () }

local SHORT_NAMES = {
	Presoak = "PRE",
	HighPressure = "HP",
	Foam = "FOAM",
	Rinse = "RNS",
	ClearCoat = "CC",
	HotWax = "WAX",
	SpotFree = "SF",
}

local machines: { Machine } = {
	{
		key = "Blasters",
		label = "Wheel blasters",
		short = "BLST",
		z = (Blasters.MIN_Z + Blasters.MAX_Z) / 2,
		get = Blasters.isOn,
		set = Blasters.set,
	},
	{
		key = "Wraps",
		label = "Wrap-arounds",
		short = "WRAP",
		z = Brushes.WRAP_Z,
		get = function()
			return Brushes.wrapsOn
		end,
		set = Brushes.setWraps,
	},
	{
		key = "Rockers",
		label = "Rocker brushes",
		short = "RCK",
		z = (Brushes.ROCKER_START_Z + Brushes.ROCKER_END_Z) / 2,
		get = function()
			return Brushes.rockersOn
		end,
		set = Brushes.setRockers,
	},
	{
		key = "TopBrush",
		label = "Top brush",
		short = "TOP",
		z = TopBrush.Z,
		get = TopBrush.isRunning,
		set = function(on)
			if on then
				TopBrush.start()
			else
				TopBrush.stop()
			end
		end,
	},
}
for _, arch in Arches.ordered do
	table.insert(machines, {
		key = arch.key,
		label = Config.StageNames[arch.key] or arch.key,
		short = SHORT_NAMES[arch.key] or arch.key:sub(1, 3):upper(),
		z = arch.z,
		get = function()
			return arch.active
		end,
		set = function(on)
			Arches.set(arch, on)
		end,
	})
end
table.insert(machines, {
	key = "Dryers",
	label = "Dryers",
	short = "DRY",
	z = Dryers.CENTER_Z,
	get = function()
		return (Dryers.count()) > 0
	end,
	set = function(on)
		if on then
			Dryers.startAll()
		else
			Dryers.stop()
		end
	end,
})
local machineByKey: { [string]: Machine } = {}
for _, machine in machines do
	machineByKey[machine.key] = machine
end

-- The tunnel lights an operator can switch: each group's mode is a CarWash
-- attribute ("Lights" .. group) the client light scripts follow. "Auto" runs
-- the light show with the wash. The emergency stop overrides them all.
local LIGHT_GROUPS = {
	Ceiling = { label = "Ceiling lights", modes = { "Auto", "On", "Off" } },
	Hexagons = { label = "Wall hexagons", modes = { "Auto", "On", "Off" } },
	Arches = { label = "Arch LEDs", modes = { "Auto", "Off" } },
}

-- The programs, cheapest first.
local programOrder = {}
for key in Config.Programs do
	table.insert(programOrder, key)
end
table.sort(programOrder, function(a, b)
	return Config.Programs[a].price < Config.Programs[b].price
end)

------------------------------------------------------------------------------
-- Published state

local State = Instance.new("Configuration")
State.Name = "CarWashPanel"

local function publish(name: string, value: any)
	if State:GetAttribute(name) ~= value then
		State:SetAttribute(name, value)
	end
end

local function publishStatic()
	local machineList = {}
	for _, machine in machines do
		table.insert(machineList, { key = machine.key, label = machine.label })
	end
	State:SetAttribute("Machines", HttpService:JSONEncode(machineList))

	local programList = {}
	for _, key in programOrder do
		local program = Config.Programs[key]
		table.insert(programList, {
			key = key,
			name = program.name,
			price = program.price,
			stages = #program.arches + (if program.topBrush then 1 else 0),
		})
	end
	State:SetAttribute("Programs", HttpService:JSONEncode(programList))
	State:SetAttribute("Currency", Config.Currency)

	-- The lane from the entry gate to the exit gate, for the car position bar.
	local marks = {}
	for _, machine in machines do
		table.insert(marks, { key = machine.key, short = machine.short, z = machine.z })
	end
	State:SetAttribute(
		"Lane",
		HttpService:JSONEncode({
			entryZ = CarWash.GateEN:GetPivot().Position.Z,
			exitZ = CarWash.GateEX:GetPivot().Position.Z,
			marks = marks,
		})
	)
end

-- Stats since the server started.
local stats = {
	Washed = 0,
	Revenue = 0,
	Comp = 0,
	EStops = 0,
	WashSeconds = 0,
}
local counts: { [string]: number } = {}

local function publishStats()
	for name, value in stats do
		publish("Stat_" .. name, value)
	end
	for _, key in programOrder do
		publish("Count_" .. key, counts[key] or 0)
	end
end

-- The event log, newest last.
type LogEntry = { t: number, text: string, kind: string }
local log: { LogEntry } = {}

local function addLog(kind: string, text: string)
	table.insert(log, { t = workspace:GetServerTimeNow(), text = text, kind = kind })
	while #log > PanelConfig.LogLength do
		table.remove(log, 1)
	end
	State:SetAttribute("Log", HttpService:JSONEncode(log))
end

local function programName(key: string): string
	local program = Config.Programs[key]
	return if program then program.name else key
end

local function duration(seconds: number): string
	seconds = math.floor(seconds + 0.5)
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function onLineEvent(kind: string, ...: any)
	local args = { ... }
	if kind == "Paid" then
		stats.Revenue += args[2]
		addLog("good", `Paid {Config.Currency}{args[2]} for a {programName(args[1])}`)
	elseif kind == "Comp" then
		stats.Comp += 1
	elseif kind == "Admitted" then
		addLog("info", `Entry gate open for a {programName(args[1])}`)
	elseif kind == "WashStarted" then
		addLog("info", `Car in: {programName(args[1])} started`)
	elseif kind == "WashFinished" then
		stats.Washed += 1
		stats.WashSeconds += args[2]
		counts[args[1]] = (counts[args[1]] or 0) + 1
		addLog("good", `{programName(args[1])} finished in {duration(args[2])}`)
	elseif kind == "WashFailed" then
		addLog("alert", `{programName(args[1])} stopped early: {args[2]}`)
	elseif kind == "EStop" then
		stats.EStops += 1
	end
	publishStats()
end

------------------------------------------------------------------------------
-- The booth (CarWash.ControlBooth, saved in the place)

type Booth = {
	screen: BasePart,
	estop: BasePart?,
	lamps: { [string]: BasePart },
}

local LAMP_COLORS = {
	Red = Color3.fromRGB(255, 45, 45),
	Amber = Color3.fromRGB(255, 170, 20),
	Green = Color3.fromRGB(40, 230, 90),
}

local function getBooth(): Booth?
	local model = CarWash:FindFirstChild("ControlBooth")
	local screen = model and model:FindFirstChild("Screen", true)
	if not (screen and screen:IsA("BasePart")) then
		warn("ControlPanel: Workspace.CarWash.ControlBooth with a Screen part is missing; the panel has nowhere to show")
		return nil
	end
	local lamps = {}
	for name in LAMP_COLORS do
		local lamp = model:FindFirstChild(name, true)
		if lamp and lamp:IsA("BasePart") then
			lamps[name] = lamp
		end
	end
	local estop = model:FindFirstChild("EStop", true)
	return {
		screen = screen,
		estop = if estop and estop:IsA("BasePart") then estop else nil,
		lamps = lamps,
	}
end

local function showLamps(booth: Booth, line: string)
	local lit = {
		Red = line == "Stopped",
		Amber = line == "Washing" or line == "Admitted",
		Green = line == "Idle",
	}
	for name, lamp in booth.lamps do
		local on = lit[name]
		lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		lamp.Color = if on then LAMP_COLORS[name] else LAMP_COLORS[name]:Lerp(Color3.new(0, 0, 0), 0.7)
	end
end

------------------------------------------------------------------------------
-- Operators

local operators: { [Player]: boolean } = {}

local function isOperator(player: Player): boolean
	if PanelConfig.AdminsInStudio and RunService:IsStudio() then
		return true
	end
	if table.find(PanelConfig.Admins, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	elseif game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		return ok and rank == 255
	end
	return false
end

local function onPlayerAdded(player: Player)
	local allowed = isOperator(player)
	operators[player] = allowed
	player:SetAttribute("CarWashOperator", allowed)
end

------------------------------------------------------------------------------
-- Commands

local function lineIdle(): (boolean, string)
	local line = WashLine.state()
	if line == "Idle" then
		return true, ""
	elseif line == "Stopped" then
		return false, "Locked out: reset the emergency stop first"
	end
	return false, "Machine tests only while the line is idle"
end

local function emergencyStop(player: Player): (boolean, string)
	local ok, message = WashLine.emergencyStop()
	if ok then
		addLog("alert", `{player.DisplayName} pressed EMERGENCY STOP`)
	end
	return ok, message
end

local COMMANDS: { [string]: (Player, any, any) -> (boolean, string) } = {
	EStop = emergencyStop,

	Reset = function(player)
		local ok, message = WashLine.resetStop()
		if ok then
			addLog("warn", `{player.DisplayName} reset the emergency stop`)
		end
		return ok, message
	end,

	Gate = function(player, which, open)
		if (which ~= "Entry" and which ~= "Exit") or type(open) ~= "boolean" then
			return false, "Bad gate command"
		end
		if which == "Entry" then
			Gates.setEntry(open)
		else
			Gates.setExit(open)
		end
		local verb = if open then "opened" else "closed"
		addLog("info", `{player.DisplayName} {verb} the {which:lower()} gate`)
		return true, `{which} gate {if open then "opening" else "closing"}`
	end,

	Machine = function(player, key, on)
		local machine = type(key) == "string" and machineByKey[key]
		if not machine or type(on) ~= "boolean" then
			return false, "Unknown machine"
		end
		local idle, reason = lineIdle()
		if not idle then
			return false, reason
		end
		machine.set(on)
		addLog("info", `{player.DisplayName} test: {machine.label} {if on then "on" else "off"}`)
		return true, `{machine.label} {if on then "on" else "off"}`
	end,

	AllOff = function(player)
		local idle, reason = lineIdle()
		if not idle then
			return false, reason
		end
		Wash.reset()
		addLog("info", `{player.DisplayName} switched every machine off`)
		return true, "All machines off"
	end,

	FreeWash = function(player, program)
		if type(program) ~= "string" then
			return false, "Unknown wash"
		end
		local ok, message = WashLine.admitFree(program)
		if ok then
			addLog("info", `{player.DisplayName} started a free {programName(program)}`)
		end
		return ok, message
	end,

	CancelAdmission = function(player)
		local ok, message = WashLine.cancelAdmission()
		if ok then
			addLog("warn", `{player.DisplayName} cancelled the waiting car's admission`)
		end
		return ok, message
	end,

	Lights = function(player, group, mode)
		local spec = type(group) == "string" and LIGHT_GROUPS[group]
		if not spec or not table.find(spec.modes, mode) then
			return false, "Unknown light setting"
		end
		CarWash:SetAttribute("Lights" .. group, mode)
		addLog("info", `{player.DisplayName} set {spec.label:lower()} to {mode}`)
		return true, `{spec.label}: {mode}`
	end,

	ResetStats = function(player)
		for name in stats do
			stats[name] = 0
		end
		table.clear(counts)
		State:SetAttribute("StartedAt", workspace:GetServerTimeNow())
		publishStats()
		addLog("info", `{player.DisplayName} reset the stats`)
		return true, "Stats reset"
	end,
}

local lastCommand: { [Player]: number } = {}

local function onCommand(player: Player, action: unknown, a: unknown, b: unknown): (boolean, string)
	if not operators[player] then
		return false, "Operator access only"
	end
	local handler = type(action) == "string" and COMMANDS[action]
	if not handler then
		return false, "Unknown command"
	end
	local now = os.clock()
	if now - (lastCommand[player] or 0) < COMMAND_COOLDOWN then
		return false, "Slow down"
	end
	lastCommand[player] = now

	local ok, success, message = pcall(handler, player, a, b)
	if not ok then
		warn(`ControlPanel: {action} failed: {success}`)
		return false, "Command failed"
	end
	return success, message
end

------------------------------------------------------------------------------

local function update(booth: Booth?)
	local line, admitted = WashLine.state()
	publish("Line", line)
	publish("Admitted", admitted)
	publish("EStop", line == "Stopped")
	publish("CarInTunnel", Wash.carInTunnel())
	for _, machine in machines do
		publish("M_" .. machine.key, machine.get())
	end
	local dryersOn, dryersTotal = Dryers.count()
	publish("DryersOn", dryersOn)
	publish("DryersTotal", dryersTotal)
	publish("Conveyor", math.round(Conveyor.speed * 20) / 20)
	publish("EntryOpen", Gates.entryOpen)
	publish("ExitOpen", Gates.exitOpen)
	if booth then
		showLamps(booth, line)
	end
end

function ControlPanel.start()
	local remotes = ReplicatedStorage:FindFirstChild("CarWashRemotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "CarWashRemotes"
		remotes.Parent = ReplicatedStorage
	end
	local remote = Instance.new("RemoteFunction")
	remote.Name = "ControlPanel"
	remote.OnServerInvoke = onCommand
	remote.Parent = remotes

	local booth = getBooth()

	if booth and booth.estop then
		local detector = Instance.new("ClickDetector")
		detector.MaxActivationDistance = 16
		detector.Parent = booth.estop
		detector.MouseClick:Connect(function(player)
			if operators[player] then
				emergencyStop(player)
			end
		end)
	end

	publishStatic()
	for group in LIGHT_GROUPS do
		CarWash:SetAttribute("Lights" .. group, "Auto")
	end
	State:SetAttribute("StartedAt", workspace:GetServerTimeNow())
	publishStats()
	addLog("info", "Control panel online")
	State.Parent = ReplicatedStorage

	WashLine.onEvent(onLineEvent)
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		operators[player] = nil
		lastCommand[player] = nil
	end)

	task.spawn(function()
		while true do
			update(booth)
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return ControlPanel
