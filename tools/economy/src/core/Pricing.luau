--!strict
-- Pricing: fish value, meat yield, per-piece sale values and rod-offer prices.
-- Pure functions over Config; every price is decided here on the server,
-- never taken from a client.

local Config = require(script.Parent.Config)

local Pricing = {}

local function tierOf(tier: any): number
	if type(tier) ~= "number" or tier ~= tier then
		return 1
	end
	return math.clamp(math.floor(tier), 1, 1000)
end

-- Only configured variant names survive; anything else is a normal fish.
function Pricing.variant(v: any): string?
	if type(v) == "string" and Config.Variants[v] then
		return v
	end
	return nil
end

function Pricing.fishValue(tier: any): number
	local t = tierOf(tier)
	local fv = Config.FishValue
	return math.max(1, math.floor(fv.Base * fv.Growth ^ (t - 1) + 0.5))
end

function Pricing.meatYield(tier: any): number
	local t = tierOf(tier)
	for _, band in ipairs(Config.MeatYield) do
		if t <= band.MaxTier then
			return band.Pieces
		end
	end
	return 1
end

function Pricing.saleMultiplier(variant: any): number
	local v = Pricing.variant(variant)
	return if v then Config.Variants[v].Sale else 1
end

-- Total sale value of one whole fish (all its pieces together).
function Pricing.fishSaleValue(tier: any, variant: any): number
	return Pricing.fishValue(tier) * Pricing.saleMultiplier(variant)
end

-- The fish's sale value split across its meat pieces: floor share each, the
-- remainder on the last piece, so the pieces sum to exactly the fish value.
-- `multiplier` (the owner's Meat Price, >= 1; anything else is 1) scales the
-- WHOLE fish's value once, rounded, before the split.
function Pricing.pieceValues(tier: any, variant: any, multiplier: any): { number }
	local total = Pricing.fishSaleValue(tier, variant)
	if type(multiplier) == "number" and multiplier == multiplier and multiplier > 1 and multiplier <= 100 then
		total = math.floor(total * multiplier + 0.5)
	end
	local n = Pricing.meatYield(tier)
	local share = total // n
	local out = table.create(n, share)
	out[n] = total - share * (n - 1)
	return out
end

function Pricing.offerPrice(tier: any, variant: any): number
	local t = tierOf(tier)
	local factor = 0.4
	for _, band in ipairs(Config.OfferPrice.Factors) do
		if t <= band.MaxTier then
			factor = band.Factor
			break
		end
	end
	local v = Pricing.variant(variant)
	local pm = if v then Config.Variants[v].Price else 1
	return math.max(Config.OfferPrice.MinPrice, math.floor(factor * Pricing.fishValue(t) * pm + 0.5))
end

-- Expected profit of buying an offer, if `recapture` (0..1) of bought fish
-- are caught again and sold. A planning number, not a promise.
function Pricing.expectedNet(tier: any, variant: any, recapture: number): number
	return recapture * Pricing.fishSaleValue(tier, variant) - Pricing.offerPrice(tier, variant)
end

return Pricing
