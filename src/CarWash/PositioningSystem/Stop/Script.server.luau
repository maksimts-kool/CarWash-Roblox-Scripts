function Act()
	script.Parent.Parent.Parent.c.AssemblyLinearVelocity = Vector3.new(0,0,0)
	script.Parent.Parent.Parent.Steps.DriveForward.Controller.Value.Value = false
	script.Parent.Parent.Parent.Steps.BackUp.Controller.Value.Value = false
	script.Parent.Parent.Parent.WrapArounds.Regen.regen.Disabled = true
	script.Parent.Parent.Parent.StepsWash.Step1.Controller.Value.Value = false
	script.Parent.Parent.Parent.StepsWash.Step1.Controller.Value2.Value = false
	script.Parent.Parent.Parent.StepsWash.Step2.Controller.Value.Value = false
	script.Parent.Parent.Parent.StepsWash.Step2.Controller.Value2.Value = false
	script.Parent.Parent.Parent.StepsWash.Step3.Controller.Value.Value = false
	script.Parent.Parent.Parent.StepsWash.Step3.Controller.Value2.Value = false
	script.Parent.Parent.Parent.StepsWash.Step4.Controller.Value.Value = false
	script.Parent.Parent.Parent.StepsWash.Step4.Controller.Value2.Value = false
	script.Parent.Parent.Parent.RockerBrushes.Sensor.Script.Disabled = true
	script.Parent.Parent.Parent.Steps.Stop.Controller.Value.Value = true
	if script.Parent.Parent.Parent.Type.Value == "Bottom" then
		script.Parent.Parent.Parent.BottomWash.Disabled = false
		script.Parent.Parent.Parent.WhatWash.B.Controller.Value.Value = true
		script.Parent.Parent.Parent.TimerWash.Mode.Value = 1
	end
	if script.Parent.Parent.Parent.Type.Value == "Middle" then
		script.Parent.Parent.Parent.MiddleWash.Disabled = false
		script.Parent.Parent.Parent.WhatWash.M.Controller.Value.Value = true
		script.Parent.Parent.Parent.TimerWash.Mode.Value = 2
	end
	if script.Parent.Parent.Parent.Type.Value == "Top" then
		script.Parent.Parent.Parent.TopWash.Disabled = false
		script.Parent.Parent.Parent.WhatWash.T.Controller.Value.Value = true
		script.Parent.Parent.Parent.TimerWash.Mode.Value = 3
		
	end
	script.Parent.Parent.Forward.Script.Disabled = false
	script.Parent.Parent.Back.Script.Disabled = false
	wait(4)
	script.Disabled = true
	script.Parent.Parent.Forward.Script.Disabled = true
	script.Parent.Parent.Back.Script.Disabled = true
end
script.Parent.Touched:Connect(Act)