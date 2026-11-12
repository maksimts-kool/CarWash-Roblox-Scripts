-- Gives every player a Cash balance (shown on the leaderboard). There is no
-- income over time: Cash only comes from job rewards (ServerScriptService.Simulator).
-- The pay terminal (Kiosk) charges washes through Cash.charge.

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
end

-- Pays `price` for a wash. Returns false if it can't be paid.
--
-- A customer's wash money (the "WashBudget" attribute the simulator puts on a
-- player with a job) pays first. It isn't the player's money: it only ever
-- buys the wash, and what's left goes back to the customer when the job ends.
-- Only a bigger wash than the customer paid for comes out of the player's Cash.
function Cash.charge(player: Player, price: number): boolean
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash")

	local budget = player:GetAttribute("WashBudget")
	local fromBudget = if type(budget) == "number" then math.clamp(budget, 0, price) else 0
	local fromCash = price - fromBudget
	if fromCash > 0 and (not cash or cash.Value < fromCash) then
		return false
	end
	if fromBudget > 0 then
		player:SetAttribute("WashBudget", (budget :: number) - fromBudget)
	end
	if fromCash > 0 then
		cash.Value -= fromCash
	end
	return true
end

function Cash.start()
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
end

return Cash
