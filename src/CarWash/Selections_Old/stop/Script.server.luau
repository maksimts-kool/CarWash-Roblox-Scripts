script.Parent.Touched:Connect(function()
	script.Parent.Parent.HangTight.Disabled = false
	script.Parent.Parent.Parent.TL.Value.Value = 3
end)
