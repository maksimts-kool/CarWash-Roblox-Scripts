function Act()
	if script.Parent.Parent.Parent.Value.Value == true then
		script.Parent.Enabled = true
		script.Parent.Parent.Material = Enum.Material.Neon
	else
		script.Parent.Enabled = false
		script.Parent.Parent.Material = Enum.Material.SmoothPlastic
	end
end
script.Parent.Parent.Parent.Value.Changed:Connect(Act)