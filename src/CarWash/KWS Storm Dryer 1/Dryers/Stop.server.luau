for i=1,0,-0.01 do
script.Parent.Dryer.PlaybackSpeed = i
 wait(0.1)
end
wait(3)
script.Parent.Dryer.PlaybackSpeed = 1
script.Disabled = true