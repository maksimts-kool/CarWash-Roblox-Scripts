-- How dirty, soapy, wet and shiny every car is, section by section.
--
-- Every model with a VehicleSeat is tagged "WashableCar". Its length is cut
-- into Config.Condition.Segments sections, numbered from the nose (1) to the
-- tail, and each section has its own Dirt / Soap / Wet / Shine (0..1). A
-- machine in the wash only works on the sections under it, so the nose gets
-- foamed, rinsed and dried before the tail does.
--
-- Attributes on the car (read by client/CarCondition and client/CarConditionHud):
--   Segments                  how many sections
--   Dirt1..N, Soap1..N, ...   each section
--   Dirt, Soap, Wet, Shine    the whole car (average of the sections)
--   Condition                 a name for the whole car: "Very Dirty", "Dirty",
--                             "Dusty", "Soapy", "Wet", "Wet & Dirty", "Drying",
--                             "Clean", "Shiny", "Showroom Shine"
--
-- Out on the road dirt builds up with distance (faster when wet) and water
-- and soap go by themselves. In the wash, Wash calls setEffect as each machine
-- starts and stops, with the stretch of lane (world Z) it works on; the rates
-- are Config.ConditionEffects. Set a Dirt attribute on a car in Studio to
-- choose how dirty it starts.

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)
local Car = require(script.Parent.Wash.Car)

local TAG = "WashableCar"
local TICK = 0.2
local KEYS = { "Dirt", "Soap", "Wet", "Shine" }

local Settings = Config.Condition
local Effects = Config.ConditionEffects
local SEGMENTS = Settings.Segments or 6

local CarCondition = {}
CarCondition.TAG = TAG

type Values = { Dirt: number, Soap: number, Wet: number, Shine: number }
type State = {
	model: Model,
	seat: VehicleSeat,
	frontZ: number, -- seat-space Z of the nose (the seat faces -Z)
	length: number,
	segments: { Values },
}
type Zone = { minZ: number, maxZ: number }

local cars: { [Model]: State } = {}
-- machines working on the car in the wash: the stretch of lane each covers,
-- or `true` for the whole car
local active: { [string]: Zone | boolean } = {}

local function round(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

local function average(s: State): Values
	local total = { Dirt = 0, Soap = 0, Wet = 0, Shine = 0 }
	for _, segment in s.segments do
		for _, key in KEYS do
			total[key] += segment[key]
		end
	end
	for _, key in KEYS do
		total[key] /= #s.segments
	end
	return total :: any
end

local function conditionName(v: Values): string
	if v.Soap >= 0.3 then
		return "Soapy"
	elseif v.Wet >= 0.4 then
		return if v.Dirt >= 0.3 then "Wet & Dirty" else "Wet"
	elseif v.Wet >= 0.08 then
		-- still dirty: it's getting wet in the wash, not drying off after it
		return if v.Dirt >= 0.3 then "Wet & Dirty" else "Drying"
	elseif v.Dirt >= 0.65 then
		return "Very Dirty"
	elseif v.Dirt >= 0.3 then
		return "Dirty"
	elseif v.Dirt >= 0.12 then
		return "Dusty"
	elseif v.Shine >= 0.85 then
		return "Showroom Shine"
	elseif v.Shine >= 0.45 then
		return "Shiny"
	end
	return "Clean"
end

local function setAttribute(model: Model, name: string, value: any)
	if model:GetAttribute(name) ~= value then
		model:SetAttribute(name, value)
	end
end

-- Only changed values are written, rounded, so idle cars cost no traffic.
local function publish(s: State)
	local model = s.model
	setAttribute(model, "Segments", #s.segments)
	for index, segment in s.segments do
		for _, key in KEYS do
			setAttribute(model, key .. index, round(segment[key]))
		end
	end
	local whole = average(s)
	for _, key in KEYS do
		setAttribute(model, key, round(whole[key]))
	end
	setAttribute(model, "Condition", conditionName(whole))
end

-- The car's nose and length along the seat's Z, from its visible parts.
local function measure(model: Model, seat: BasePart): (number, number)
	local low, high = math.huge, -math.huge
	local seatCF = seat.CFrame
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 0.95 then
			local cf = seatCF:ToObjectSpace(part.CFrame)
			local half = part.Size / 2
			local extent = math.abs(cf.XVector.Z) * half.X + math.abs(cf.YVector.Z) * half.Y + math.abs(cf.ZVector.Z) * half.Z
			low = math.min(low, cf.Z - extent)
			high = math.max(high, cf.Z + extent)
		end
	end
	if low == math.huge then
		return -Config.DefaultCarLength / 2, Config.DefaultCarLength
	end
	return low, high - low
end

local function register(seat: VehicleSeat)
	if not seat:IsDescendantOf(workspace) then
		return
	end
	local model = seat:FindFirstAncestorWhichIsA("Model")
	if not model or cars[model] then
		return
	end

	local low, high = Settings.StartDirt[1], Settings.StartDirt[2]
	local startDirt = low + math.random() * (high - low)
	local function initial(key: string, index: number, default: number): number
		-- a copy of a car keeps the original's sections; a Studio attribute sets the whole car
		local value = model:GetAttribute(key .. index)
		if type(value) ~= "number" then
			value = model:GetAttribute(key)
		end
		return if type(value) == "number" then math.clamp(value, 0, 1) else default
	end
	local segments = {}
	for index = 1, SEGMENTS do
		segments[index] = {
			Dirt = initial("Dirt", index, startDirt),
			Soap = initial("Soap", index, 0),
			Wet = initial("Wet", index, 0),
			Shine = initial("Shine", index, 0),
		}
	end

	local frontZ, length = measure(model, seat)
	local s: State = { model = model, seat = seat, frontZ = frontZ, length = length, segments = segments }
	cars[model] = s
	CollectionService:AddTag(model, TAG)
	publish(s)
end

-- The state of the car `model` is (or belongs to), registering it if needed.
local function stateFor(model: Model?): State?
	if not model then
		return nil
	end
	if cars[model] then
		return cars[model]
	end
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	if not seat then
		return nil
	end
	register(seat)
	local owner = seat:FindFirstAncestorWhichIsA("Model")
	return if owner then cars[owner] else nil
end

-- Is section `index` of the car anywhere inside `zone` (world Z)?
local function inZone(s: State, index: number, zone: Zone): boolean
	local step = s.length / #s.segments
	local seatCF = s.seat.CFrame
	local a = seatCF:PointToWorldSpace(Vector3.new(0, 0, s.frontZ + (index - 1) * step)).Z
	local b = seatCF:PointToWorldSpace(Vector3.new(0, 0, s.frontZ + index * step)).Z
	return math.max(a, b) >= zone.minZ and math.min(a, b) <= zone.maxZ
end

local function applyEffects(s: State, dt: number)
	for name, zone in active do
		local effect = Effects[name]
		if not effect then
			continue
		end
		for index, segment in s.segments do
			if zone == true or inZone(s, index, zone :: Zone) then
				segment.Dirt += (effect.dirt or 0) * dt
				segment.Soap += (effect.soap or 0) * dt
				segment.Wet += (effect.wet or 0) * dt
				segment.Shine += (effect.shine or 0) * dt
			end
		end
	end
end

-- Out on the road: dirt builds up with distance, water and soap go by themselves.
local function weather(s: State, dt: number, inWash: boolean)
	local speed = s.seat.AssemblyLinearVelocity.Magnitude
	for _, segment in s.segments do
		if not inWash and speed > 1 then
			local gained = speed * dt * Settings.DirtPerStud
			if segment.Wet > 0.3 then
				gained *= Settings.WetDirtMultiplier
			end
			segment.Dirt += gained
			segment.Shine -= gained * Settings.ShineLossPerDirt
		end
		segment.Soap -= Settings.SoapRunoffPerSecond * segment.Wet * dt
		segment.Wet -= Settings.AirDryPerSecond * (1 + speed / 40) * dt
	end
end

local function step(dt: number)
	local washing = stateFor(Car.model())
	local machinesOn = next(active) ~= nil
	for model, s in cars do
		if not model:IsDescendantOf(workspace) or not s.seat:IsDescendantOf(model) then
			cars[model] = nil
			continue
		end
		if s == washing and machinesOn then
			applyEffects(s, dt)
		else
			weather(s, dt, s == washing)
		end
		for _, segment in s.segments do
			for _, key in KEYS do
				segment[key] = math.clamp(segment[key], 0, 1)
			end
		end
		publish(s)
	end
end

-- A machine (a key of Config.ConditionEffects) starts or stops working on the
-- car in the wash. It works on the stretch of lane from zA to zB (world Z,
-- either order), or on the whole car without them.
function CarCondition.setEffect(name: string, on: boolean, zA: number?, zB: number?)
	if not on then
		active[name] = nil
	elseif zA and zB then
		active[name] = { minZ = math.min(zA, zB), maxZ = math.max(zA, zB) }
	else
		active[name] = true
	end
end

function CarCondition.clearEffects()
	table.clear(active)
end

-- { Dirt, Soap, Wet, Shine } of the whole car, or nil if it isn't one.
function CarCondition.get(model: Model): Values?
	local s = stateFor(model)
	return if s then average(s) else nil
end

-- Sets one value ("Dirt", "Soap", "Wet" or "Shine") on the whole car, e.g.
-- from a mud pit.
function CarCondition.set(model: Model, key: string, value: number)
	local s = stateFor(model)
	if s and table.find(KEYS, key) then
		for _, segment in s.segments do
			segment[key] = math.clamp(value, 0, 1)
		end
		publish(s)
	end
end

function CarCondition.start()
	for _, item in workspace:GetDescendants() do
		if item:IsA("VehicleSeat") then
			register(item)
		end
	end
	workspace.DescendantAdded:Connect(function(item)
		if item:IsA("VehicleSeat") then
			-- wait for the rest of the car to arrive with it
			task.defer(register, item)
		end
	end)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TICK)
			local now = os.clock()
			step(now - last)
			last = now
		end
	end)
end

return CarCondition
