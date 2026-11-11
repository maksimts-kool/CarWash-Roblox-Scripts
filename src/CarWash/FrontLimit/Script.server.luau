function Act()
	script.Parent.Parent.Machine.Motor.ToFront.Value = false
	script.Disabled = true
end
script.Parent.Touched:Connect(Act)