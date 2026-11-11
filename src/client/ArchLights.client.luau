-- Animates the arch LEDs (each arch's Rope, and the Lava Wax Arch's LED bar) on
-- each player's client, so the colours glide every frame
-- instead of jumping, and it costs no network traffic.
--
-- The server (Wash/Arches) sets two attributes on each arch model in CarWash.New:
--   LightMode  = "Idle" or the stage key ("Presoak", "Foam", ...)
--   LightSince = workspace:GetServerTimeNow() when the mode changed
-- Everything is a function of server time, so all arches and all players
-- show the same thing at the same moment.
--
-- The look is deliberately calm: one colour per stage that breathes slowly,
-- soft fades in and out, and a faint idle glow.

local RunService = game:GetService("RunService")

local New = workspace:WaitForChild("CarWash"):WaitForChild("New")

local CULL_DISTANCE = 250
local FADE_IN_SECONDS = 0.8
local FADE_OUT_SECONDS = 1.2
local BREATH_SECONDS = 4 -- one slow in-and-out
local IDLE_LEVEL = 0.12
local ACTIVE_LEVEL = 0.5
local BREATH_DEPTH = 0.12 -- how much the level rises and falls while breathing
local MAX_LIGHT_BRIGHTNESS = 0.9
local MIN_TRANSPARENCY = 0.3 -- the rope never goes fully solid
local TAU = math.pi * 2

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Each stage: the colour it glows and, optionally, a second colour it drifts
-- towards and back over DRIFT_SECONDS.
local DRIFT_SECONDS = 8
local STAGES = {
	Idle = { rgb(30, 70, 200) },
	Presoak = { rgb(0, 200, 170), rgb(0, 140, 220) },
	HighPressure = { rgb(150, 200, 255) },
	Foam = { rgb(0, 150, 255), rgb(230, 60, 200) },
	Rinse = { rgb(30, 100, 240) },
	ClearCoat = { rgb(140, 70, 230), rgb(60, 170, 230) },
	HotWax = { rgb(255, 90, 10), rgb(255, 150, 30) },
	SpotFree = { rgb(90, 220, 210) },
}

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function breathe(now, offset)
	return 0.5 + 0.5 * math.sin(TAU * (now / BREATH_SECONDS - offset))
end

local function stageColor(mode, now, arch)
	local colors = STAGES[mode] or STAGES.Idle
	if #colors == 1 then
		return colors[1]
	end
	local drift = 0.5 + 0.5 * math.sin(TAU * (now / DRIFT_SECONDS - arch.order * 0.1))
	return colors[1]:Lerp(colors[2], smooth(drift))
end

local function stageLevel(mode, now, arch)
	-- Idle breathes as a gentle wave rolling down the tunnel; active arches
	-- breathe together.
	if mode == "Idle" then
		return IDLE_LEVEL * (0.6 + 0.4 * breathe(now, arch.order * 0.12))
	end
	return ACTIVE_LEVEL + BREATH_DEPTH * (breathe(now, 0) - 0.5)
end

local arches = {}

local function findLed(model)
	local rope = model:FindFirstChild("Rope", true)
	if rope and rope:IsA("BasePart") then
		return rope
	end
	local led = model:FindFirstChild("LED", true)
	if led and led:IsA("BasePart") then
		return led
	end
	return nil
end

local function addArch(model)
	local led = findLed(model)
	if not led then
		return
	end
	local light = led:FindFirstChildWhichIsA("PointLight")
	if not light then
		light = Instance.new("PointLight")
		light.Parent = led
	end
	light.Shadows = false
	light.Enabled = true
	light.Range = 10
	led.Material = Enum.Material.Neon

	table.insert(arches, {
		model = model,
		led = led,
		light = light,
		position = led.Position,
		order = 0,
	})
	-- order by where the car meets them (it travels toward -Z)
	table.sort(arches, function(a, b)
		return a.position.Z > b.position.Z
	end)
	for index, arch in arches do
		arch.order = index
	end
end

for _, child in New:GetChildren() do
	if child:IsA("Model") then
		addArch(child)
	end
end
New.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		task.defer(addArch, child)
	end
end)

local function render(arch, now)
	local mode = arch.model:GetAttribute("LightMode") or "Idle"
	local since = arch.model:GetAttribute("LightSince") or 0
	local age = now - since

	if mode ~= arch.mode then
		arch.previous, arch.mode = arch.mode, mode
	end

	local color, level = stageColor(mode, now, arch), stageLevel(mode, now, arch)

	-- Soft cross-fade from whatever was showing before.
	local fadeSeconds = if mode == "Idle" then FADE_OUT_SECONDS else FADE_IN_SECONDS
	if arch.previous and age < fadeSeconds then
		local k = smooth(age / fadeSeconds)
		local fromColor, fromLevel = stageColor(arch.previous, now, arch), stageLevel(arch.previous, now, arch)
		color, level = fromColor:Lerp(color, k), fromLevel + (level - fromLevel) * k
	end

	arch.led.Color = color
	-- 0.85 (faint) at nothing, down to MIN_TRANSPARENCY at full stage level
	local glow = math.clamp(level / ACTIVE_LEVEL, 0, 1)
	arch.led.Transparency = 0.85 - (0.85 - MIN_TRANSPARENCY) * glow
	arch.light.Color = color
	arch.light.Brightness = MAX_LIGHT_BRIGHTNESS * level / (ACTIVE_LEVEL + BREATH_DEPTH / 2)
end

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	for _, arch in arches do
		if (arch.position - cameraPosition).Magnitude < CULL_DISTANCE then
			render(arch, now)
		end
	end
end)
