-- The DuraBlaster wheel blasters (CarWash.DuraBlasters): two spinning
-- manifolds per side, plus an Eye sensor that swings the blaster arms in
-- toward the car while something is in front of it. The arms swing on each
-- side's "Move" joint and the manifolds spin on the joints in their
-- SpinnerAttatchment (see Joints).

local Joints = require(script.Parent.Parent.Joints)

local CarWash = workspace:WaitForChild("CarWash")
local Blasters = CarWash.DuraBlasters
local Eye = Blasters.Eye :: BasePart

local SIDES = { Blasters.LeftDuraBlaster, Blasters.RightDuraBlaster }
local SPIN_SPEED = 720 -- degrees per second

local EYE_RANGE = 12
local EYE_INTERVAL = 0.05
local CONTOUR_HOLD = 0.5 -- keep the arms in this long after the eye loses the car
local CONTOUR_ANGLE = -30
local REST_ANGLE = 30
local ARM_SPEED = math.deg(1) -- degrees per second

local Module = {}

-- The blasters can switch off once the car's tail passes this.
Module.END_Z = Eye.Position.Z - 2

function Module.set(on: boolean)
	for _, side in SIDES do
		for _, item in side:GetDescendants() do
			if item:IsA("Motor6D") and item:HasTag(Joints.TAG) and item.Parent.Name == "SpinnerAttatchment" then
				Joints.spin(item, if on then SPIN_SPEED else 0)
			elseif item:IsA("ParticleEmitter") and item.Name == "HP" then
				item.Enabled = on
			end
		end
	end
end

local function setArms(contoured: boolean)
	for _, side in SIDES do
		Joints.servo(Joints.get(side, "Move"), if contoured then CONTOUR_ANGLE else REST_ANGLE, ARM_SPEED)
	end
end

-- Watches the Eye for as long as the server runs.
function Module.startContouring()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- the arms only move on the clients, so leave the blasters out of it
	params.FilterDescendantsInstances = SIDES
	params.IgnoreWater = true

	task.spawn(function()
		local contoured = nil
		local lastSeen = -math.huge
		while true do
			if workspace:Raycast(Eye.Position, Eye.CFrame.LookVector * EYE_RANGE, params) then
				lastSeen = os.clock()
			end
			local want = os.clock() - lastSeen < CONTOUR_HOLD
			if want ~= contoured then
				contoured = want
				setArms(want)
			end
			task.wait(EYE_INTERVAL)
		end
	end)
end

return Module
