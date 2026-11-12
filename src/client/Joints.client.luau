-- Moves the wash's machinery: every Motor6D the server's Joints module made
-- from the old hinges and fan motors (tagged "CarWashJoint"). Their parts are
-- anchored assemblies, so nothing is simulated; each frame this sets every
-- joint's Transform from its attributes:
--
--   Mode   "Servo": swing to Target (degrees) at up to Speed (degrees/s)
--          "Motor": spin at Spin (degrees/s)
--   Rest   the hinge angle the joint was built at
--   Sign   1, or -1 when it turns the other way round
--   Kind   "Slide": the joint slides along its axis instead of turning, and
--          Target / Speed / Rest are in studs (the top brush's lift)
--
-- Swings ease in and out and spins speed up and slow down smoothly. A joint
-- seen for the first time starts at its Target, so players who join late see
-- the gates and arms where they are.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "CarWashJoint"
local SERVO_EASE = 0.35 -- seconds a swing takes to reach full speed (and to stop)
local SPIN_EASE = 1.5 -- seconds a motor takes to reach full speed from rest (and back)

type State = { angle: number, velocity: number, written: number? }

local joints: { [Motor6D]: State } = {}

local function approach(value: number, goal: number, step: number): number
	if value < goal then
		return math.min(value + step, goal)
	end
	return math.max(value - step, goal)
end

local function add(joint: Instance)
	if not joint:IsA("Motor6D") or joints[joint] then
		return
	end
	local start = if joint:GetAttribute("Mode") == "Servo"
		then joint:GetAttribute("Target")
		else joint:GetAttribute("Rest")
	joints[joint] = { angle = start or 0, velocity = 0 }
end

local function remove(joint: Instance)
	joints[joint :: Motor6D] = nil
end

local function stepServo(joint: Motor6D, state: State, dt: number)
	local target = joint:GetAttribute("Target") or state.angle
	local speed = math.max(joint:GetAttribute("Speed") or 90, 1)
	local accel = speed / SERVO_EASE
	local distance = target - state.angle
	if math.abs(distance) < 1e-3 and math.abs(state.velocity) < 1e-2 then
		state.angle, state.velocity = target, 0
		return
	end
	-- head for the target, but no faster than lets it stop there
	local want = math.sign(distance) * math.min(speed, math.sqrt(2 * accel * math.abs(distance)))
	state.velocity = approach(state.velocity, want, accel * dt)
	local step = state.velocity * dt
	if math.sign(step) == math.sign(distance) and math.abs(step) >= math.abs(distance) then
		state.angle, state.velocity = target, 0
	else
		state.angle += step
	end
end

local function stepMotor(joint: Motor6D, state: State, dt: number)
	local spin = joint:GetAttribute("Spin") or 0
	local rate = math.max(math.abs(spin), math.abs(state.velocity), 1) / SPIN_EASE
	state.velocity = approach(state.velocity, spin, rate * dt)
	state.angle = (state.angle + state.velocity * dt) % 360
end

RunService.PreSimulation:Connect(function(dt)
	for joint, state in joints do
		if joint:GetAttribute("Mode") == "Motor" then
			stepMotor(joint, state, dt)
		else
			stepServo(joint, state, dt)
		end
		if state.angle ~= state.written then
			state.written = state.angle
			local turn = (joint:GetAttribute("Sign") or 1) * (state.angle - (joint:GetAttribute("Rest") or 0))
			if joint:GetAttribute("Kind") == "Slide" then
				joint.Transform = CFrame.new(turn, 0, 0)
			else
				joint.Transform = CFrame.Angles(math.rad(turn), 0, 0)
			end
		end
	end
end)

CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
for _, joint in CollectionService:GetTagged(TAG) do
	add(joint)
end
