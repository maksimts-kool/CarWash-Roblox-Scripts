-- The car going through the wash: finding it, measuring it, and towing it.
--
-- The conveyor holds the car straight in the lane with a LinearVelocity and an
-- AlignOrientation on its VehicleSeat, so the driver can't move it until it has
-- left through the exit gate. If the car disappears mid-wash (the player left)
-- a "virtual" car keeps moving so the timeline still finishes.
--
-- Publishes CarFront / CarLength on CarWash for the client light show.

local Config = require(script.Parent.Parent.Config)

local CarWash = workspace:WaitForChild("CarWash")

local PUBLISH_SECONDS = 0.1
local LANE_CORRECTION = 1.5 -- sideways studs/s per stud off the lane centre
local MAX_LANE_SPEED = 1.5

local Car = {}

local state = {}
local lastPublish = 0

local function worldHalfSize(part: BasePart, axis: string): number
	local half = part.Size / 2
	local cf = part.CFrame
	return math.abs(cf.RightVector[axis]) * half.X
		+ math.abs(cf.UpVector[axis]) * half.Y
		+ math.abs(cf.LookVector[axis]) * half.Z
end

-- Size and balance of the car, from its visible parts.
local function measure()
	local minX, maxX, minZ, maxZ, mass = math.huge, -math.huge, math.huge, -math.huge, 0
	for _, part in state.model:GetDescendants() do
		if part:IsA("BasePart") then
			mass += part.Mass
			if part.Transparency < 1 then
				local halfX, halfZ = worldHalfSize(part, "X"), worldHalfSize(part, "Z")
				minX = math.min(minX, part.Position.X - halfX)
				maxX = math.max(maxX, part.Position.X + halfX)
				minZ = math.min(minZ, part.Position.Z - halfZ)
				maxZ = math.max(maxZ, part.Position.Z + halfZ)
			end
		end
	end
	state.frontOffset = minZ - state.seat.Position.Z
	state.length = maxZ - minZ
	state.centerOffsetX = (minX + maxX) / 2 - state.seat.Position.X
	state.mass = mass
end

-- Forgets the last car. The next one starts as a virtual car at `startZ`.
function Car.reset(startZ: number)
	Car.releaseTow()
	state = {
		virtualFront = startZ,
		length = Config.DefaultCarLength,
		frontOffset = 0,
		centerOffsetX = 0,
	}
end

function Car.has(): boolean
	return state.seat ~= nil and state.seat:IsDescendantOf(workspace)
end

-- The car's model, while there is a real car.
function Car.model(): Model?
	return if Car.has() then state.model else nil
end

-- Z of the car's nose (the car travels toward -Z).
function Car.front(): number
	if Car.has() then
		return state.seat.Position.Z + state.frontOffset
	end
	return state.virtualFront
end

function Car.rear(): number
	return Car.front() + state.length
end

function Car.length(): number
	return state.length
end

-- Takes the vehicle `hit` belongs to as the car, if it is one.
function Car.capture(hit: BasePart)
	local model = hit:FindFirstAncestorWhichIsA("Model")
	while model do
		local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
		if seat then
			state.model, state.seat = model, seat
			measure()
			return
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
end

function Car.publish(force: boolean?)
	if not force and os.clock() - lastPublish < PUBLISH_SECONDS then
		return
	end
	lastPublish = os.clock()
	CarWash:SetAttribute("CarFront", Car.front())
	CarWash:SetAttribute("CarLength", state.length)
end

function Car.unpublish()
	CarWash:SetAttribute("CarFront", nil)
	CarWash:SetAttribute("CarLength", nil)
end

-- Waits until a car touching `sensor` has its nose at `pickupZ`, or times out.
function Car.waitForPickup(sensor: BasePart, pickupZ: number, timeout: number)
	local connection = sensor.Touched:Connect(function(hit)
		if not Car.has() then
			Car.capture(hit)
		end
	end)
	local deadline = os.clock() + timeout
	while os.clock() < deadline and not (Car.has() and Car.front() <= pickupZ) do
		if Car.has() then
			Car.publish()
		end
		task.wait(0.05)
	end
	connection:Disconnect()
end

-- The conveyor takes over the car.
function Car.grab()
	if not Car.has() then
		return
	end
	measure()

	local seat = state.seat
	local attachment = Instance.new("Attachment")
	attachment.Name = "WashTow"
	-- The seat is off-centre, so pull from the centre of mass or the car would yaw.
	attachment.Position = seat.CFrame:PointToObjectSpace(seat.AssemblyCenterOfMass)
	attachment.Parent = seat

	local force = state.mass * 1000
	local tow = Instance.new("LinearVelocity")
	tow.Name = "WashTow"
	tow.Attachment0 = attachment
	tow.RelativeTo = Enum.ActuatorRelativeTo.World
	tow.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	tow.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	tow.MaxAxesForce = Vector3.new(force, 0, force)
	tow.VectorVelocity = Vector3.zero
	tow.Parent = seat

	-- Straighten the car along the lane, whichever way it came in.
	local look = seat.CFrame.LookVector
	local straightZ = if look.Z <= 0 then -1 else 1
	local yawError = math.atan2(look.X, look.Z) - math.atan2(0, straightZ)

	local align = Instance.new("AlignOrientation")
	align.Name = "WashTowAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.MaxTorque = force * 10
	align.Responsiveness = 15
	align.CFrame = CFrame.Angles(0, -yawError, 0) * seat.CFrame.Rotation
	align.Parent = seat

	state.attachment, state.tow, state.align = attachment, tow, align
end

function Car.releaseTow()
	for _, key in { "tow", "align", "attachment" } do
		if state[key] then
			state[key]:Destroy()
			state[key] = nil
		end
	end
end

-- Moves the car toward -Z at `speed`, steering it back to `laneX`.
-- `deltaTime` advances the virtual car when the real one is gone.
function Car.drive(speed: number, laneX: number, deltaTime: number)
	if not Car.has() then
		state.virtualFront -= speed * deltaTime
		return
	end
	if state.tow then
		local lateral = 0
		if speed > 0 then
			local centerX = state.seat.Position.X + state.centerOffsetX
			lateral = math.clamp((laneX - centerX) * LANE_CORRECTION, -MAX_LANE_SPEED, MAX_LANE_SPEED)
		end
		state.tow.VectorVelocity = Vector3.new(lateral, 0, -speed)
	end
	state.virtualFront = Car.front()
end

return Car
