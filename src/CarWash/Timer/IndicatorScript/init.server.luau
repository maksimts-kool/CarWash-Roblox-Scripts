This = script.Parent
Characters = require(script.Characters)

function SetDisplay(ID,CHAR)
	if This:FindFirstChild("DIG"..ID) and Characters[CHAR] ~= nil then
 		for i,l in pairs(Characters[CHAR]) do 
			for r=1,7 do	
				This["DIG"..ID]["D"..r].Color = (l:sub(r,r) == "1" and Color3.fromRGB(160, 0, 0) or Color3.fromRGB(27, 42, 53))
			end
		end
	end
end

function ChangeFloor(SF)
	SetDisplay(1,(string.len(SF) == 2 and SF:sub(1,1) or SF))		
	SetDisplay(2,(string.len(SF) == 2 and SF:sub(2,2) or SF))
end

This.Value.Changed:Connect(function()
	ChangeFloor(This.Value.Value)
end)

ChangeFloor("--")
