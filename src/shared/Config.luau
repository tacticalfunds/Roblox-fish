--!strict
-- Central tuning table for the Fish Tycoon prototype.
-- Pure data: no Roblox services, safe to require from server, client and the
-- offline logic tests. Times are seconds, distances are studs, money is whole
-- coins.

local Config = {}

-- Name of the scene folder built by src/setup/BuildPrototypeScene. Runtime code
-- only ever looks inside this folder; it never touches other Workspace content
-- (including Workspace.FishGrinder).
Config.SceneFolderName = "FishTycoonPrototype"
Config.RemotesFolderName = "FishTycoonRemotes"

-- Move each character onto its assigned plot's SpawnPoint when it spawns.
Config.TeleportToPlotOnSpawn = true

Config.StartingMoney = 0

Config.Fish = {
	PerPlot = 18, -- target number of swimming fish per plot
	SchoolSize = 6, -- fish spawn in schools of this size
	RespawnSeconds = 1.5, -- one missing fish is respawned every interval
	SchoolSpeed = 5, -- studs/second the school centre travels
	SchoolSpread = 3.5, -- max offset of a fish from its school centre
	Depth = 0.35, -- how far below the water surface fish swim
	TickRate = 15, -- server simulation steps per second
}

-- The net is anchored to a fixed dock marker (NetAnchor). The player steers the
-- outer tip; the enclosure is the circular sector (the "bag") between the
-- anchor and the swept arc, radius fixed at cast time. See src/server/Net.luau
-- for the full state machine and the geometry proof behind the clamp order.
Config.Net = {
	AnchorReach = 7, -- studs from NetAnchor the character must stand within to cast
	SweepLeash = 21, -- studs from NetAnchor the character may wander while sweeping/hauling before it auto-finishes
	MaxSpeed = 24, -- studs/second the tip may travel; faster input is clamped
	DeploySeconds = 0.4, -- timed "net drops into the water" delay before sweeping is allowed
	HaulSeconds = 1.1, -- timed "bag closes and is pulled in" delay before unloading
	MaxSweepDegrees = 324, -- the sector may not wrap past this; keeps the bag an open shape, not a full circle
	SweepDeadzoneDegrees = 4, -- angular jitter under this is ignored (does not flip sweep direction or reverse the sector)
	CatchTolerance = 1.5, -- extra studs of sector radius allowed for latency when verifying claims
	ReturnReach = 7, -- studs from NetReturn (beside the grinder) the character must stand within to auto-unload into the hopper
}

Config.Grinder = {
	PortionsPerFish = 1,
}

Config.Stations = {
	PollInterval = 0.1, -- how often the server checks which pad each owner stands on
	TransferInterval = 0.15, -- seconds per item moved while standing on a pad
	PadHeight = 8, -- a character counts as "on" a pad up to this far above it
	PadMargin = 0.5,
}

Config.Customers = {
	MaxQueue = 3,
	SpawnIntervalMin = 6,
	SpawnIntervalMax = 12,
	OrderSizeMin = 1,
	OrderSizeMax = 4,
	PatienceSeconds = 50,
	PricePerPortion = 6,
	CompletionBonus = 4, -- extra coins for a fully served order
}

-- Upgrade curves. Level 1 is the starting level.
-- Cost to go from level L to L+1 = floor(BaseCost * CostGrowth^(L-1)).
Config.Upgrades = {
	Net = {
		DisplayName = "Net",
		MaxLevel = 6,
		BaseCost = 20,
		CostGrowth = 1.8,
	},
	Carry = {
		DisplayName = "Carry",
		MaxLevel = 6,
		BaseCost = 25,
		CostGrowth = 1.8,
	},
	Processing = {
		DisplayName = "Grinder",
		MaxLevel = 6,
		BaseCost = 30,
		CostGrowth = 1.9,
	},
}

-- Stat curves. Linear: Base + PerLevel * (level - 1).
-- Geometric: max(Min, Base * Multiplier^(level - 1)).
Config.Stats = {
	NetRadius = { Upgrade = "Net", Kind = "Linear", Base = 3, PerLevel = 0.75 },
	NetCapacity = { Upgrade = "Net", Kind = "Linear", Base = 4, PerLevel = 2 },
	CarryCapacity = { Upgrade = "Carry", Kind = "Linear", Base = 8, PerLevel = 4 },
	ProcessSeconds = { Upgrade = "Processing", Kind = "Geometric", Base = 1.6, Multiplier = 0.8, Min = 0.35 },
	GrinderStorage = { Upgrade = "Processing", Kind = "Linear", Base = 20, PerLevel = 10 },
}

Config.RateLimits = {
	-- Token buckets: Rate tokens per second, Burst max stored tokens.
	NetStart = { Rate = 3, Burst = 3 },
	NetMove = { Rate = 30, Burst = 10 },
	NetClaim = { Rate = 15, Burst = 6 },
	NetHaul = { Rate = 3, Burst = 3 },
}

Config.MaxClaimIdsPerCall = 24

Config.Camera = {
	Height = 42,
	Back = 34,
	LookAhead = -10, -- look this far past the character towards the water
	FieldOfView = 50,
}

Config.Visual = {
	MaxStackParts = 40, -- the carried stack shows at most this many blocks
	StackItemHeight = 0.55,
}

return Config
