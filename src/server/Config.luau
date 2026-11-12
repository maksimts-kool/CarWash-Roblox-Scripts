-- Every number you'd want to tune for the wash, in one place.

local Config = {}

-- The washes the pay terminal sells. `arches` lists the arch stages the
-- program runs (keys from Wash/Arches); the wrap-around and rocker brushes,
-- blasters and dryers run for every car. `topBrush` adds the top brush
-- (Wash/TopBrush), which follows the car's roof. Bigger washes crawl slower through the arches (`archSpeed`,
-- studs per second) so each stage gets more time.
Config.Programs = {
	Small = {
		name = "Small Wash",
		price = 5,
		archSpeed = 0.9,
		arches = { "Presoak", "HighPressure", "Foam", "Rinse", "SpotFree" },
	},
	Middle = {
		name = "Middle Wash",
		price = 10,
		archSpeed = 0.75,
		topBrush = true,
		arches = { "Presoak", "HighPressure", "Foam", "Rinse", "ClearCoat", "SpotFree" },
	},
	Full = {
		name = "Full Wash",
		price = 15,
		archSpeed = 0.6,
		topBrush = true,
		arches = { "Presoak", "HighPressure", "Foam", "Rinse", "ClearCoat", "HotWax", "SpotFree" },
	},
}

-- The arch stages in tunnel order, and what the screens call them.
Config.StageOrder = { "Presoak", "HighPressure", "Foam", "Rinse", "ClearCoat", "HotWax", "SpotFree" }
Config.StageNames = {
	Presoak = "Presoak",
	HighPressure = "High Pressure",
	Foam = "Triple Foam",
	Rinse = "Rinse",
	ClearCoat = "Clear Coat",
	HotWax = "Hot Wax",
	SpotFree = "Spot-Free Rinse",
	TopBrush = "Top Brush",
}

-- What the pay terminal lists on each wash's card, in this order: the top
-- brush (only washes with `topBrush`), then the arch stages.
Config.MenuFeatures = { "TopBrush", "Presoak", "HighPressure", "Foam", "Rinse", "ClearCoat", "HotWax", "SpotFree" }

-- What the Wash Time screen calls the first step (the brushes).
Config.BrushStageName = "Brush Wash"
Config.TopBrushStageName = "Top + Brush Wash" -- for washes with `topBrush`

Config.Currency = "€"

-- Player money (leaderstats.Cash). No income over time: it only comes from
-- job rewards, and customers pay for their own washes (see Cash.charge).
Config.StartingCash = 0

-- Conveyor, studs per second.
Config.ConveyorSpeed = 2 -- into the dryers and out through the exit gate
Config.TunnelSpeed = 1.2 -- through the blasters, wrap-arounds and rockers
Config.ConveyorAccel = 1.5 -- how quickly the car eases between speeds
Config.StallSeconds = 12 -- give up on a move if the car makes no progress for this long

-- Wash timeline.
Config.ArrivalTimeout = 45 -- how long a paid customer gets to reach the conveyor
Config.DrySeconds = 60
Config.DefaultCarLength = 14
Config.ArchLead = 1.5 -- an arch starts when the car's nose is this far before it
Config.ArchTrail = 1.5 -- and stops once the car's tail is this far past it

-- Dryers. Each one starts when the car's nose is right under its first air
-- outlet, one after the other, never two at once.
Config.DryerLead = 1 -- studs before the dryer's first outlet the nose has to be
Config.DryerStagger = 1.5 -- seconds between one dryer starting (or stopping) and the next
Config.DryerVolume = 0.8 -- multiplier on the dryer sounds' volume as saved in the place
Config.DryerHearDistance = 70 -- studs; the dryers fade to silence by here
Config.DryerStartupSeconds = 2.5 -- the startup sound is cut short (faded out) after this
Config.DryerStopSeconds = 1.2 -- the hum fades out over this while the stop sound plays
-- The uploaded sounds/dryer_stop.ogg. Set to "" to use a Sound named "Stop" saved
-- in the dryer instead (if there is one).
Config.DryerStopSoundId = "rbxassetid://101218008415689"

-- Gates (target angles, in degrees, of the arm's joint).
Config.GateOpenAngle = -80
Config.GateClosedAngle = 0
Config.EntryGateSettleSeconds = 2 -- after opening, before the car may trigger the wash
Config.ExitGateOpenSeconds = 5

-- The operator's control panel (see ControlPanel).
Config.ControlPanel = {
	-- UserIds that may use it, on top of the place's owner (or, for a group
	-- place, the group's owner rank).
	Admins = {} :: { number },
	-- In Studio play tests everyone is an admin (test players have made-up ids).
	AdminsInStudio = true,
	LogLength = 40, -- log lines kept
}

-- Car condition (see CarCondition). Every car carries Dirt / Soap / Wet /
-- Shine, 0..1 each, per section of the car from nose to tail.
Config.Condition = {
	Segments = 6, -- sections along the car; a machine only works on the ones under it
	StartDirt = { 0.45, 0.8 }, -- a car spawns with random dirt in this range (unless it has a Dirt attribute)
	DirtPerStud = 0.0004, -- dirt picked up per stud driven outside the wash
	WetDirtMultiplier = 1.6, -- a wet car picks dirt up this much faster
	ShineLossPerDirt = 1.5, -- shine lost per unit of dirt picked up
	AirDryPerSecond = 0.012, -- water evaporating by itself (faster while driving)
	SoapRunoffPerSecond = 0.02, -- soap running off a wet car by itself
}

-- What each machine does to a section of the car, per second, while that
-- section is under it (each section spends roughly 5-10 s under a machine).
-- Keys add that much, or with a minus remove it. Only the presoak and the
-- triple foam put soap on; the brushes just wet and scrub.
Config.ConditionEffects = {
	Blasters = { wet = 0.15, dirt = -0.01 },
	Wraps = { wet = 0.12, dirt = -0.02 },
	TopBrush = { wet = 0.1, dirt = -0.02 },
	Rockers = { wet = 0.1, dirt = -0.012 },
	Presoak = { wet = 0.3, soap = 0.06, dirt = -0.02 },
	HighPressure = { wet = 0.3, soap = -0.08, dirt = -0.04 },
	Foam = { wet = 0.1, soap = 0.2 },
	Rinse = { wet = 0.3, soap = -0.2, dirt = -0.02 },
	ClearCoat = { wet = 0.2, soap = -0.1, shine = 0.04 },
	HotWax = { wet = 0.1, shine = 0.06 },
	SpotFree = { wet = 0.3, soap = -0.3, shine = 0.015 },
	Dryers = { wet = -0.025, soap = -0.01 },
}

-- How far either side of a brush or arch it reaches the car, in studs.
Config.ConditionReach = {
	Wraps = 3,
	Arch = 2,
}

return Config
