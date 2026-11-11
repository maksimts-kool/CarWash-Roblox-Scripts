for i=0.7,0,-0.3 do
	script.Parent.SpotFreeRinse2.Volume = i
	wait(0.1)
end
script.Parent.SpotFreeRinse2.Volume = 0
script.Parent.SpotFreeRinse2:Stop()
wait(3)
script.Parent.SpotFreeRinse2.Volume = 0.7
script.Disabled = true