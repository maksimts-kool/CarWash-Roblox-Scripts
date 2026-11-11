-- The conveyor belts (CarWash.ConveyorPart) and moving the car along them.

local RunService = game:GetService("RunService")

local Config = require(script.Parent.Parent.Config)
local Car = require(script.Parent.Car)

local ConveyorPart = workspace:WaitForChild("CarWash"):WaitForChild("ConveyorPart")

local belts = {}
for _, child in ConveyorPart:GetChildren() do
	if child.Name:match("^Conveyor") then
		table.insert(belts, child)
	end
end

-- Halfway between the left wheel track and the right belt.
local LANE_X = (ConveyorPart.Conveyor4.Position.X + ConveyorPart.Conveyor3.Position.X) / 2
local MIN_SPEED = 0.4 -- the car creeps the last bit onto its target
local BRAKING = 1.5 -- studs/s of speed per stud left to the target

export type Trigger = {
	ready: () -> boolean,
	run: () -> (),
}

local Conveyor = {}

local function setBelts(speed: number)
	for _, belt in belts do
		belt.AssemblyLinearVelocity = belt.CFrame.LookVector * speed
	end
end

function Conveyor.stop()
	setBelts(0)
end

-- Trigger conditions, by where the car is.
function Conveyor.frontReaches(z: number): () -> boolean
	return function()
		return Car.front() <= z
	end
end

function Conveyor.rearPasses(z: number): () -> boolean
	return function()
		return Car.rear() <= z
	end
end

-- Moves the car until its nose reaches targetZ, easing between speeds.
--
-- Each trigger runs once, the moment its condition holds; any still pending
-- run at the end, in list order. cruiseSpeed() gives the speed for where the
-- car is now (default Config.ConveyorSpeed). Gives up if the car makes no
-- progress for Config.StallSeconds.
function Conveyor.moveCarTo(targetZ: number, triggers: { Trigger }?, cruiseSpeed: (() -> number)?)
	local cruise = cruiseSpeed or function()
		return Config.ConveyorSpeed
	end
	local pending = table.clone(triggers or {})
	local speed = 0
	local bestFront, lastProgress = Car.front(), os.clock()

	local function runReadyTriggers()
		local index = 1
		while index <= #pending do
			if pending[index].ready() then
				table.remove(pending, index).run()
			else
				index += 1
			end
		end
	end

	while Car.front() > targetZ and os.clock() - lastProgress < Config.StallSeconds do
		local deltaTime = RunService.Heartbeat:Wait()
		-- slow to a stop on the target, otherwise cruise at this zone's speed
		local goal = math.clamp((Car.front() - targetZ) * BRAKING, MIN_SPEED, cruise())
		local step = Config.ConveyorAccel * deltaTime
		speed += math.clamp(goal - speed, -step, step)

		setBelts(speed)
		Car.drive(speed, LANE_X, deltaTime)
		if Car.front() < bestFront - 0.05 then
			bestFront, lastProgress = Car.front(), os.clock()
		end
		Car.publish()
		runReadyTriggers()
	end

	Car.drive(0, LANE_X, 0)
	Car.publish(true)
	setBelts(0)
	while #pending > 0 do
		table.remove(pending, 1).run()
	end
end

return Conveyor
