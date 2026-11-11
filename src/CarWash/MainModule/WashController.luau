-- Runs every machine in the wash line from one timeline, so the conveyor,
-- brushes, gantry, dryers, displays and exit gate always agree.
local RunService = game:GetService("RunService")

local WashController = {}

local CarWash = script.Parent.Parent
local Machine = CarWash.Machine
local Motor = Machine.Motor
local Sounds = Machine.Sounds
local Arms = { CarWash.Arm, CarWash.Arm2 }
local Wraps = CarWash.WrapArounds.Brushes
local Rockers = CarWash.RockerBrushes
local Blasters = CarWash.DuraBlasters
local ExitGate = CarWash.GateEX.Frame.MotorSupport.HingeConstraint
local WashDisplay = CarWash.TimerWash.Value
local DryDisplay = CarWash.Timer.Value

local Belts = {}
for _, child in CarWash.ConveyorPart:GetChildren() do
	if child.Name:match("^Conveyor") then
		table.insert(Belts, child)
	end
end

local Dryers = {}
for _, child in CarWash:GetChildren() do
	if child.Name:match("^KWS Storm Dryer") then
		table.insert(Dryers, child.Dryers)
	end
end

local CONVEYOR_SPEED = 2
local ARRIVAL_TIMEOUT = 45 -- how long a paid customer gets to reach the conveyor
local DRY_SECONDS = 60
local DEFAULT_CAR_LENGTH = 14
local EXIT_GATE_OPEN_SECONDS = 5
local SWEEP_ANGLE = 20
local SWEEP_PERIOD = 1.5

-- Halfway between the left wheel track and the right belt.
local LANE_X = (CarWash.ConveyorPart.Conveyor4.Position.X + CarWash.ConveyorPart.Conveyor3.Position.X) / 2

local PICKUP_Z = Wraps.Sensor.Position.Z
local WRAP_Z = Wraps.BrushOne.MotorAnchor.Position.Z
local ROCKER_START_Z = Rockers.Sensor.Position.Z
local ROCKER_END_Z = ROCKER_START_Z - 9
local BLASTER_END_Z = Blasters.Eye.Position.Z - 2
local WASH_STOP_Z = CarWash.PositioningSystem.Stop.Position.Z
local EXIT_SENSOR_Z = CarWash.GateEX.CloseSensor.Position.Z

local DRYER_START_Z = -math.huge
local dryerCenterSum = 0
for _, dryer in Dryers do
	DRYER_START_Z = math.max(DRYER_START_Z, dryer.OnSensor.Position.Z)
	dryerCenterSum += (dryer.OnSensor.Position.Z + dryer.OffSensor.Position.Z) / 2
end
local DRY_CENTER_Z = dryerCenterSum / #Dryers

-- Each gantry move stops on its limit sensor and is then padded to `travel`
-- seconds, which keeps the whole program on a fixed clock.
local LIMITS = {
	Back = { sensor = CarWash.BackLimit, flag = Motor.ToBack, travel = 9 },
	VeryBack = { sensor = CarWash.VeryBackLimit, flag = Motor.ToBack, travel = 13 },
	Middle = { sensor = CarWash.MiddleLimit, flag = Motor.ToFront, travel = 5 },
	Front = { sensor = CarWash.FrontLimit, flag = Motor.ToFront, travel = 9 },
}

local function setArms(flag, on)
	for _, arm in Arms do
		arm[flag].Value = on
	end
end

local function trigger(sequenceScript)
	sequenceScript.Disabled = false
end

local FULL_PASS = { "Back", "Front" }

local STAGES = {
	Presoak = {
		path = FULL_PASS, soak = 20, sweep = true,
		start = function() setArms("Soap", true) trigger(Sounds.PresoakStart) end,
		stop = function() setArms("Soap", false) trigger(Sounds.PresoakStop) end,
	},
	HighPressure = {
		path = FULL_PASS, sweep = true,
		start = function() setArms("Wash", true) trigger(Sounds.HPStart) end,
		stop = function() setArms("Wash", false) trigger(Sounds.HPStop) end,
	},
	Foam = {
		path = FULL_PASS, soak = 18,
		start = function() trigger(Machine.FoamStart) end,
		stop = function() trigger(Machine.FoamStop) end,
	},
	ClearCoat = {
		path = FULL_PASS, soak = 7, sweep = true,
		start = function() setArms("Soap", true) setArms("Rinse", true) trigger(Sounds.ClearStart) end,
		stop = function() setArms("Soap", false) setArms("Rinse", false) trigger(Sounds.ClearStop) end,
	},
	HotWax = {
		path = { "VeryBack", "Middle", "Front" }, soak = 19,
		start = function() Machine.HotWax.Value.Value = true end,
		stop = function() Machine.HotWax.Value.Value = false end,
	},
	SpotFree = {
		path = FULL_PASS, sweep = true,
		start = function() setArms("Rinse", true) trigger(Sounds.SpotStart) end,
		stop = function() setArms("Rinse", false) trigger(Sounds.SpotStop) end,
	},
}

-- These add up to the 128 / 153 / 199 seconds the Wash Time display was built for.
local PROGRAMS = {
	Small = { "Presoak", "HighPressure", "Foam", "HighPressure", "SpotFree" },
	Middle = { "Presoak", "HighPressure", "Foam", "HighPressure", "ClearCoat", "SpotFree" },
	Full = { "Presoak", "HighPressure", "Foam", "HighPressure", "ClearCoat", "HotWax", "SpotFree" },
}

local car = {}
local runId = 0
local sweepRun = 0
local dryersRunning = false

local function sleepUntil(moment)
	local remaining = moment - os.clock()
	if remaining > 0 then
		task.wait(remaining)
	end
end

local function startCountdown(display, format, seconds)
	local myRun = runId
	local endsAt = os.clock() + seconds
	task.spawn(function()
		while myRun == runId and os.clock() < endsAt do
			display.Value = format:format(math.ceil(endsAt - os.clock()))
			task.wait(0.1)
		end
	end)
	return endsAt
end

local function setBelts(speed)
	for _, belt in Belts do
		belt.AssemblyLinearVelocity = belt.CFrame.LookVector * speed
	end
end

local function setBlasters(on)
	for _, side in { Blasters.LeftDuraBlaster, Blasters.RightDuraBlaster } do
		for _, item in side:GetDescendants() do
			if item:IsA("HingeConstraint") and item.Parent.Name == "SpinnerAttatchment" then
				item.AngularVelocity = on and 40 or 0
				item.MotorMaxTorque = on and 15 or 0
			elseif item:IsA("ParticleEmitter") and item.Name == "HP" then
				item.Enabled = on
			end
		end
	end
end

local function setWrapAngle(angle)
	Wraps.BrushOne.BrushPart.MotorHold.HingeConstraint.TargetAngle = angle
	Wraps.BrushTwo.BrushPart.MotorHold.HingeConstraint.TargetAngle = -angle
end

local function setWraps(on)
	for _, brush in { Wraps.BrushOne, Wraps.BrushTwo } do
		brush.BrushPart.Nozzle.ParticleEmitter.Enabled = on
	end
	Wraps.BrushOne.BrushMotor.MotorMain.HingeConstraint.AngularVelocity = on and 15 or 0
	Wraps.BrushTwo.BrushMotor.MotorMain.HingeConstraint.AngularVelocity = on and -15 or 0
	if on then
		Wraps.Air:Play()
		setWrapAngle(45)
	else
		Wraps.Brush:Stop()
		setWrapAngle(0)
	end
end

local function setRockers(on)
	for index, brush in { Rockers.BrushOne.RockerBrush, Rockers.BrushTwo.RockerBrush } do
		for _, nozzle in { brush.Nozzle, brush.Nozzle2, brush.Nozzle3 } do
			nozzle.ParticleEmitter.Enabled = on
		end
		brush.BrushMotor.MotorMain.HingeConstraint.AngularVelocity = on and 15 or 0
		brush.BrushPart.MotorHold.HingeConstraint.TargetAngle = on and (index == 1 and 30 or -30) or 0
	end
	if on then
		Rockers.Sound:Play()
	else
		Rockers.Sound:Stop()
	end
end

local function setFans(dryer, speed)
	for _, item in dryer:GetDescendants() do
		if item.Name == "FanMotor" then
			item.RightParamB = speed
		end
	end
end

local function startDryers()
	dryersRunning = true
	for _, dryer in Dryers do
		dryer.Startup:Play()
		setFans(dryer, 1)
		dryer.Dryer:Play()
	end
end

local function stopDryers()
	dryersRunning = false
	for _, dryer in Dryers do
		setFans(dryer, 0)
		dryer.Stop.Disabled = false
		dryer.Stop2.Disabled = false
	end
end

local function startSweep()
	sweepRun += 1
	local myRun = sweepRun
	task.spawn(function()
		local side = 1
		while myRun == sweepRun do
			Arms[1].Motor.HingeConstraint.TargetAngle = SWEEP_ANGLE * side
			Arms[2].Motor.HingeConstraint.TargetAngle = -SWEEP_ANGLE * side
			side = -side
			task.wait(SWEEP_PERIOD)
		end
	end)
end

local function stopSweep()
	sweepRun += 1
	for _, arm in Arms do
		arm.Motor.HingeConstraint.TargetAngle = 0
	end
end

local function moveGantry(limitName, finishBy)
	local limit = LIMITS[limitName]
	limit.sensor.Script.Disabled = false
	limit.flag.Value = true
	while limit.flag.Value and os.clock() < finishBy do
		task.wait(0.05)
	end
	limit.flag.Value = false
	limit.sensor.Script.Disabled = true
	sleepUntil(finishBy)
end

local function stageSeconds(stage)
	local total = stage.soak or 0
	for _, limitName in stage.path do
		total += LIMITS[limitName].travel
	end
	return total
end

local function hasCar()
	return car.seat ~= nil and car.seat:IsDescendantOf(workspace)
end

local function carFront()
	if hasCar() then
		return car.seat.Position.Z + car.frontOffset
	end
	return car.virtualFront
end

local function carRear()
	return carFront() + car.length
end

local function worldHalfSize(part, axis)
	local half = part.Size / 2
	local cf = part.CFrame
	return math.abs(cf.RightVector[axis]) * half.X
		+ math.abs(cf.UpVector[axis]) * half.Y
		+ math.abs(cf.LookVector[axis]) * half.Z
end

local function measureCar()
	local minX, maxX, minZ, maxZ, mass = math.huge, -math.huge, math.huge, -math.huge, 0
	for _, part in car.model:GetDescendants() do
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
	car.frontOffset = minZ - car.seat.Position.Z
	car.length = maxZ - minZ
	car.centerOffsetX = (minX + maxX) / 2 - car.seat.Position.X
	car.mass = mass
end

local function captureVehicle(hit)
	local model = hit:FindFirstAncestorWhichIsA("Model")
	while model do
		local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
		if seat then
			car.model, car.seat = model, seat
			measureCar()
			return
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
end

local function waitForCar()
	local connection = Wraps.Sensor.Touched:Connect(function(hit)
		if not hasCar() then
			captureVehicle(hit)
		end
	end)
	local deadline = os.clock() + ARRIVAL_TIMEOUT
	while os.clock() < deadline and not (hasCar() and carFront() <= PICKUP_Z) do
		task.wait(0.05)
	end
	connection:Disconnect()
end

-- The conveyor takes over the car: it holds it straight in the lane and the
-- driver cannot move it until it has left through the exit gate.
local function grabCar()
	if not hasCar() then
		return
	end
	measureCar()

	local seat = car.seat
	local attachment = Instance.new("Attachment")
	attachment.Name = "WashTow"
	-- The seat is off-center, so pull from the center of mass or the car would yaw.
	attachment.Position = seat.CFrame:PointToObjectSpace(seat.AssemblyCenterOfMass)
	attachment.Parent = seat

	local force = car.mass * 1000
	local tow = Instance.new("LinearVelocity")
	tow.Name = "WashTow"
	tow.Attachment0 = attachment
	tow.RelativeTo = Enum.ActuatorRelativeTo.World
	tow.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	tow.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	tow.MaxAxesForce = Vector3.new(force, 0, force)
	tow.VectorVelocity = Vector3.zero
	tow.Parent = seat

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

	car.attachment, car.tow, car.align = attachment, tow, align
end

local function releaseTow()
	for _, key in { "tow", "align", "attachment" } do
		if car[key] then
			car[key]:Destroy()
			car[key] = nil
		end
	end
end

local function setCarVelocity(speed)
	if not car.tow then
		return
	end
	local lateral = 0
	if speed > 0 then
		local centerX = car.seat.Position.X + car.centerOffsetX
		lateral = math.clamp((LANE_X - centerX) * 1.5, -1.5, 1.5)
	end
	car.tow.VectorVelocity = Vector3.new(lateral, 0, -speed)
end

-- Moves the car until its front reaches targetZ. Each trigger fires once, the
-- moment the car reaches that point, and anything still unfired fires at the end.
local function moveCarTo(targetZ, triggers)
	setBelts(CONVEYOR_SPEED)
	local deadline = os.clock() + math.max(carFront() - targetZ, 0) / CONVEYOR_SPEED + 15
	local pending = table.clone(triggers or {})

	local function checkTriggers()
		for index = #pending, 1, -1 do
			if pending[index].ready() then
				table.remove(pending, index).run()
			end
		end
	end

	while carFront() > targetZ and os.clock() < deadline do
		local deltaTime = RunService.Heartbeat:Wait()
		local speed = math.clamp((carFront() - targetZ) * 1.5, 0.4, CONVEYOR_SPEED)
		if hasCar() then
			setCarVelocity(speed)
			car.virtualFront = carFront()
		else
			car.virtualFront -= speed * deltaTime
		end
		checkTriggers()
	end

	setCarVelocity(0)
	setBelts(0)
	for index = #pending, 1, -1 do
		table.remove(pending, index).run()
	end
end

local function frontReaches(z)
	return function()
		return carFront() <= z
	end
end

local function rearPasses(z)
	return function()
		return carRear() <= z
	end
end

local function runTunnel()
	setBlasters(true)
	setWraps(true)
	moveCarTo(WASH_STOP_Z, {
		{ ready = rearPasses(BLASTER_END_Z), run = function() setBlasters(false) end },
		{ ready = frontReaches(WRAP_Z + 5), run = function()
			Wraps.Air2:Play()
			Wraps.Brush:Play()
			setWrapAngle(15)
		end },
		{ ready = rearPasses(WRAP_Z - 2), run = function()
			Wraps.Air:Play()
			setWrapAngle(45)
		end },
		{ ready = rearPasses(WRAP_Z - 12), run = function() setWraps(false) end },
		{ ready = frontReaches(ROCKER_START_Z), run = function() setRockers(true) end },
		{ ready = rearPasses(ROCKER_END_Z), run = function() setRockers(false) end },
	})
end

local function runProgram(program)
	local total = 0
	for _, name in program do
		total += stageSeconds(STAGES[name])
	end
	startCountdown(WashDisplay, "%03d", total)

	local clock = os.clock()
	for _, name in program do
		local stage = STAGES[name]
		stage.start()
		if stage.sweep then
			startSweep()
		end
		for _, limitName in stage.path do
			clock += LIMITS[limitName].travel
			moveGantry(limitName, clock)
		end
		stopSweep()
		stage.stop()
		clock += stage.soak or 0
		sleepUntil(clock)
	end
	WashDisplay.Value = "---"
end

local function runDryers()
	moveCarTo(DRY_CENTER_Z - car.length / 2, {
		{ ready = frontReaches(DRYER_START_Z), run = startDryers },
	})
	sleepUntil(startCountdown(DryDisplay, "%02d", DRY_SECONDS))
	DryDisplay.Value = "--"
	stopDryers()
end

local function releaseCar()
	ExitGate.TargetAngle = -80
	task.wait(EXIT_GATE_OPEN_SECONDS)
	moveCarTo(EXIT_SENSOR_Z - car.length - 3)
	ExitGate.TargetAngle = 0
	releaseTow()
end

function WashController:Run(washType, entryHit)
	local program = PROGRAMS[washType]
	assert(program, "Unknown wash type: " .. tostring(washType))

	car = { virtualFront = PICKUP_Z, length = DEFAULT_CAR_LENGTH, frontOffset = 0, centerOffsetX = 0 }
	if entryHit then
		captureVehicle(entryHit)
	end

	waitForCar()
	grabCar()
	runTunnel()
	runProgram(program)
	runDryers()
	releaseCar()
end

-- Puts every machine back to idle.
function WashController:Reset()
	runId += 1
	stopSweep()
	Motor.ToBack.Value = false
	Motor.ToFront.Value = false
	for _, limit in LIMITS do
		limit.sensor.Script.Disabled = true
	end
	for _, flag in { "Wash", "Soap", "Rinse" } do
		setArms(flag, false)
	end
	Machine.T1.On.Value = false
	Machine.T2.On.Value = false
	Machine.HotWax.Value.Value = false
	setWraps(false)
	setRockers(false)
	setBlasters(false)
	setBelts(0)
	if dryersRunning then
		stopDryers()
	end
	releaseTow()
	WashDisplay.Value = "---"
	DryDisplay.Value = "--"
end

-- Stops a wash that went wrong and lets the car out.
function WashController:Abort()
	self:Reset()
	ExitGate.TargetAngle = -80
end

function WashController:Initialize()
	self:Reset()
end

return WashController
