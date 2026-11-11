script.Parent.Touched:Connect(function()
	script.Parent.Parent.Parent.TL2.red.Transparency = 0.95
	script.Parent.Parent.Parent.TL2.green.Transparency = 0
	script.Parent.Parent.HangTight.Disabled = true
	script.Parent.Parent.Script.Disabled = false
	script.Parent.Parent.Parent.TL.Value.Value = 1
end)
