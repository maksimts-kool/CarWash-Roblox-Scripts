-- Drives the tunnel's ceiling lights (CarWash.Lights) and the wall hexagons
-- (CarWash.Heaxgonsystem) on each player's client, so they follow the wash:
--
--   Idle      ceiling lights off, hexagons roll a slow blue / purple wave
--   Ready     paid: ceiling rows flicker on one by one from the entrance and the
--             hexagons chase "come in" toward the conveyor
--   Washing   a glow on the hexagons follows the car, lit in the colour of the
--             arch it is under (read straight off that arch's LED); the ceiling
--             rows over the car brighten and pick up the same tint
--   Drying    air streaks race down the hexagons, warm light over the car
--   Exit      green chevrons run to the exit, ceiling rows switch off behind the car
--   Finished  the rest of the ceiling shuts off row by row, the hexagons go dark
--             one by one and then fade back into the idle wave
--   Stopped   emergency stop: full white work light, hexagons pulse red
--
-- The server (Wash) publishes on workspace.CarWash:
--   WashPhase       one of the phases above
--   WashPhaseSince  workspace:GetServerTimeNow() when the phase began
--   CarFront        Z of the car's nose (the car travels toward the exit)
--   CarLength       studs
-- Everything else is a function of server time, so all players see the same show.
--
-- The operator can override each group from the ControlPanel, with CarWash
-- attributes LightsCeiling / LightsHexagons = "Auto" (the show above), "On"
-- (steady full light) or "Off". The emergency stop (Stopped) beats both.
-- Runs on the client, so it costs no network traffic.

local RunService = game:GetService("RunService")

local CarWash = workspace:WaitForChild("CarWash")
local New = CarWash:WaitForChild("New")
local LightsFolder = CarWash:WaitForChild("Lights")
local HexFolder = CarWash:WaitForChild("Heaxgonsystem")

local CULL_DISTANCE = 300
local STANDBY_CEILING = 0 -- ceiling level while no wash is running (0 = off)
local READY_ROW_DELAY = 0.22 -- seconds between rows flickering on
local FINISH_ROW_DELAY = 0.2 -- seconds between rows switching off
local FINISH_HEX_DELAY = 0.05 -- seconds between hexagons going dark
local FINISH_REST = 1.5 -- seconds of darkness before the idle wave returns
local FADE_RATE = 6 -- how quickly lights ease toward their target (per second)
local CAR_SMOOTHING = 6
local TAU = math.pi * 2

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local CEILING_OFF = rgb(60, 60, 64)
local CEILING_WHITE = rgb(235, 240, 255)
local CEILING_WARM = rgb(255, 222, 175)
local HEX_OFF = rgb(14, 14, 20)
local HEX_IDLE = { rgb(69, 126, 170), rgb(150, 0, 152) }
local HEX_INVITE = rgb(0, 200, 255)
local HEX_TUNNEL = rgb(120, 190, 255) -- the car is between arches (blasters, brushes)
local HEX_AIR = rgb(215, 240, 255)
local HEX_EXIT = rgb(40, 230, 90)
local HEX_ALARM = rgb(255, 30, 30)
local HEX_STEADY = rgb(110, 63, 161) -- "On": halfway between the idle wave's colours
local WHITE = rgb(255, 255, 255)

-- Distance into the tunnel along the car's path, so "ahead" is always +s.
local ENTRY_Z = CarWash:WaitForChild("GateEN"):GetPivot().Position.Z
local EXIT_Z = CarWash:WaitForChild("GateEX"):GetPivot().Position.Z
local DIRECTION = if EXIT_Z < ENTRY_Z then -1 else 1
local function depth(z)
	return (z - ENTRY_Z) * DIRECTION
end

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- 1 at distance 0, easing to 0 at `width`.
local function bump(distance, width)
	return smooth(1 - math.abs(distance) / width)
end

-- A fluorescent tube striking: a few stutters, then steady.
local FLICKER = { { 0.06, 1 }, { 0.14, 0 }, { 0.2, 0.8 }, { 0.34, 0 }, { 0.42, 0.45 }, { 0.5, 0 } }
local function flicker(age, seed)
	local scaled = age / seed
	for _, step in FLICKER do
		if scaled < step[1] then
			return step[2]
		end
	end
	return 1
end

local function ease(current, target, rate, deltaTime)
	return current + (target - current) * (1 - math.exp(-rate * deltaTime))
end

------------------------------------------------------------------------------
-- Gather the lights.

local ceilingRows = {}
do
	local byDepth = {}
	for _, model in LightsFolder:GetChildren() do
		local neon = model:FindFirstChild("NeonLight")
		if neon and neon:IsA("BasePart") then
			local s = depth(neon.Position.Z)
			local key = math.floor(s + 0.5)
			local row = byDepth[key]
			if not row then
				row = { s = s, lights = {}, level = STANDBY_CEILING, color = CEILING_WHITE }
				byDepth[key] = row
				table.insert(ceilingRows, row)
			end
			table.insert(row.lights, {
				neon = neon,
				surface = neon:FindFirstChildWhichIsA("SurfaceLight"),
			})
		end
	end
	table.sort(ceilingRows, function(a, b)
		return a.s < b.s
	end)
	for index, row in ceilingRows do
		row.index = index
		row.seed = 0.8 + ((index * 7) % 5) / 10 -- each row stutters a little differently
	end
end

local hexes = {}
do
	for _, part in HexFolder:GetDescendants() do
		if part:IsA("BasePart") and part.Name == "Color" then
			if part:IsA("UnionOperation") then
				part.UsePartColor = true
			end
			part.Material = Enum.Material.Neon
			table.insert(hexes, { part = part, s = depth(part.Position.Z), y = part.Position.Y, level = 0, color = HEX_IDLE[1] })
		end
	end
	table.sort(hexes, function(a, b)
		return a.s < b.s
	end)
	local minY, maxY = math.huge, -math.huge
	for index, hex in hexes do
		hex.index = index
		minY, maxY = math.min(minY, hex.y), math.max(maxY, hex.y)
	end
	for _, hex in hexes do
		hex.high = if maxY > minY then (hex.y - minY) / (maxY - minY) else 0 -- 0 bottom row, 1 top row
	end
end

local tunnelCenter = Vector3.zero
do
	local sum, count = Vector3.zero, 0
	for _, hex in hexes do
		sum += hex.part.Position
		count += 1
	end
	for _, row in ceilingRows do
		sum += row.lights[1].neon.Position
		count += 1
	end
	if count > 0 then
		tunnelCenter = sum / count
	end
end

-- Each arch's LED, which ArchLights colours for its stage.
local arches = {}
local function addArch(model)
	if not model:IsA("Model") then
		return
	end
	local led = model:FindFirstChild("Rope", true) or model:FindFirstChild("LED", true)
	if led and led:IsA("BasePart") then
		table.insert(arches, { model = model, led = led, s = depth(led.Position.Z) })
	end
end
for _, child in New:GetChildren() do
	addArch(child)
end
New.ChildAdded:Connect(function(child)
	task.defer(addArch, child)
end)

-- The colour of the running arch closest to the car, or the tunnel blue.
local function stageColorNear(s)
	local best, bestDistance = nil, 14
	for _, arch in arches do
		local mode = arch.model:GetAttribute("LightMode")
		if mode and mode ~= "Idle" then
			local distance = math.abs(arch.s - s)
			if distance < bestDistance then
				best, bestDistance = arch, distance
			end
		end
	end
	return if best then best.led.Color else HEX_TUNNEL
end

------------------------------------------------------------------------------
-- What each light should show. Targets return level (0..1), colour and
-- whether to jump there at once (flicker, switching off) instead of easing.
-- A nil level means "hold whatever you're showing".

local function idleHex(hex, now)
	local wave = 0.5 + 0.5 * math.sin(TAU * (now * 0.12 - hex.s / 40 - hex.high * 0.08))
	local level = 0.6 + 0.2 * math.sin(TAU * (now / 5 - hex.s / 30))
	return level, HEX_IDLE[1]:Lerp(HEX_IDLE[2], wave)
end

local function ceilingTarget(row, phase, age, car, stageColor)
	if phase == "Stopped" then
		return 1, CEILING_WHITE, true
	elseif phase == "Ready" then
		local start = (row.index - 1) * READY_ROW_DELAY
		if age < start then
			return STANDBY_CEILING, CEILING_WHITE, true
		end
		local level = 0.75 * flicker(age - start, row.seed)
		if car then
			level += 0.25 * bump(row.s - car.center, car.length / 2 + 8)
		end
		return level, CEILING_WHITE, age - start < 0.6
	elseif phase == "Washing" and car then
		local over = bump(row.s - car.center, car.length / 2 + 9)
		return 0.5 + 0.5 * over, CEILING_WHITE:Lerp(stageColor, 0.35 * over), false
	elseif phase == "Drying" and car then
		local over = bump(row.s - car.center, car.length / 2 + 10)
		return 0.3 + 0.7 * over, CEILING_WHITE:Lerp(CEILING_WARM, over), false
	elseif phase == "Exit" then
		if car and row.s < car.rear - 4 then
			return 0, CEILING_WHITE, true -- the car has left this row behind
		end
		return 0.85, CEILING_WHITE, false
	elseif phase == "Finished" then
		if age < (row.index - 1) * FINISH_ROW_DELAY then
			return nil
		end
		return STANDBY_CEILING, CEILING_WHITE, true
	elseif phase == "Washing" or phase == "Drying" then
		return 0.6, CEILING_WHITE, false
	end
	return STANDBY_CEILING, CEILING_WHITE, false
end

local function hexTarget(hex, phase, age, now, car, stageColor)
	if phase == "Stopped" then
		return 0.25 + 0.75 * (0.5 + 0.5 * math.cos(TAU * age)), HEX_ALARM
	elseif phase == "Ready" then
		-- pulses running in from the entrance
		local behindHead = (age * 25 - hex.s - hex.high * 1.5) % 30
		local pulse = math.exp(-behindHead / 5)
		local level, color = 0.2 + 0.8 * pulse, HEX_INVITE:Lerp(WHITE, 0.3 * pulse)
		if car then
			local glow = bump(hex.s - car.center, car.length / 2 + 5)
			if glow > pulse then
				level, color = math.max(level, glow), HEX_INVITE:Lerp(WHITE, 0.4)
			end
		end
		return level, color
	elseif phase == "Washing" and car then
		local glow = bump(hex.s - car.center, car.length / 2 + 5)
		-- a fading wake where the car has been
		local wake = if hex.s < car.rear then 0.5 * math.exp(-(car.rear - hex.s) / 10) else 0
		-- a little scout pulse running ahead of the nose
		local ahead = hex.s - car.front
		local head = (age * 12) % 30
		local scout = if ahead > 0 then 0.7 * math.exp(-math.abs(ahead - head) / 2.5) * (1 - head / 30) else 0
		local lit = math.max(glow, wake, scout)
		local baseLevel, baseColor = idleHex(hex, now)
		return math.max(0.12 * baseLevel, lit), baseColor:Lerp(stageColor, smooth(lit * 2))
	elseif phase == "Drying" then
		local behindHead = (age * 40 - hex.s + hex.high * 1.5) % 25
		local streak = math.exp(-behindHead / 3)
		local level = 0.15 + 0.65 * streak
		if car then
			level = math.max(level, bump(hex.s - car.center, car.length / 2 + 4))
		end
		return level, HEX_AIR
	elseif phase == "Exit" then
		local behindHead = (age * 20 - hex.s - math.abs(hex.high - 0.5) * 3) % 16
		local chevron = math.exp(-behindHead / 3)
		local level = 0.1 + 0.8 * chevron
		if car then
			level = math.max(level, bump(hex.s - car.center, car.length / 2 + 4))
		end
		return level, HEX_EXIT:Lerp(WHITE, 0.2 * chevron)
	elseif phase == "Finished" then
		local darkAt = (hex.index - 1) * FINISH_HEX_DELAY
		if age < darkAt then
			return nil
		end
		local back = darkAt + (#hexes - hex.index) * FINISH_HEX_DELAY + FINISH_REST
		if age < back then
			return 0, hex.color
		end
		return idleHex(hex, now)
	elseif phase == "Washing" then
		return 0.3, HEX_TUNNEL
	end
	return idleHex(hex, now)
end

------------------------------------------------------------------------------
-- Apply.

local function showCeiling(row)
	local on = row.level > 0.03
	for _, light in row.lights do
		local neon = light.neon
		local material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		if neon.Material ~= material then
			neon.Material = material
		end
		neon.Color = if on then CEILING_OFF:Lerp(row.color, row.level) else CEILING_OFF
		local surface = light.surface
		if surface then
			surface.Enabled = on
			surface.Color = row.color
			surface.Brightness = 1.2 * row.level
		end
	end
end

local function showHex(hex)
	hex.part.Color = HEX_OFF:Lerp(hex.color, math.clamp(hex.level, 0, 1))
end

local car = nil -- { front, center, rear, length } in depth units, smoothed

local function updateCar(deltaTime)
	local frontZ = CarWash:GetAttribute("CarFront")
	if typeof(frontZ) ~= "number" then
		car = nil
		return
	end
	local length = CarWash:GetAttribute("CarLength") or 14
	local front = depth(frontZ)
	if not car or math.abs(front - car.front) > 20 then
		car = { front = front, length = length }
	else
		car.front = ease(car.front, front, CAR_SMOOTHING, deltaTime)
		car.length = length
	end
	car.rear = car.front - car.length
	car.center = car.front - car.length / 2
end

RunService.RenderStepped:Connect(function(deltaTime)
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - tunnelCenter).Magnitude > CULL_DISTANCE then
		return
	end

	local now = workspace:GetServerTimeNow()
	local phase = CarWash:GetAttribute("WashPhase") or "Idle"
	local age = now - (CarWash:GetAttribute("WashPhaseSince") or 0)
	updateCar(deltaTime)
	local stageColor = if car then stageColorNear(car.center) else HEX_TUNNEL

	local ceilingMode = if phase == "Stopped" then "Auto" else CarWash:GetAttribute("LightsCeiling") or "Auto"
	local hexMode = if phase == "Stopped" then "Auto" else CarWash:GetAttribute("LightsHexagons") or "Auto"

	for _, row in ceilingRows do
		local level, color, snap
		if ceilingMode == "On" then
			level, color, snap = 1, CEILING_WHITE, false
		elseif ceilingMode == "Off" then
			level, color, snap = 0, CEILING_WHITE, false
		else
			level, color, snap = ceilingTarget(row, phase, age, car, stageColor)
		end
		if level then
			if snap then
				row.level, row.color = level, color
			else
				row.level = ease(row.level, level, FADE_RATE, deltaTime)
				row.color = row.color:Lerp(color, 1 - math.exp(-FADE_RATE * deltaTime))
			end
		end
		showCeiling(row)
	end

	for _, hex in hexes do
		local level, color
		if hexMode == "On" then
			level, color = 1, HEX_STEADY
		elseif hexMode == "Off" then
			level, color = 0, hex.color
		else
			level, color = hexTarget(hex, phase, age, now, car, stageColor)
		end
		if level then
			hex.level = ease(hex.level, level, FADE_RATE, deltaTime)
			hex.color = hex.color:Lerp(color, 1 - math.exp(-FADE_RATE * deltaTime))
		end
		showHex(hex)
	end
end)
