local Parameters = RaycastParams.new()
Parameters.FilterType = Enum.RaycastFilterType.Blacklist
Parameters.FilterDescendantsInstances = {}
Parameters.IgnoreWater = true
DebounceTime = 0.5

if DebounceTime < 0 then DebounceTime = 0 end
if DebounceTime > 1.5 then DebounceTime = 1.5 end
CurrentDebounce = 0

while wait() do
	local Result = workspace:Raycast(script.Parent.Position, script.Parent.CFrame.LookVector * 12, Parameters)
	if Result then
		CurrentDebounce = DebounceTime
		script.Parent.Parent.Contour.Enabled = true
		script.Parent.Parent.Reset.Enabled = false
	else
		if CurrentDebounce <= 0 then
			script.Parent.Parent.Contour.Enabled = false
			script.Parent.Parent.Reset.Enabled = true
		end
	end
	CurrentDebounce -= wait()
	if CurrentDebounce < 0 then
		CurrentDebounce = 0
	end
end
