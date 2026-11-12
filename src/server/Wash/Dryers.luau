-- The KWS Storm Dryers (every CarWash child named "KWS Storm Dryer ..."). Each
-- has fans (FanMotor parts, spun through the joints Joints set up), Startup /
-- Dryer (hum) sounds, a Stop sound for the spin-down, and AirOutlet parts on
-- the spouts with "DryerAir" emitters.
--
-- The dryers start one after the other, each only once the car's nose is right
-- under its first outlet, and stop one after the other too. Each plays its
-- Startup sound, then its hum, and on stop the hum fades quickly under the Stop
-- sound. Levels and timings are in Config.

local TweenService = game:GetService("TweenService")

local Config = require(script.Parent.Parent.Config)
local Joints = require(script.Parent.Parent.Joints)

local CarWash = workspace:WaitForChild("CarWash")

local FAN_SPIN = 720 -- degrees per second
local CROSSFADE = 0.4 -- the hum fades in over the last bit of the startup sound
local STARTUP_CUT_FADE = 0.4 -- a cut-short startup sound fades out over this
local NO_STOP_SOUND_FADE = 2.5 -- without a Stop sound the hum winds down by itself over this

local Dryers = {}

------------------------------------------------------------------------------
-- Finding the dryers

local function isEmitter(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("BasePart") or instance:IsA("Attachment"))
end

-- A sound parented to a Model plays everywhere at full volume. Moves it onto a
-- part of the dryer so it comes from the dryer and fades with distance.
local function placeSound(sound: Sound, holder: BasePart?)
	if holder and not isEmitter(sound.Parent) then
		sound.Parent = holder
	end
	sound.RollOffMaxDistance = math.min(sound.RollOffMaxDistance, Config.DryerHearDistance)
	sound.RollOffMinDistance = math.min(sound.RollOffMinDistance, sound.RollOffMaxDistance / 4)
end

local function stopSoundFor(dryer: Instance, hum: Sound): Sound?
	local stop = dryer:FindFirstChild("Stop", true)
	if Config.DryerStopSoundId ~= "" then
		if not (stop and stop:IsA("Sound")) then
			stop = Instance.new("Sound")
			stop.Name = "Stop"
			stop.Volume = hum.Volume
			stop.RollOffMode = hum.RollOffMode
			stop.RollOffMinDistance = hum.RollOffMinDistance
			stop.RollOffMaxDistance = hum.RollOffMaxDistance
			stop.Parent = hum.Parent
		end
		stop.SoundId = Config.DryerStopSoundId
	end
	return if stop and stop:IsA("Sound") then stop else nil
end

local units = {}
local outletMinZ, outletMaxZ = math.huge, -math.huge
for _, child in CarWash:GetChildren() do
	if not child.Name:match("^KWS Storm Dryer") then
		continue
	end
	local dryer = child.Dryers
	local hum = dryer.Dryer :: Sound
	local startup = dryer:FindFirstChild("Startup") :: Sound?

	local air, fans, outlets = {}, {}, {}
	for _, item in child:GetDescendants() do
		if item:IsA("ParticleEmitter") and item.Name == "DryerAir" then
			table.insert(air, item)
		elseif item:IsA("BasePart") and item.Name == "AirOutlet" then
			table.insert(outlets, item)
		elseif item:IsA("BasePart") and item.Name == "FanMotor" then
			local joint = Joints.get(item)
			if joint then
				table.insert(fans, joint)
			end
		end
	end

	-- The car drives toward -Z, so the outlet with the highest Z is the first it meets.
	local on, off = dryer.OnSensor.Position.Z, dryer.OffSensor.Position.Z
	local firstZ = -math.huge
	for _, outlet in outlets do
		firstZ = math.max(firstZ, outlet.Position.Z)
		outletMinZ = math.min(outletMinZ, outlet.Position.Z)
		outletMaxZ = math.max(outletMaxZ, outlet.Position.Z)
	end
	if firstZ == -math.huge then
		firstZ = (on + off) / 2
	end

	local holder = outlets[1] or (dryer:IsA("Model") and dryer.PrimaryPart) or dryer:FindFirstChildWhichIsA("BasePart", true)
	hum.Looped = true
	placeSound(hum, holder)
	if startup then
		placeSound(startup, holder)
	end
	local stop = stopSoundFor(dryer, hum)
	if stop then
		placeSound(stop, holder)
	end

	table.insert(units, {
		name = child.Name,
		hum = hum,
		humVolume = hum.Volume * Config.DryerVolume,
		humSpeed = hum.PlaybackSpeed,
		startup = startup,
		startupVolume = if startup then startup.Volume * Config.DryerVolume else 0,
		stop = stop,
		stopVolume = if stop then stop.Volume * Config.DryerVolume else 0,
		air = air,
		fans = fans,
		startZ = firstZ + Config.DryerLead,
		centerZ = (on + off) / 2,
		running = false,
		queued = false,
		gen = 0, -- bumped on every start/stop so stale delayed steps do nothing
		tweens = {},
	})
end

table.sort(units, function(a, b)
	if a.startZ ~= b.startZ then
		return a.startZ > b.startZ
	end
	return a.name < b.name
end)

-- Where the car's nose has to be for each dryer to start, in the order the car
-- meets them (index i is dryer i for Dryers.startUnit).
Dryers.startZs = {}
-- The car parks centred under the dryers.
local centerSum = 0
for index, unit in units do
	Dryers.startZs[index] = unit.startZ
	centerSum += unit.centerZ
end
Dryers.CENTER_Z = centerSum / #units
-- Where along the lane the air blows (for CarCondition): the outlets, plus a
-- few studs either side for the spread of the air.
Dryers.MIN_Z = (if outletMinZ < math.huge then outletMinZ else Dryers.CENTER_Z) - 3
Dryers.MAX_Z = (if outletMaxZ > -math.huge then outletMaxZ else Dryers.CENTER_Z) + 3

------------------------------------------------------------------------------
-- One dryer

local function setFans(unit, speed: number)
	for _, joint in unit.fans do
		Joints.spin(joint, speed)
	end
end

local function setAir(unit, on: boolean)
	for _, emitter in unit.air do
		emitter.Enabled = on
	end
end

local function cancelTweens(unit)
	for _, tween in unit.tweens do
		tween:Cancel()
	end
	table.clear(unit.tweens)
end

local function tween(unit, instance: Instance, seconds: number, goal)
	local t = TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), goal)
	table.insert(unit.tweens, t)
	t:Play()
end

-- Runs `fn` after `seconds` unless the dryer has been started or stopped since.
local function after(unit, seconds: number, fn: () -> ())
	local gen = unit.gen
	task.delay(seconds, function()
		if unit.gen == gen then
			fn()
		end
	end)
end

local function startUnit(unit)
	unit.running = true
	unit.gen += 1
	cancelTweens(unit)
	setFans(unit, FAN_SPIN)
	setAir(unit, true)
	if unit.stop then
		unit.stop:Stop()
	end

	local hum, startup = unit.hum, unit.startup
	hum:Stop()
	hum.PlaybackSpeed = unit.humSpeed

	local humAt = 0
	if startup then
		local cut = Config.DryerStartupSeconds
		local length = startup.TimeLength -- 0 if it hasn't loaded yet
		local playFor = if length > 0 then math.min(length, cut) else cut
		startup.Volume = unit.startupVolume
		startup.TimePosition = 0
		startup:Play()
		humAt = math.max(0, playFor - CROSSFADE)
		if length == 0 or length > cut then
			after(unit, math.max(0, cut - STARTUP_CUT_FADE), function()
				tween(unit, startup, STARTUP_CUT_FADE, { Volume = 0 })
				after(unit, STARTUP_CUT_FADE, function()
					startup:Stop()
				end)
			end)
		end
	end

	after(unit, humAt, function()
		hum.Volume = 0
		hum:Play()
		tween(unit, hum, CROSSFADE, { Volume = unit.humVolume })
	end)
end

local function stopUnit(unit)
	unit.running = false
	unit.gen += 1
	cancelTweens(unit)
	setFans(unit, 0)
	setAir(unit, false)

	local hum, startup = unit.hum, unit.startup
	if startup and startup.IsPlaying then
		tween(unit, startup, 0.3, { Volume = 0 })
	end

	local fade = Config.DryerStopSeconds
	if unit.stop then
		unit.stop.Volume = unit.stopVolume
		unit.stop.TimePosition = 0
		unit.stop:Play()
	else
		fade = NO_STOP_SOUND_FADE
	end
	if hum.IsPlaying then
		tween(unit, hum, fade, { Volume = 0, PlaybackSpeed = unit.humSpeed * 0.6 })
	end
	after(unit, fade, function()
		hum:Stop()
		hum.PlaybackSpeed = unit.humSpeed
		if startup then
			startup:Stop()
		end
	end)
end

------------------------------------------------------------------------------
-- One after the other

-- Starts and stops go through one queue, Config.DryerStagger apart.
local nextSlot = 0
local queueGen = 0

local function enqueue(fn: () -> ())
	local now = os.clock()
	local at = math.max(now, nextSlot)
	nextSlot = at + Config.DryerStagger
	local gen = queueGen
	task.delay(at - now, function()
		if queueGen == gen then
			fn()
		end
	end)
end

-- Drops everything still waiting in the queue.
local function clearQueue()
	queueGen += 1
	nextSlot = 0
	for _, unit in units do
		unit.queued = false
	end
end

-- Starts dryer `index` (see Dryers.startZs), after the one before it if that
-- only just started.
function Dryers.startUnit(index: number)
	local unit = units[index]
	if not unit or unit.running or unit.queued then
		return
	end
	unit.queued = true
	enqueue(function()
		unit.queued = false
		startUnit(unit)
	end)
end

-- Starts every dryer that isn't running yet, one after the other.
function Dryers.startAll()
	for index in units do
		Dryers.startUnit(index)
	end
end

function Dryers.stop()
	clearQueue()
	for _, unit in units do
		if unit.running then
			enqueue(function()
				stopUnit(unit)
			end)
		end
	end
end

-- Back to idle: winds down whatever is running, otherwise just makes sure it's all off.
function Dryers.reset()
	clearQueue()
	for _, unit in units do
		if unit.running then
			stopUnit(unit)
		else
			unit.gen += 1
			cancelTweens(unit)
			setFans(unit, 0)
			setAir(unit, false)
		end
	end
end

return Dryers
