-- Every number you'd want to tune for the wash, in one place.

local Config = {}

-- The washes the pay terminal sells. `arches` lists the arch stages the
-- program runs (keys from Wash/Arches); the brushes, blasters and dryers run
-- for every car. Bigger washes crawl slower through the arches (`archSpeed`,
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
		arches = { "Presoak", "HighPressure", "Foam", "Rinse", "ClearCoat", "SpotFree" },
	},
	Full = {
		name = "Full Wash",
		price = 15,
		archSpeed = 0.6,
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
}

Config.Currency = "€"

-- Player money (leaderstats.Cash).
Config.StartingCash = 15
Config.PaycheckAmount = 10
Config.PaycheckInterval = 120 -- seconds

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

return Config
