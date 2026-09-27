--!strict
-- Tuning for the dock-rod -> aquarium -> river recycling system.
-- Pure data (no Roblox APIs) so the offline tests can load it. Every number is
-- a tentative design value, not approved balance.

local Config = {}

-- Master feature flag. The system does nothing while this is false AND the
-- installed ReplicatedStorage.AquariumCycle folder's "Enabled" attribute is
-- not true. The installer sets that attribute; untick it in Studio to fall
-- back to the original rod -> grinder behaviour without uninstalling.
Config.Enabled = false

-- Catch cycle timings (seconds). The server drives these; the client never
-- supplies timing.
Config.BiteSeconds = 2.5 -- after a cast, earliest moment a river fish may be hooked
Config.LiftSeconds = 1.5 -- after a hook, earliest moment the fish may be landed in the tank
-- Safety net only: a cast with no fish hooked by then is cancelled and its
-- slot freed. The live RodFishingSystem hooks at most ~11 s after reserving
-- (0.6 s stagger + 0.55 s cast + up to 9 s wait + 0.6 s bite), so this is
-- well above the normal path.
Config.CastTimeoutSeconds = 30
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

-- Shared-scene integration (live place: one tank, five shared rods, one
-- button). There is exactly one tank owner, so capacity is never multiplied
-- per player.
Config.Scene = {
	OwnerKey = "SharedTank",
	FolderName = "AquariumCycle", -- ReplicatedStorage folder installed by the installer
	RuntimeFolderName = "AquariumCycleRuntime", -- Workspace folder created at runtime only
	StepInterval = 0.1, -- server timer resolution
	PromptDistance = 12,
	PromptSlack = 6, -- extra studs allowed on the server-side distance check
	PlayerActionCooldown = 0.5,
	TitleText = "Fish in tank", -- replaces the bound "Fish available" label at runtime
	-- Hide the placeholder "E / NEW CAR / PLACE CAR" prompt while running (its
	-- count BillboardGui is kept). Set false if hiding it also hides the count.
	HidePlaceholderPrompt = true,
	FullColor = { 235, 70, 60 }, -- Amount label colour while no slot is free
	ToTankSeconds = 1.3, -- server arc from the rod line into the tank
	ToTankArcHeight = 12,
	TankFishSize = 2.6, -- longest side of a fish swimming in the tank (client)
	TankMargin = 2, -- studs kept clear of the tank walls (client)
	RiverSpeed = { 4, 6.5 }, -- matches FishSpawner SPEED
	RiverSeedBase = 1000000, -- keeps released fish seeds apart from FishSpawner's 1..N
}

return Config
