function Act()
	if script.Parent.Value == true then
		script.Parent.Parent.Start.Disabled = false
for i= 0,2.5,0.5 do
script.Parent.Parent.BodyVelocity.Velocity = Vector3.new(0,0,-i)
script.Parent.Parent.BodyVelocity.Velocity = Vector3.new(0,0,-i)
wait(0.1)
end
	else	
for i= 2.5,0,-0.5 do
script.Parent.Parent.BodyVelocity.Velocity = Vector3.new(0,0,-i)
script.Parent.Parent.BodyVelocity.Velocity = Vector3.new(0,0,-i)
wait(0.1)	
		end
script.Parent.Parent.Stop.Disabled = false
	end
	end
script.Parent.Changed:Connect(Act)