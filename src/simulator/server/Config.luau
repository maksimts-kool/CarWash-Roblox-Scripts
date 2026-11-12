-- Car Wash Simulator: every tunable number for the job / reward / progression
-- layer. Server only, like ServerScriptService.CarWash.Config: the HUD gets
-- what it shows (currency, icons, wash names, upgrades and their prices) from
-- the "Shared" attribute the Simulator script puts on ReplicatedStorage.SimRemotes.
--
-- Loop: take a job at the Job Board -> a customer's dirty car appears in the
-- Drop-Off lot and the customer hands over the money for their wash (it can
-- only buy the wash, it isn't yours) -> pay at the kiosk, run it through the wash ->
-- deliver it to Customer Pickup -> get paid (base + tip by cleanliness), XP,
-- rating. Spend cash on upgrades; levels unlock fancier customers.

local Config = {}

Config.Currency = "€"

-- Icons8 "Fluency" icons (icons8.com), uploaded as images. Upgrades use the
-- icon with their id.
Config.Icons = {
	Cash = "rbxassetid://123378557908445",
	Level = "rbxassetid://82832719106232",
	Star = "rbxassetid://83710378057446",
	Upgrades = "rbxassetid://105815263383367",
	JobBoard = "rbxassetid://107911268026055",
	Car = "rbxassetid://117507131556939",
	Kiosk = "rbxassetid://99217328365940",
	CarWash = "rbxassetid://122926420040014",
	Pickup = "rbxassetid://120135818710261",
	Timer = "rbxassetid://97858446076580",
	Check = "rbxassetid://114511196963191",
	Close = "rbxassetid://81828433879296",
	Arrow = "rbxassetid://118962382274637",
	Crown = "rbxassetid://115974109064049",
	Tip = "rbxassetid://123887853586694",
	XP = "rbxassetid://94984182890858",
	Party = "rbxassetid://130795228054838",
	Shine = "rbxassetid://135571824432447",
	PremiumSoap = "rbxassetid://126213818844579",
	TipJar = "rbxassetid://85126589646692",
	LoyaltyCard = "rbxassetid://115360307454420", -- not used right now
	DetailKit = "rbxassetid://135571824432447", -- same sparkles as Shine
	Billboard = "rbxassetid://89909576505023",
	Info = "rbxassetid://134112785711806",
	Warning = "rbxassetid://116817217096927",
	Story = "rbxassetid://90203129028678",
	Customer = "rbxassetid://87982608943466",
}
Config.DataStoreName = "CarWashSim_v1"
Config.AutosaveSeconds = 90

-- Wash programs (keys of the wash's Config.Programs), cheapest first.
Config.ProgramRank = { Small = 1, Middle = 2, Full = 3 }
Config.ProgramNames = { Small = "Small Wash", Middle = "Middle Wash", Full = "Full Wash" }

-- Customer cars. `car` is a model in ServerStorage.SimCars. A customer asks
-- for one of `wants` (picked at random) and pays `pay` before tips.
Config.Customers = {
	{ car = "Myvi", carName = "Perodua Myvi", unlock = 1, pay = 30, xp = 25, wants = { "Small", "Small", "Middle" } },
	{ car = "Model3", carName = "Tesla Model 3", unlock = 2, pay = 50, xp = 35, wants = { "Small", "Middle", "Middle" } },
	{ car = "Sedan", carName = "Tesla Model S", unlock = 4, pay = 65, xp = 45, wants = { "Middle", "Middle", "Full" } },
	{ car = "Highland", carName = "Tesla Model 3 Highland", unlock = 6, pay = 85, xp = 60, wants = { "Middle", "Full" } },
	{ car = "Roadster", carName = "Tesla Roadster", unlock = 9, pay = 140, xp = 90, wants = { "Full" } },
}

Config.CustomerNames = {
	"Gus", "Marta", "Dr. Lin", "Coach Ray", "Ms. Patel", "Big Tony", "Elena", "Kofi",
	"Yuki", "Sven", "Aunt Rosa", "Mayor Bell", "Priya", "Old Man Jenkins", "Lola", "Mateo",
}
Config.CustomerLines = {
	"Took it off-road. Don't ask.",
	"The kids had a mud party in it.",
	"Got a date tonight, make it shine!",
	"It's been raining for a week straight.",
	"A flock of seagulls. Enough said.",
	"Parked under a tree. Big mistake.",
	"Drove past the GrimeCo plant again...",
}

-- A VIP pays this much more, but only tips for 4+ stars.
Config.VipChanceBase = 0.05
Config.VipPayMultiplier = 2

Config.StartDirt = { 0.7, 0.95 } -- customer cars arrive this dirty
Config.JobTimeoutSeconds = 15 * 60 -- an unfinished job is cancelled after this
Config.DeliverMaxSpeed = 4 -- studs/s: the car must be (almost) stopped on the pad

-- Rating: 0..100 score from how clean the car comes back.
--   (1 - dirt) * 70 + shine * 20 + 10 if it's dry and rinsed
Config.StarThresholds = { 90, 75, 55, 35 } -- score for 5, 4, 3, 2 stars (else 1)
Config.TipPerStar = 0.15 -- tip = pay * TipPerStar * (stars - 2), 3+ stars only
Config.ShowroomBonus = 0.25 -- extra tip for "Showroom Shine"
Config.WrongProgramStars = 1 -- stars lost for a cheaper wash than they asked for
Config.LevelPayBonus = 0.03 -- +3% pay per level above 1
Config.DetailKitScore = 4 -- cleanliness score per Detail Kit level

-- XP needed to go from `level` to `level + 1`.
function Config.xpToNext(level: number): number
	return math.floor(80 * level ^ 1.35)
end

-- Upgrades bought at the Upgrades shop. cost(level) is the price of the next level.
Config.Upgrades = {
	{
		id = "PremiumSoap",
		name = "Premium Soap",
		desc = "+10% base pay per level",
		max = 5,
		cost = function(level) return math.floor(120 * 1.9 ^ level) end,
	},
	{
		id = "TipJar",
		name = "Tip Jar",
		desc = "+15% tips per level",
		max = 5,
		cost = function(level) return math.floor(90 * 1.8 ^ level) end,
	},
	{
		id = "DetailKit",
		name = "Detail Kit",
		desc = "+4 cleanliness score per level",
		max = 5,
		cost = function(level) return math.floor(100 * 2 ^ level) end,
	},
	{
		id = "Billboard",
		name = "Billboard Ads",
		desc = "+8% VIP customer chance per level",
		max = 4,
		cost = function(level) return math.floor(250 * 2.1 ^ level) end,
	},
}

function Config.upgrade(id: string)
	for _, u in Config.Upgrades do
		if u.id == id then
			return u
		end
	end
	return nil
end

-- What the HUD needs to know, as plain data (no functions): published as
-- JSON on ReplicatedStorage.SimRemotes' "Shared" attribute.
function Config.shared()
	local upgrades = {}
	for _, upgrade in Config.Upgrades do
		local costs = {}
		for level = 0, upgrade.max - 1 do
			costs[level + 1] = upgrade.cost(level)
		end
		table.insert(upgrades, {
			id = upgrade.id,
			name = upgrade.name,
			desc = upgrade.desc,
			max = upgrade.max,
			costs = costs, -- costs[level + 1] is the price of the next level
		})
	end
	return {
		Currency = Config.Currency,
		Icons = Config.Icons,
		ProgramNames = Config.ProgramNames,
		Upgrades = upgrades,
	}
end

return Config
