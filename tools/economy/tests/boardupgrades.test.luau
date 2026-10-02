-- Offline tests: the upgrade board's saved levels (BoardUpgrades + MoneyStore
-- `upgrades`) and the Rod Luck weighting. Run via run_tests.py. Covers: the
-- tuning and its guard rails, loading (missing / invalid / newer builds'
-- entries), one write per purchase (money + levels together, other fields
-- kept), staged level invisible until written, failed saves undo, spam in
-- flight, funds, max, rejoin; luck factors and the renormalised odds; Meat
-- Price on the whole fish once, before the split, owned fish only, paid once.

local Config = require("../src/Config")
local MoneyStore = require("../src/MoneyStore")
local BoardUpgrades = require("../src/BoardUpgrades")
local Pricing = require("../src/Pricing")
local Ledger = require("../src/Ledger")
local Sales = require("../src/Sales")

local failures, passes = 0, 0
local function check(name: string, cond: any)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. name)
	end
end
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = deepCopy(x)
	end
	return out
end
local function fakeStore()
	local store = { data = {}, writes = 0, mode = nil :: string?, during = nil :: any }
	function store.update(key, transform)
		if store.mode == "error" then
			error("DataStore request failed (fake)")
		end
		if store.during then
			local fn = store.during
			store.during = nil
			fn()
		end
		local result = transform(deepCopy(store.data[key]))
		if store.mode == "errorAfter" then
			error("DataStore write failed (fake)")
		end
		if result ~= nil then
			store.data[key] = deepCopy(result)
			store.writes += 1
		end
		return store.data[key]
	end
	return store
end
local t = 1000
local function now()
	return t
end
local KEY = MoneyStore.key(9)
local function loaded(store, job)
	local m = MoneyStore.new(store, job or "jobA", now)
	m:begin(9)
	m:attemptLoad(9)
	return m
end

------------------------------------------------------------ tuning

check("config check passes", Config.check() == true)

-- The current levels are the fast-start tuning; the checks below were written
-- for the original three-level ones, so they pin those (the same tables
-- BoardUpgrades reads).
do
	local U = Config.BoardUpgrades
	local function list(t)
		return table.concat(t, ",")
	end
	check("fast start: Rod Luck 1x > 1.5x > 2x > 2.5x > 3x for 10, 45, 140, 350",
		list(U.RodLuck.Values) == "1,1.5,2,2.5,3" and list(U.RodLuck.Costs) == "10,45,140,350" and U.RodLuck.FirstValue == 1.5)
	check("fast start: Meat Price 1x > 1.25x ... 3x for 10, 40, 90, 180, 400, 900",
		list(U.MeatPrice.Values) == "1,1.25,1.5,1.75,2,2.5,3" and list(U.MeatPrice.Costs) == "10,40,90,180,400,900" and U.MeatPrice.FirstValue == 1.25)
	check("fast start: Faster Reels 1x > 1.1x > 1.2x > 1.35x > 1.5x for 10, 45, 140, 350",
		list(U.FasterReels.Values) == "1,1.1,1.2,1.35,1.5" and list(U.FasterReels.Costs) == "10,45,140,350" and U.FasterReels.FirstValue == 1.1)
	check("fast start: Meat Price 1.25x on a tier-1 fish (4) pays 5", Pricing.pieceValues(1, nil, 1.25)[1] == 5)
	U.RodLuck.Values, U.RodLuck.Costs, U.RodLuck.FirstValue = { 1, 2, 2.5, 3 }, { 10, 75, 300 }, 2
	U.MeatPrice.Values, U.MeatPrice.Costs, U.MeatPrice.FirstValue = { 1, 2, 2.5, 3 }, { 10, 150, 600 }, 2
	U.FasterReels.Values, U.FasterReels.Costs, U.FasterReels.FirstValue = { 1, 1.2, 1.35, 1.5 }, { 10, 100, 400 }, 1.2
	check("config check passes with the pinned levels", Config.check() == true)
end
check("Rod Luck is a board upgrade", BoardUpgrades.known("RodLuck") and not BoardUpgrades.known("NetStrength")
	and not BoardUpgrades.known("Hack") and not BoardUpgrades.known(5))
local values, costs, level = { BoardUpgrades.value("RodLuck", 0) }, {}, 0
while true do
	local nextLevel, cost, nextValue = BoardUpgrades.nextStep("RodLuck", level)
	if not nextLevel then
		break
	end
	table.insert(costs, cost)
	table.insert(values, nextValue)
	check("next value = the value at the next level", nextValue == BoardUpgrades.value("RodLuck", nextLevel :: number))
	level = nextLevel :: number
end
check("Rod Luck: 1x > 2x for $10 (the card), then 2.5x, 3x", table.concat(values, ",") == "1,2,2.5,3" and table.concat(costs, ",") == "10,75,300")
check("first step costs UpgradeFirstCost", costs[1] == Config.UpgradeFirstCost)
check("past the last level: nothing more, the last value", BoardUpgrades.nextStep("RodLuck", 3) == nil and BoardUpgrades.value("RodLuck", 9) == 3)
do
	local u = Config.BoardUpgrades.RodLuck
	local saved = { Values = u.Values, Costs = u.Costs }
	u.Values = { 1, 3, 4, 5 }
	check("config check: a first value other than the card's (FirstValue) is refused", Config.check() == false)
	u.Values = { 1, 2, 2.5, 9 }
	check("config check: a value over MaxValue is refused", Config.check() == false)
	u.Values = saved.Values
	u.Costs = { 25, 75, 300 }
	check("config check: a first cost other than UpgradeFirstCost is refused", Config.check() == false)
	u.Costs = { 10, 75, 9000 }
	check("config check: a cost over UpgradeCostCap is refused", Config.check() == false)
	u.Costs = { 10, 75 }
	check("config check: one cost per step", Config.check() == false)
	u.Costs = saved.Costs
	check("config check passes again", Config.check() == true)
end

------------------------------------------------------------ loading the field

do
	local lv, w = BoardUpgrades.load(nil)
	check("no field: all level 0, writable", w and BoardUpgrades.level(lv, "RodLuck") == 0)
	lv, w = BoardUpgrades.load({ RodLuck = 1, FutureThing = 7 })
	check("known + a newer build's entry: level 1, the other kept", w and BoardUpgrades.level(lv, "RodLuck") == 1 and lv.FutureThing == 7)
	lv, w = BoardUpgrades.load({ RodLuck = 9 })
	check("a newer build's higher level is kept; its effect is the last value", w and lv.RodLuck == 9 and BoardUpgrades.value("RodLuck", BoardUpgrades.level(lv, "RodLuck")) == 3)
	for _, bad in ipairs({ "x", 5, { RodLuck = "1" }, { RodLuck = 1.5 }, { RodLuck = -1 } }) do
		local l2, w2 = BoardUpgrades.load(bad)
		check("invalid field " .. (if type(bad) == "table" then "{RodLuck=" .. tostring(bad.RodLuck) .. "}" else tostring(bad)) .. ": level 0, not writable",
			not w2 and BoardUpgrades.level(l2, "RodLuck") == 0)
	end
end

------------------------------------------------------------ Rod Luck weighting

check("luck factor: the commonest tier x1, the rarest x luck, halfway x sqrt(luck)",
	near(BoardUpgrades.luckFactor(1, 1, 5, 2), 1) and near(BoardUpgrades.luckFactor(5, 1, 5, 2), 2)
	and near(BoardUpgrades.luckFactor(3, 1, 5, 2), math.sqrt(2)))
check("no luck (1x, nil, below 1) or one tier: x1 everywhere", near(BoardUpgrades.luckFactor(5, 1, 5, 1), 1)
	and near(BoardUpgrades.luckFactor(5, 1, 5, nil :: any), 1) and near(BoardUpgrades.luckFactor(5, 1, 5, 0.5), 1)
	and near(BoardUpgrades.luckFactor(3, 3, 3, 2), 1))
do
	-- a pool like the river's: common fish heavy, rare ones light
	local pool = { { tier = 1, w = 50 }, { tier = 2, w = 25 }, { tier = 3, w = 12 }, { tier = 4, w = 5 }, { tier = 5, w = 1 } }
	local function odds(luck)
		local out, total = {}, 0
		for i, e in ipairs(pool) do
			out[i] = e.w * BoardUpgrades.luckFactor(e.tier, 1, 5, luck)
			total += out[i]
		end
		for i in ipairs(out) do
			out[i] /= total
		end
		return out
	end
	local base, lucky = odds(1), odds(2)
	local sum = 0
	for _, p in ipairs(lucky) do
		sum += p
	end
	check("2x: the odds still add up to 1 (renormalised)", near(sum, 1))
	check("2x: rarest vs commonest odds exactly doubled", near((lucky[5] / lucky[1]) / (base[5] / base[1]), 2))
	check("2x: the rarest fish is likelier but far from certain", lucky[5] > base[5] and lucky[5] < 0.05)
	check("2x: the commonest fish is a bit less likely, still the most likely", lucky[1] < base[1] and lucky[1] > lucky[2])
end

------------------------------------------------------------ saved levels (MoneyStore)

do
	local store = fakeStore()
	local m = loaded(store)
	check("new player: level 0, an empty table written with the record", m:upgradeLevel(9, "RodLuck") == 0 and type(store.data[KEY].upgrades) == "table")
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 1000, netKg = 25, rods = { owned = { FishingRod4 = true }, equipped = "FishingRod4" }, other = "x",
		upgrades = { FutureThing = 3 } }
	local m = loaded(store)
	local writes = store.writes
	local ok, why, newLevel, cost = m:buyUpgrade(9, "RodLuck")
	check("buy Rod Luck: ok, level 1 for 10", ok and why == nil and newLevel == 1 and cost == 10)
	check("one write with money - 10 AND the level; net, rods, other fields and a newer build's entry kept",
		store.writes == writes + 1 and store.data[KEY].money == 990 and store.data[KEY].upgrades.RodLuck == 1
		and store.data[KEY].upgrades.FutureThing == 3 and store.data[KEY].netKg == 25
		and store.data[KEY].rods.owned.FishingRod4 == true and store.data[KEY].other == "x")
	check("memory matches", m:upgradeLevel(9, "RodLuck") == 1 and m:balance(9) == 990)
	local _, _, l2, c2 = m:buyUpgrade(9, "RodLuck")
	local _, _, l3, c3 = m:buyUpgrade(9, "RodLuck")
	check("next levels: 2 for 75, 3 for 300", l2 == 2 and c2 == 75 and l3 == 3 and c3 == 300 and m:balance(9) == 615)
	check("at the last level: refused, not charged", select(2, m:buyUpgrade(9, "RodLuck")) == "max" and m:balance(9) == 615)
	check("unknown / Net Strength ids: refused", select(2, m:buyUpgrade(9, "Hack")) == "unknown" and select(2, m:buyUpgrade(9, "NetStrength")) == "unknown"
		and select(2, m:buyUpgrade(9, nil)) == "unknown" and m:balance(9) == 615)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 9 }
	local m = loaded(store)
	check("not enough money (9 < 10): nothing charged or written", select(2, m:buyUpgrade(9, "RodLuck")) == "funds" and m:balance(9) == 9
		and m:upgradeLevel(9, "RodLuck") == 0)
end
for _, bad in ipairs({ "junk", { RodLuck = "2" } }) do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 900, upgrades = deepCopy(bad) }
	local m = loaded(store)
	check("unreadable upgrades: level 0, can't buy", m:upgradeLevel(9, "RodLuck") == 0 and select(2, m:buyUpgrade(9, "RodLuck")) == "upgradesUnavailable"
		and m:balance(9) == 900)
	m:save(9, false)
	local kept = store.data[KEY].upgrades
	check("unreadable upgrades: never overwritten", if type(bad) == "table" then type(kept) == "table" and kept.RodLuck == "2" else kept == bad)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 500 }
	store.mode = "error"
	local m = MoneyStore.new(store, "jobA", now)
	m:begin(9)
	m:attemptLoad(9)
	m:markFailed(9, "error")
	check("failed load: no level, can't buy", m:upgradeLevel(9, "RodLuck") == nil and select(2, m:buyUpgrade(9, "RodLuck")) == "notLoaded")
end
for _, mode in ipairs({ "error", "errorAfter" }) do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 100 }
	local m = loaded(store)
	local seen
	store.during = function()
		seen = m:upgradeLevel(9, "RodLuck")
	end
	store.mode = mode
	local ok, why = m:buyUpgrade(9, "RodLuck")
	if mode == "errorAfter" then
		check("during the failing write: still level 0 (staged level invisible)", seen == 0)
	end
	check("save " .. mode .. ": refused, money back, still level 0", not ok and tostring(why):find("notSaved", 1, true) ~= nil
		and m:balance(9) == 100 and m:upgradeLevel(9, "RodLuck") == 0 and m:isDirty(9))
	store.mode = nil
	local u = store.data[KEY].upgrades
	check("save " .. mode .. ": the store never got level 1", not (type(u) == "table" and u.RodLuck == 1))
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 100 }
	local m = loaded(store)
	local seen, again, net, rod = nil, nil, nil, nil
	store.during = function()
		seen = m:upgradeLevel(9, "RodLuck")
		again = { m:buyUpgrade(9, "RodLuck") }
		net = { m:buyNetKg(9) }
		rod = { m:buyRod(9, "FishingRod4") }
	end
	check("successful buy", m:buyUpgrade(9, "RodLuck"))
	check("during its write: level 0; a second upgrade, a net and a rod buy refused (busy)", seen == 0 and again[2] == "busy"
		and net[2] == "busy" and rod[2] == "busy")
	check("charged once; level 1 after", m:balance(9) == 90 and m:upgradeLevel(9, "RodLuck") == 1)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 500 }
	local m = loaded(store)
	m:buyUpgrade(9, "RodLuck")
	m:buyNetKg(9)
	m:save(9, true)
	m:forget(9)
	t += 10
	local m2 = loaded(store, "jobB")
	check("rejoin elsewhere: Rod Luck level 1, 20 kg and the money", m2:upgradeLevel(9, "RodLuck") == 1 and m2:netKg(9) == 20
		and m2:balance(9) == 480)
	check("next price continues from level 1 (75)", select(4, m2:buyUpgrade(9, "RodLuck")) == 75)
end

------------------------------------------------------------ Faster Reels (tuning; the reel itself: reels_sim)

check("Faster Reels is a board upgrade: 1x > 1.2x for $10, then 1.35x $100, 1.5x $400, capped at 2", BoardUpgrades.known("FasterReels")
	and select(3, BoardUpgrades.nextStep("FasterReels", 0)) == 1.2 and select(2, BoardUpgrades.nextStep("FasterReels", 0)) == 10
	and select(2, BoardUpgrades.nextStep("FasterReels", 1)) == 100 and select(2, BoardUpgrades.nextStep("FasterReels", 2)) == 400
	and BoardUpgrades.value("FasterReels", 3) == 1.5 and BoardUpgrades.nextStep("FasterReels", 3) == nil
	and Config.BoardUpgrades.FasterReels.MaxValue == 2)
check("every board card is a board upgrade except Net Strength (NetKg)", table.concat(BoardUpgrades.ids(), ",") == "RodLuck,MeatPrice,FasterReels")

------------------------------------------------------------ Meat Price

check("Meat Price is a board upgrade: 1x > 2x for $10, then 2.5x $150, 3x $600", BoardUpgrades.known("MeatPrice")
	and BoardUpgrades.value("MeatPrice", 0) == 1 and select(3, BoardUpgrades.nextStep("MeatPrice", 0)) == 2
	and select(2, BoardUpgrades.nextStep("MeatPrice", 0)) == 10 and select(2, BoardUpgrades.nextStep("MeatPrice", 1)) == 150
	and select(2, BoardUpgrades.nextStep("MeatPrice", 2)) == 600 and BoardUpgrades.nextStep("MeatPrice", 3) == nil)
local function sum(list)
	local t = 0
	for _, v in ipairs(list) do
		t += v
	end
	return t
end
do
	local plain14, double14 = Pricing.pieceValues(14, nil), Pricing.pieceValues(14, nil, 2)
	check("2x: the whole fish's value doubles, split into the same number of pieces", #double14 == #plain14
		and sum(double14) == 2 * Pricing.fishSaleValue(14, nil))
	local gold19 = Pricing.pieceValues(19, "Gold", 2)
	check("2x on a Gold fish: tier value x Gold x 2, once (not per piece)", #gold19 == Pricing.meatYield(19)
		and sum(gold19) == 2 * Pricing.fishValue(19) * 5)
	local whole = math.floor(Pricing.fishSaleValue(10, nil) * 2.5 + 0.5) -- 42 x 2.5 = 105 (per piece it would be 53 + 53)
	local p25 = Pricing.pieceValues(10, nil, 2.5)
	check("2.5x on a 2-piece fish: the WHOLE value x2.5 rounded once, then the usual split (not each piece x2.5)",
		#p25 == 2 and p25[1] == whole // 2 and p25[2] == whole - whole // 2)
	local silver3 = Pricing.pieceValues(3, "Silver", 2.5)
	check("2.5x: rounded once on the whole fish", sum(silver3) == math.floor(Pricing.fishSaleValue(3, "Silver") * 2.5 + 0.5))
	local ok = true
	for _, bad in ipairs({ 0.5, 1, 0 / 0, "2", 1000, -3 }) do
		ok = ok and sum(Pricing.pieceValues(14, nil, bad)) == Pricing.fishSaleValue(14, nil)
	end
	check("no / invalid multiplier (0.5, 1, NaN, a string, 1000, negative): the plain value", ok and sum(Pricing.pieceValues(14, nil, nil)) == Pricing.fishSaleValue(14, nil))
	check("the tier and variant values themselves are unchanged", Pricing.fishValue(14) == math.floor(4 * 1.3 ^ 13 + 0.5)
		and Pricing.saleMultiplier("Gold") == 5 and Pricing.saleMultiplier("Silver") == 2)
end
do
	local l = Ledger.new("T")
	local owned = l:issueFish({ ownerId = 42, tier = 14, variant = "Silver", fishName = "Tuna", source = "Net", multiplier = 2 })
	local unowned = l:issueFish({ ownerId = nil, tier = 14, variant = "Silver", fishName = "Tuna", source = "Harpoon", multiplier = 2 })
	local function total(ids)
		local t = 0
		for _, id in ipairs(ids) do
			t += (l:get(id) :: any).value
		end
		return t
	end
	check("ledger: an owned fish's pieces carry 2x its value", total(owned) == 2 * Pricing.fishSaleValue(14, "Silver"))
	check("ledger: an unowned fish ignores any multiplier", total(unowned) == Pricing.fishSaleValue(14, "Silver"))
	local paid = {}
	local firstValue = (l:get(owned[1]) :: any).value
	local first = { Sales.settle(l, owned[1], function(ownerId, amount)
		table.insert(paid, amount)
		return "paid"
	end) }
	local again = { Sales.settle(l, owned[1], function(ownerId, amount)
		table.insert(paid, amount)
		return "paid"
	end) }
	check("each piece still pays once, its value fixed at the cut", first[1] == true and first[2] == firstValue and paid[1] == firstValue
		and again[1] == false and again[2] == 0 and #paid == 1)
end
do
	local l = Ledger.new("S")
	local asked = {}
	local ids = Sales.issue(l, nil, "Cod", 14, { OwnerId = 77, Source = "Rod" }, function(ownerId)
		table.insert(asked, ownerId)
		return 2
	end)
	check("Sales.issue asks the OWNER's multiplier once per fish", #asked == 1 and asked[1] == 77
		and sum((function()
			local v = {}
			for _, id in ipairs(ids) do
				table.insert(v, (l:get(id) :: any).value)
			end
			return v
		end)()) == 2 * Pricing.fishSaleValue(14, nil))
	asked = {}
	Sales.issue(l, nil, "Cod", 14, { Source = "Harpoon" }, function(ownerId)
		table.insert(asked, ownerId)
		return 2
	end)
	check("an unowned fish: the multiplier isn't even asked", #asked == 0)
	local broken = Sales.issue(l, nil, "Cod", 14, { OwnerId = 78 }, function()
		error("boom")
	end)
	local t = 0
	for _, id in ipairs(broken) do
		t += (l:get(id) :: any).value
	end
	check("a failing multiplier lookup: the plain value, the fish still issued", #broken == Pricing.meatYield(14) and t == Pricing.fishSaleValue(14, nil))
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 500, upgrades = { RodLuck = 2 } }
	local m = loaded(store)
	local ok, _, level, cost = m:buyUpgrade(9, "MeatPrice")
	check("Meat Price: its own level (RodLuck untouched), one write", ok and level == 1 and cost == 10 and m:upgradeLevel(9, "RodLuck") == 2
		and store.data[KEY].upgrades.MeatPrice == 1 and store.data[KEY].upgrades.RodLuck == 2 and store.data[KEY].money == 490)
end

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("board upgrade tests failed")
end
