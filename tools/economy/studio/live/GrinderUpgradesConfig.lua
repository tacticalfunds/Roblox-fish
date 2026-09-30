-- Grinder upgrades: the belt conveyor + blender blade tiers.
-- Shared by GrinderUpgradesServer, GrinderUpgradesClient and EconomyService (sale multiplier).
local C = {}

C.ConveyorPrice = 4000

-- Blade tiers in order. Model = ReplicatedStorage.Blades[Model].
-- Mult multiplies the Money paid for the owner's meat when it sells.
C.Blades = {
	{ Name = "Common",    Model = "BladeCommon",    Price = 0,          Mult = 1 },
	{ Name = "Uncommon",  Model = "BladeUncommon",  Price = 4000,       Mult = 1.25 },
	{ Name = "Rare",      Model = "BladeRare",      Price = 15000,      Mult = 1.5 },
	{ Name = "Epic",      Model = "BladeEpic",      Price = 50000,      Mult = 2 },
	{ Name = "Legendary", Model = "BladeLegendary", Price = 150000,     Mult = 2.5 },
	{ Name = "Mythical",  Model = "BladeMythical",  Price = 500000,     Mult = 3.5 },
	{ Name = "Divine",    Model = "BladeDivine",    Price = 1500000,    Mult = 5 },
	{ Name = "Galactic",  Model = "BladeGalactic",  Price = 5000000,    Mult = 7 },
	{ Name = "Secret",    Model = "BladeSecret",    Price = 15000000,   Mult = 10 },
}

function C.blade(tier)
	tier = math.clamp(math.floor(tonumber(tier) or 1), 1, #C.Blades)
	return C.Blades[tier], tier
end

function C.mult(tier)
	return (C.blade(tier)).Mult
end

-- Net capacity: each buy at a KG sign adds Step kg to YOUR net limit.
-- Base is the NetLift model's MaxWeight attribute. Price of buy #n (0-based):
-- BasePrice * Growth^n, rounded to 2 significant digits.
C.Kg = { Step = 5, BasePrice = 100, Growth = 1.35 }

function C.kgPrice(buys)
	local raw = C.Kg.BasePrice * C.Kg.Growth ^ (buys or 0)
	local mag = 10 ^ math.max(0, math.floor(math.log10(raw)) - 1)
	return math.floor(raw / mag + 0.5) * mag
end

function C.netMax(baseKg, buys)
	return baseKg + C.Kg.Step * (buys or 0)
end

function C.short(n)
	if n >= 1e9 then return string.format("$%gB", math.floor(n / 1e7) / 100) end
	if n >= 1e6 then return string.format("$%gM", math.floor(n / 1e4) / 100) end
	if n >= 1e3 then return string.format("$%gK", math.floor(n / 10) / 100) end
	return "$" .. tostring(n)
end

return C
