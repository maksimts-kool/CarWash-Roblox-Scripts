function VehiclesInWash()
	if script.Parent.Value >= 0 then
		script.Parent.Parent.On.Value = true
	elseif script.Parent.Value <= 0 then
		script.Parent.Parent.On.Value = false
	end
end
script.Parent.Changed:Connect(VehiclesInWash)