-- Offline tests: net capacity (+5 KG signs) saved in the Money record
-- (MoneyStore + NetKg). Run via run_tests.py. Covers: the cost curve and
-- cap, v1 / v2 records without the field, invalid data never overwritten,
-- one write per purchase (money + kg together, rods kept), staged value
-- invisible until written, failed saves undo, spam in flight, funds, max,
-- rejoin, the shared net rule.

local Config = require("../src/Config")
local MoneyStore = require("../src/MoneyStore")
local NetKg = require("../src/NetKg")

local failures, passes = 0, 0
local function check(name: string, cond: any)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. name)
	end
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

-- The current curve is the fast-start tuning; the checks below were written
-- for the original one (10, 25, 50, 100, then x1.5), so they pin it (the same
-- table NetKg reads).
do
	local all, c = {}, 0
	for i = 1, (Config.NetKg.Max - Config.NetKg.Base) / Config.NetKg.Step do
		c = if i <= #Config.NetKg.Costs then Config.NetKg.Costs[i] else math.floor(c * Config.NetKg.Growth / 5 + 0.5) * 5
		table.insert(all, c)
	end
	check("fast-start curve: 10, 20, 35, 60, 90, 125, 175, 245, 345 (1105 to 60 kg)",
		table.concat(all, ",") == "10,20,35,60,90,125,175,245,345")
	check("fast-start curve: the module's own costs match", NetKg.cost(0) == 10 and NetKg.cost(5) == 125 and NetKg.cost(8) == 345)
	Config.NetKg.Costs = { 10, 25, 50, 100 }
	Config.NetKg.Growth = 1.5
	check("config check passes with the pinned curve", Config.check() == true)
end
local costs, kg = {}, NetKg.base()
while true do
	local nextKg, cost = NetKg.nextStep(kg)
	if not nextKg then
		break
	end
	table.insert(costs, cost)
	kg = nextKg
end
check("costs 10, 25, 50, 100, then x1.5 rounded to 5, to 60 kg", table.concat(costs, ",") == "10,25,50,100,150,225,340,510,765" and kg == 60)
check("the first step costs the board's UpgradeFirstCost ($10)", costs[1] == Config.UpgradeFirstCost and Config.UpgradeFirstCost == 10)
do
	local saved = Config.NetKg.Costs
	Config.NetKg.Costs = { 25, 50, 100 }
	check("config check: a first step other than UpgradeFirstCost is refused", Config.check() == false)
	Config.NetKg.Costs = { 10, 25, 50, 4000 }
	check("config check: a step over UpgradeCostCap (4000 x1.5) is refused", Config.check() == false)
	Config.NetKg.Costs = saved
	check("config check passes again", Config.check() == true)
end
check("nothing past the cap", NetKg.nextStep(60) == nil and NetKg.nextStep(75) == nil)
check("shared net: the highest, never below the floor", NetKg.shared({ 20, 35, 15 }, 15) == 35 and NetKg.shared({}, 15) == 15 and NetKg.shared({ 10 }, 15) == 15)

------------------------------------------------------------ loading

do
	local store = fakeStore()
	local m = loaded(store)
	check("new player: 15 kg, written with the record", m:netKg(9) == 15 and store.data[KEY].netKg == 15)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 500, rods = { owned = { FishingRod4 = true }, equipped = "FishingRod4" } }
	local m = loaded(store)
	check("v2 record without netKg: 15 kg, money and rods untouched", m:netKg(9) == 15 and m:balance(9) == 500 and m:rodStats(9).Id == "FishingRod4")
	m:save(9, false)
	check("save adds netKg, keeps rods", store.data[KEY].netKg == 15 and store.data[KEY].rods.owned.FishingRod4 == true)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 1, money = 300 }
	local m = loaded(store)
	check("v1 record: 15 kg, money untouched", m:netKg(9) == 15 and m:balance(9) == 300)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 3, money = 10, netKg = 80 }
	local m = loaded(store)
	check("a newer build's 80 kg is kept (above this Max)", m:netKg(9) == 80 and select(2, m:buyNetKg(9)) == "max")
	m:save(9, false)
	check("and written back as is", store.data[KEY].netKg == 80)
end
for _, bad in ipairs({ "20", 17.5, -5, 10, { 20 } }) do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 900, netKg = deepCopy(bad) }
	local m = loaded(store)
	check("invalid netKg " .. tostring(bad) .. ": Base, can't buy", m:netKg(9) == 15 and select(2, m:buyNetKg(9)) == "netUnavailable" and m:balance(9) == 900)
	m:save(9, false)
	local kept = store.data[KEY].netKg
	check("invalid netKg " .. tostring(bad) .. ": never overwritten", type(bad) == "table" and type(kept) == "table" or kept == bad)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 500, netKg = 30 }
	store.mode = "error"
	local m = MoneyStore.new(store, "jobA", now)
	m:begin(9)
	m:attemptLoad(9)
	m:markFailed(9, "error")
	check("failed load: no capacity, can't buy, record untouched", m:netKg(9) == nil and select(2, m:buyNetKg(9)) == "notLoaded"
		and store.data[KEY].netKg == 30 and store.writes == 0)
end

------------------------------------------------------------ buying

do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 1000, rods = { owned = { FishingRod3 = true }, equipped = "FishingRod3" }, other = "x" }
	local m = loaded(store)
	local writes = store.writes
	local ok, why, newKg, cost = m:buyNetKg(9)
	check("buy +5: ok, 15 -> 20 kg for 10", ok and why == nil and newKg == 20 and cost == 10)
	check("one write with money - 10 AND 20 kg; rods and other fields kept", store.writes == writes + 1 and store.data[KEY].money == 990
		and store.data[KEY].netKg == 20 and store.data[KEY].rods.owned.FishingRod3 == true and store.data[KEY].other == "x")
	check("memory matches", m:netKg(9) == 20 and m:balance(9) == 990)
	local _, _, k2, c2 = m:buyNetKg(9)
	local _, _, k3, c3 = m:buyNetKg(9)
	check("next steps: 25 kg for 25, 30 kg for 50", k2 == 25 and c2 == 25 and k3 == 30 and c3 == 50 and m:balance(9) == 915)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 9 }
	local m = loaded(store)
	check("not enough money (9 < 10): nothing charged or written", select(2, m:buyNetKg(9)) == "funds" and m:balance(9) == 9 and m:netKg(9) == 15)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 99999, netKg = 55 }
	local m = loaded(store)
	check("last step: 55 -> 60 for 765", select(3, m:buyNetKg(9)) == 60 and m:balance(9) == 99999 - 765)
	check("at the cap: refused, not charged", select(2, m:buyNetKg(9)) == "max" and m:balance(9) == 99999 - 765)
end
for _, mode in ipairs({ "error", "errorAfter" }) do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 100 }
	local m = loaded(store)
	local seen
	store.during = function()
		seen = m:netKg(9)
	end
	store.mode = mode
	local ok, why = m:buyNetKg(9)
	if mode == "errorAfter" then
		check("during the failing write: still 15 kg (staged value invisible)", seen == 15)
	end
	check("save " .. mode .. ": refused, money back, still 15 kg", not ok and tostring(why):find("notSaved", 1, true) ~= nil
		and m:balance(9) == 100 and m:netKg(9) == 15 and m:isDirty(9))
	store.mode = nil
	check("save " .. mode .. ": the store never got 20 kg", store.data[KEY].netKg ~= 20)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 100 }
	local m = loaded(store)
	local seen, again, rod = nil, nil, nil
	store.during = function()
		seen = m:netKg(9)
		again = { m:buyNetKg(9) }
		rod = { m:buyRod(9, "FishingRod4") }
	end
	check("successful buy", m:buyNetKg(9))
	check("during its write: 15 kg; a second buy and a rod buy refused (busy)", seen == 15 and again[2] == "busy" and rod[2] == "busy")
	check("charged once; 20 kg after", m:balance(9) == 90 and m:netKg(9) == 20)
end

------------------------------------------------------------ adopting earlier KG-sign buys (GrinderUpgrades)

do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 500 }
	local m = loaded(store)
	local writes = store.writes
	check("adopt 3 earlier buys (30 kg): raised, no write yet, money untouched", m:adoptNetKg(9, 30) == "raised" and m:netKg(9) == 30
		and store.writes == writes and m:balance(9) == 500 and m:isDirty(9))
	check("the same report again: kept (never added twice)", m:adoptNetKg(9, 30) == "kept" and m:netKg(9) == 30)
	check("a lower report: kept (never lowers)", m:adoptNetKg(9, 20) == "kept" and m:netKg(9) == 30)
	check("invalid reports refused", m:adoptNetKg(9, 12) == "invalid" and m:adoptNetKg(9, 31.5) == "invalid"
		and m:adoptNetKg(9, "40") == "invalid" and m:adoptNetKg(9, 0 / 0) == "invalid" and m:netKg(9) == 30)
	m:save(9, false)
	check("saved with the next save", store.data[KEY].netKg == 30 and store.data[KEY].money == 500)
	check("next step continues from 30 (30 -> 35 for 100)", select(4, m:buyNetKg(9)) == 100)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 500, netKg = 45 }
	local m = loaded(store)
	check("already higher (bought here since): kept at 45", m:adoptNetKg(9, 30) == "kept" and m:netKg(9) == 45)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 500, netKg = "junk" }
	local m = loaded(store)
	check("unreadable netKg: not adopted, never overwritten", m:adoptNetKg(9, 30) == "netUnavailable" and m:netKg(9) == 15)
	m:save(9, false)
	check("unreadable netKg still as it was", store.data[KEY].netKg == "junk")
end
do
	local store = fakeStore()
	local m = MoneyStore.new(store, "jobA", now)
	m:begin(9)
	check("not loaded: not adopted", m:adoptNetKg(9, 30) == "notLoaded")
end

------------------------------------------------------------ rejoin

do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 500 }
	local m = loaded(store)
	m:buyNetKg(9)
	m:buyNetKg(9)
	m:save(9, true)
	m:forget(9)
	t += 10
	local m2 = loaded(store, "jobB")
	check("rejoin elsewhere: 25 kg and the money", m2:netKg(9) == 25 and m2:balance(9) == 465)
	check("next price continues from 25 kg (50 -> 30 kg)", select(4, m2:buyNetKg(9)) == 50)
end

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("netkg tests failed")
end
