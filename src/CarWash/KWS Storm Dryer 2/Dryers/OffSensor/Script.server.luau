function act()
script.Parent.Parent.OffSensor.Script.Disabled = true
script.Parent.Parent.dryer1.DryerFan.FanMotor.RightParamB = 0
script.Parent.Parent.dryer2.DryerFan.FanMotor.RightParamB = 0
script.Parent.Parent.dryer3.DryerFan.FanMotor.RightParamB = 0
script.Parent.Parent.Stop.Disabled = false
script.Parent.Parent.Stop2.Disabled = false
script.Parent.Parent.Slow.Disabled = false
script.Parent.Parent.OnSensor.Script.Disabled = false
end
script.Parent.Touched:connect(act) 