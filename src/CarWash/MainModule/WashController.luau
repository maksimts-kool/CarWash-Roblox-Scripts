-- Runs every machine in the wash line from one timeline, so the conveyor,
-- brushes, arches, dryers, displays and exit gate always agree.
local RunService = game:GetService("RunService")

local WashController = {}

local CarWash = script.Parent.Parent
local New = CarWash.New
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

-- Conveyor speeds, studs per second.
local CONVEYOR_SPEED = 2 -- into the dryers and out through the exit gate
local TUNNEL_SPEED = 1.2 -- through the blasters, wrap-arounds and rockers
-- Through the arches. Bigger washes crawl slower so every stage gets more time,
-- the way the old gantry's bigger programs ran longer.
local ARCH_SPEED = { Small = 0.9, Middle = 0.75, Full = 0.6 }
local CONVEYOR_ACCEL = 1.5 -- how quickly the car eases between speeds
local STALL_SECONDS = 12 -- give up on a move if the car makes no progress for this long
local ARRIVAL_TIMEOUT = 45 -- how long a paid customer gets to reach the conveyor
local DRY_SECONDS = 60
local DEFAULT_CAR_LENGTH = 14
local EXIT_GATE_OPEN_SECONDS = 5
local ARCH_LEAD = 1.5 -- an arch starts when the car's nose is this far before it
local ARCH_TRAIL = 1.5 -- and stops once the car's tail is this far past it

-- Halfway between the left wheel track and the right belt.
local LANE_X = (CarWash.ConveyorPart.Conveyor4.Position.X + CarWash.ConveyorPart.Conveyor3.Position.X) / 2

local PICKUP_Z = Wraps.Sensor.Position.Z
local WRAP_Z = Wraps.BrushOne.MotorAnchor.Position.Z
local ROCKER_START_Z = Rockers.Sensor.Position.Z
local ROCKER_END_Z = ROCKER_START_Z - 9
local BLASTER_END_Z = Blasters.Eye.Position.Z - 2
local EXIT_SENSOR_Z = CarWash.GateEX.CloseSensor.Position.Z

local DRYER_START_Z = -math.huge
local dryerCenterSum = 0
for _, dryer in Dryers do
	DRYER_START_Z = math.max(DRYER_START_Z, dryer.OnSensor.Position.Z)
	dryerCenterSum += (dryer.OnSensor.Position.Z + dryer.OffSensor.Position.Z) / 2
end
local DRY_CENTER_Z = dryerCenterSum / #Dryers

local function emittersIn(root, name)
	local list = {}
	for _, item in root:GetDescendants() do
		if item:IsA("ParticleEmitter") and item.Name == name then
			table.insert(list, item)
		end
	end
	return list
end

local function setEmitters(list, on)
	for _, emitter in list do
		emitter.Enabled = on
	end
end

-- Arches in CarWash.New, in the order the car meets them. Each one has its
-- jets, a Rope LED (animated on the clients by New.ArchLights from the
-- LightMode / LightSince attributes) and a Speaker part with Start / Loop / Stop sounds.
local ArchOrder = {}

local function later(arch, seconds, callback)
	local myRun = arch.run
	task.delay(seconds, function()
		if arch.run == myRun then
			callback()
		end
	end)
end

local function defineArch(key, modelName, setup)
	local model = New[modelName]
	local arch = {
		key = key,
		model = model,
		z = model.Frame:GetBoundingBox().Position.Z,
		speaker = model:FindFirstChild("Speaker"),
		run = 0,
		active = false,
	}
	if type(setup) == "string" then
		local jets = emittersIn(model, setup)
		arch.start = function() setEmitters(jets, true) end
		arch.stop = function() setEmitters(jets, false) end
	else
		setup(arch, model)
	end
	table.insert(ArchOrder, arch)
end

-- The old gantry's stages, one arch each: presoak, high pressure, triple foam
-- (its T1 / T2 foam cannons are mounted on the foam arch), a second high-pressure
-- pass, clear coat, hot wax and spot-free rinse.
defineArch("Presoak", "KWS Dyna Arch (DoublePresoak)", "Presoak")
defineArch("HighPressure", "KWS Dyna Arch (HighPressure)", function(arch, model)
	local starter, jets = emittersIn(model, "HPStart"), emittersIn(model, "HP")
	arch.start = function()
		setEmitters(starter, true)
		later(arch, 1, function()
			setEmitters(starter, false)
			setEmitters(jets, true)
		end)
	end
	arch.stop = function()
		setEmitters(starter, false)
		setEmitters(jets, false)
	end
end)
defineArch("Foam", "KWS Dyna Arch (TripleFoam)", "Foam")
defineArch("Rinse", "KWS Dyna Arch (SingleRinse)", function(arch, model)
	local burst, rinse = emittersIn(model, "Rinse2"), emittersIn(model, "Rinse")
	arch.start = function()
		setEmitters(burst, true)
		later(arch, 0.6, function()
			setEmitters(burst, false)
			setEmitters(rinse, true)
		end)
	end
	arch.stop = function()
		setEmitters(burst, false)
		setEmitters(rinse, false)
	end
end)
defineArch("ClearCoat", "KWS Dyna Arch (RainOff)", "Sealent")
defineArch("HotWax", "Lava Wax Arch", function(arch, model)
	local lava = model.Lava
	-- The LED bar is animated by New.ArchLights like the other arches' ropes.
	arch.start = function()
		later(arch, 1, function() lava.RainBar.Wax2.Enabled = true end)
		later(arch, 1.7, function() lava.RainBar.Wax.Enabled = true end)
	end
	arch.stop = function()
		lava.RainBar.Wax2.Enabled = false
		lava.RainBar.Wax.Enabled = false
	end
end)
defineArch("SpotFree", "KWS Dyna Arch (RainBar)", "Water")

-- Which arches each program runs, the same stages the gantry ran for each one.
-- Brushes, blasters and dryers run for every car.
local BASIC = { Presoak = true, HighPressure = true, Foam = true, Rinse = true, SpotFree = true }
local PROGRAMS = {
	Small = BASIC,
	Middle = table.clone(BASIC),
	Full = table.clone(BASIC),
}
PROGRAMS.Middle.ClearCoat = true
PROGRAMS.Full.ClearCoat = true
PROGRAMS.Full.HotWax = true

local car = {}
local runId = 0
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

-- The clients animate the LEDs; the server only says which show to run and since when.
local function setLights(arch, on)
	arch.model:SetAttribute("LightMode", if on then arch.key else "Idle")
	arch.model:SetAttribute("LightSince", workspace:GetServerTimeNow())
end

local function setArchSound(arch, on)
	local speaker = arch.speaker
	if not speaker then
		return
	end
	local start, loop, stop = speaker:FindFirstChild("Start"), speaker:FindFirstChild("Loop"), speaker:FindFirstChild("Stop")
	if on then
		local introSeconds = 0
		if start then
			start:Play()
			introSeconds = if start.IsLoaded then math.min(start.TimeLength - 0.1, 6) else 2
		end
		if loop then
			later(arch, math.max(introSeconds, 0), function() loop:Play() end)
		end
	else
		if start then
			start:Stop()
		end
		if loop then
			loop:Stop()
		end
		if stop then
			stop:Play()
		end
	end
end

local function setArch(arch, on, force)
	if arch.active == on and not force then
		return
	end
	arch.active = on
	arch.run += 1
	if on then
		arch.start()
	else
		arch.stop()
	end
	setLights(arch, on)
	if not force then
		setArchSound(arch, on)
	end
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
-- moment the car reaches that point, and anything still unfired fires at the
-- end, in the order the triggers were listed. cruiseSpeed() gives the speed for
-- where the car is now (default CONVEYOR_SPEED); the car eases between speeds.
local function moveCarTo(targetZ, triggers, cruiseSpeed)
	cruiseSpeed = cruiseSpeed or function()
		return CONVEYOR_SPEED
	end
	local pending = table.clone(triggers or {})
	local speed = 0
	local bestFront, lastProgress = carFront(), os.clock()

	local function checkTriggers()
		local index = 1
		while index <= #pending do
			if pending[index].ready() then
				table.remove(pending, index).run()
			else
				index += 1
			end
		end
	end

	while carFront() > targetZ and os.clock() - lastProgress < STALL_SECONDS do
		local deltaTime = RunService.Heartbeat:Wait()
		-- slow to a stop on the target, otherwise cruise at this zone's speed
		local goal = math.clamp((carFront() - targetZ) * 1.5, 0.4, cruiseSpeed())
		speed += math.clamp(goal - speed, -CONVEYOR_ACCEL * deltaTime, CONVEYOR_ACCEL * deltaTime)
		setBelts(speed)
		if carFront() < bestFront - 0.05 then
			bestFront, lastProgress = carFront(), os.clock()
		end
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
	while #pending > 0 do
		table.remove(pending, 1).run()
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

-- Where the car runs at which speed: TUNNEL_SPEED until its nose reaches the
-- first arch of the program, the program's arch speed until its tail clears the
-- last one, then CONVEYOR_SPEED on to the dryers.
local function zoneSpeed(zone)
	if carFront() > zone.archStartZ then
		return TUNNEL_SPEED
	elseif carRear() > zone.archEndZ then
		return zone.archSpeed
	end
	return CONVEYOR_SPEED
end

-- Seconds until the car's tail clears the last arch, at the zone speeds.
local function washSecondsLeft(zone)
	local rear = carRear()
	local left = rear - zone.archEndZ
	if left <= 0 then
		return 0
	end
	-- the tail is here when the nose reaches the first arch
	local beforeArches = math.clamp(rear - (zone.archStartZ + car.length), 0, left)
	return beforeArches / TUNNEL_SPEED + (left - beforeArches) / zone.archSpeed
end

-- Wash Time shows how long until the car's tail clears the last arch it uses.
local function startWashCountdown(zone)
	local myRun = runId
	task.spawn(function()
		while myRun == runId do
			local remaining = math.ceil(washSecondsLeft(zone))
			if remaining <= 0 then
				break
			end
			WashDisplay.Value = ("%03d"):format(remaining)
			task.wait(0.1)
		end
		if myRun == runId then
			WashDisplay.Value = "---"
		end
	end)
end

-- One continuous pull from the pickup point to the dryers: blasters, wrap-arounds,
-- rockers, then every arch in the program, each switching on as the car's nose
-- reaches it and off once the tail has passed.
local function runTunnel(program, archSpeed)
	local triggers = {
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
	}

	local zone = { archStartZ = -math.huge, archEndZ = math.huge, archSpeed = archSpeed }
	for _, arch in ArchOrder do
		if program[arch.key] then
			table.insert(triggers, { ready = frontReaches(arch.z + ARCH_LEAD), run = function() setArch(arch, true) end })
			table.insert(triggers, { ready = rearPasses(arch.z - ARCH_TRAIL), run = function() setArch(arch, false) end })
			-- start slowing a little before the first arch so it's already crawling when it switches on
			zone.archStartZ = math.max(zone.archStartZ, arch.z + ARCH_LEAD + 1.5)
			zone.archEndZ = math.min(zone.archEndZ, arch.z - ARCH_TRAIL)
		end
	end
	table.insert(triggers, { ready = frontReaches(DRYER_START_Z), run = startDryers })

	startWashCountdown(zone)
	setBlasters(true)
	setWraps(true)
	moveCarTo(DRY_CENTER_Z - car.length / 2, triggers, function()
		return zoneSpeed(zone)
	end)
end

local function runDryers()
	if not dryersRunning then
		startDryers()
	end
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
	runTunnel(program, ARCH_SPEED[washType])
	runDryers()
	releaseCar()
end

-- Puts every machine back to idle.
function WashController:Reset()
	runId += 1
	for _, arch in ArchOrder do
		setArch(arch, false, true)
		if arch.speaker then
			for _, sound in arch.speaker:GetChildren() do
				if sound:IsA("Sound") then
					sound:Stop()
				end
			end
		end
	end
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
