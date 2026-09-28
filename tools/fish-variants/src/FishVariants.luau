--!strict
-- FishVariants (ModuleScript in ReplicatedStorage). Pure rules for rare fish
-- variants. No Roblox APIs, so it's tested offline.
--
-- A variant is rolled exactly ONCE, when a new logical fish is created (a
-- FishSpawner spawn or a rod pick), and stored as the "Variant" attribute.
-- Everything downstream only copies it: the aquarium, a release back into the
-- river, the net catch payload, every meat piece, carried and loaded meat, and
-- the sale. Nothing rerolls.
--
-- Money: the economy's meat ledger prices each piece with the variant's
-- sale multiplier (tools/economy Config.Variants, which must use the same
-- names) and pays it once, when the piece sells. saleInfo() below is kept for
-- the pre-economy FishPayout adapter and is not used by the economy.

local FishVariants = {}

export type Def = {
	Chance: number, -- probability for a newly created fish
	Multiplier: number, -- sale value multiplier, applied per meat piece
	Label: string,
	Color: { number }, -- RGB 0-255 for glow/sparkles/label
}

-- Tentative defaults. Mutually exclusive; checked rarest first.
FishVariants.Defs = {
	Gold = { Chance = 0.005, Multiplier = 5, Label = "GOLD", Color = { 255, 205, 60 } },
	Silver = { Chance = 0.02, Multiplier = 2, Label = "SILVER", Color = { 215, 230, 245 } },
} :: { [string]: Def }

FishVariants.Order = { "Gold", "Silver" } -- roll order (rarest first)

-- r is a uniform random number in [0, 1). Returns a variant name or nil
-- (normal fish). Gold: [0, 0.005), Silver: [0.005, 0.025), else normal.
function FishVariants.roll(r: number): string?
	if type(r) ~= "number" or r ~= r then
		return nil
	end
	local edge = 0
	for _, name in ipairs(FishVariants.Order) do
		edge += FishVariants.Defs[name].Chance
		if r < edge then
			return name
		end
	end
	return nil
end

-- Only known variant names survive; anything else becomes nil (normal).
function FishVariants.sanitize(v: any): string?
	if type(v) == "string" and FishVariants.Defs[v] then
		return v
	end
	return nil
end

function FishVariants.multiplier(v: any): number
	local name = FishVariants.sanitize(v)
	return if name then FishVariants.Defs[name].Multiplier else 1
end

-- Optional 4th FishCaught argument: a payload table. Older listeners that
-- take (player, fishName, tier) simply ignore it.
function FishVariants.payload(variant: any, source: string): { Variant: string?, Source: string }
	return { Variant = FishVariants.sanitize(variant), Source = source }
end

-- Reads the variant out of an optional FishCaught payload.
function FishVariants.fromPayload(extra: any): string?
	if type(extra) ~= "table" then
		return nil
	end
	return FishVariants.sanitize(extra.Variant)
end

export type SaleInfo = {
	kind: string, -- "Customer" | "Truck"
	fishName: string?,
	tier: number?,
	variant: string?,
	multiplier: number,
	ownerId: number?, -- player who caught the fish (meat OwnerId)
	sellerId: number?, -- player who delivered it (truck only)
	customer: string?,
}

-- Builds sale metadata from a meat's attributes, read through `get` BEFORE
-- the meat is destroyed.
function FishVariants.saleInfo(get: (string) -> any, kind: string): SaleInfo
	local variant = FishVariants.sanitize(get("Variant"))
	local tier = get("Tier")
	local owner = get("OwnerId")
	local name = get("FromFish")
	return {
		kind = kind,
		fishName = if type(name) == "string" then name else nil,
		tier = if type(tier) == "number" then tier else nil,
		variant = variant,
		multiplier = FishVariants.multiplier(variant),
		ownerId = if type(owner) == "number" then owner else nil,
		sellerId = nil,
		customer = nil,
	}
end

return FishVariants
