function act()
script.Parent.Parent.Sensor2.Script.Disabled = true
script.Parent.Parent.BrushOne.BrushPart.MotorHold.HingeConstraint.TargetAngle = 45
script.Parent.Parent.BrushTwo.BrushPart.MotorHold.HingeConstraint.TargetAngle = -45
wait(5)
script.Parent.Parent.Brush:Stop()
script.Parent.Parent.Air:Play()
wait(0.4)
script.Parent.Parent.BrushOne.BrushPart.Nozzle.ParticleEmitter.Enabled = false
script.Parent.Parent.BrushTwo.BrushPart.Nozzle.ParticleEmitter.Enabled = false
	script.Parent.Parent.BrushOne.BrushMotor.MotorMain.HingeConstraint.AngularVelocity = 0
	script.Parent.Parent.BrushTwo.BrushMotor.MotorMain.HingeConstraint.AngularVelocity = 0
	script.Parent.Parent.BrushTwo.BrushPart.MotorHold.HingeConstraint.TargetAngle = 0
	script.Parent.Parent.BrushOne.BrushPart.MotorHold.HingeConstraint.TargetAngle = 0
script.Parent.Parent.Sensor.Script.Disabled = false
end
script.Parent.Touched:connect(act) 