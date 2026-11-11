script.Parent.HangTight.Disabled = true
script.Disabled = true
script.Parent.Parent.Conveyor.ConveyorStopper.CanCollide = true
script.Parent.Standard.Disabled = false
script.Parent.Superior.Disabled = false
script.Parent.Ultimate.Disabled = false
script.Parent.Beeper.Beep2:Play()
script.Parent.BasicWashButton.LED.BrickColor = BrickColor.new("Really blue")
script.Parent.BasicWashButton.Button.ClickDetector.MaxActivationDistance = 32
script.Parent.BottomWashButton.LED.BrickColor = BrickColor.new("Really blue")
script.Parent.BottomWashButton.Button.ClickDetector.MaxActivationDistance = 32
script.Parent.MiddleWashButton.LED.BrickColor = BrickColor.new("Really blue")
script.Parent.MiddleWashButton.Button.ClickDetector.MaxActivationDistance = 32
script.Parent.TopWashButton.LED.BrickColor = BrickColor.new("Really blue")
script.Parent.TopWashButton.Button.ClickDetector.MaxActivationDistance = 32
script.Parent.Instructions.SurfaceGui.TextLabel.Text = "Select A Wash or Enter Code Now"
wait(0.5)
script.Parent.Beeper.Beep2:Stop()