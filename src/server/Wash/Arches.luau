-- The arches in CarWash.New, in the order the car meets them: presoak, high
-- pressure, triple foam, a second high-pressure pass, clear coat, hot wax and
-- spot-free rinse. (KWS Dyna Arch (Mapping) at the entrance is decoration.)
--
-- Each arch has its jets (ParticleEmitters sharing the stage's name), a Speaker
-- part with Start / Loop / Stop sounds, and an LED that the clients animate
-- (client/ArchLights) from the LightMode / LightSince attributes set here.

local Config = require(script.Parent.Parent.Config)

local New = workspace:WaitForChild("CarWash"):WaitForChild("New")

export type Arch = {
	key: string,
	model: Model,
	z: number,
	speaker: BasePart?,
	run: number,
	active: boolean,
	start: () -> (),
	stop: () -> (),
}

local Arches = {}

Arches.ordered = {} :: { Arch }
Arches.byKey = {} :: { [string]: Arch }

-- What the Wash Time screen calls each stage.
Arches.StageNames = Config.StageNames

local function emittersIn(root: Instance, name: string): { ParticleEmitter }
	local list = {}
	for _, item in root:GetDescendants() do
		if item:IsA("ParticleEmitter") and item.Name == name then
			table.insert(list, item)
		end
	end
	return list
end

local function setEmitters(list: { ParticleEmitter }, on: boolean)
	for _, emitter in list do
		emitter.Enabled = on
	end
end

-- Runs callback after `seconds` unless the arch was switched since.
local function later(arch: Arch, seconds: number, callback: () -> ())
	local run = arch.run
	task.delay(seconds, function()
		if arch.run == run then
			callback()
		end
	end)
end

-- setup is either the jets' emitter name, or a function that sets
-- arch.start / arch.stop for arches with a more elaborate sequence.
local function define(key: string, modelName: string, setup: string | (Arch, Model) -> ())
	local model = New[modelName]
	local arch = {
		key = key,
		model = model,
		z = model.Frame:GetBoundingBox().Position.Z,
		speaker = model:FindFirstChild("Speaker"),
		run = 0,
		active = false,
	} :: Arch

	if type(setup) == "string" then
		local jets = emittersIn(model, setup)
		arch.start = function()
			setEmitters(jets, true)
		end
		arch.stop = function()
			setEmitters(jets, false)
		end
	else
		setup(arch, model)
	end

	table.insert(Arches.ordered, arch)
	Arches.byKey[key] = arch
end

-- An opening blast (`burstName`) for `burstSeconds`, then the steady jets.
local function burstThenSpray(burstName: string, burstSeconds: number, jetName: string)
	return function(arch: Arch, model: Model)
		local burst, jets = emittersIn(model, burstName), emittersIn(model, jetName)
		arch.start = function()
			setEmitters(burst, true)
			later(arch, burstSeconds, function()
				setEmitters(burst, false)
				setEmitters(jets, true)
			end)
		end
		arch.stop = function()
			setEmitters(burst, false)
			setEmitters(jets, false)
		end
	end
end

define("Presoak", "KWS Dyna Arch (DoublePresoak)", "Presoak")
define("HighPressure", "KWS Dyna Arch (HighPressure)", burstThenSpray("HPStart", 1, "HP"))
define("Foam", "KWS Dyna Arch (TripleFoam)", "Foam")
define("Rinse", "KWS Dyna Arch (SingleRinse)", burstThenSpray("Rinse2", 0.6, "Rinse"))
define("ClearCoat", "KWS Dyna Arch (RainOff)", "Sealent")
define("HotWax", "Lava Wax Arch", function(arch, model)
	local rainBar = model.Lava.RainBar
	arch.start = function()
		later(arch, 1, function()
			rainBar.Wax2.Enabled = true
		end)
		later(arch, 1.7, function()
			rainBar.Wax.Enabled = true
		end)
	end
	arch.stop = function()
		rainBar.Wax2.Enabled = false
		rainBar.Wax.Enabled = false
	end
end)
define("SpotFree", "KWS Dyna Arch (RainBar)", "Water")

local function setLights(arch: Arch, on: boolean)
	arch.model:SetAttribute("LightMode", if on then arch.key else "Idle")
	arch.model:SetAttribute("LightSince", workspace:GetServerTimeNow())
end

-- Start plays once, Loop takes over when it ends; Stop plays on the way out.
local function setSound(arch: Arch, on: boolean)
	local speaker = arch.speaker
	if not speaker then
		return
	end
	local start = speaker:FindFirstChild("Start") :: Sound?
	local loop = speaker:FindFirstChild("Loop") :: Sound?
	local stop = speaker:FindFirstChild("Stop") :: Sound?

	if on then
		local introSeconds = 0
		if start then
			start:Play()
			introSeconds = if start.IsLoaded then math.min(start.TimeLength - 0.1, 6) else 2
		end
		if loop then
			later(arch, math.max(introSeconds, 0), function()
				loop:Play()
			end)
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

-- Switches an arch's jets, lights and sound. `silent` skips the sound, for
-- resetting everything to idle.
function Arches.set(arch: Arch, on: boolean, silent: boolean?)
	if arch.active == on and not silent then
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
	if not silent then
		setSound(arch, on)
	end
end

-- Every arch off and quiet, at once.
function Arches.resetAll()
	for _, arch in Arches.ordered do
		Arches.set(arch, false, true)
		if arch.speaker then
			for _, sound in arch.speaker:GetChildren() do
				if sound:IsA("Sound") then
					sound:Stop()
				end
			end
		end
	end
end

return Arches
