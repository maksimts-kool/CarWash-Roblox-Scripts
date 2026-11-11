-- CarWashModules/MainModule.lua
local MainModule = {}
local MainScreenModule = require(script.MainScreenModule)
local WashController = require(script.WashController)

MainModule.values = {
	MAIN_SCREEN_DONE = false,
	OCCUPIED = false,
	WASH = ""
}

function MainModule:StartWash(entryHit)
	if self.values.OCCUPIED then
		return warn("Wash already in progress!")
	end

	self.values.OCCUPIED = true
	print("Starting wash process for ".. self.values.WASH)

	task.spawn(function()
		local ok, err = pcall(WashController.Run, WashController, self.values.WASH, entryHit)
		if not ok then
			warn("Wash stopped early: " .. tostring(err))
			WashController:Abort()
		end
		self:FinishWash()
	end)
end

function MainModule:FinishWash()
	print("Finished wash process for ".. self.values.WASH)
	self.values.OCCUPIED = false
	self.values.WASH = ""
end

function MainModule:Initialize()
	MainScreenModule:Initialize(self)
	WashController:Initialize()
	
	script.Parent.GateEN.CloseSensor.Touched:Connect(function(hit)
		if not self.values.MAIN_SCREEN_DONE then return end
		MainScreenModule:ResetFrame()
		self.values.MAIN_SCREEN_DONE = false
		script.Parent.GateEN.Frame.MotorSupport.HingeConstraint.TargetAngle = 0
		MainModule:StartWash(hit)
	end)
	print("MainModule initialized and listening for UI button.")
end

return MainModule