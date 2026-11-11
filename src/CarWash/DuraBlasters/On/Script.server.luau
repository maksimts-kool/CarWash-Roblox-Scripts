function output()
	if script.Parent.Value == true then
		script.Parent.Parent.BlastersOn.Enabled = true
	else
		script.Parent.Parent.BlastersOff.Enabled = true
	end
end
script.Parent.Changed:Connect(output)