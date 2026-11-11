function act()
script.Parent.Parent.OnSensor.Script.Disabled = true
script.Parent.Parent.Startup:Play()
script.Parent.Parent.dryer1.DryerFan.FanMotor.RightParamB = 1
wait(2.5)
script.Parent.Parent.dryer2.DryerFan.FanMotor.RightParamB = 1
wait(1.5)
script.Parent.Parent.dryer3.DryerFan.FanMotor.RightParamB = 1
wait(1.5)
script.Parent.Parent.Dryer:Play()
script.Parent.Parent.OffSensor.Script.Disabled = false
end
script.Parent.Touched:connect(act) 