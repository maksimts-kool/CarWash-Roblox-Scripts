-- The Wash Time (CarWash.TimerWash) and Dry Time (CarWash.TimerDryer) screens.
-- The server only sets attributes on those models; client/TimerScreens draws them:
--
--   State                     "Idle" | "Waiting" | "Running" | "Done"
--   EndsAt                    server time the countdown reaches zero
--   Total                     length of the countdown in seconds
--   Stage                     what the machine is doing now ("Triple Foam", ...)
--   StageIndex / StageCount   "Step 2 of 6"
--   StageEndsAt / StageTotal  timing of the current step, for the progress bar
--   Program                   the wash the customer paid for

local CarWash = workspace:WaitForChild("CarWash")

local FIELDS = { "EndsAt", "Total", "Stage", "StageIndex", "StageCount", "StageEndsAt", "StageTotal" }

local Screens = {}

Screens.Wash = CarWash.TimerWash :: Model
Screens.Dry = CarWash.TimerDryer :: Model

export type Fields = {
	EndsAt: number?,
	Total: number?,
	Stage: string?,
	StageIndex: number?,
	StageCount: number?,
	StageEndsAt: number?,
	StageTotal: number?,
}

-- Sets the screen's state. Any field left out is cleared.
function Screens.set(screen: Model, state: string, fields: Fields?)
	local values = fields or {}
	for _, key in FIELDS do
		screen:SetAttribute(key, values[key])
	end
	screen:SetAttribute("State", state)
end

function Screens.setProgram(name: string?)
	Screens.Wash:SetAttribute("Program", name)
	Screens.Dry:SetAttribute("Program", name)
end

function Screens.idle()
	Screens.set(Screens.Wash, "Idle")
	Screens.set(Screens.Dry, "Idle")
	Screens.setProgram(nil)
end

return Screens
