function Act()
	if script.Parent.Parent.Wash.Value == true then
		script.Parent.WashOn.Disabled = false
	else
		script.Parent.WashOff.Disabled = false
	end
end
script.Parent.Parent.Wash.Changed:Connect(Act)