function act()
script.Parent.Parent.Sensor.Script.Disabled = true
script.Parent.Parent.BrushOne.BrushPart.Nozzle.ParticleEmitter.Enabled = true
script.Parent.Parent.BrushTwo.BrushPart.Nozzle.ParticleEmitter.Enabled = true
script.Parent.Parent.BrushTwo.BrushMotor.MotorMain.HingeConstraint.AngularVelocity = -15
script.Parent.Parent.BrushOne.BrushMotor.MotorMain.HingeConstraint.AngularVelocity = 15
script.Parent.Parent.Air:Play()
wait(1)
script.Parent.Parent.BrushTwo.BrushPart.MotorHold.HingeConstraint.TargetAngle = -45
script.Parent.Parent.BrushOne.BrushPart.MotorHold.HingeConstraint.TargetAngle = 45
wait(2)
script.Parent.Parent.Brush:Play()
wait(5)
script.Parent.Parent.Air:Play()
script.Parent.Parent.BrushOne.BrushPart.MotorHold.HingeConstraint.TargetAngle = 15
script.Parent.Parent.Air2:Play()
script.Parent.Parent.BrushTwo.BrushPart.MotorHold.HingeConstraint.TargetAngle = -15
wait(8)
script.Parent.Parent.Sensor2.Script.Disabled = false
end
script.Parent.Touched:connect(act) 