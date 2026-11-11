
--[[
script.Parent.Dryer.Sound2:Play()
wait(6)
]]--
script.Parent.TStart.Disabled = false
script.Parent.FoamSound.Sound:Play()
wait(2.1)
script.Parent.FoamSound.Sound2:Play()

script.Disabled = true