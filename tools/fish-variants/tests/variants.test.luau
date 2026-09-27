-- Offline pure-logic tests for tools/fish-variants/src/FishVariants.luau.
--   luau tools/fish-variants/tests/variants.test.luau
-- Not Roblox runtime tests.

local FishVariants = require("../src/FishVariants")

local failures, passes = 0, 0
local function check(name: string, cond: any)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. name)
	end
end

-- Roll boundaries: Gold [0, .005), Silver [.005, .025), normal otherwise.
check("roll 0 is Gold", FishVariants.roll(0) == "Gold")
check("roll just under gold edge", FishVariants.roll(0.0049) == "Gold")
check("roll at gold edge is Silver", FishVariants.roll(0.005) == "Silver")
check("roll just under silver edge", FishVariants.roll(0.0249) == "Silver")
check("roll at silver edge is normal", FishVariants.roll(0.025) == nil)
check("roll high is normal", FishVariants.roll(0.99) == nil)
check("roll NaN is normal", FishVariants.roll(0 / 0) == nil)
check("roll junk is normal", FishVariants.roll("x" :: any) == nil)

-- Rates over many rolls.
do
	math.randomseed(42)
	local n, gold, silver = 400000, 0, 0
	for _ = 1, n do
		local v = FishVariants.roll(math.random())
		if v == "Gold" then
			gold += 1
		elseif v == "Silver" then
			silver += 1
		end
	end
	print(string.format("rates: gold %.3f%%, silver %.3f%%", gold / n * 100, silver / n * 100))
	check("gold ~0.5%", math.abs(gold / n - 0.005) < 0.0006)
	check("silver ~2%", math.abs(silver / n - 0.02) < 0.0012)
end

-- Sanitize / multiplier.
check("sanitize keeps known", FishVariants.sanitize("Silver") == "Silver")
check("sanitize drops unknown", FishVariants.sanitize("Diamond") == nil)
check("sanitize drops non-string", FishVariants.sanitize(5) == nil)
check("multiplier normal 1", FishVariants.multiplier(nil) == 1)
check("multiplier silver 2", FishVariants.multiplier("Silver") == 2)
check("multiplier gold 5", FishVariants.multiplier("Gold") == 5)
check("multiplier unknown 1", FishVariants.multiplier("gold") == 1)

-- FishCaught payload round trip, backwards compatible.
do
	local p = FishVariants.payload("Gold", "Net")
	check("payload carries variant and source", p.Variant == "Gold" and p.Source == "Net")
	check("payload round trip", FishVariants.fromPayload(p) == "Gold")
	check("no payload = normal", FishVariants.fromPayload(nil) == nil)
	check("bad payload = normal", FishVariants.fromPayload("Gold") == nil)
	check("payload sanitizes", FishVariants.payload("Hacked", "Rod").Variant == nil)
end

-- Sale info read from meat attributes (before the meat is destroyed).
do
	local attrs = { Variant = "Silver", Tier = 7, OwnerId = 123, FromFish = "Cod" }
	local info = FishVariants.saleInfo(function(k)
		return attrs[k]
	end, "Customer")
	check("sale kind", info.kind == "Customer")
	check("sale fields", info.fishName == "Cod" and info.tier == 7 and info.ownerId == 123)
	check("sale variant + multiplier", info.variant == "Silver" and info.multiplier == 2)
	local plain = FishVariants.saleInfo(function()
		return nil
	end, "Truck")
	check("sale from plain meat", plain.variant == nil and plain.multiplier == 1 and plain.tier == nil)
	local junk = FishVariants.saleInfo(function(k)
		return if k == "Variant" then "Gold!!" elseif k == "Tier" then "high" else 5
	end, "Truck")
	check("junk attributes sanitized", junk.variant == nil and junk.tier == nil and junk.fishName == nil)
end

-- Rewards scale coherently: each meat piece carries the multiplier, so a
-- fish's total value is pieces * base * multiplier (GrinderProcessor meatFor).
do
	local function meatFor(tier)
		if tier <= 5 then
			return 1
		elseif tier <= 13 then
			return 2
		elseif tier <= 18 then
			return 3
		end
		return 5
	end
	local base = 10
	for _, tier in ipairs({ 1, 9, 16, 20 }) do
		local pieces = meatFor(tier)
		local normal = pieces * base * FishVariants.multiplier(nil)
		local gold = pieces * base * FishVariants.multiplier("Gold")
		check("gold fish worth 5x at tier " .. tier, gold == 5 * normal)
	end
end

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("fish-variants tests failed")
end
