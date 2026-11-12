-- Shows how dirty, soapy, wet and shiny each car is, section by section. The
-- server (CarCondition) cuts every "WashableCar" into `Segments` sections
-- from nose to tail and publishes Dirt1..N / Soap1..N / Wet1..N / Shine1..N
-- (0..1). Each painted part and each foam spot belongs to the section it sits
-- in, so as the car passes under a machine you see that part of it change:
--
--   Dirt   the paint muddies toward brown and loses its gloss; dust kicks up
--          behind the car when it drives
--   Soap   the paint whitens and foam clumps sit on the body
--   Wet    the paint darkens a touch and turns glossy, water drips off the sides
--   Shine  extra gloss and the odd glint on the paint once that section is
--          clean and dry, with a burst of glints when the car comes out clean
--
-- Foam, drips and glints come from "spots" stuck to the body: rays are cast
-- down onto the car and in from its sides, and each hit gets an attachment,
-- so nothing floats in the air around the car.
--
-- All local and cosmetic: the server only sends the numbers.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "WashableCar"
local KEYS = { "Dirt", "Soap", "Wet", "Shine" }
local KINDS = { "foam", "drip", "glint" }
local CULL_DISTANCE = 250
local EASE_RATE = 2.5 -- how quickly the looks catch up with the server's numbers
local REPAINT_STEP = 0.005 -- repaint a section once a value has moved this much
local TOP_SPOTS = 36 -- foam / glint spots on the roof, bonnet and boot
local SIDE_SPOTS = 28 -- foam / drip spots down the doors and sills
-- Particles per second over the whole car at full soap / water / shine,
-- each from a random spot in a section that has some.
local FOAM_PER_SECOND = 40
local DRIPS_PER_SECOND = 45
local GLINTS_PER_SECOND = 4
local CLEAN = { Clean = true, Shiny = true, ["Showroom Shine"] = true }

local MUD = Color3.fromRGB(96, 78, 56)
local FOAM = Color3.fromRGB(246, 246, 252)

-- Not paint: windows, lights, screens, seats and the like keep their look.
local SKIP_MATERIALS = {
	[Enum.Material.Glass] = true,
	[Enum.Material.Neon] = true,
	[Enum.Material.ForceField] = true,
}
local SKIP_WORDS = {
	"light", "lamp", "glass", "window", "windshield", "windscreen", "mirror", "screen",
	"gui", "seat", "interior", "plate", "indicator", "reflector", "signal", "dash",
}

local TEX_FOAM = "rbxasset://textures/particles/smoke_main.dds" -- built in, soft and puffy
local TEX_PUFF = "rbxassetid://10034873151"
local TEX_DROPS = "rbxassetid://16171528032" -- the wheel blasters' drops
local TEX_SPARKLE = "rbxassetid://8611887703" -- the clear coat arch's star

local function seq(points: { { number } }): NumberSequence
	local keys = {}
	for _, point in points do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keys)
end

-- Foam clumps: white, still, stuck to the paint.
local FOAM_FX = {
	Texture = TEX_FOAM,
	Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
	LightInfluence = 0.6,
	LightEmission = 0.05,
	Size = seq({ { 0, 0.3 }, { 0.3, 0.7 }, { 1, 0.8 } }),
	Transparency = seq({ { 0, 1 }, { 0.12, 0.1 }, { 0.85, 0.2 }, { 1, 1 } }),
	Lifetime = NumberRange.new(3, 5),
	Speed = NumberRange.new(0, 0),
	Rotation = NumberRange.new(0, 360),
	RotSpeed = NumberRange.new(-5, 5),
	LockedToPart = true,
	ZOffset = 0.15,
}
-- Water running off the sides.
local DRIP_FX = {
	Texture = TEX_DROPS,
	Color = ColorSequence.new(Color3.fromRGB(210, 235, 255)),
	LightEmission = 0.3,
	Size = seq({ { 0, 0.1 }, { 1, 0.06 } }),
	Transparency = seq({ { 0, 0.15 }, { 1, 0.5 } }),
	Lifetime = NumberRange.new(0.4, 0.8),
	Speed = NumberRange.new(0.2, 0.5),
	SpreadAngle = Vector2.new(10, 10),
	EmissionDirection = Enum.NormalId.Bottom,
	Acceleration = Vector3.new(0, -35, 0),
}
-- Glints on clean, shiny paint.
local GLINT_FX = {
	Texture = TEX_SPARKLE,
	Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 240, 190)),
	LightEmission = 1,
	Size = seq({ { 0, 0 }, { 0.5, 0.4 }, { 1, 0 } }),
	Lifetime = NumberRange.new(0.4, 0.8),
	Speed = NumberRange.new(0, 0),
	Rotation = NumberRange.new(0, 360),
	LockedToPart = true,
	ZOffset = 0.2,
}
-- Dust thrown up behind a dirty car.
local DUST_FX = {
	Texture = TEX_PUFF,
	Color = ColorSequence.new(Color3.fromRGB(150, 125, 95)),
	Size = seq({ { 0, 1 }, { 1, 3.5 } }),
	Transparency = seq({ { 0, 0.6 }, { 1, 1 } }),
	Lifetime = NumberRange.new(1, 2),
	Speed = NumberRange.new(2, 4),
	SpreadAngle = Vector2.new(35, 20),
	EmissionDirection = Enum.NormalId.Back,
	Rotation = NumberRange.new(0, 360),
	Drag = 1,
}

local fxFolder = Instance.new("Folder")
fxFolder.Name = "CarConditionFx"
fxFolder.Parent = workspace

local function emitter(parent: Instance, props): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Rate = 0
	e.Parent = parent
	return e
end

local function isPaint(part: BasePart, model: Model): boolean
	if part.Transparency >= 0.5 or SKIP_MATERIALS[part.Material] or part:IsA("Seat") or part:IsA("VehicleSeat") then
		return false
	end
	if part:FindFirstChildWhichIsA("SurfaceAppearance") then
		return false
	end
	local node: Instance? = part
	while node and node ~= model do
		local name = node.Name:lower()
		for _, word in SKIP_WORDS do
			if name:find(word, 1, true) then
				return false
			end
		end
		node = node.Parent
	end
	return true
end

------------------------------------------------------------------------------
-- One car

type Paint = { color: Color3, reflectance: number, appliedColor: Color3?, appliedReflectance: number? }

local cars = {}

local function segmentCount(model: Instance): number
	local count = model:GetAttribute("Segments")
	return if type(count) == "number" and count >= 1 then count else 1
end

-- What the server says section `index` is at (or the whole car, until the
-- section attributes arrive).
local function target(model: Instance, key: string, index: number): number?
	local value = model:GetAttribute(key .. index)
	if type(value) ~= "number" then
		value = model:GetAttribute(key)
	end
	return if type(value) == "number" then value else nil
end

local function makeBox(car)
	local box = Instance.new("Part")
	box.Name = car.model.Name
	box.Anchored = true
	box.CanCollide = false
	box.CanQuery = false
	box.CanTouch = false
	box.CastShadow = false
	box.Transparency = 1
	box.Size = Vector3.one
	box.Parent = fxFolder
	car.box = box

	local tail = Instance.new("Attachment")
	tail.Name = "DustTail"
	tail.Parent = box
	car.dustAttachment = tail
	car.dust = emitter(tail, DUST_FX)
end

-- Fresh per-section tables, `count` long.
local function perSection(count: number, make: () -> any)
	local list = {}
	for index = 1, count do
		list[index] = make()
	end
	return list
end

-- Which section a point at seat-space Z `z` is in (1 = nose; the seat faces -Z).
local function sectionAt(car, z: number): number
	local fraction = (z - car.frontZ) / math.max(car.length, 0.1)
	return math.clamp(math.floor(fraction * car.count) + 1, 1, car.count)
end

-- Casts rays at the car and sticks foam / drip / glint spots where they hit.
local function placeSpots(car, size: Vector3, solid: { BasePart })
	for _, child in car.box:GetChildren() do
		if child:IsA("Attachment") and child ~= car.dustAttachment then
			child:Destroy()
		end
	end
	car.emitters = {}
	car.budget = {}
	for _, kind in KINDS do
		car.emitters[kind] = perSection(car.count, function()
			return {}
		end)
		car.budget[kind] = perSection(car.count, function()
			return 0
		end)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = solid

	local boxCF = car.box.CFrame
	local half = size / 2
	local rng = Random.new()

	local function add(result: RaycastResult, kind: string)
		local attachment = Instance.new("Attachment")
		attachment.Name = kind
		attachment.Position = boxCF:PointToObjectSpace(result.Position + result.Normal * 0.05)
		attachment.Parent = car.box
		local section = sectionAt(car, car.offset.Z + attachment.Position.Z)
		table.insert(car.emitters.foam[section], emitter(attachment, FOAM_FX))
		if kind == "Side" then
			table.insert(car.emitters.drip[section], emitter(attachment, DRIP_FX))
		else
			table.insert(car.emitters.glint[section], emitter(attachment, GLINT_FX))
		end
	end

	-- straight down onto the roof, bonnet and boot
	local placed, tries = 0, 0
	while placed < TOP_SPOTS and tries < TOP_SPOTS * 4 do
		tries += 1
		local from = boxCF:PointToWorldSpace(Vector3.new(
			rng:NextNumber(-0.85, 0.85) * half.X,
			half.Y + 2,
			rng:NextNumber(-0.92, 0.92) * half.Z
		))
		local result = workspace:Raycast(from, boxCF.UpVector * -(size.Y + 4), params)
		if result then
			add(result, "Top")
			placed += 1
		end
	end

	-- in from both sides onto the doors and sills
	placed, tries = 0, 0
	while placed < SIDE_SPOTS and tries < SIDE_SPOTS * 4 do
		tries += 1
		local side = if tries % 2 == 0 then 1 else -1
		local from = boxCF:PointToWorldSpace(Vector3.new(
			side * (half.X + 2),
			rng:NextNumber(-0.55, 0.25) * half.Y,
			rng:NextNumber(-0.85, 0.85) * half.Z
		))
		local result = workspace:Raycast(from, boxCF.RightVector * -side * (half.X + 2), params)
		if result then
			add(result, "Side")
			placed += 1
		end
	end
end

-- Measures the car in the seat's space (the body is welded to the seat, so
-- everything stuck to the box follows the car), sorts its paint into
-- sections and places the spots.
local function scan(car)
	car.needsScan = false
	local model, seat = car.model, car.seat
	local seatCF = seat.CFrame
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = -low
	local solid = {}
	local centres = {}
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or part.Transparency >= 0.95 then
			continue
		end
		table.insert(solid, part)
		local cf = seatCF:ToObjectSpace(part.CFrame)
		centres[part] = cf.Z
		local half = part.Size / 2
		local x, y, z = cf.XVector, cf.YVector, cf.ZVector
		local extent = Vector3.new(
			math.abs(x.X) * half.X + math.abs(y.X) * half.Y + math.abs(z.X) * half.Z,
			math.abs(x.Y) * half.X + math.abs(y.Y) * half.Y + math.abs(z.Y) * half.Z,
			math.abs(x.Z) * half.X + math.abs(y.Z) * half.Y + math.abs(z.Z) * half.Z
		)
		low = low:Min(cf.Position - extent)
		high = high:Max(cf.Position + extent)
	end
	if low.X == math.huge then
		return
	end
	local size = high - low
	car.count = segmentCount(model)
	car.frontZ = low.Z
	car.length = size.Z
	car.offset = CFrame.new((low + high) / 2)
	car.box.Size = size
	car.box.CFrame = seatCF * car.offset
	car.dustAttachment.Position = Vector3.new(0, -size.Y / 2 + 0.3, size.Z / 2) -- low at the back

	-- paint, by section (a part belongs to the section its centre is in)
	local known = {}
	for _, section in car.paint or {} do
		for part, paint in section do
			known[part] = paint
		end
	end
	car.paint = perSection(car.count, function()
		return {}
	end)
	for _, part in solid do
		local paint = known[part]
		if not paint and isPaint(part, model) then
			paint = { color = part.Color, reflectance = part.Reflectance } :: Paint
		end
		if paint then
			car.paint[sectionAt(car, centres[part])][part] = paint
		end
	end

	car.shown = perSection(car.count, function()
		return {}
	end)
	car.painted = perSection(car.count, function()
		return {}
	end)
	for index = 1, car.count do
		for _, key in KEYS do
			car.shown[index][key] = target(model, key, index) or 0 -- start where the car is, no fade-in
			car.painted[index][key] = -1
		end
	end
	placeSpots(car, size, solid)
end

local function repaint(car, index: number)
	local v = car.shown[index]
	local dirt, soap, wet, shine = v.Dirt, v.Soap, v.Wet, v.Shine
	local darken = 1 - 0.18 * wet * (1 - soap)
	local gloss = wet * 0.22 * (1 - soap) + shine * 0.2 * (1 - dirt)
	for part, paint: Paint in car.paint[index] do
		if part.Material == Enum.Material.Neon then
			continue -- a light switched on
		end
		-- something else recoloured it (lights, a paint job): that's the new clean colour
		if paint.appliedColor and part.Color ~= paint.appliedColor then
			paint.color = part.Color
		end
		if paint.appliedReflectance and math.abs(part.Reflectance - paint.appliedReflectance) > 0.001 then
			paint.reflectance = part.Reflectance
		end
		local c = paint.color:Lerp(MUD, dirt * 0.6):Lerp(FOAM, soap * 0.6)
		c = Color3.new(c.R * darken, c.G * darken, c.B * darken)
		part.Color = c
		part.Reflectance = math.clamp(paint.reflectance * (1 - dirt * 0.8) + gloss, 0, 0.5)
		paint.appliedColor, paint.appliedReflectance = part.Color, part.Reflectance
	end
	for _, key in KEYS do
		car.painted[index][key] = v[key]
	end
end

-- Emits `perSecond` particles of `kind` from section `index`, one at a time
-- from its random spots (spot emitters keep Rate 0: tiny rates never fire).
local function emitFrom(car, kind: string, index: number, perSecond: number, deltaTime: number)
	local list = car.emitters[kind][index]
	if perSecond <= 0 or #list == 0 then
		car.budget[kind][index] = 0
		return
	end
	local budget = math.min(car.budget[kind][index] + perSecond * deltaTime, 10)
	while budget >= 1 do
		list[math.random(#list)]:Emit(1)
		budget -= 1
	end
	car.budget[kind][index] = budget
end

local function emit(car, index: number, deltaTime: number)
	local v = car.shown[index]
	local share = 1 / car.count
	local dirt, soap, wet, shine = v.Dirt, v.Soap, v.Wet, v.Shine
	emitFrom(car, "foam", index, if soap > 0.04 then soap * FOAM_PER_SECOND * share else 0, deltaTime)
	emitFrom(car, "drip", index, if wet > 0.05 then wet * DRIPS_PER_SECOND * share else 0, deltaTime)
	local spotless = dirt < 0.12 and soap < 0.05 and wet < 0.08
	emitFrom(car, "glint", index, if spotless and shine > 0.3 then shine * GLINTS_PER_SECOND * share else 0, deltaTime)
end

local function track(model: Instance)
	if not model:IsA("Model") or cars[model] then
		return
	end
	local seat = model:FindFirstChildWhichIsA("VehicleSeat", true)
	if not seat then
		-- streaming: try again once the seat arrives
		local connection
		connection = model.DescendantAdded:Connect(function(item)
			if item:IsA("VehicleSeat") then
				connection:Disconnect()
				task.defer(track, model)
			end
		end)
		return
	end

	local car = {
		model = model,
		seat = seat,
		count = 1,
		frontZ = 0,
		length = 1,
		offset = CFrame.identity,
		needsScan = true,
		visible = false,
		connections = {},
	}
	makeBox(car)
	cars[model] = car

	local function rescan()
		car.needsScan = true
	end
	table.insert(car.connections, model.DescendantAdded:Connect(function(item)
		if item:IsA("BasePart") then
			rescan()
		end
	end))
	table.insert(car.connections, model:GetAttributeChangedSignal("Segments"):Connect(rescan))
	local lastCondition = model:GetAttribute("Condition")
	table.insert(car.connections, model:GetAttributeChangedSignal("Condition"):Connect(function()
		local condition = model:GetAttribute("Condition")
		if car.visible and car.emitters and CLEAN[condition] and not CLEAN[lastCondition] then
			for _, section in car.emitters.glint do
				for _, e in section do
					e:Emit(1)
				end
			end
		end
		lastCondition = condition
	end))
end

local function untrack(model: Instance)
	local car = cars[model]
	if not car then
		return
	end
	cars[model] = nil
	for _, connection in car.connections do
		connection:Disconnect()
	end
	car.box:Destroy()
end

for _, model in CollectionService:GetTagged(TAG) do
	track(model)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(track)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(untrack)

------------------------------------------------------------------------------
-- Every frame

RunService.RenderStepped:Connect(function(deltaTime)
	local camera = workspace.CurrentCamera
	local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
	local blend = 1 - math.exp(-EASE_RATE * deltaTime)

	for model, car in cars do
		local seat = car.seat
		if not model:IsDescendantOf(workspace) or not seat:IsDescendantOf(model) then
			untrack(model)
			continue
		end
		if (seat.Position - cameraPosition).Magnitude > CULL_DISTANCE then
			if car.visible then
				car.visible = false
				car.dust.Rate = 0
			end
			continue
		end
		car.visible = true
		if car.needsScan then
			scan(car)
		end
		if not car.shown then
			continue -- nothing visible to measure yet
		end

		car.box.CFrame = seat.CFrame * car.offset
		local dirtSum = 0
		for index = 1, car.count do
			local v, painted = car.shown[index], car.painted[index]
			local changed = false
			for _, key in KEYS do
				local goal = target(model, key, index)
				if goal then
					v[key] += (goal - v[key]) * blend
				end
				if math.abs(v[key] - painted[key]) > REPAINT_STEP then
					changed = true
				end
			end
			if changed then
				repaint(car, index)
			end
			emit(car, index, deltaTime)
			dirtSum += v.Dirt
		end

		local dirt = dirtSum / car.count
		local wet = model:GetAttribute("Wet") or 0
		local speed = seat.AssemblyLinearVelocity.Magnitude
		car.dust.Rate = if dirt > 0.25 and wet < 0.3 and speed > 8 then dirt * math.clamp(speed / 50, 0, 1) * 30 else 0
	end
end)
