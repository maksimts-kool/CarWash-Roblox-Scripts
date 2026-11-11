function Act()
	script.Parent.Parent.Parent.Steps.DriveForward.Controller.Value.Value = false
	script.Parent.Parent.Parent.Steps.BackUp.Controller.Value.Value = true
	script.Parent.Parent.Parent.Steps.Stop.Controller.Value.Value = false
	script.Parent.Parent.Stop.Script.Disabled = true
	wait(1)
	script.Parent.Parent.Stop.Script.Disabled = false
end
script.Parent.Touched:Connect(Act)