-- The emergency stop (pressed on the ControlPanel). While it is active the
-- wash timeline halts: every long wait in the wash checks it, and the wash
-- thread errors out with HALTED, which WashLine catches. Machines are switched
-- off by whoever presses the stop (WashLine.emergencyStop), not here.

local HALTED = "CarWash emergency stop"
local POLL = 0.1

local Stop = {}

Stop.active = false

-- Errors out of the wash if the emergency stop is active.
function Stop.check()
	if Stop.active then
		error(HALTED, 0)
	end
end

-- task.wait(seconds), but errors out as soon as the stop is pressed.
function Stop.wait(seconds: number)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		Stop.check()
		task.wait(math.min(POLL, deadline - os.clock()))
	end
	Stop.check()
end

-- Was this error (from pcall) the emergency stop?
function Stop.isHalt(err: unknown): boolean
	return err == HALTED
end

return Stop
