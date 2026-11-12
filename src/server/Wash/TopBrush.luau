-- The top brush (CarWash.New.TopBrush): a horizontal brush on a carriage that
-- slides up and down the two posts. Only programs with `topBrush = true` in
-- Config.Programs use it (Middle and Full).
--
--   Carriage    slides on its "Lift" joint; Lift 0 is the top, negative is down
--   BrushMotor  spins on its "MotorMain" joint
--
-- The model has no constraints or body movers: Joints builds both joints from
-- plain Attachments (LiftGuide / LiftCarriage, SpinHolder / SpinAxle).
--
-- While it runs, the brush follows the car's outline: it raycasts the car's
-- visible parts under the brush and lowers the carriage until the brush just
-- rests on the highest point it would touch (hood, windscreen, roof, boot),
-- rising over the car and back to the top once the car has gone. The client
-- animates the joints (client/Joints), easing between targets.

local Car = require(script.Parent.Car)
local Joints = require(script.Parent.Parent.Joints)

local Model = workspace:WaitForChild("CarWash"):WaitForChild("New"):WaitForChild("TopBrush")
local Carriage = Model.Carriage
local Brush = Model.BrushMotor
local Axle = Brush.motor :: BasePart

local SPIN_SPEED = math.deg(15) -- degrees per second, like the wrap-arounds
local LIFT_SPEED = 5 -- studs per second the carriage moves at
local SQUEEZE = 0.2 -- studs the bristles press into the car
local FOLLOW_INTERVAL = 0.05 -- seconds between contour checks
local RETARGET = 0.05 -- studs; smaller changes aren't republished
local SAMPLES_X = 7 -- rays across the brush
local SAMPLE_STEP_Z = 0.4 -- studs between rays along the car
local EDGE_INSET = 0.4 -- studs in from each end of the brush

local lift = Joints.get(Carriage.Motor, "Lift")
local spin = Joints.get(Axle, "MotorMain")
if not lift then
	warn("TopBrush: Carriage.Motor has no Lift joint; the brush can't move up and down")
end
if not spin then
	warn("TopBrush: BrushMotor.motor has no MotorMain joint; the brush can't spin")
end

-- The brush's size, from its bristle rings.
local radius, minX, maxX = 0, math.huge, -math.huge
for _, ring in Brush:GetChildren() do
	if ring:IsA("UnionOperation") then
		radius = math.max(radius, ring.Size.Y / 2)
		minX = math.min(minX, ring.Position.X - ring.Size.X / 2)
		maxX = math.max(maxX, ring.Position.X + ring.Size.X / 2)
	end
end

local REST = if lift then lift:GetAttribute("Rest") or 0 else 0
local LIFT_MIN = if lift then lift:GetAttribute("Min") or -6.8 else 0
local LIFT_MAX = if lift then lift:GetAttribute("Max") or 0 else 0
local TOP_Y = Axle.Position.Y -- brush centre with the carriage at Lift = REST (saved at the top)
local AXLE_Z = Axle.Position.Z

local emitters: { ParticleEmitter } = {}
for _, item in Model:GetDescendants() do
	if item:IsA("ParticleEmitter") then
		item.Enabled = false
		table.insert(emitters, item)
	end
end
local sound = Carriage.Motor:FindFirstChild("Brush") :: Sound?

local TopBrush = {}

-- Where the brush is along the lane, and when the wash switches it on / off:
-- on as the car's nose gets near, off once its tail is clear of the bristles.
TopBrush.Z = AXLE_Z
TopBrush.START_Z = AXLE_Z + radius + 2
TopBrush.END_Z = AXLE_Z - radius - 1

local running = false
local run = 0
local lastTarget = LIFT_MAX

local function setLift(value: number, force: boolean?)
	value = math.clamp(value, LIFT_MIN, LIFT_MAX)
	if force or math.abs(value - lastTarget) > RETARGET then
		lastTarget = value
		Joints.servo(lift, value, LIFT_SPEED)
	end
end

local function setEffects(on: boolean)
	for _, emitter in emitters do
		emitter.Enabled = on
	end
	Joints.spin(spin, if on then SPIN_SPEED else 0)
	if sound then
		if on then
			sound:Play()
		else
			sound:Stop()
		end
	end
end

-- The car's visible parts: invisible hitboxes would hold the brush up in mid-air.
local function visibleParts(model: Model): { BasePart }
	local parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 0.95 then
			table.insert(parts, part)
		end
	end
	return parts
end

-- How high (Y) the brush centre has to be to clear what's under it, or nil
-- if there's no car under the brush.
local function clearanceY(params: RaycastParams): number?
	local best: number? = nil
	local castFrom = TOP_Y + radius + 1
	local down = Vector3.new(0, -(castFrom + 5), 0)
	local z = -radius
	while z <= radius do
		-- a roof point dz along the lane touches a round brush this much above it
		local rise = math.sqrt(math.max(radius * radius - z * z, 0))
		for i = 0, SAMPLES_X - 1 do
			local x = (minX + EDGE_INSET) + (maxX - minX - 2 * EDGE_INSET) * i / (SAMPLES_X - 1)
			local hit = workspace:Raycast(Vector3.new(x, castFrom, AXLE_Z + z), down, params)
			if hit then
				local need = hit.Position.Y + rise - SQUEEZE
				if not best or need > best then
					best = need
				end
			end
		end
		z += SAMPLE_STEP_Z
	end
	return best
end

local function follow(myRun: number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local tracked: Model? = nil

	while running and run == myRun do
		local car = Car.model()
		if car ~= tracked then
			tracked = car
			params.FilterDescendantsInstances = if car then visibleParts(car) else {}
		end
		local centreY = if car then clearanceY(params) else nil
		if centreY then
			setLift(REST + (centreY - TOP_Y))
		else
			setLift(LIFT_MAX) -- nothing under the brush: wait at the top
		end
		task.wait(FOLLOW_INTERVAL)
	end
end

-- Starts the brush spinning and following the car.
function TopBrush.start()
	if running then
		return
	end
	running = true
	run += 1
	setEffects(true)
	task.spawn(follow, run)
end

-- Stops the brush and raises it back to the top.
function TopBrush.stop()
	running = false
	run += 1
	setEffects(false)
	setLift(LIFT_MAX, true)
end

-- park it at the top when the server starts
TopBrush.stop()

return TopBrush
