-- Welds the moving machine parts into rigid assemblies when the server starts.
--
-- These models are saved unanchored and unwelded (they used to hang on
-- hinges). Each one is welded to its PrimaryPart, or its first part, and
-- unanchored; Joints then hangs it off its frame with a scripted joint. This
-- replaces the qPerfectionWeld / Weld script copies that used to sit inside
-- each model.

local CarWash = workspace:WaitForChild("CarWash")

-- Paths under CarWash.
local ASSEMBLIES = {
	{ "Clearance Arch", "Clearance Bar" },
	{ "GateEN", "GateArm" },
	{ "GateEX", "GateArm" },
	{ "WrapArounds", "Brushes", "BrushOne", "BrushPart" },
	{ "WrapArounds", "Brushes", "BrushOne", "BrushMotor" },
	{ "WrapArounds", "Brushes", "BrushTwo", "BrushPart" },
	{ "WrapArounds", "Brushes", "BrushTwo", "BrushMotor" },
	{ "RockerBrushes", "BrushTwo", "RockerBrush", "BrushPart" },
	{ "RockerBrushes", "BrushTwo", "RockerBrush", "BrushMotor" },
	{ "New", "TopBrush", "Carriage" }, -- slides up and down the posts on its Lift joint
	{ "New", "TopBrush", "BrushMotor" }, -- spins on the carriage on its MotorMain joint
}

-- The rotary wheel blasters' heads (BlasterPart, BlasterPart2, ...) under each
-- Blaster model; each is welded to its Motor, the part its Rotate joint turns.
local WHEEL_BLASTERS = "RotaryWheelBlasters"

-- Every model with this name under a dryer is a fan assembly (motor + blades).
local DRYER_FAN = "DryerFan"

local Welds = {}

local function resolve(path)
	local instance = CarWash
	for _, name in path do
		instance = instance:FindFirstChild(name)
		if not instance then
			return nil
		end
	end
	return instance
end

function Welds.weld(model: Instance, root: BasePart?)
	local parts = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(parts, item)
		end
	end

	root = root or (model:IsA("Model") and model.PrimaryPart) or parts[1]
	if not root then
		warn(`Welds: nothing to weld in {model:GetFullName()}`)
		return
	end

	for _, part in parts do
		if part ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "AssemblyWeld"
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	for _, part in parts do
		part.Anchored = false
	end
end

function Welds.weldAll()
	for _, path in ASSEMBLIES do
		local model = resolve(path)
		if model then
			Welds.weld(model)
		else
			warn(`Welds: CarWash.{table.concat(path, ".")} not found`)
		end
	end

	local blasters = CarWash:FindFirstChild(WHEEL_BLASTERS)
	if blasters then
		for _, blaster in blasters:GetChildren() do
			for _, head in blaster:GetChildren() do
				local motor = head:FindFirstChild("Motor")
				if head:IsA("Model") and head.Name:match("^BlasterPart") and motor and motor:IsA("BasePart") then
					-- the old weld script the heads were saved with, if it hasn't run yet
					local script = head:FindFirstChild("Weld")
					if script and script:IsA("Script") then
						script:Destroy()
					end
					Welds.weld(head, motor)
				end
			end
		end
	else
		warn(`Welds: CarWash.{WHEEL_BLASTERS} not found`)
	end

	for _, child in CarWash:GetChildren() do
		if child.Name:match("^KWS Storm Dryer") then
			for _, item in child:GetDescendants() do
				if item.Name == DRYER_FAN and item:IsA("Model") then
					Welds.weld(item)
				end
			end
		end
	end
end

return Welds
