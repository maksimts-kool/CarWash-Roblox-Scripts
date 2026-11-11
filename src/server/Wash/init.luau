-- Runs every machine in the wash line from one timeline, so the conveyor,
-- brushes, arches, dryers, screens and exit gate always agree.
--
--   pickup -> blasters + wrap-arounds -> rockers -> arches -> dryers -> exit
--
-- The car moves at Config.TunnelSpeed until its nose reaches the program's
-- first arch, at the program's archSpeed until its tail clears the last one,
-- then at Config.ConveyorSpeed into the dryers and out.
--
-- Publishes WashPhase / WashPhaseSince on CarWash for the client light show:
-- "Idle", "Ready", "Washing", "Drying", "Exit", "Finished".

local Config = require(script.Parent.Config)
local Gates = require(script.Parent.Gates)
local Arches = require(script.Arches)
local Blasters = require(script.Blasters)
local Brushes = require(script.Brushes)
local Car = require(script.Car)
local Conveyor = require(script.Conveyor)
local Dryers = require(script.Dryers)
local Screens = require(script.Screens)

local CarWash = workspace:WaitForChild("CarWash")

local BRUSH_STAGE = "Brush Wash"
-- Countdown estimates follow the car; they're only republished when they
-- drift this many seconds.
local COUNTDOWN_TOLERANCE = 0.5
local COUNTDOWN_INTERVAL = 0.1
local EXIT_CLEARANCE = 3 -- studs past the exit sensor before the gate closes

local Wash = {}

-- Bumped on every reset so a running countdown knows it's stale.
local runId = 0

local function setPhase(phase: string)
	CarWash:SetAttribute("WashPhase", phase)
	CarWash:SetAttribute("WashPhaseSince", workspace:GetServerTimeNow())
end

local function now(): number
	return workspace:GetServerTimeNow()
end

------------------------------------------------------------------------------
-- The arch zone and its countdown

type Zone = {
	archStartZ: number, -- the car slows to archSpeed once its nose passes this
	archEndZ: number, -- and speeds up once its tail passes this
	archSpeed: number,
	stageStarts: { number }, -- where the car's nose is when each step begins
	stage: number,
	stageEndsAt: number,
}

local function zoneSpeed(zone: Zone): number
	if Car.front() > zone.archStartZ then
		return Config.TunnelSpeed
	elseif Car.rear() > zone.archEndZ then
		return zone.archSpeed
	end
	return Config.ConveyorSpeed
end

-- Seconds to cover `distance` studs from `position`, at the zone speeds.
local function travelSeconds(zone: Zone, distance: number, beforeArches: number): number
	beforeArches = math.clamp(beforeArches, 0, distance)
	return beforeArches / Config.TunnelSpeed + (distance - beforeArches) / zone.archSpeed
end

-- Seconds until the car's tail clears the last arch.
local function washSecondsLeft(zone: Zone): number
	local rear = Car.rear()
	local left = rear - zone.archEndZ
	if left <= 0 then
		return 0
	end
	-- the tail is at archStartZ + length when the nose reaches the first arch
	return travelSeconds(zone, left, rear - (zone.archStartZ + Car.length()))
end

-- Seconds until the car's nose reaches z. Only right while the tail is still
-- in the arches, which holds for every stage boundary.
local function secondsUntilFront(zone: Zone, z: number): number
	local front = Car.front()
	local left = front - z
	if left <= 0 then
		return 0
	end
	return travelSeconds(zone, left, front - zone.archStartZ)
end

-- Seconds left in the current step: until the next step's arch switches on,
-- or for the last step until the whole wash is done.
local function stageSecondsLeft(zone: Zone): number
	local nextStart = zone.stageStarts[zone.stage + 1]
	if nextStart then
		return secondsUntilFront(zone, nextStart)
	end
	return washSecondsLeft(zone)
end

local function publishStage(zone: Zone)
	local left = stageSecondsLeft(zone)
	zone.stageEndsAt = now() + left
	Screens.Wash:SetAttribute("StageTotal", math.max(left, 1))
	Screens.Wash:SetAttribute("StageEndsAt", zone.stageEndsAt)
end

local function setStage(zone: Zone, index: number, name: string)
	if Screens.Wash:GetAttribute("State") == "Running" then
		zone.stage = index
		Screens.Wash:SetAttribute("StageIndex", index)
		Screens.Wash:SetAttribute("Stage", name)
		publishStage(zone)
	end
end

-- Wash Time counts down to the car's tail clearing the last arch; its
-- progress bar shows how far through the current step the car is.
local function startCountdown(zone: Zone)
	local myRun = runId
	local endsAt = now() + washSecondsLeft(zone)
	zone.stage = 1
	Screens.set(Screens.Wash, "Running", {
		EndsAt = endsAt,
		Total = math.max(washSecondsLeft(zone), 1),
		Stage = BRUSH_STAGE,
		StageIndex = 1,
		StageCount = #zone.stageStarts,
	})
	publishStage(zone)

	task.spawn(function()
		while myRun == runId do
			local left = washSecondsLeft(zone)
			if left <= 0 then
				break
			end
			local t = now()
			if math.abs(t + left - endsAt) > COUNTDOWN_TOLERANCE then
				endsAt = t + left
				Screens.Wash:SetAttribute("EndsAt", endsAt)
			end
			local stageEstimate = t + stageSecondsLeft(zone)
			if math.abs(stageEstimate - zone.stageEndsAt) > COUNTDOWN_TOLERANCE then
				zone.stageEndsAt = stageEstimate
				Screens.Wash:SetAttribute("StageEndsAt", stageEstimate)
			end
			task.wait(COUNTDOWN_INTERVAL)
		end
		if myRun == runId then
			Screens.set(Screens.Wash, "Done")
		end
	end)
end

------------------------------------------------------------------------------
-- The timeline

-- One continuous pull from the pickup point to the dryers. Each machine
-- switches on as the car's nose reaches it and off once its tail has passed.
local function runTunnel(program)
	local front, rear = Conveyor.frontReaches, Conveyor.rearPasses
	local triggers: { Conveyor.Trigger } = {
		{ ready = rear(Blasters.END_Z), run = function() Blasters.set(false) end },
		{ ready = front(Brushes.WRAP_Z + 5), run = Brushes.closeWraps },
		{ ready = rear(Brushes.WRAP_Z - 2), run = Brushes.openWraps },
		{ ready = rear(Brushes.WRAP_Z - 12), run = function() Brushes.setWraps(false) end },
		{ ready = front(Brushes.ROCKER_START_Z), run = function() Brushes.setRockers(true) end },
		{ ready = rear(Brushes.ROCKER_END_Z), run = function() Brushes.setRockers(false) end },
	}

	-- The brushes are step 1 (already running), then one step per arch.
	local zone: Zone = {
		archStartZ = -math.huge,
		archEndZ = math.huge,
		archSpeed = program.archSpeed,
		stageStarts = { Brushes.PICKUP_Z },
		stage = 1,
		stageEndsAt = 0,
	}
	local runsArch = {}
	for _, key in program.arches do
		runsArch[key] = true
	end
	for _, arch in Arches.ordered do
		if runsArch[arch.key] then
			local startZ = arch.z + Config.ArchLead
			local endZ = arch.z - Config.ArchTrail
			table.insert(zone.stageStarts, startZ)
			local stageIndex = #zone.stageStarts
			table.insert(triggers, {
				ready = front(startZ),
				run = function()
					Arches.set(arch, true)
					setStage(zone, stageIndex, Arches.StageNames[arch.key] or arch.key)
				end,
			})
			table.insert(triggers, { ready = rear(endZ), run = function() Arches.set(arch, false) end })
			-- start slowing a little early so the car is already crawling when the first arch switches on
			zone.archStartZ = math.max(zone.archStartZ, startZ + 1.5)
			zone.archEndZ = math.min(zone.archEndZ, endZ)
		end
	end
	-- each dryer starts as the car's nose gets right under it, one at a time
	for index, z in Dryers.startZs do
		table.insert(triggers, { ready = front(z), run = function() Dryers.startUnit(index) end })
	end

	startCountdown(zone)
	Blasters.set(true)
	Brushes.setWraps(true)
	Conveyor.moveCarTo(Dryers.CENTER_Z - Car.length() / 2, triggers, function()
		return zoneSpeed(zone)
	end)
end

local function runDryers()
	-- any dryer the car's nose didn't reach starts now, still one at a time
	Dryers.startAll()
	Screens.set(Screens.Dry, "Running", {
		EndsAt = now() + Config.DrySeconds,
		Total = Config.DrySeconds,
	})
	task.wait(Config.DrySeconds)
	Screens.set(Screens.Dry, "Done")
	Dryers.stop()
end

local function releaseCar()
	Gates.setExit(true)
	task.wait(Config.ExitGateOpenSeconds)
	Conveyor.moveCarTo(Gates.ExitSensor.Position.Z - Car.length() - EXIT_CLEARANCE)
	Gates.setExit(false)
	Car.releaseTow()
end

-- Washes one car with `programKey` (a key of Config.Programs). `entryHit` is
-- the part that tripped the entry gate, used to identify the car early.
-- Yields until the car has left; errors if something goes wrong.
function Wash.run(programKey: string, entryHit: BasePart?)
	local program = Config.Programs[programKey]
	assert(program, "Unknown wash program: " .. tostring(programKey))

	Car.reset(Brushes.PICKUP_Z)
	Blasters.reset()
	if entryHit then
		Car.capture(entryHit)
	end

	Screens.setProgram(program.name)
	Screens.set(Screens.Wash, "Waiting")
	Screens.set(Screens.Dry, "Waiting")
	Car.waitForPickup(Brushes.PickupSensor, Brushes.PICKUP_Z, Config.ArrivalTimeout)
	Car.grab()
	Car.publish(true)

	setPhase("Washing")
	runTunnel(program)
	setPhase("Drying")
	runDryers()
	setPhase("Exit")
	releaseCar()
	setPhase("Finished")

	Car.unpublish()
	Screens.idle()
end

-- A paid customer's gate is open: the tunnel lights power up for them.
function Wash.ready()
	setPhase("Ready")
end

-- Every machine back to idle.
function Wash.reset()
	runId += 1
	Arches.resetAll()
	Brushes.setWraps(false)
	Brushes.setRockers(false)
	Blasters.set(false)
	Conveyor.stop()
	Dryers.reset()
	Car.releaseTow()
	Car.unpublish()
	Screens.idle()
end

-- Stops a wash that went wrong and lets the car out.
function Wash.abort()
	Wash.reset()
	Gates.setExit(true)
	setPhase("Finished")
end

function Wash.start()
	Wash.reset()
	setPhase("Idle")
	Blasters.startSensing()
end

return Wash
