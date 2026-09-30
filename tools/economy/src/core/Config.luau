--!strict
-- Economy tuning (ModuleScript under ServerScriptService.EconomyService).
-- Pure data, no Roblox APIs, so the offline tests load it directly.
--
-- EVERY number here is a tentative design target, not measured balance. See
-- tools/economy/README.md for the assumptions behind them.

local Config = {}

------------------------------------------------------------ currency

-- One soft currency, shown as leaderstats.Money (the name RodShopServer
-- already looks for). Nothing else creates Money, Cash or a Money attribute.
Config.CurrencyName = "Money"

-- One-time grant for a brand-new player (no saved record at all). Never
-- given on a failed or corrupt load, never given twice. Sized so that after
-- the first tank upgrade (50) there is still working capital for starter
-- rod-fish offers (1-3 each) - see Config.check().
Config.StartingGrant = 100

-- Balances are whole numbers in [0, MaxBalance].
Config.MaxBalance = 1_000_000_000_000

------------------------------------------------------------ saving

Config.DataStoreName = "FishEconomy_v1"
Config.KeyPrefix = "player_"
-- 2: adds the optional `rods` field ({ owned = { [rodId] = true }, equipped
-- = rodId }). v1 records load unchanged (Basic only); every save keeps every
-- field it doesn't manage, and never lowers a newer version number.
Config.SchemaVersion = 2
Config.AutosaveSeconds = 60
-- Session lock: a record locked by another server is not loaded until the
-- lock is older than this (the owning server refreshes it on every save).
Config.LockSeconds = 300
-- Load attempts before a player is marked "load failed" (then retried in
-- the background every LoadRetryEverySeconds while they stay).
Config.LoadAttempts = 3
Config.LoadRetryDelays = { 1, 2, 4 }
Config.LoadRetryEverySeconds = 30
-- Credits earned while a player's money is still loading (or failed to load)
-- are held in memory and applied once the load succeeds; capped, and dropped
-- if they leave before it does (never written over their saved record).
Config.MaxPendingCredit = 1_000_000
-- In Studio play tests with DataStore access disabled, use an in-memory
-- store so the economy can be tried. Never used in a live server.
Config.StudioMemoryStoreFallback = true

------------------------------------------------------------ fish value

-- Whole fish value by tier: round(Base * Growth^(tier - 1)), at least 1.
Config.FishValue = { Base = 4, Growth = 1.3 }

-- Meat pieces per fish. MUST match GrinderProcessor's meatFor(tier):
-- tier <= 5 -> 1, <= 13 -> 2, <= 18 -> 3, else 5. A fish's value is SPLIT
-- across its pieces (never multiplied by them).
Config.MeatYield = {
	{ MaxTier = 5, Pieces = 1 },
	{ MaxTier = 13, Pieces = 2 },
	{ MaxTier = 18, Pieces = 3 },
	{ MaxTier = math.huge, Pieces = 5 },
}

-- Rare variants (names match the fish-variants feature). Sale multiplies the
-- fish value; Price multiplies the rod-offer price, and is kept well below
-- Sale so a rare catch keeps most of its upside.
export type VariantDef = { Sale: number, Price: number }
Config.Variants = {
	Silver = { Sale = 2, Price = 1.25 },
	Gold = { Sale = 5, Price = 1.75 },
} :: { [string]: VariantDef }

------------------------------------------------------------ rod offers

-- Offer price = max(MinPrice, round(Factor * FishValue * variant Price)).
-- Factors are below the expected recapture share so an average bought fish
-- makes a profit IF it is recaptured and sold; nothing guarantees that.
Config.OfferPrice = {
	MinPrice = 1,
	Factors = {
		{ MaxTier = 5, Factor = 0.3 }, -- starter fish: 1-3 Money
		{ MaxTier = math.huge, Factor = 0.4 },
	},
}

Config.Offer = {
	TimeoutSeconds = 20, -- unanswered offers slip off the hook (no charge)
	-- The caster buys at the ROD STAND with a proximity prompt (E / gamepad /
	-- tap). Distances are measured from the stand, never from the fish (the
	-- fish on the line is animated on clients, its server position is stale).
	PromptDistance = 10, -- ProximityPrompt.MaxActivationDistance, studs
	-- The server accepts a Buy up to PromptDistance + ReachSlack from the
	-- stand (movement between the key press and the request arriving).
	ReachSlack = 4,
	-- The prompt anchor sits this far above the stand's lowest point.
	StandHeight = 2.5,
	ActionCooldown = 0.25, -- per player, between Buy/Pass requests
}
-- Attribute on ReplicatedStorage.Economy: set false to switch rod offers off
-- during play (open offers are cancelled, nothing charged; rods go back to
-- the original free rod -> aquarium behaviour, exactly as if not installed).
Config.RodOffersAttribute = "RodOffersEnabled"

------------------------------------------------------------ meat pipeline

Config.Pipeline = {
	MaxStack = 96, -- GrinderProcessor MAX_STACK (objects on the meat stack)
	-- Meat objects allowed in the pit (blender + belt). Beyond this new pieces
	-- are HELD as ledger records (no objects) and re-emitted later.
	MaxPitObjects = 24,
	-- Held records above which the pipeline counts as saturated: the harpoon
	-- skips shots and the net pad refuses lifts (fish stay in the river).
	MaxHeld = 150,
}

------------------------------------------------------------ ownership

-- The shared scene has NO plot owner. Who is paid for a sold piece:
--   * rod fish: the buyer (carried through tank -> river -> net/harpoon)
--   * net catches of river fish: the player who stepped on the pad
--   * harpoon catches: the fish's buyer if it has one, else the player
--     named by HarpoonGun's "OwnerUserId" attribute (set explicitly by a
--     developer), else NOBODY (the piece still sells, nothing is paid)
-- An owner who is not in the server when a piece sells is not paid.
Config.HarpoonOwnerAttribute = "OwnerUserId"

------------------------------------------------------------ rod shop

-- RodShopServer charges through this service. PAID purchases stay closed
-- until the saved-ownership path is validated in Studio with real DataStore
-- access: set true here, or (for a test) the RodShopOpen attribute on
-- ReplicatedStorage.Economy. Equipping a rod you own always works.
Config.RodShopOpen = false

-- The five rods (ReplicatedStorage.Rods, by model name). Owned rods are
-- saved in the player's Money record; one copy each, bought once. BiteWait
-- multiplies the random wait before a bite (lower = faster). Legacy
-- Tier/Title/Price attributes on the rod models are ignored.
-- INITIAL easy-early-game tuning, NOT measured pacing.
Config.Rods = {
	{ Id = "FishingRod1", Key = "Basic", Name = "Basic Rod", Price = 0, BiteWait = 1 },
	{ Id = "FishingRod4", Key = "Tiger", Name = "Tiger Rod", Price = 150, BiteWait = 0.85 },
	{ Id = "FishingRod3", Key = "Coral", Name = "Coral Rod", Price = 600, BiteWait = 0.75 },
	{ Id = "FishingRod2", Key = "Tide", Name = "Tide Rod", Price = 2000, BiteWait = 0.65 },
	{ Id = "FishingRod5", Key = "Magma", Name = "Magma Rod", Price = 7500, BiteWait = 0.55 },
}
-- Every player owns this one (free, never stored as bought) and falls back
-- to it whenever the equipped rod isn't owned or known.
Config.BaseRod = "FishingRod1"
-- Always in stock (early progression is never blocked by a random roll);
-- the other rods keep RodShopServer's per-player restock.
Config.AlwaysStockedRods = { "FishingRod1", "FishingRod4" }
-- Seconds between rod actions (buy / equip) per player.
Config.RodActionCooldown = 0.5

------------------------------------------------------------ net capacity (+5 KG signs)

-- Each player OWNS a net capacity in kg, saved with their Money. The net
-- lift's MaxWeight is the highest capacity among the players in the server
-- (never below the place's own MaxWeight). A +5 KG sign sells the next step.
-- The same saved capacity is sold by both KGsign posts and the upgrade
-- board's Net Strength card.
-- Costs: the list first, then the previous cost x Growth rounded to 5, up
-- to Max (15 -> 60 kg: 10, 25, 50, 100, 150, 225, 340, 510, 765 = 2175).
-- The first step is Config.UpgradeFirstCost like every board upgrade.
-- INITIAL tuning, not measured pacing.
Config.NetKg = {
	Base = 15, -- everyone starts here (the place's NetLift.MaxWeight)
	Step = 5, -- kg per purchase
	Max = 60, -- nothing is sold past this
	Costs = { 10, 25, 50, 100 },
	Growth = 1.5,
}
-- PAID signs stay closed until the saved path is validated in Studio with
-- real DataStore access: set true here, or (for a test) the NetKgOpen
-- attribute on ReplicatedStorage.Economy.
Config.NetKgOpen = false
Config.NetKgCooldown = 0.5 -- seconds between sign presses per player

------------------------------------------------------------ upgrade board (Workspace.Board)

-- Every board upgrade's FIRST step costs this; later steps come from each
-- upgrade's own tuning and never cost more than UpgradeCostCap.
Config.UpgradeFirstCost = 10
Config.UpgradeCostCap = 5000
Config.UpgradeBoardReach = 20 -- studs from the board's face (server check, plus half the board)

-- The board's other upgrades: each player owns a LEVEL per upgrade (0 = not
-- bought), saved in their Money record's `upgrades` table. Values[level + 1]
-- is the effect at that level; Costs[level + 1] is the price of the next
-- level; nothing is sold past the last value. Checked by Config.check:
-- Values[1] = 1 (no effect), Values[2] = FirstValue (what the card promises),
-- increasing, <= MaxValue; Costs[1] = UpgradeFirstCost, increasing, <=
-- UpgradeCostCap, one fewer than Values. INITIAL tuning, not measured pacing.
Config.BoardUpgrades = {
	-- Rod Luck: on the owner's own casts, rarer fish are weighted up relative
	-- to common ones and the odds renormalised. Value = the factor on the
	-- RAREST tier's weight relative to the commonest (tiers between scale
	-- geometrically). 2x is not a guaranteed rare fish. Silver/Gold odds are
	-- not touched.
	RodLuck = { Name = "Rod Luck", Values = { 1, 2, 2.5, 3 }, Costs = { 10, 75, 300 }, FirstValue = 2, MaxValue = 5 },
}
Config.BoardUpgradeIds = { "RodLuck" } -- the order they are listed and checked
-- PAID board upgrades (other than Net Strength, which is NetKgOpen) stay
-- closed until the saved path is validated in Studio with real DataStore
-- access: set true here, or (for a test) the UpgradesOpen attribute on
-- ReplicatedStorage.Economy.
Config.BoardUpgradesOpen = false
Config.BoardUpgradeCooldown = 0.5 -- seconds between presses per player

------------------------------------------------------------ checks

-- Design guard rails, asserted by the tests and by the installer.
function Config.check(firstTankUpgradeCost: number?): (boolean, string?)
	if type(Config.StartingGrant) ~= "number" or Config.StartingGrant < 0 then
		return false, "StartingGrant must be >= 0"
	end
	local first = firstTankUpgradeCost or 50
	-- after the first tank upgrade at least 10 starter offers must be affordable
	local starterPrice = 3
	if Config.StartingGrant - first < 10 * starterPrice then
		return false, "StartingGrant leaves too little working capital after the first tank upgrade"
	end
	for name, def in pairs(Config.Variants) do
		if def.Price >= def.Sale then
			return false, "variant " .. name .. " price multiplier eats its sale multiplier"
		end
	end
	local o = Config.Offer
	if not (o.PromptDistance > 0 and o.PromptDistance <= 30 and o.ReachSlack >= 0 and o.ReachSlack <= 10) then
		return false, "buy prompt distance must be in (0, 30] and slack in [0, 10]"
	end
	for _, band in ipairs(Config.OfferPrice.Factors) do
		if band.Factor <= 0 or band.Factor >= 1 then
			return false, "offer price factor must be in (0, 1)"
		end
	end
	local seen, prev = {}, 1
	for i, rod in ipairs(Config.Rods) do
		if type(rod.Id) ~= "string" or seen[rod.Id] then
			return false, "rod ids must be unique strings"
		end
		seen[rod.Id] = true
		if type(rod.Price) ~= "number" or rod.Price < 0 or rod.Price ~= math.floor(rod.Price) then
			return false, "rod " .. rod.Id .. ": price must be a whole number >= 0"
		end
		if not (type(rod.BiteWait) == "number" and rod.BiteWait > 0 and rod.BiteWait <= 1 and rod.BiteWait <= prev) then
			return false, "rod " .. rod.Id .. ": BiteWait must be in (0, 1] and never worse than the rod before"
		end
		prev = rod.BiteWait
		if (i == 1) ~= (rod.Id == Config.BaseRod) or (i == 1 and rod.Price ~= 0) then
			return false, "the first rod must be the free BaseRod"
		end
	end
	local n = Config.NetKg
	if not (n.Base > 0 and n.Step > 0 and n.Max >= n.Base and (n.Max - n.Base) % n.Step == 0 and n.Growth >= 1 and #n.Costs >= 1) then
		return false, "NetKg: Base / Step / Max / Growth / Costs out of range"
	end
	local last = 0
	for _, c in ipairs(n.Costs) do
		if type(c) ~= "number" or c <= last or c ~= math.floor(c) then
			return false, "NetKg: Costs must be increasing whole numbers"
		end
		last = c
	end
	for _, id in ipairs(Config.BoardUpgradeIds) do
		local u = Config.BoardUpgrades[id]
		if type(u) ~= "table" or type(u.Values) ~= "table" or type(u.Costs) ~= "table" then
			return false, "BoardUpgrades." .. tostring(id) .. " missing"
		end
		if #u.Values < 2 or #u.Costs ~= #u.Values - 1 or u.Values[1] ~= 1 or u.Values[2] ~= u.FirstValue then
			return false, "BoardUpgrades." .. id .. ": Values must start 1, FirstValue with one Cost per step"
		end
		for i = 2, #u.Values do
			if not (type(u.Values[i]) == "number" and u.Values[i] > u.Values[i - 1] and u.Values[i] <= u.MaxValue) then
				return false, "BoardUpgrades." .. id .. ": Values must increase, up to MaxValue"
			end
		end
		if u.Costs[1] ~= Config.UpgradeFirstCost then
			return false, "BoardUpgrades." .. id .. ": the first step must cost UpgradeFirstCost"
		end
		for i, c in ipairs(u.Costs) do
			if not (type(c) == "number" and c == math.floor(c) and c > 0 and c <= Config.UpgradeCostCap and (i == 1 or c > u.Costs[i - 1])) then
				return false, "BoardUpgrades." .. id .. ": Costs must be increasing whole numbers up to UpgradeCostCap"
			end
		end
	end
	if n.Costs[1] ~= Config.UpgradeFirstCost then
		return false, "NetKg: the first step must cost UpgradeFirstCost"
	end
	-- the whole curve (the list, then x Growth rounded to 5) stays under the cap
	local steps = (n.Max - n.Base) / n.Step
	local c = 0
	for i = 1, steps do
		c = if i <= #n.Costs then n.Costs[i] else math.floor(c * n.Growth / 5 + 0.5) * 5
		if c > Config.UpgradeCostCap then
			return false, "NetKg: a step costs more than UpgradeCostCap"
		end
	end
	return true, nil
end

return Config
