function Act()
	if script.Parent.Parent.Soap.Value == true then
		script.Parent.Soap.Enabled = true
	else
		script.Parent.Soap.Enabled = false
	end
end
script.Parent.Parent.Soap.Changed:Connect(Act)