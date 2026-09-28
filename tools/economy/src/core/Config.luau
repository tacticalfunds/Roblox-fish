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
Config.SchemaVersion = 1
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
	TimeoutSeconds = 20, -- unanswered offers are passed automatically
	-- Server-side range check: the buyer's character must be within this many
	-- studs of the fish on the line. The button accepts presses from 80 studs,
	-- so this keeps buying to the dock area; tune after measuring in Studio.
	MaxBuyDistance = 100,
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

-- RodShopServer charges through this service. Rod ownership is not yet
-- linked to rod stats or saved, so the shop stays closed until that exists.
Config.RodShopOpen = false

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
	for _, band in ipairs(Config.OfferPrice.Factors) do
		if band.Factor <= 0 or band.Factor >= 1 then
			return false, "offer price factor must be in (0, 1)"
		end
	end
	return true, nil
end

return Config
