-- Everything the simulator remembers about a player, saved to a DataStore.
--
-- Cash lives in leaderstats.Cash, which CarWash.Cash creates; this module
-- loads the saved amount into it. The rest is mirrored onto player attributes
-- for the HUD:
--   Level, XP, XPNext, Rating (average stars), Jobs, Upg_<id>, DataLoaded

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local PlayerData = {}

type Profile = {
	XP: number,
	Level: number,
	Upgrades: { [string]: number },
	Stats: { Jobs: number, StarSum: number, Perfect: number, Earned: number },
	canSave: boolean,
}

local profiles: { [Player]: Profile } = {}
local notify: RemoteEvent

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("Simulator: no DataStore, progress won't be saved:", result)
	end
end

local function key(player: Player): string
	return "u" .. player.UserId
end

local function cashValue(player: Player): IntValue?
	local leaderstats = player:WaitForChild("leaderstats", 10)
	return leaderstats and leaderstats:WaitForChild("Cash", 10) :: IntValue?
end

local function mirror(player: Player, p: Profile)
	player:SetAttribute("Level", p.Level)
	player:SetAttribute("XP", p.XP)
	player:SetAttribute("XPNext", Config.xpToNext(p.Level))
	player:SetAttribute("Jobs", p.Stats.Jobs)
	player:SetAttribute("Rating", if p.Stats.Jobs > 0 then p.Stats.StarSum / p.Stats.Jobs else 0)
	for _, upgrade in Config.Upgrades do
		player:SetAttribute("Upg_" .. upgrade.id, p.Upgrades[upgrade.id] or 0)
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local level = leaderstats and leaderstats:FindFirstChild("Level")
	if level then
		(level :: IntValue).Value = p.Level
	end
end

local function load(player: Player)
	local saved = nil
	local canSave = store ~= nil
	if store then
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if ok then
			saved = result
		else
			-- don't overwrite a save we couldn't read
			canSave = false
			warn("Simulator: couldn't load data for", player.Name, result)
		end
	end
	if player.Parent ~= Players then
		return
	end

	local p: Profile = {
		XP = 0,
		Level = 1,
		Upgrades = {},
		Stats = { Jobs = 0, StarSum = 0, Perfect = 0, Earned = 0 },
		canSave = canSave,
	}
	if type(saved) == "table" then
		p.XP = tonumber(saved.XP) or 0
		p.Level = math.max(1, tonumber(saved.Level) or 1)
		if type(saved.Upgrades) == "table" then
			for id, level in saved.Upgrades do
				p.Upgrades[id] = tonumber(level) or 0
			end
		end
		if type(saved.Stats) == "table" then
			for k in p.Stats do
				p.Stats[k] = tonumber(saved.Stats[k]) or 0
			end
		end
	end

	local cash = cashValue(player)
	if cash and type(saved) == "table" and tonumber(saved.Cash) then
		cash.Value = tonumber(saved.Cash) :: number
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats and not leaderstats:FindFirstChild("Level") then
		local level = Instance.new("IntValue")
		level.Name = "Level"
		level.Parent = leaderstats
	end

	profiles[player] = p
	mirror(player, p)
	player:SetAttribute("DataLoaded", true)

	if saved == nil then
		notify:FireClient(player, "Welcome to SUDS STATION! Aunt Rosa left you her car wash.", "story")
	else
		notify:FireClient(player, "Welcome back!", "info")
	end
end

local function save(player: Player)
	local p = profiles[player]
	if not p or not p.canSave or not store then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash")
	local data = {
		Cash = if cash then (cash :: IntValue).Value else 0,
		XP = p.XP,
		Level = p.Level,
		Upgrades = p.Upgrades,
		Stats = p.Stats,
	}
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(key(player), data, { player.UserId })
	end)
	if not ok then
		warn("Simulator: couldn't save data for", player.Name, err)
	end
end

function PlayerData.get(player: Player): Profile?
	return profiles[player]
end

function PlayerData.cash(player: Player): number
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash")
	return if cash then (cash :: IntValue).Value else 0
end

function PlayerData.addCash(player: Player, amount: number)
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash")
	if cash then
		(cash :: IntValue).Value += amount
	end
end

function PlayerData.spendCash(player: Player, amount: number): boolean
	local leaderstats = player:FindFirstChild("leaderstats")
	local cash = leaderstats and leaderstats:FindFirstChild("Cash") :: IntValue?
	if not cash or cash.Value < amount then
		return false
	end
	cash.Value -= amount
	return true
end

-- Adds XP; returns the new level if the player levelled up.
function PlayerData.addXP(player: Player, amount: number): number?
	local p = profiles[player]
	if not p then
		return nil
	end
	p.XP += amount
	local levelled = nil
	while p.XP >= Config.xpToNext(p.Level) do
		p.XP -= Config.xpToNext(p.Level)
		p.Level += 1
		levelled = p.Level
	end
	mirror(player, p)
	return levelled
end

function PlayerData.recordJob(player: Player, stars: number, earned: number)
	local p = profiles[player]
	if not p then
		return
	end
	p.Stats.Jobs += 1
	p.Stats.StarSum += stars
	p.Stats.Earned += earned
	if stars >= 5 then
		p.Stats.Perfect += 1
	end
	mirror(player, p)
end

function PlayerData.upgradeLevel(player: Player, id: string): number
	local p = profiles[player]
	return if p then p.Upgrades[id] or 0 else 0
end

function PlayerData.setUpgrade(player: Player, id: string, level: number)
	local p = profiles[player]
	if p then
		p.Upgrades[id] = level
		mirror(player, p)
	end
end

function PlayerData.start(notifyRemote: RemoteEvent)
	notify = notifyRemote
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 20
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for _, player in Players:GetPlayers() do
				task.spawn(save, player)
			end
		end
	end)
end

return PlayerData
