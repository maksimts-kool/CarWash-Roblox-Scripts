for i=1,0,-0.1 do
	script.Parent.SpotFreeRinse2.PlaybackSpeed = i
	wait(0.1)
end
script.Parent.SpotFreeRinse2.PlaybackSpeed = 0
script.Parent.SpotFreeRinse2:Stop()
wait(3)
script.Parent.SpotFreeRinse2.PlaybackSpeed = 1
script.Disabled = true