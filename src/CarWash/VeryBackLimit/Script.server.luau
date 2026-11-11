function Act()
	script.Parent.Parent.Machine.Motor.ToBack.Value = false
	script.Disabled = true
end
script.Parent.Touched:Connect(Act)