-- Offline tests: rod ownership saved in the Money record (MoneyStore v2 +
-- Rods). Run via run_tests.py. The DataStore is a fake that fails on purpose.
-- Covers: v1 migration without touching money, unknown fields / newer
-- versions kept, corrupt rod data never overwritten, purchase = one write
-- of money + rod, save failures undo both, duplicates / spam while a
-- purchase is in flight, funds, forged / unowned equips, rejoin.

local Config = require("../src/Config")
local MoneyStore = require("../src/MoneyStore")
local Rods = require("../src/Rods")

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

-- UpdateAsync-like fake. mode: "error" (throws before running), "errorAfter"
-- (runs the transform, throws without writing). `during` runs mid-call (as a
-- yield would let other code run).
local function fakeStore()
	local store = { data = {}, writes = 0, mode = nil :: string?, during = nil :: any, after = nil :: any }
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
		if store.after then -- runs once the write's value is built, before it returns
			local fn = store.after
			store.after = nil
			fn()
		end
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
local KEY = MoneyStore.key(7)
local TIGER, CORAL, MAGMA = "FishingRod4", "FishingRod3", "FishingRod5"
local function loaded(store, job)
	local m = MoneyStore.new(store, job or "jobA", now)
	m:begin(7)
	local r = m:attemptLoad(7)
	return m, r
end

------------------------------------------------------------ catalog

check("config check passes", Config.check() == true)
local ids = {}
for _, r in ipairs(Rods.list()) do
	table.insert(ids, r.Id .. ":" .. r.Price .. ":" .. r.BiteWait)
end
check("catalog: Basic 0 x1, Tiger 150 x.85, Coral 600 x.75, Tide 2000 x.65, Magma 7500 x.55",
	table.concat(ids, ",") == "FishingRod1:0:1,FishingRod4:150:0.85,FishingRod3:600:0.75,FishingRod2:2000:0.65,FishingRod5:7500:0.55")
check("Basic and Tiger always stocked", Rods.alwaysStocked("FishingRod1") and Rods.alwaysStocked(TIGER) and not Rods.alwaysStocked(MAGMA))

------------------------------------------------------------ loading / migration

do -- new player: Basic owned + equipped, written with the grant
	local store = fakeStore()
	local m, r = loaded(store)
	check("new player loads", r == "ready")
	local p = m:rods(7)
	check("new player: owns Basic only, Basic equipped", p.owned.FishingRod1 and not p.owned[TIGER] and p.equipped == "FishingRod1")
	check("new record: v2 with a rods field, grant money", store.data[KEY].v == 2 and type(store.data[KEY].rods) == "table"
		and store.data[KEY].money == Config.StartingGrant)
end

do -- v1 record: money kept exactly, Basic, other fields kept
	local store = fakeStore()
	store.data[KEY] = { v = 1, money = 4321, granted = true, lock = nil, stats = { caught = 99 } }
	local m = loaded(store)
	check("v1 record: money unchanged", m:balance(7) == 4321)
	check("v1 record: Basic equipped", m:rods(7).equipped == "FishingRod1")
	check("v1 record: bite wait x1", m:rodStats(7).BiteWait == 1)
	check("v1 save: money kept, unknown field kept, v2", m:save(7, false) and store.data[KEY].money == 4321
		and store.data[KEY].stats.caught == 99 and store.data[KEY].v == 2)
end

do -- a newer build's data: version, unknown rods and sub-fields all kept
	local store = fakeStore()
	store.data[KEY] = { v = 5, money = 10, future = "x",
		rods = { owned = { [TIGER] = true, FishingRod9 = true }, equipped = "FishingRod9", skins = { a = 1 } } }
	local m = loaded(store)
	check("unknown equipped rod: plays with Basic here", m:rodStats(7).Id == "FishingRod1")
	check("owned known rods load", m:rods(7).owned[TIGER] == true)
	m:save(7, false)
	local d = store.data[KEY]
	check("newer version number not lowered", d.v == 5)
	check("unknown top field, rod id, rod sub-field and equipped id kept",
		d.future == "x" and d.rods.owned.FishingRod9 == true and d.rods.skins.a == 1 and d.rods.equipped == "FishingRod9")
	check("equipping here replaces the kept equip", m:equipRod(7, TIGER) and m:save(7, false) and store.data[KEY].rods.equipped == TIGER)
end

for _, bad in ipairs({ "junk", { owned = "all" }, { owned = { [TIGER] = 1 } }, { owned = {}, equipped = 5 } }) do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 900, rods = deepCopy(bad) }
	local m = loaded(store)
	check("corrupt rods field: loads Basic, money fine", m:balance(7) == 900 and m:rodStats(7).Id == "FishingRod1")
	check("corrupt rods field: can't buy", select(2, m:buyRod(7, TIGER)) == "rodsUnavailable" and m:balance(7) == 900)
	m:save(7, false)
	local same = type(bad) == "string" and store.data[KEY].rods == bad
		or type(bad) == "table" and type(store.data[KEY].rods) == "table" and store.data[KEY].rods.owned ~= nil == (bad.owned ~= nil)
	check("corrupt rods field: never overwritten on save", same)
end

do -- failed load: nothing written, no rods, no buying
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 500, rods = { owned = { [TIGER] = true }, equipped = TIGER } }
	store.mode = "error"
	local m = MoneyStore.new(store, "jobA", now)
	m:begin(7)
	m:attemptLoad(7)
	m:markFailed(7, "error")
	check("failed load: no rod profile, Basic stats", m:rods(7) == nil and m:rodStats(7).Id == "FishingRod1")
	check("failed load: can't buy or equip", select(2, m:buyRod(7, CORAL)) == "notLoaded" and select(2, m:equipRod(7, TIGER)) == "notLoaded")
	check("failed load: record untouched", store.writes == 0 and store.data[KEY].rods.equipped == TIGER)
end

------------------------------------------------------------ buying

do -- a purchase is ONE write holding the new balance and the rod
	local store = fakeStore()
	store.data[KEY] = { v = 1, money = 1000 }
	local m = loaded(store)
	local writes = store.writes
	local ok, why = m:buyRod(7, TIGER)
	check("buy Tiger: ok", ok and why == nil)
	check("buy Tiger: exactly one write", store.writes == writes + 1)
	check("that write has money - 150 AND Tiger owned + equipped", store.data[KEY].money == 850
		and store.data[KEY].rods.owned[TIGER] == true and store.data[KEY].rods.equipped == TIGER)
	check("buy Tiger: memory matches", m:balance(7) == 850 and m:rodStats(7).Id == TIGER and m:rodStats(7).BiteWait == 0.85)
	check("buying it again: refused as owned, nothing charged", select(2, m:buyRod(7, TIGER)) == "owned" and m:balance(7) == 850)
	check("Basic isn't stored as bought", store.data[KEY].rods.owned.FishingRod1 == nil)
end

do -- not enough money: nothing charged, nothing written
	local store = fakeStore()
	store.data[KEY] = { v = 1, money = 100 }
	local m = loaded(store)
	local writes = store.writes
	check("can't afford Tiger (150 > 100)", select(2, m:buyRod(7, TIGER)) == "funds")
	check("funds: nothing charged, nothing written, not owned", m:balance(7) == 100 and store.writes == writes and not m:rods(7).owned[TIGER])
end

for _, mode in ipairs({ "error", "errorAfter" }) do -- save fails: both undone
	local store = fakeStore()
	store.data[KEY] = { v = 1, money = 1000 }
	local m = loaded(store)
	store.mode = mode
	local ok, why = m:buyRod(7, CORAL)
	check("save " .. mode .. ": purchase reported failed", not ok and tostring(why):find("notSaved", 1, true) ~= nil)
	check("save " .. mode .. ": money back, rod not owned, Basic equipped", m:balance(7) == 1000
		and not m:rods(7).owned[CORAL] and m:rods(7).equipped == "FishingRod1")
	store.mode = nil
	check("save " .. mode .. ": the store never got the rod", store.data[KEY].money == 1000 and (store.data[KEY].rods == nil or not store.data[KEY].rods.owned[CORAL]))
	check("save " .. mode .. ": can buy after", m:buyRod(7, CORAL) and m:balance(7) == 400)
end

do -- lock lost to another server: not bought, not charged, no further saves
	local store = fakeStore()
	store.data[KEY] = { v = 1, money = 1000 }
	local m = loaded(store)
	store.data[KEY].lock = { job = "jobB", t = t }
	local ok, why = m:buyRod(7, TIGER)
	check("lock lost: refused", not ok and tostring(why):find("lockLost", 1, true) ~= nil)
	check("lock lost: other server's record untouched", store.data[KEY].money == 1000 and store.data[KEY].rods == nil)
end

do -- spam / duplicates while the purchase write is in flight
	local store = fakeStore()
	store.data[KEY] = { v = 1, money = 800 }
	local m = loaded(store)
	local during = {}
	store.during = function()
		during.again = { m:buyRod(7, TIGER) }
		during.other = { m:buyRod(7, CORAL) }
		during.equip = { m:equipRod(7, "FishingRod1") }
		during.save = { m:save(7, false) }
		during.credit = m:credit(7, 5)
	end
	check("buy Tiger with spam in flight", m:buyRod(7, TIGER))
	check("spam: second buy of the same rod refused (busy)", during.again[1] == false and during.again[2] == "busy")
	check("spam: another rod refused while one saves", during.other[1] == false and during.other[2] == "busy")
	check("spam: equip refused while saving", during.equip[1] == false and during.equip[2] == "busy")
	check("spam: an overlapping save refused", during.save[1] == false)
	check("charged once; the sale credit that arrived meanwhile kept", m:balance(7) == 800 - 150 + 5)
	check("the credit went into the same write", store.data[KEY].money == 655)
	-- a credit that lands after the write's value was built: dirty, saved next time
	store.after = function()
		m:credit(7, 3)
	end
	m:save(7, false)
	check("credit after the write was built: still dirty, saved next time", m:isDirty(7) and m:save(7, false) and store.data[KEY].money == 658)
end

do -- an equip that happens while a save is in flight isn't lost
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 50, rods = { owned = { [TIGER] = true, [CORAL] = true }, equipped = TIGER } }
	local m = loaded(store)
	store.after = function()
		m:equipRod(7, CORAL)
	end
	m:save(7, false)
	check("equip during a save: still dirty", m:isDirty(7))
	m:save(7, false)
	check("and saved next time", store.data[KEY].rods.equipped == CORAL)
end

------------------------------------------------------------ equipping

do
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 50, rods = { owned = { [TIGER] = true }, equipped = "FishingRod1" } }
	local m = loaded(store)
	check("equip owned Tiger: ok, no charge", m:equipRod(7, TIGER) and m:balance(7) == 50 and m:rodStats(7).Id == TIGER)
	check("equip again: already equipped", select(2, m:equipRod(7, TIGER)) == "equipped")
	check("forged: equip an unowned rod refused", select(2, m:equipRod(7, MAGMA)) == "notOwned" and m:rodStats(7).Id == TIGER)
	for _, forged in ipairs({ "Magma", "FishingRod99", 5, "", { "x" } }) do
		check("forged id refused: " .. tostring(forged), select(2, m:equipRod(7, forged)) == "unknown"
			and not m:buyRod(7, forged) and m:balance(7) == 50)
	end
	check("Basic always equippable", m:equipRod(7, "FishingRod1") and m:rodStats(7).BiteWait == 1)
	-- a record that claims Magma equipped but not owned plays with Basic
	store.data[KEY] = { v = 2, money = 50, rods = { owned = {}, equipped = MAGMA } }
	local m2 = loaded(store, "jobA")
	check("equipped but not owned in the record: Basic", m2:rodStats(7).Id == "FishingRod1")
end

------------------------------------------------------------ rejoin

do
	local store = fakeStore()
	store.data[KEY] = { v = 1, money = 3000 }
	local m = loaded(store)
	m:buyRod(7, TIGER)
	m:buyRod(7, CORAL)
	m:equipRod(7, TIGER)
	check("leave: final save releases the lock", m:save(7, true))
	m:forget(7)
	t += 10
	local m2 = loaded(store, "jobB")
	local p = m2:rods(7)
	check("rejoin elsewhere: money, both rods, Tiger equipped", m2:balance(7) == 3000 - 150 - 600 and p.owned[TIGER] and p.owned[CORAL]
		and p.equipped == TIGER and m2:rodStats(7).BiteWait == 0.85)
	check("rejoin: Coral can be equipped without paying", m2:equipRod(7, CORAL) and m2:balance(7) == 2250)
	check("rejoin: Coral can't be bought again", select(2, m2:buyRod(7, CORAL)) == "owned")
end

do -- an old (v1) server saving a v2 record keeps the rods (it copies unknown fields)
	local store = fakeStore()
	store.data[KEY] = { v = 2, money = 100, lock = { job = "old", t = t }, rods = { owned = { [TIGER] = true }, equipped = TIGER } }
	-- what the released v1 MoneyStore.save does: copy(old), v = 1, money, lock
	local v1 = deepCopy(store.data[KEY])
	v1.v = 1
	v1.money = 120
	v1.lock = nil
	store.data[KEY] = v1
	local m = loaded(store)
	check("after an old server's save: rods still there", m:rods(7).owned[TIGER] and m:rods(7).equipped == TIGER and m:balance(7) == 120)
end

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("rods tests failed")
end
