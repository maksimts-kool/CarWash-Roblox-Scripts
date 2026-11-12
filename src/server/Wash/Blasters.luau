-- The rotary wheel blasters (CarWash.RotaryWheelBlasters): one blaster on each
-- side of the lane (Blaster1, Blaster2), each with three spinning heads
-- (BlasterPart, BlasterPart2, BlasterPart3) whose hp1..hp5 nozzles fire at the
-- wheels. Each head spins on the "Joint" Joints made from its Motor's old
-- Rotate joint (see Joints).
--
-- The Sensor is a beam across the left wheel track just before the heads.
-- Whatever of the car crosses it is remembered by its distance behind the
-- car's nose; while the blasters are on, the heads spin and the nozzles fire
-- only while one of those spots (a wheel) is in front of the heads. If the
-- sensor saw nothing of the car, the nozzles just fire the whole time.

local Car = require(script.Parent.Car)
local Joints = require(script.Parent.Parent.Joints)

local CarWash = workspace:WaitForChild("CarWash")
local Model = CarWash.RotaryWheelBlasters
local Sensor = Model.Sensor :: BasePart

local SPIN_SPEED = 720 -- degrees per second
local SENSE_INTERVAL = 0.05
local SPAN_GAP = 0.5 -- studs: sightings closer than this belong to the same wheel
local FIRE_MARGIN = 0.75 -- studs: start firing this far before a wheel reaches the heads (and stop as far after)

-- The heads, each with its spin joint and nozzle emitters.
type Head = { joint: Motor6D?, emitters: { ParticleEmitter } }
local heads: { Head } = {}
local headMinZ, headMaxZ = math.huge, -math.huge

for _, blaster in Model:GetChildren() do
	if not (blaster:IsA("Model") and blaster.Name:match("^Blaster%d")) then
		continue
	end
	for _, head in blaster:GetChildren() do
		local motor = head:FindFirstChild("Motor")
		if not (head:IsA("Model") and head.Name:match("^BlasterPart") and motor and motor:IsA("BasePart")) then
			continue
		end
		local emitters = {}
		for _, item in head:GetDescendants() do
			if item:IsA("ParticleEmitter") then
				item.Enabled = false
				table.insert(emitters, item)
			end
		end
		local joint = Joints.get(motor)
		if not joint then
			warn(`Blasters: {motor:GetFullName()} has no spin joint`)
		end
		table.insert(heads, { joint = joint, emitters = emitters })
		local halfZ = head:GetExtentsSize().Z / 2
		headMinZ = math.min(headMinZ, motor.Position.Z - halfZ)
		headMaxZ = math.max(headMaxZ, motor.Position.Z + halfZ)
	end
end

local Module = {}

-- The blasters can switch off once the car's tail passes this.
Module.END_Z = headMinZ - 2
-- Where along the lane the heads spray (for CarCondition).
Module.MIN_Z = headMinZ
Module.MAX_Z = headMaxZ

-- What the sensor saw of the current car: spans of distance behind its nose.
type Span = { from: number, to: number }
local spans: { Span } = {}

local powered = false
local spinning = false
local firing = false

local function setSpin(on: boolean)
	if on == spinning then
		return
	end
	spinning = on
	for _, head in heads do
		Joints.spin(head.joint, if on then SPIN_SPEED else 0)
	end
end

local function setFiring(on: boolean)
	if on == firing then
		return
	end
	firing = on
	for _, head in heads do
		for _, emitter in head.emitters do
			emitter.Enabled = on
		end
	end
end

local function record(offset: number)
	local last = spans[#spans]
	if last and offset >= last.from - SPAN_GAP and offset <= last.to + SPAN_GAP then
		last.from = math.min(last.from, offset)
		last.to = math.max(last.to, offset)
	else
		table.insert(spans, { from = offset, to = offset })
	end
end

-- Is a wheel the sensor saw in front of the heads right now?
local function wheelAtHeads(): boolean
	local front = Car.front()
	for _, span in spans do
		local nearZ, farZ = front + span.from - FIRE_MARGIN, front + span.to + FIRE_MARGIN
		if nearZ <= headMaxZ and farZ >= headMinZ then
			return true
		end
	end
	return false
end

local function update()
	setSpin(powered)
	if not powered then
		setFiring(false)
	elseif not Car.has() or #spans == 0 then
		-- no car to follow, or the sensor missed it: just keep firing
		setFiring(true)
	else
		setFiring(wheelAtHeads())
	end
end

-- Switches the blasters on (spinning, firing at the wheels) or off.
function Module.set(on: boolean)
	powered = on
	update()
end

function Module.isOn(): boolean
	return powered
end

-- Forgets the last car's wheels. Call when a new car is taken on.
function Module.reset()
	table.clear(spans)
end

-- Watches the Sensor for as long as the server runs.
function Module.startSensing()
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include

	task.spawn(function()
		while true do
			local car = Car.model()
			if car then
				params.FilterDescendantsInstances = { car }
				if #workspace:GetPartsInPart(Sensor, params) > 0 then
					record(Sensor.Position.Z - Car.front())
				end
			end
			update()
			task.wait(SENSE_INTERVAL)
		end
	end)
end

return Module
