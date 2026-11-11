for i=0.5,0,-0.0055 do
script.Parent.Dryer.Volume = i
 wait(0.1)
end
wait(1)
script.Parent.Dryer.Volume = 0.5
script.Parent.Dryer:Stop()
script.Disabled = true