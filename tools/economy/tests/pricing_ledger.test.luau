-- Offline tests: pricing rules and the meat ledger (settle once, holding,
-- ownership, variants). Run via run_tests.py. Not Roblox runtime tests.

local Config = require("../src/Config")
local Pricing = require("../src/Pricing")
local Ledger = require("../src/Ledger")

-- seeded generator (the Luau CLI has no Roblox Random)
local function makeRng(seed: number)
	local s = seed
	local r = {}
	function r:NextNumber(): number
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
	function r:NextInteger(a: number, b: number): number
		return a + math.floor(self:NextNumber() * (b - a + 1))
	end
	return r
end

local failures, passes = 0, 0
local function check(name: string, cond: any)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. name)
	end
end

------------------------------------------------------------ pricing

check("config guard rails hold", (Config.check(50)))
check("tier 1 worth 4", Pricing.fishValue(1) == 4)
check("tier 5 worth 11", Pricing.fishValue(5) == 11)
check("tier 6 worth 15", Pricing.fishValue(6) == 15)
check("tier 10 worth 42", Pricing.fishValue(10) == 42)
check("tier 14 worth 121", Pricing.fishValue(14) == 121)
check("tier 19 worth 450", Pricing.fishValue(19) == 450)
check(
	"bad tier treated as tier 1",
	Pricing.fishValue(nil) == 4 and Pricing.fishValue(0 / 0) == 4 and Pricing.fishValue(-3) == 4
)

-- Yield bands must equal GrinderProcessor.meatFor
local function meatFor(tier)
	tier = tier or 1
	if tier <= 5 then
		return 1
	elseif tier <= 13 then
		return 2
	elseif tier <= 18 then
		return 3
	else
		return 5
	end
end
do
	local same = true
	for t = 1, 30 do
		if Pricing.meatYield(t) ~= meatFor(t) then
			same = false
		end
	end
	check("meat yield matches the live grinder for tiers 1-30", same)
end

-- A fish's value is split across its pieces, never multiplied by them
do
	local exact, counts = true, true
	for t = 1, 30 do
		for _, v in ipairs({ false, "Silver", "Gold" }) do
			local variant = if v then v else nil
			local pieces = Pricing.pieceValues(t, variant)
			local sum = 0
			for _, p in ipairs(pieces) do
				sum += p
				if p < 1 or p ~= math.floor(p) then
					exact = false
				end
			end
			if sum ~= Pricing.fishSaleValue(t, variant) then
				exact = false
			end
			if #pieces ~= Pricing.meatYield(t) then
				counts = false
			end
		end
	end
	check("pieces sum exactly to the fish sale value (all tiers, all variants)", exact)
	check("one value per meat piece", counts)
	local p6 = Pricing.pieceValues(6, nil)
	check("tier 6 splits 7 + 8", p6[1] == 7 and p6[2] == 8)
	local p14 = Pricing.pieceValues(14, nil)
	check("tier 14 splits 40 + 40 + 41", p14[1] == 40 and p14[2] == 40 and p14[3] == 41)
	local g19 = Pricing.pieceValues(19, "Gold")
	check("gold tier 19 = 5 x 450", #g19 == 5 and g19[1] == 450 and g19[5] == 450)
end

check(
	"variant multipliers 1/2/5",
	Pricing.saleMultiplier(nil) == 1 and Pricing.saleMultiplier("Silver") == 2 and Pricing.saleMultiplier("Gold") == 5
)
check("unknown variant is normal", Pricing.saleMultiplier("Diamond") == 1 and Pricing.variant("gold") == nil)

-- Offer prices: starter fish cheap, never above sale value, rare upside kept
do
	local starter = true
	for t = 1, 5 do
		local p = Pricing.offerPrice(t, nil)
		if p < 1 or p > 3 then
			starter = false
		end
	end
	check("starter offers (tiers 1-5) cost 1-3", starter)
	local below = true
	for t = 1, 30 do
		for _, v in ipairs({ false, "Silver", "Gold" }) do
			local variant = if v then v else nil
			if Pricing.offerPrice(t, variant) >= Pricing.fishSaleValue(t, variant) then
				below = false
			end
		end
	end
	check("an offer never costs as much as the fish sells for", below)
	check(
		"examples: t1 1, t5 3, t10 17, t14 48, t19 180",
		Pricing.offerPrice(1) == 1
			and Pricing.offerPrice(5) == 3
			and Pricing.offerPrice(10) == 17
			and Pricing.offerPrice(14) == 48
			and Pricing.offerPrice(19) == 180
	)
	check(
		"gold t19 costs 315, silver t10 costs 21",
		Pricing.offerPrice(19, "Gold") == 315 and Pricing.offerPrice(10, "Silver") == 21
	)
	-- rare fish keep most of their multiplier: profit ratio vs a normal fish
	local normal = Pricing.expectedNet(10, nil, 0.7)
	local silver = Pricing.expectedNet(10, "Silver", 0.7)
	local gold = Pricing.expectedNet(10, "Gold", 0.7)
	check("silver profit > 2x normal profit at 70% recapture", silver > 2 * normal)
	check("gold profit > 5x normal profit at 70% recapture", gold > 5 * normal)
	-- break-even recapture share (price / sale value) stays below 45% for normal fish
	local worst = 0
	for t = 1, 30 do
		worst = math.max(worst, Pricing.offerPrice(t) / Pricing.fishSaleValue(t))
	end
	check("normal break-even recapture <= 45% (worst " .. string.format("%.2f", worst) .. ")", worst <= 0.45)
	check("a bought fish that is never recaptured is a loss (no guaranteed profit)", Pricing.expectedNet(5, nil, 0) < 0)
end

-- Starting grant: after the first tank upgrade (50) there's money for fish
do
	local left = Config.StartingGrant - 50
	check("grant leaves >= 30 after the first tank upgrade", left >= 30)
	check("grant covers 10+ starter offers after that", left >= 10 * Pricing.offerPrice(5))
	local saved = Config.StartingGrant
	Config.StartingGrant = 60
	check("config check rejects a grant that leaves no working capital", not Config.check(50))
	Config.StartingGrant = saved
end

------------------------------------------------------------ ledger

local function healthy(l, label)
	local ok, why = l:check()
	check(label .. " (" .. tostring(why) .. ")", ok)
end

-- Issue: one record per piece, owner/variant/value fixed at the grinder
do
	local l = Ledger.new()
	local ids = l:issueFish({ ownerId = 111, tier = 14, variant = "Gold", fishName = "Tuna", source = "Net" })
	check("tier 14 cut into 3 pieces", #ids == 3)
	local total = 0
	local ok = true
	for _, id in ipairs(ids) do
		local p = l:get(id)
		total += p.value
		if p.ownerId ~= 111 or p.variant ~= "Gold" or p.fishName ~= "Tuna" or p.state ~= "Live" then
			ok = false
		end
	end
	check("every piece keeps owner, variant, species", ok)
	check("gold tier 14 pieces sum to 605", total == 121 * 5)
	check("ids unique", ids[1] ~= ids[2] and ids[2] ~= ids[3])
	healthy(l, "ledger healthy after issue")
end

-- Settle exactly once
do
	local l = Ledger.new()
	local id = l:issueFish({ ownerId = 5, tier = 1 })[1]
	local first = l:settle(id)
	check("first settle returns the piece", first ~= nil and first.value == 4 and first.ownerId == 5)
	check("second settle of the same id pays nothing", l:settle(id) == nil)
	check(
		"settle of an unknown id pays nothing",
		l:settle("P999") == nil and l:settle(nil) == nil and l:settle(42) == nil
	)
	check("totals count one settlement", l.totals.settled == 1)
end

-- Duplicate objects (clones with the same PieceId) on BOTH routes pay once
do
	local l = Ledger.new()
	local id = l:issueFish({ ownerId = 7, tier = 3, variant = "Silver" })[1]
	-- customer route: bot clone on the table sells
	local sold = l:settle(id)
	-- a stray copy of the same piece reaches a truck
	check("customer sale pays once", sold ~= nil and sold.variant == "Silver" and sold.value == 7 * 2)
	check("truck delivery of a copy pays nothing", l:carry(id) == false and l:settle(id) == nil)
end

-- Truck route keeps identity through carrying
do
	local l = Ledger.new()
	local ids = l:issueFish({ ownerId = 9, tier = 19, variant = "Gold" })
	check("carry marks the piece", l:carry(ids[1]) and l:get(ids[1]).state == "Carried")
	check("carried piece can't be carried twice", not l:carry(ids[1]))
	local p = l:settle(ids[1])
	check(
		"truck delivery settles a carried piece with its variant",
		p ~= nil and p.variant == "Gold" and p.value == 450
	)
end

-- Holding: full pipeline / carrier left -> data only, re-emitted oldest first
do
	local l = Ledger.new()
	local a = l:issueFish({ ownerId = 1, tier = 1 })[1]
	local b = l:issueFish({ ownerId = 2, tier = 1 })[1]
	check("hold a", l:hold(a))
	check("hold b", l:hold(b))
	check("can't hold twice", not l:hold(a))
	check("held count 2", l.heldCount == 2)
	check("a held piece can't be sold (it has no object)", l:settle(a) == nil and l:get(a) ~= nil)
	healthy(l, "healthy with held pieces")
	local first = l:takeHeld()
	check("oldest held first", first ~= nil and first.id == a and first.state == "Live")
	check("re-emitted piece keeps its owner", first.ownerId == 1)
	local c = l:issueFish({ ownerId = 3, tier = 1 })[1]
	check("carry c", l:carry(c))
	check("carrier left: carried piece is held, not lost", l:hold(c) and l:get(c).state == "Held")
	check("next held is b", l:takeHeld().id == b)
	check("then c", l:takeHeld().id == c)
	check("then none", l:takeHeld() == nil)
	check("held count back to 0", l.heldCount == 0)
	healthy(l, "healthy after draining")
end

-- Void removes held pieces cleanly
do
	local l = Ledger.new()
	local a = l:issueFish({ ownerId = 1, tier = 1 })[1]
	l:hold(a)
	check("void held piece", l:void(a) ~= nil and l.heldCount == 0)
	check("stale queue entry skipped", l:takeHeld() == nil)
	healthy(l, "healthy after void")
end

-- Ownership: only positive integer UserIds; anything else = unowned
do
	local l = Ledger.new()
	local id1 = l:issueFish({ ownerId = nil, tier = 1, source = "Harpoon" })[1]
	local id2 = l:issueFish({ ownerId = -4, tier = 1 })[1]
	local id3 = l:issueFish({ ownerId = 1.5, tier = 1 })[1]
	local id4 = l:issueFish({ ownerId = "123" :: any, tier = 1 })[1]
	check("unowned harpoon piece has no owner", l:get(id1).ownerId == nil and l:get(id1).source == "Harpoon")
	check(
		"invalid owners become unowned",
		l:get(id2).ownerId == nil and l:get(id3).ownerId == nil and l:get(id4).ownerId == nil
	)
	check(
		"unknown variant becomes normal",
		l:get(l:issueFish({ ownerId = 1, tier = 1, variant = "Diamond" })[1]).variant == nil
	)
end

-- Randomised: pieces are settled at most once whatever the operation order
do
	local l = Ledger.new()
	local rng = makeRng(7)
	local all = {}
	local settledTimes = {}
	for _ = 1, 3000 do
		local op = rng:NextInteger(1, 6)
		if op == 1 or #all == 0 then
			for _, id in ipairs(l:issueFish({ ownerId = rng:NextInteger(1, 4), tier = rng:NextInteger(1, 20) })) do
				table.insert(all, id)
			end
		else
			local id = all[rng:NextInteger(1, #all)]
			if op == 2 then
				if l:settle(id) then
					settledTimes[id] = (settledTimes[id] or 0) + 1
				end
			elseif op == 3 then
				l:carry(id)
			elseif op == 4 then
				l:hold(id)
			elseif op == 5 then
				l:takeHeld()
			else
				if l:settle(id) then
					settledTimes[id] = (settledTimes[id] or 0) + 1
				end
			end
		end
	end
	local once = true
	for _, n in pairs(settledTimes) do
		if n ~= 1 then
			once = false
		end
	end
	check("random ops: no piece ever settled twice", once)
	healthy(l, "random ops: ledger healthy")
end

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("pricing/ledger tests failed")
end
