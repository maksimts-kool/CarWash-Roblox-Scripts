-- Gives every player a Cash balance (shown on the leaderboard) and pays them
-- a small income over time. The pay terminal (MainModule.MainScreenModule)
-- charges washes from leaderstats.Cash.
local Players = game:GetService("Players")

local STARTING_CASH = 10
local PAYCHECK_AMOUNT = 10
local PAYCHECK_INTERVAL = 120 -- seconds

local function setupPlayer(player)
	if player:FindFirstChild("leaderstats") then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = STARTING_CASH
	cash.Parent = leaderstats

	leaderstats.Parent = player

	task.spawn(function()
		while player.Parent == Players do
			task.wait(PAYCHECK_INTERVAL)
			if player.Parent == Players and cash.Parent then
				cash.Value += PAYCHECK_AMOUNT
			end
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
	setupPlayer(player)
end
