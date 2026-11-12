-- Ties the customer flow together:
--
--   pay at the Kiosk -> entry gate opens (when the wash is free)
--   -> car drives through the gate -> gate closes, Wash runs -> line is free
--
-- and keeps the ProgressScreen at the entrance in step:
--   Select    nobody has paid yet
--   Good      paid, gate open, drive in
--   Occupied  a car is being washed
--
-- The ControlPanel drives the line too: an operator (free) wash, cancelling
-- an admission, and the emergency stop. Everything that happens is reported
-- to WashLine.onEvent listeners (the panel's stats and log).

local Config = require(script.Parent.Config)
local Gates = require(script.Parent.Gates)
local Kiosk = require(script.Parent.Kiosk)
local Wash = require(script.Parent.Wash)
local Stop = require(script.Parent.Wash.Stop)

local ProgressGui = workspace:WaitForChild("CarWash").ProgressScreen.Screen.SurfaceGui
local STATUS_FRAMES = {
	Select = ProgressGui.Select,
	Good = ProgressGui.Good,
	Occupied = ProgressGui.Occupied,
}

local WashLine = {}

local washing = false
local admitted: string? = nil -- the paid program whose car may drive in
local waiting = 0 -- payments waiting for the wash to be free

------------------------------------------------------------------------------
-- Events

-- Event kinds and their arguments:
--   "Paid" (program, price)   "Comp" (program)   "Admitted" (program)
--   "Cancelled" (program)     "WashStarted" (program)
--   "WashFinished" (program, seconds)   "WashFailed" (program, message)
--   "EStop" (wasWashing)      "Released" (wasWashing)
local listeners: { (string, ...any) -> () } = {}

local function emit(kind: string, ...: any)
	for _, listener in listeners do
		task.spawn(listener, kind, ...)
	end
end

function WashLine.onEvent(listener: (string, ...any) -> ())
	table.insert(listeners, listener)
end

------------------------------------------------------------------------------

local function showStatus()
	local status = if washing then "Occupied" elseif admitted then "Good" else "Select"
	for name, frame in STATUS_FRAMES do
		frame.Visible = name == status
	end
end

local function runWash(program: string, entryHit: BasePart)
	washing = true
	showStatus()
	print(`CarWash: starting {program}`)
	emit("WashStarted", program)
	local started = os.clock()

	local ok, err = pcall(Wash.run, program, entryHit)
	if ok then
		print(`CarWash: finished {program}`)
		emit("WashFinished", program, os.clock() - started)
	elseif Stop.isHalt(err) then
		-- machines were switched off by emergencyStop; hold until the operator resets
		print(`CarWash: {program} halted by the emergency stop`)
		while Stop.active do
			task.wait(0.1)
		end
		Wash.abort() -- lets the car out through the exit gate
	else
		warn(`CarWash: wash stopped early: {err}`)
		emit("WashFailed", program, tostring(err))
		Wash.abort()
	end

	washing = false
	showStatus()
end

-- Called after payment. Waits until the wash is free, then opens the entry
-- gate for this customer. A newer payment replaces one whose car never drove
-- in, so an abandoned payment can't block the wash.
local function admit(program: string)
	waiting += 1
	while washing or Stop.active do
		task.wait(0.1)
	end
	waiting -= 1
	Wash.reset() -- switch off anything an operator left running in a test
	Gates.setEntry(true)
	Wash.ready()
	task.wait(Config.EntryGateSettleSeconds)
	if Stop.active then
		return -- stopped while the gate opened; the operator takes it from here
	end
	admitted = program
	showStatus()
	emit("Admitted", program)
end

local function onCarEntered(hit: BasePart)
	local program = admitted
	if not program or Stop.active then
		return
	end
	admitted = nil
	Kiosk.reset()
	Gates.setEntry(false)
	task.spawn(runWash, program, hit)
end

------------------------------------------------------------------------------
-- The ControlPanel

-- What the line is doing: "Stopped", "Washing", "Admitted" or "Idle", and the
-- program of the car admitted or waiting to be (nil if none).
function WashLine.state(): (string, string?)
	if Stop.active then
		return "Stopped", admitted
	elseif washing then
		return "Washing", admitted
	elseif admitted or waiting > 0 then
		return "Admitted", admitted
	end
	return "Idle", nil
end

-- Lets a car in for `program` without paying. Only when the line is free.
function WashLine.admitFree(program: string): (boolean, string)
	if not Config.Programs[program] then
		return false, "Unknown wash"
	end
	local line = WashLine.state()
	if line ~= "Idle" then
		return false, if line == "Stopped" then "Reset the emergency stop first" else "The line is busy"
	end
	emit("Comp", program)
	task.spawn(admit, program)
	return true, `Gate opening for a free {Config.Programs[program].name}`
end

-- Takes back an admission whose car hasn't driven in: closes the entry gate.
function WashLine.cancelAdmission(): (boolean, string)
	local program = admitted
	if not program then
		return false, "No car is waiting to drive in"
	end
	admitted = nil
	Gates.setEntry(false)
	Kiosk.reset()
	if not washing then
		Wash.setPhase("Idle")
	end
	showStatus()
	emit("Cancelled", program)
	return true, "Admission cancelled, entry gate closing"
end

-- Halts the conveyor and every machine where they are. The car stays put
-- (the conveyor lets go of it) and the gates stay as they are.
function WashLine.emergencyStop(): (boolean, string)
	if Stop.active then
		return false, "Already stopped"
	end
	Stop.active = true
	Wash.reset()
	Wash.setPhase("Stopped")
	emit("EStop", washing)
	return true, "EMERGENCY STOP"
end

-- Clears the emergency stop. A car that was being washed is let out through
-- the exit gate; the line then takes the next customer.
function WashLine.resetStop(): (boolean, string)
	if not Stop.active then
		return false, "Not stopped"
	end
	Stop.active = false
	local wasWashing = washing
	if not wasWashing then
		Wash.setPhase(if admitted then "Ready" else "Idle")
	end
	emit("Released", wasWashing)
	return true, if wasWashing then "Reset: exit gate opening for the car" else "Reset: line ready"
end

function WashLine.start()
	Wash.start()
	Kiosk.start(function(program: string)
		emit("Paid", program, Config.Programs[program].price)
		admit(program)
	end)
	Gates.EntrySensor.Touched:Connect(onCarEntered)
	showStatus()
end

return WashLine
