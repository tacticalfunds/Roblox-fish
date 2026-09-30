-- Offline tests: MoneyStore's purchase journal (pendingPurchases) for
-- purchases another store delivers (GrinderUpgrades). Covers: begin = debit +
-- entry in ONE write; a failed begin leaves no debit and no entry (also when
-- the write landed but errored); settle delivered / not; unknown tokens;
-- one open purchase at a time; entries survive save, forget and reload;
-- unreadable entries never overwritten; funds; other fields kept.

local MoneyStore = require("../src/MoneyStore")

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
		local result = transform(deepCopy(store.data[key]))
		if result ~= nil then
			store.data[key] = deepCopy(result)
			store.writes += 1
		end
		if store.mode == "errorAfter" then
			error("DataStore write failed (fake)")
		end
		return store.data[key]
	end
	return store
end
local t = 5000
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
local function count(tbl)
	local n = 0
	for _ in pairs(tbl or {}) do
		n += 1
	end
	return n
end

do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 20000, netKg = 25, other = "x" }
	local m = loaded(store)
	local writes = store.writes
	local ok = m:beginPurchase(9, "G:1", "GrinderUpgrades", 4000, "Uncommon Blade")
	check("begin: ok, ONE write with the money - 4000 AND the entry", ok and store.writes == writes + 1 and store.data[KEY].money == 16000
		and store.data[KEY].pendingPurchases["G:1"].amount == 4000 and store.data[KEY].pendingPurchases["G:1"].source == "GrinderUpgrades"
		and store.data[KEY].pendingPurchases["G:1"].t == 5000)
	check("other fields kept", store.data[KEY].netKg == 25 and store.data[KEY].other == "x")
	check("a second purchase while one is open: refused (unsettled), not charged", select(2, m:beginPurchase(9, "G:2", "GrinderUpgrades", 100)) == "unsettled"
		and m:balance(9) == 16000)
	check("open purchases listed", count(m:openPurchases(9)) == 1)
	check("settle delivered: entry gone, money stays", m:settlePurchase(9, "G:1", true) == "settled" and m:balance(9) == 16000
		and count(m:openPurchases(9)) == 0)
	check("settle it again: nothing (notOpen), no double effect", m:settlePurchase(9, "G:1", false) == "notOpen" and m:balance(9) == 16000)
	m:save(9, false)
	check("saved: no entry left in the record", store.data[KEY].pendingPurchases == nil and store.data[KEY].money == 16000)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 20000 }
	local m = loaded(store)
	m:beginPurchase(9, "G:1", "GrinderUpgrades", 4000)
	check("settle NOT delivered: refunded, entry gone", m:settlePurchase(9, "G:1", false) == "settled" and m:balance(9) == 20000
		and count(m:openPurchases(9)) == 0)
	m:save(9, false)
	check("saved together: 20000, no entry", store.data[KEY].money == 20000 and store.data[KEY].pendingPurchases == nil)
end
for _, mode in ipairs({ "error", "errorAfter" }) do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 20000 }
	local m = loaded(store)
	store.mode = mode
	local ok, why = m:beginPurchase(9, "G:1", "GrinderUpgrades", 4000)
	store.mode = nil
	check("begin write " .. mode .. ": refused, money back, no entry in the session", not ok and tostring(why):find("notSaved", 1, true) ~= nil
		and m:balance(9) == 20000 and count(m:openPurchases(9)) == 0 and m:isDirty(9))
	m:save(9, false)
	check("begin write " .. mode .. ": the next save leaves 20000 and no entry", store.data[KEY].money == 20000
		and store.data[KEY].pendingPurchases == nil)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 20000 }
	local m = loaded(store)
	m:beginPurchase(9, "G:1", "GrinderUpgrades", 4000, "Uncommon Blade")
	m:save(9, true) -- final save while the delivery is still open (a shutdown)
	m:forget(9)
	check("a final save keeps the debit AND the entry", store.data[KEY].money == 16000 and count(store.data[KEY].pendingPurchases) == 1)
	check("settling after forget: notOpen (left for the next load)", m:settlePurchase(9, "G:1", false) == "notOpen")
	t += 100
	local m2 = loaded(store, "jobB")
	local open = m2:openPurchases(9)
	check("next load: the entry is back, with its amount and time", open and open["G:1"] and open["G:1"].amount == 4000 and open["G:1"].t == 5000
		and open["G:1"].what == "Uncommon Blade" and m2:balance(9) == 16000)
	check("settled there (not delivered): refunded once", m2:settlePurchase(9, "G:1", false) == "settled" and m2:balance(9) == 20000
		and m2:settlePurchase(9, "G:1", false) == "notOpen" and m2:balance(9) == 20000)
end
do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 100 }
	local m = loaded(store)
	check("not enough money: funds, nothing written", select(2, m:beginPurchase(9, "G:1", "GrinderUpgrades", 4000)) == "funds"
		and m:balance(9) == 100 and store.data[KEY].pendingPurchases == nil)
end
for _, bad in ipairs({ "junk", { ["G:1"] = { source = "GrinderUpgrades", amount = -5, t = 1 } }, { ["G:1"] = "x" } }) do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 20000, pendingPurchases = deepCopy(bad) }
	local m = loaded(store)
	check("unreadable pendingPurchases: no such purchases this session", select(2, m:beginPurchase(9, "G:9", "GrinderUpgrades", 10)) == "purchasesUnavailable"
		and m:openPurchases(9) == nil and m:balance(9) == 20000)
	m:save(9, false)
	local kept = store.data[KEY].pendingPurchases
	check("unreadable pendingPurchases: never overwritten", if type(bad) == "table" then type(kept) == "table" else kept == bad)
end
do
	local store = fakeStore()
	local m = MoneyStore.new(store, "jobA", now)
	m:begin(9)
	check("not loaded: refused", select(2, m:beginPurchase(9, "G:1", "GrinderUpgrades", 10)) == "notLoaded" and m:openPurchases(9) == nil)
end

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("journal tests failed")
end
