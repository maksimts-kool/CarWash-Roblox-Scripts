function Act()
	if script.Parent.Parent.Parent.Value.Value == true then
		script.Parent.Enabled = true
		script.Parent.Parent.Parent.start:Play()
		wait(2)
		script.Parent.Parent.Parent.going:Play()
		script.Parent.Parent.Parent.going.Looped = true
	else
		script.Parent.Parent.Parent.going.Looped = false
		script.Parent.Parent.Parent.stop:Play()
		script.Parent.Enabled = false
	end
end
script.Parent.Parent.Parent.Value.Changed:Connect(Act)