-- Car Wash Simulator: the job / reward / progression layer on top of the
-- tunnel wash (ServerScriptService.CarWash, which it leaves alone apart from
-- reading the LastWashProgram attribute Wash puts on a car as it leaves, and
-- the WashBudget attribute Cash.charge spends: the customer's wash money).
--
--   PlayerData  Cash (leaderstats, from CarWash.Cash), XP, Level, upgrades,
--               stats; saved to a DataStore
--   Jobs        Job Board -> customer car in the Drop-Off lot -> wash ->
--               deliver to Customer Pickup -> reward
--   (here)      remotes and the upgrade shop

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SimConfig = require(ReplicatedStorage:WaitForChild("SimConfig"))

-- Remotes the HUD uses.
local remotes = Instance.new("Folder")
remotes.Name = "SimRemotes"
local function remote(class: string, name: string)
	local r = Instance.new(class)
	r.Name = name
	r.Parent = remotes
	return r
end
local Notify = remote("RemoteEvent", "Notify") -- server -> client: toast text
local Reward = remote("RemoteEvent", "Reward") -- server -> client: job result card
local CancelJob = remote("RemoteEvent", "CancelJob") -- client -> server
local BuyUpgrade = remote("RemoteFunction", "BuyUpgrade") -- client -> server: (id) -> ok, message
remotes.Parent = ReplicatedStorage

local PlayerData = require(script.PlayerData)
local Jobs = require(script.Jobs)

PlayerData.start(Notify)
Jobs.start(Notify, Reward, CancelJob)

---------------------------------------------------------------- shop
local buying: { [Player]: boolean } = {}

BuyUpgrade.OnServerInvoke = function(player: Player, id: unknown)
	if type(id) ~= "string" or buying[player] then
		return false, "Try again"
	end
	local upgrade = SimConfig.upgrade(id)
	if not upgrade or not PlayerData.get(player) then
		return false, "Unknown upgrade"
	end
	buying[player] = true
	local level = PlayerData.upgradeLevel(player, id)
	local ok, message
	-- the shop row shows the price and level, so messages don't repeat them
	if level >= upgrade.max then
		ok, message = false, ""
	else
		local cost = upgrade.cost(level)
		if PlayerData.spendCash(player, cost) then
			PlayerData.setUpgrade(player, id, level + 1)
			ok, message = true, ""
		else
			ok, message = false, "Not enough money yet"
		end
	end
	buying[player] = nil
	return ok, message
end
