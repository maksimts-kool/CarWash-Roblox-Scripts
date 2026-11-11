function Act()
script.Disabled = true
script.Parent.Parent.WashPackage.Value = "Basic"
script.Parent.BasicWashButton.LED.BrickColor = BrickColor.new("Really red")
script.Parent.BasicWashButton.Button.ClickDetector.MaxActivationDistance = 0
script.Parent.BottomWashButton.LED.BrickColor = BrickColor.new("Really blue")
script.Parent.BottomWashButton.Button.ClickDetector.MaxActivationDistance = 0
script.Parent.MiddleWashButton.LED.BrickColor = BrickColor.new("Really blue")
script.Parent.MiddleWashButton.Button.ClickDetector.MaxActivationDistance = 0
script.Parent.TopWashButton.LED.BrickColor = BrickColor.new("Really blue")
script.Parent.TopWashButton.Button.ClickDetector.MaxActivationDistance = 0

script.Parent.Beeper.Beep2:Play()
wait(0.1)
script.Parent.Beeper.Beep2:Stop()
script.Parent.Instructions.SurfaceGui.TextLabel.Text = "You Have Selected the Express Wash"
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
script.Parent.Parent.PositionSensors.BlasterTrigger.Script2.Disabled = false
script.Parent.BasicWashButton.LED.BrickColor = BrickColor.new("Really black")
script.Parent.BasicWashButton.Button.ClickDetector.MaxActivationDistance = 0
script.Parent.BottomWashButton.LED.BrickColor = BrickColor.new("Really black")
script.Parent.BottomWashButton.Button.ClickDetector.MaxActivationDistance = 0
script.Parent.MiddleWashButton.LED.BrickColor = BrickColor.new("Really black")
script.Parent.MiddleWashButton.Button.ClickDetector.MaxActivationDistance = 0
script.Parent.TopWashButton.LED.BrickColor = BrickColor.new("Really black")
script.Parent.TopWashButton.Button.ClickDetector.MaxActivationDistance = 0
end
script.Parent.BasicWashButton.Button.ClickDetector.MouseClick:Connect(Act)