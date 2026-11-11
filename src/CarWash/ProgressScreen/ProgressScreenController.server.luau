-- Shows the ProgressScreen state that matches the car wash's current status.

local CHECK_INTERVAL = 0.2

local model = script.Parent
local MainModule = require(model.Parent:WaitForChild("MainModule"))
local gui = model:WaitForChild("Screen"):WaitForChild("SurfaceGui")

local frames = {
	Select = gui:WaitForChild("Select"),
	Good = gui:WaitForChild("Good"),
	Occupied = gui:WaitForChild("Occupied"),
}

local function getState()
	local values = MainModule.values

	if values.OCCUPIED then
		return "Occupied"
	elseif values.MAIN_SCREEN_DONE then
		return "Good"
	end

	return "Select"
end

local currentState

while true do
	local state = getState()

	if state ~= currentState then
		currentState = state

		for name, frame in frames do
			frame.Visible = name == state
		end
	end

	task.wait(CHECK_INTERVAL)
end
