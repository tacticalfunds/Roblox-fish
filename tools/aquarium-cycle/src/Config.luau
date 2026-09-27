--!strict
-- Tuning for the dock-rod -> aquarium -> river recycling system.
-- Pure data (no Roblox APIs) so the offline tests can load it. Every number is
-- a tentative design value, not approved balance.

local Config = {}

-- Master feature flag. The system does nothing at all while this is false.
-- It stays false in the repo; an installer flips it only after Astra has
-- reviewed the scene bindings in Studio.
Config.Enabled = false

-- Catch cycle timings (seconds). The server drives these; the client never
-- supplies timing.
Config.BiteSeconds = 2.5 -- after a cast, earliest moment a river fish may be hooked
Config.LiftSeconds = 1.5 -- after a hook, earliest moment the fish may be landed in the tank
Config.CastTimeoutSeconds = 12 -- a cast with no fish hooked by then is cancelled and its slot freed
Config.ReleaseSwimSeconds = 3 -- time a released fish spends swimming from tank back to river

-- Upgrade tables. Each list is indexed by level (1 = starting level); the
-- length of the list is the max level, so values can never run away.
-- Costs[i] is the price to go from level i to i+1 (length = max level - 1).
Config.Upgrades = {
	Capacity = {
		DisplayName = "Tank Capacity",
		Values = { 3, 6, 10, 15 }, -- fish the tank holds
		Costs = { 50, 150, 400 },
	},
	ReleaseRate = {
		DisplayName = "Release Rate",
		Values = { 1, 2, 4, 6 }, -- fish sent back to the river per release
		Costs = { 40, 120, 350 },
	},
}

-- Seconds between releases, independent of level (the batch size above is
-- the throughput upgrade, so there is only one lever for it).
Config.ReleaseCooldownSeconds = 4

return Config
