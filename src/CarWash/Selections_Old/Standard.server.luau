function Act()
script.Disabled = true
script.Parent.Parent.WashType.Value = "Standard"
script.Parent.BasicWashButton.LED.BrickColor = BrickColor.new("Really blue")
script.Parent.BasicWashButton.Button.ClickDetector.MaxActivationDistance = 0
script.Parent.BottomWashButton.LED.BrickColor = BrickColor.new("Really red")
script.Parent.BottomWashButton.Button.ClickDetector.MaxActivationDistance = 0
script.Parent.MiddleWashButton.LED.BrickColor = BrickColor.new("Really blue")
script.Parent.MiddleWashButton.Button.ClickDetector.MaxActivationDistance = 0
script.Parent.TopWashButton.LED.BrickColor = BrickColor.new("Really blue")
script.Parent.TopWashButton.Button.ClickDetector.MaxActivationDistance = 0

script.Parent.Beeper.Beep2:Play()
wait(0.1)
script.Parent.Beeper.Beep2:Stop()
script.Parent.Instructions.SurfaceGui.TextLabel.Text = "You Have Selected the Standard Wash"
wait(3)
script.Parent.Instructions.SurfaceGui.TextLabel.Text = "Please Insert the price for the wash you've selected"
wait(3)
script.Parent.Instructions.SurfaceGui.TextLabel.Text = "Or insert Your Credit Card Using The Card Reader"
wait(1)
script.Parent.Beeper.Beep2:Play()
wait(0.1)
script.Parent.Beeper.Beep2:Stop()
script.Parent.Instructions.SurfaceGui.TextLabel.Text = "Processing Transaction"
wait(4)
script.Parent.Beeper.Beep2:Play()
wait(1)
script.Parent.Beeper.Beep2:Stop()
	script.Parent.Instructions.SurfaceGui.TextLabel.Text = "Thank You, Please Advance Into The Wash Slowly"
	script.Parent.Parent.TL.Value.Value = 2
	script.Parent.Parent.Barrier.Value.Value = true
	script.Parent.Parent.Conveyor.ConveyorStopper.CanCollide = false
	script.Parent.Parent.TL2.red.Transparency = 0
	script.Parent.Parent.TL2.green.Transparency = 0.95
script.Parent.BasicWashButton.LED.BrickColor = BrickColor.new("Really black")
script.Parent.BasicWashButton.Button.ClickDetector.MaxActivationDistance = 0
script.Parent.BottomWashButton.LED.BrickColor = BrickColor.new("Really black")
script.Parent.BottomWashButton.Button.ClickDetector.MaxActivationDistance = 0
script.Parent.MiddleWashButton.LED.BrickColor = BrickColor.new("Really black")
script.Parent.MiddleWashButton.Button.ClickDetector.MaxActivationDistance = 0
script.Parent.TopWashButton.LED.BrickColor = BrickColor.new("Really black")
script.Parent.TopWashButton.Button.ClickDetector.MaxActivationDistance = 0
end
script.Parent.BottomWashButton.Button.ClickDetector.MouseClick:Connect(Act)