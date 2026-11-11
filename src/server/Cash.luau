-- Gives every player a Cash balance (shown on the leaderboard) and pays them a
-- small income over time. The pay terminal (Kiosk) charges washes from it.

local Players = game:GetService("Players")

local Config = require(script.Parent.Config)

local Cash = {}

local function setupPlayer(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = Config.StartingCash
	cash.Parent = leaderstats

	leaderstats.Parent = player

	task.spawn(function()
		while player.Parent == Players do
			task.wait(Config.PaycheckInterval)
			if player.Parent == Players and cash.Parent then
				cash.Value += Config.PaycheckAmount
			end
		end
	end)
end

-- Takes `price` from the player's Cash. Returns false if they can't afford it.
function Cash.charge(player: Player, price: number): boolean
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash")
	if not cash or cash.Value < price then
		return false
	end
	cash.Value -= price
	return true
end

function Cash.start()
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
end

return Cash
