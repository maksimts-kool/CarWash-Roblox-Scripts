		script.Parent.WashStarter.Enabled = true
		script.Parent.Wash.Enabled = false
		while true do
			script.Parent.WashStarter.Acceleration = script.Parent.WashStarter.Acceleration - Vector3.new(0,2.5,0)
			wait()
			if script.Parent.WashStarter.Acceleration == Vector3.new(0,-75,0) then break end
		end
script.Parent.WashStarter.Enabled = false
script.Disabled = true