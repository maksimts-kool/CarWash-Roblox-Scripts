-- The wrap-around brushes (CarWash.WrapArounds) and the rocker brushes
-- (CarWash.RockerBrushes). Each brush has soapy nozzle sprays and a FlingFx
-- ring of emitters; they all switch with the brush. Each brush swings on its
-- MotorHold joint and spins on its MotorMain joint (see Joints).

local Joints = require(script.Parent.Parent.Joints)

local CarWash = workspace:WaitForChild("CarWash")
local Wraps = CarWash.WrapArounds.Brushes
local Rockers = CarWash.RockerBrushes

local WRAP_SPIN = math.deg(15) -- degrees per second
local ROCKER_SPIN = math.deg(15)
local ROCKER_ANGLE = 30
local WRAP_OPEN_ANGLE = 45 -- swung wide, around the car's sides
local WRAP_CLOSED_ANGLE = 15 -- swung in, across the car's front and back

local Brushes = {}

-- What's running, for the ControlPanel.
Brushes.wrapsOn = false
Brushes.rockersOn = false

-- The conveyor picks the car up when its nose reaches the wrap-around sensor.
Brushes.PickupSensor = Wraps.Sensor :: BasePart
Brushes.PICKUP_Z = Wraps.Sensor.Position.Z
Brushes.WRAP_Z = Wraps.BrushOne.MotorAnchor.Position.Z
Brushes.ROCKER_START_Z = Rockers.Sensor.Position.Z
Brushes.ROCKER_END_Z = Brushes.ROCKER_START_Z - 9

local function setEmittersUnder(root: Instance, on: boolean)
	for _, item in root:GetDescendants() do
		if item:IsA("ParticleEmitter") then
			item.Enabled = on
		end
	end
end

local function setWrapAngle(angle: number)
	Joints.servo(Joints.get(Wraps.BrushOne.BrushPart.MotorHold), angle)
	Joints.servo(Joints.get(Wraps.BrushTwo.BrushPart.MotorHold), -angle)
end

function Brushes.setWraps(on: boolean)
	Brushes.wrapsOn = on
	for _, brush in { Wraps.BrushOne, Wraps.BrushTwo } do
		setEmittersUnder(brush, on)
	end
	Joints.spin(Joints.get(Wraps.BrushOne.BrushMotor.MotorMain), if on then WRAP_SPIN else 0)
	Joints.spin(Joints.get(Wraps.BrushTwo.BrushMotor.MotorMain), if on then -WRAP_SPIN else 0)
	if on then
		Wraps.Air:Play()
		setWrapAngle(WRAP_OPEN_ANGLE)
	else
		Wraps.Brush:Stop()
		setWrapAngle(0)
	end
end

-- The car's nose has reached the brushes: swing in to scrub the front.
function Brushes.closeWraps()
	Wraps.Air2:Play()
	Wraps.Brush:Play()
	setWrapAngle(WRAP_CLOSED_ANGLE)
end

-- Swing back out to let the car through and scrub its sides.
function Brushes.openWraps()
	Wraps.Air:Play()
	setWrapAngle(WRAP_OPEN_ANGLE)
end

function Brushes.setRockers(on: boolean)
	Brushes.rockersOn = on
	for index, brush in { Rockers.BrushOne.RockerBrush, Rockers.BrushTwo.RockerBrush } do
		setEmittersUnder(brush, on)
		Joints.spin(Joints.get(brush.BrushMotor.MotorMain), if on then ROCKER_SPIN else 0)
		local side = if index == 1 then 1 else -1
		Joints.servo(Joints.get(brush.BrushPart.MotorHold), if on then side * ROCKER_ANGLE else 0)
	end
	if on then
		Rockers.Sound:Play()
	else
		Rockers.Sound:Stop()
	end
end

return Brushes
