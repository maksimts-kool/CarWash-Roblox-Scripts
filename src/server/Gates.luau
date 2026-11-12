-- The entry gate (GateEN) and exit gate (GateEX) barrier arms, each swung by
-- the joint that replaced its hinge (see Joints).

local Config = require(script.Parent.Config)
local Joints = require(script.Parent.Joints)

local CarWash = workspace:WaitForChild("CarWash")
local EntryJoint = Joints.get(CarWash.GateEN.Frame.MotorSupport)
local ExitJoint = Joints.get(CarWash.GateEX.Frame.MotorSupport)

local Gates = {}

-- Where each arm was last sent (true = open), for the ControlPanel.
Gates.entryOpen = false
Gates.exitOpen = false

-- Touched when a car has driven through the entry gate.
Gates.EntrySensor = CarWash.GateEN.CloseSensor :: BasePart
-- The car is clear of the wash once its tail passes this.
Gates.ExitSensor = CarWash.GateEX.CloseSensor :: BasePart

local function angle(open: boolean): number
	return if open then Config.GateOpenAngle else Config.GateClosedAngle
end

function Gates.setEntry(open: boolean)
	Gates.entryOpen = open
	Joints.servo(EntryJoint, angle(open))
end

function Gates.setExit(open: boolean)
	Gates.exitOpen = open
	Joints.servo(ExitJoint, angle(open))
end

return Gates
