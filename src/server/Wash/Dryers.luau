-- The KWS Storm Dryers (every CarWash child named "KWS Storm Dryer ..."). Each
-- has fans (FanMotor parts with a surface motor), Startup / Dryer sounds, and
-- AirOutlet parts on the spouts with "DryerAir" emitters.

local TweenService = game:GetService("TweenService")

local CarWash = workspace:WaitForChild("CarWash")

-- On stop, the dryer hum winds down in pitch and volume, then stops.
local SPIN_DOWN = TweenInfo.new(10, Enum.EasingStyle.Linear)
local FADE_OUT = TweenInfo.new(9, Enum.EasingStyle.Linear)

local units = {}
for _, child in CarWash:GetChildren() do
	if child.Name:match("^KWS Storm Dryer") then
		local dryer = child.Dryers
		local hum = dryer.Dryer :: Sound
		local air = {}
		for _, item in dryer:GetDescendants() do
			if item:IsA("ParticleEmitter") and item.Name == "DryerAir" then
				table.insert(air, item)
			end
		end
		table.insert(units, {
			dryer = dryer,
			hum = hum,
			humVolume = hum.Volume,
			humSpeed = hum.PlaybackSpeed,
			air = air,
			windDown = 0,
			tweens = {},
		})
	end
end

local Dryers = {}

-- The dryers start when the car's nose reaches the first one's OnSensor, and
-- the car parks centred under them.
Dryers.START_Z = -math.huge
local centerSum = 0
for _, unit in units do
	local on, off = unit.dryer.OnSensor.Position.Z, unit.dryer.OffSensor.Position.Z
	Dryers.START_Z = math.max(Dryers.START_Z, on)
	centerSum += (on + off) / 2
end
Dryers.CENTER_Z = centerSum / #units

local running = false

local function setFans(unit, speed: number)
	for _, item in unit.dryer:GetDescendants() do
		if item.Name == "FanMotor" then
			item.RightParamB = speed
		end
	end
end

local function setAir(unit, on: boolean)
	for _, emitter in unit.air do
		emitter.Enabled = on
	end
end

-- Cancels a wind-down in progress and puts the hum back to its saved levels.
local function restoreHum(unit)
	unit.windDown += 1
	for _, tween in unit.tweens do
		tween:Cancel()
	end
	table.clear(unit.tweens)
	unit.hum.Volume = unit.humVolume
	unit.hum.PlaybackSpeed = unit.humSpeed
end

local function windDown(unit)
	restoreHum(unit)
	local id = unit.windDown
	for _, tween in {
		TweenService:Create(unit.hum, SPIN_DOWN, { PlaybackSpeed = 0 }),
		TweenService:Create(unit.hum, FADE_OUT, { Volume = 0 }),
	} do
		table.insert(unit.tweens, tween)
		tween:Play()
	end
	task.delay(SPIN_DOWN.Time, function()
		if unit.windDown == id then
			unit.hum:Stop()
			restoreHum(unit)
		end
	end)
end

function Dryers.isRunning(): boolean
	return running
end

function Dryers.start()
	running = true
	for _, unit in units do
		restoreHum(unit)
		unit.dryer.Startup:Play()
		setFans(unit, 1)
		setAir(unit, true)
		unit.hum:Play()
	end
end

function Dryers.stop()
	running = false
	for _, unit in units do
		setFans(unit, 0)
		setAir(unit, false)
		windDown(unit)
	end
end

-- Back to idle: winds down if running, otherwise just makes sure it's off.
function Dryers.reset()
	if running then
		Dryers.stop()
		return
	end
	for _, unit in units do
		setFans(unit, 0)
		setAir(unit, false)
	end
end

return Dryers
