function Act()
	if script.Parent.Parent.Rinse.Value == true then
		script.Parent.Rinse.Enabled = true
	else
		script.Parent.Rinse.Enabled = false
	end
end
script.Parent.Parent.Rinse.Changed:Connect(Act)