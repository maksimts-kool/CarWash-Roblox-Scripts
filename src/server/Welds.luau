-- Welds the moving machine parts into rigid assemblies when the server starts.
--
-- These models are saved unanchored and unwelded (the hinges that drive them
-- need them free). Each one is welded to its PrimaryPart, or its first part,
-- and unanchored. This replaces the qPerfectionWeld / Weld script copies that
-- used to sit inside each model.

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
	{ "DuraBlasters", "LeftDuraBlaster", "WheelBlasterFrame" },
	{ "DuraBlasters", "LeftDuraBlaster", "BottomSpinner" },
	{ "DuraBlasters", "LeftDuraBlaster", "TopSpinner" },
	{ "DuraBlasters", "RightDuraBlaster", "WheelBlasterFrame" },
	{ "DuraBlasters", "RightDuraBlaster", "BottomSpinner" },
	{ "DuraBlasters", "RightDuraBlaster", "TopSpinner" },
}

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

function Welds.weld(model: Instance)
	local parts = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(parts, item)
		end
	end

	local root = (model:IsA("Model") and model.PrimaryPart) or parts[1]
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
