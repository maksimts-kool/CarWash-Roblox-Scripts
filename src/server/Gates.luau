-- The entry gate (GateEN) and exit gate (GateEX) barrier arms.

local Config = require(script.Parent.Config)

local CarWash = workspace:WaitForChild("CarWash")
local EntryHinge = CarWash.GateEN.Frame.MotorSupport.HingeConstraint
local ExitHinge = CarWash.GateEX.Frame.MotorSupport.HingeConstraint

local Gates = {}

-- Touched when a car has driven through the entry gate.
Gates.EntrySensor = CarWash.GateEN.CloseSensor :: BasePart
-- The car is clear of the wash once its tail passes this.
Gates.ExitSensor = CarWash.GateEX.CloseSensor :: BasePart

local function angle(open: boolean): number
	return if open then Config.GateOpenAngle else Config.GateClosedAngle
end

function Gates.setEntry(open: boolean)
	EntryHinge.TargetAngle = angle(open)
end

function Gates.setExit(open: boolean)
	ExitHinge.TargetAngle = angle(open)
end

return Gates
