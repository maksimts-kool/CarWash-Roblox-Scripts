function act()
script.Parent.Parent.Sensor.Script.Disabled = true
script.Parent.Parent.Sound:Play()
script.Parent.Parent.BrushOne.RockerBrush.Nozzle.ParticleEmitter.Enabled = true
script.Parent.Parent.BrushOne.RockerBrush.Nozzle2.ParticleEmitter.Enabled = true
script.Parent.Parent.BrushOne.RockerBrush.Nozzle3.ParticleEmitter.Enabled = true
script.Parent.Parent.BrushTwo.RockerBrush.Nozzle.ParticleEmitter.Enabled = true
script.Parent.Parent.BrushTwo.RockerBrush.Nozzle2.ParticleEmitter.Enabled = true
script.Parent.Parent.BrushTwo.RockerBrush.Nozzle3.ParticleEmitter.Enabled = true
script.Parent.Parent.BrushOne.RockerBrush.BrushMotor.MotorMain.HingeConstraint.AngularVelocity = 15
script.Parent.Parent.BrushTwo.RockerBrush.BrushMotor.MotorMain.HingeConstraint.AngularVelocity = 15
script.Parent.Parent.BrushOne.RockerBrush.BrushPart.MotorHold.HingeConstraint.TargetAngle = 30
script.Parent.Parent.BrushTwo.RockerBrush.BrushPart.MotorHold.HingeConstraint.TargetAngle = -30
wait(30)
script.Parent.Parent.Sound:Stop()
script.Parent.Parent.BrushOne.RockerBrush.Nozzle.ParticleEmitter.Enabled = false
script.Parent.Parent.BrushOne.RockerBrush.Nozzle2.ParticleEmitter.Enabled = false
script.Parent.Parent.BrushOne.RockerBrush.Nozzle3.ParticleEmitter.Enabled = false
script.Parent.Parent.BrushTwo.RockerBrush.Nozzle.ParticleEmitter.Enabled = false
script.Parent.Parent.BrushTwo.RockerBrush.Nozzle2.ParticleEmitter.Enabled = false
script.Parent.Parent.BrushTwo.RockerBrush.Nozzle3.ParticleEmitter.Enabled = false
	script.Parent.Parent.BrushOne.RockerBrush.BrushMotor.MotorMain.HingeConstraint.AngularVelocity = 0
	script.Parent.Parent.BrushTwo.RockerBrush.BrushMotor.MotorMain.HingeConstraint.AngularVelocity = 0
	script.Parent.Parent.BrushOne.RockerBrush.BrushPart.MotorHold.HingeConstraint.TargetAngle = 0
	script.Parent.Parent.BrushTwo.RockerBrush.BrushPart.MotorHold.HingeConstraint.TargetAngle = 0
script.Parent.Parent.Sensor.Script.Disabled = false
end
script.Parent.Touched:connect(act) 