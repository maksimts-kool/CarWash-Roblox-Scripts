-- Get the StringValue object
local countdownValue = script.Parent.Value
local countdownSetting = script.Parent.Mode

-- Set the initial value
countdownValue.Value = "---"

-- Function to format numbers as three-digit strings
local function formatNumber(number)
	return string.format("%03d", number)
end

-- Determine the initial countdown value based on the NumberValue
script.Parent.Mode.Changed:Connect(function()
	local initialCountdown = nil
		if countdownSetting.Value == 1 then
			initialCountdown = 128
		elseif countdownSetting.Value == 2 then
			initialCountdown = 153
		elseif countdownSetting.Value == 3 then
			initialCountdown = 199
		end
	
		-- Set the initial value
		countdownValue.Value = formatNumber(initialCountdown)
	
		-- Countdown from the initial value to 000
		for i = initialCountdown, 0, -1 do
			countdownValue.Value = formatNumber(i)
			wait(1) -- Wait 1 second between updates (you can adjust the duration as needed)
		end
		
		-- Set the final value to "000"
		countdownValue.Value = "---"
end)
