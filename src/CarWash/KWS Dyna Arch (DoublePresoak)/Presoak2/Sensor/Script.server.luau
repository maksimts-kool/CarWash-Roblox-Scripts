function act()
script.Parent.Parent.On.Disabled = false
wait(23)
script.Parent.Parent.Off.Disabled = false
end
script.Parent.Touched:connect(act) 