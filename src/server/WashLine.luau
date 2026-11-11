-- Ties the customer flow together:
--
--   pay at the Kiosk -> entry gate opens (when the wash is free)
--   -> car drives through the gate -> gate closes, Wash runs -> line is free
--
-- and keeps the ProgressScreen at the entrance in step:
--   Select    nobody has paid yet
--   Good      paid, gate open, drive in
--   Occupied  a car is being washed

local Config = require(script.Parent.Config)
local Gates = require(script.Parent.Gates)
local Kiosk = require(script.Parent.Kiosk)
local Wash = require(script.Parent.Wash)

local ProgressGui = workspace:WaitForChild("CarWash").ProgressScreen.Screen.SurfaceGui
local STATUS_FRAMES = {
	Select = ProgressGui.Select,
	Good = ProgressGui.Good,
	Occupied = ProgressGui.Occupied,
}

local WashLine = {}

local washing = false
local admitted: string? = nil -- the paid program whose car may drive in

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

	local ok, err = pcall(Wash.run, program, entryHit)
	if not ok then
		warn(`CarWash: wash stopped early: {err}`)
		Wash.abort()
	end

	print(`CarWash: finished {program}`)
	washing = false
	showStatus()
end

-- Called by the Kiosk after payment. Waits until the wash is free, then opens
-- the entry gate for this customer. A newer payment replaces one whose car
-- never drove in, so an abandoned payment can't block the wash.
local function admit(program: string)
	while washing do
		task.wait(0.1)
	end
	Gates.setEntry(true)
	Wash.ready()
	task.wait(Config.EntryGateSettleSeconds)
	admitted = program
	showStatus()
end

local function onCarEntered(hit: BasePart)
	local program = admitted
	if not program then
		return
	end
	admitted = nil
	Kiosk.reset()
	Gates.setEntry(false)
	task.spawn(runWash, program, hit)
end

function WashLine.start()
	Wash.start()
	Kiosk.start(admit)
	Gates.EntrySensor.Touched:Connect(onCarEntered)
	showStatus()
end

return WashLine
