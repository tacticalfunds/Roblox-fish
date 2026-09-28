-- Offline tests: MoneyStore (load/save/lock/failure safety, debit/credit)
-- and Offers (Buy/Pass state machine). Run via run_tests.py.
-- Not Roblox runtime tests: the DataStore is a fake that fails on purpose.

local Config = require("../src/Config")
local MoneyStore = require("../src/MoneyStore")
local Offers = require("../src/Offers")

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

------------------------------------------------------------ fake DataStore

-- UpdateAsync-like: runs the transform on a deep copy, writes the result
-- unless it is nil. `mode` makes it fail: "error" (throws before running),
-- "errorAfter" (runs the transform, then throws without writing), "twice"
-- (runs the transform on a different value first, like a retry).
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
	local store = { data = {}, writes = 0, mode = nil :: string?, onUpdate = nil :: any }
	function store.update(key, transform)
		if store.onUpdate then
			store.onUpdate()
		end
		if store.mode == "error" then
			error("DataStore request failed (fake)")
		end
		if store.mode == "twice" then
			transform(deepCopy({ money = 1, lock = { job = "other", t = 0 } }))
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

local clockNow = 1000
local function now()
	return clockNow
end

local function newMoney(store, job)
	return MoneyStore.new(store, job or "jobA", now)
end

local KEY = MoneyStore.key(42)

------------------------------------------------------------ loading

-- Brand-new player: grant once, saved with our lock
do
	local store = fakeStore()
	local m = newMoney(store)
	m:begin(42)
	local r, kind = m:attemptLoad(42)
	check("new player loads", r == "ready" and kind == "new")
	check("new player gets the starting grant", m:balance(42) == Config.StartingGrant)
	check(
		"grant record written with our lock",
		store.data[KEY].money == Config.StartingGrant and store.data[KEY].lock.job == "jobA"
	)
	-- a second session later loads the saved money, no second grant
	check("save releases", m:save(42, true))
	m:forget(42)
	store.data[KEY].money = 7
	local m2 = newMoney(store, "jobB")
	m2:begin(42)
	check("returning player loads saved money", m2:attemptLoad(42) == "ready" and m2:balance(42) == 7)
end

-- Load error: NO grant, NO defaults, never saved
do
	local store = fakeStore()
	store.data[KEY] = { v = 1, money = 5000 }
	store.mode = "error"
	local m = newMoney(store)
	m:begin(42)
	check("errored load reports error", (m:attemptLoad(42)) == "error")
	check("still loading after an error (no defaults)", m:state(42) == "Loading" and m:balance(42) == nil)
	m:markFailed(42, "error")
	check("failed player can't spend", select(2, m:tryDebit(42, 1)) == "notLoaded")
	check("failed player is never saved", select(2, m:save(42, false)) == "notLoaded")
	check("saved record untouched by a failed load", store.data[KEY].money == 5000 and store.writes == 0)
	check("credit while failed is held as pending", m:credit(42, 30) == "pending")
	-- background retry succeeds: real money + pending, no grant
	store.mode = nil
	check("failed load can be reopened", m:reopen(42))
	check("retry loads", m:attemptLoad(42) == "ready")
	check("real money + pending credit, no grant", m:balance(42) == 5030)
	check("pending credit marks dirty", m:isDirty(42))
end

-- Error after the transform ran (write not committed): not ready, no grant
do
	local store = fakeStore()
	store.mode = "errorAfter"
	local m = newMoney(store)
	m:begin(42)
	check("write-failed load is an error", (m:attemptLoad(42)) == "error" and m:balance(42) == nil)
	check("nothing written", store.writes == 0)
end

-- Failed player leaves: pending credits dropped, record untouched
do
	local store = fakeStore()
	store.data[KEY] = { v = 1, money = 12 }
	store.mode = "error"
	local m = newMoney(store)
	m:begin(42)
	m:attemptLoad(42)
	m:markFailed(42, "error")
	m:credit(42, 99)
	m:forget(42)
	check("record untouched after a failed player leaves", store.data[KEY].money == 12 and store.writes == 0)
end

-- Corrupt record: left untouched, no grant, can't be reopened
do
	for _, bad in ipairs({ { money = "lots" }, { money = -5 }, { money = 1.5 }, { money = 0 / 0 }, "text", 7 }) do
		local store = fakeStore()
		store.data[KEY] = bad
		local m = newMoney(store)
		m:begin(42)
		local r = m:attemptLoad(42)
		local st, why = m:state(42)
		check(
			"corrupt record refused (" .. tostring(type(bad) == "table" and bad.money or bad) .. ")",
			r == "corrupt" and st == "Failed" and why == "corrupt"
		)
		check("corrupt record untouched", store.writes == 0)
		check("corrupt load not reopened", not m:reopen(42))
	end
end

-- Session lock: fresh lock of another server blocks; stale lock is taken
do
	local store = fakeStore()
	store.data[KEY] = { v = 1, money = 50, lock = { job = "other", t = clockNow - 10 } }
	local m = newMoney(store)
	m:begin(42)
	check("locked by another server", (m:attemptLoad(42)) == "locked" and m:balance(42) == nil)
	check("lock untouched", store.data[KEY].lock.job == "other")
	store.data[KEY].lock.t = clockNow - Config.LockSeconds - 1
	check(
		"stale lock taken",
		m:attemptLoad(42) == "ready" and m:balance(42) == 50 and store.data[KEY].lock.job == "jobA"
	)
end

-- UpdateAsync retrying the transform: the last run decides
do
	local store = fakeStore()
	store.mode = "twice"
	local m = newMoney(store)
	m:begin(42)
	local r, kind = m:attemptLoad(42)
	check(
		"retried transform: last decision wins (new player)",
		r == "ready" and kind == "new" and m:balance(42) == Config.StartingGrant
	)
end

-- Player leaves while the load call is in flight: lock given back
do
	local store = fakeStore()
	store.data[KEY] = { v = 1, money = 9 }
	local m = newMoney(store)
	m:begin(42)
	store.onUpdate = function()
		store.onUpdate = nil
		m:forget(42)
	end
	check("left mid-load", (m:attemptLoad(42)) == "notLoading")
	check("lock released for their next server", store.data[KEY].lock == nil and store.data[KEY].money == 9)
end

------------------------------------------------------------ session ids

do
	local n = 0
	local function guid()
		n += 1
		return "guid" .. n
	end
	check("live JobId used as the lock owner", MoneyStore.sessionId("abc-123", guid) == "abc-123")
	local a = MoneyStore.sessionId("", guid)
	local b = MoneyStore.sessionId("", guid)
	check("empty Studio JobId gets a GUID", a ~= "" and a:find("studio-", 1, true) == 1)
	check("two Studio sessions get different lock owners", a ~= b)
	check("nil JobId also gets a GUID", MoneyStore.sessionId(nil, guid) ~= "")
	-- two Studio sessions on the same real record: the second is locked out
	local store = fakeStore()
	local s1 = newMoney(store, a)
	local s2 = newMoney(store, b)
	s1:begin(42)
	s2:begin(42)
	check("session A loads", s1:attemptLoad(42) == "ready")
	check("session B is locked out (not sharing an empty owner)", (s2:attemptLoad(42)) == "locked")
	check("A still owns the record", store.data[KEY].lock.job == a)
	check("test users are negative ids", MoneyStore.isTestUser(-1) and not MoneyStore.isTestUser(42))
end

------------------------------------------------------------ spending

do
	local store = fakeStore()
	local m = newMoney(store)
	m:begin(42)
	m:attemptLoad(42)
	check("debit ok", m:tryDebit(42, 30))
	check("balance 70", m:balance(42) == 70)
	local ok, why = m:tryDebit(42, 71)
	check("insufficient funds refused", not ok and why == "funds" and m:balance(42) == 70)
	for _, bad in ipairs({ 0, -5, 1.5, 0 / 0, math.huge, "5" }) do
		check("bad debit amount refused: " .. tostring(bad), not m:tryDebit(42, bad) and m:balance(42) == 70)
	end
	check("credit paid", m:credit(42, 5) == "paid" and m:balance(42) == 75)
	check(
		"bad credit dropped",
		m:credit(42, -5) == "dropped" and m:credit(42, 2.5) == "dropped" and m:balance(42) == 75
	)
	check("credit to unknown player dropped", m:credit(999, 5) == "dropped")
	check("balance capped", m:credit(42, Config.MaxBalance) == "paid" and m:balance(42) == Config.MaxBalance)
end

------------------------------------------------------------ saving

do
	local store = fakeStore()
	local m = newMoney(store)
	m:begin(42)
	m:attemptLoad(42)
	m:tryDebit(42, 40)
	clockNow += 30
	check("autosave writes", m:save(42, false))
	check("saved balance 60 and lock refreshed", store.data[KEY].money == 60 and store.data[KEY].lock.t == clockNow)
	check("clean after save", not m:isDirty(42))
	-- error: reported as failure, stays dirty, nothing written
	m:tryDebit(42, 10)
	store.mode = "error"
	local ok, why = m:save(42, false)
	check("save error is NOT reported as success", not ok and string.find(why or "", "error") ~= nil)
	check("still dirty after failed save", m:isDirty(42) and store.data[KEY].money == 60)
	store.mode = "errorAfter"
	check("write-after error also a failure", not m:save(42, false) and store.data[KEY].money == 60)
	store.mode = nil
	-- another server stole the lock: stop everything for this player
	store.data[KEY].lock = { job = "jobB", t = clockNow }
	local ok2, why2 = m:save(42, false)
	check("lost lock: save refused", not ok2 and why2 == "lockLost")
	check(
		"lost lock: other server's record untouched",
		store.data[KEY].money == 60 and store.data[KEY].lock.job == "jobB"
	)
	check("lost lock: no more spending", not m:tryDebit(42, 1))
	check("lost lock: credits dropped", m:credit(42, 5) == "dropped")
end

-- Release on leave clears the lock; a missing record at save time is "lost"
do
	local store = fakeStore()
	local m = newMoney(store)
	m:begin(42)
	m:attemptLoad(42)
	check("release save", m:save(42, true) and store.data[KEY].lock == nil and m:state(42) == "Closed")
	check("no saving after release", not m:save(42, false))
	local m2 = newMoney(store)
	m2:begin(42)
	m2:attemptLoad(42)
	store.data[KEY] = nil
	check("record deleted under us: lost, not recreated", not m2:save(42, false) and store.data[KEY] == nil)
end

-- A save while another save is in flight is refused (the caller retries)
do
	local store = fakeStore()
	local m = newMoney(store)
	m:begin(42)
	m:attemptLoad(42)
	local inner
	store.onUpdate = function()
		store.onUpdate = nil
		inner = table.pack(m:save(42, false))
	end
	check("outer save ok", m:save(42, false))
	check("overlapping save refused as busy", inner[1] == false and inner[2] == "busy")
end

------------------------------------------------------------ offers

local function deps(o)
	o = o or {}
	local log = { debits = 0, delivered = 0, refunds = 0, refunded = 0 }
	local balance = o.balance or 100
	local d = {
		inRange = function()
			return o.inRange ~= false
		end,
		reservationOk = function()
			return o.reservationOk ~= false
		end,
		debit = function(amount)
			if o.notLoaded then
				return false, "notLoaded"
			end
			if balance < amount then
				return false, "funds"
			end
			balance -= amount
			log.debits += 1
			return true, nil
		end,
		deliver = function()
			if o.deliverError then
				error("tank exploded (fake)")
			end
			if o.deliverFails then
				return false
			end
			log.delivered += 1
			return true
		end,
		refund = function(amount)
			balance += amount
			log.refunds += 1
			log.refunded += amount
		end,
	}
	return d, log, function()
		return balance
	end
end

local CASTER, OTHER = 42, 77

do
	local offers = Offers.new(20)
	local offer = offers:open(1, CASTER, "Salmon", 10, nil, 17, 0)
	check("offer opens", offer ~= nil and offer.status == "Open" and offer.expiresAt == 20)
	check("one open offer per rod", (offers:open(1, CASTER, "Cod", 1, nil, 1, 0)) == nil)
	local d, log, bal = deps()
	check("caster buys", (offers:buy(offer.id, CASTER, 1, d)) == "bought")
	check("charged once, delivered once", log.debits == 1 and log.delivered == 1 and bal() == 83)
	check(
		"repeat click: already bought, no second charge",
		(offers:buy(offer.id, CASTER, 1, d)) == "alreadyBought" and log.debits == 1 and log.delivered == 1
	)
	check("pass after buy is closed", offers:pass(offer.id, CASTER) == "closed")
	check("rod freed after buy", offers:open(1, CASTER, "Cod", 1, nil, 1, 2) ~= nil)
end

-- Someone else can't buy or pass the caster's fish
do
	local offers = Offers.new(20)
	local offer = offers:open(2, CASTER, "Cod", 1, nil, 1, 0)
	local d, log = deps()
	check("other player's buy refused", (offers:buy(offer.id, OTHER, 1, d)) == "notYours" and log.debits == 0)
	check("other player's pass refused", offers:pass(offer.id, OTHER) == "notYours" and offer.status == "Open")
	check(
		"forged/unknown offer id",
		(offers:buy(999, CASTER, 1, d)) == "unknown" and (offers:buy("1" :: any, CASTER, 1, d)) == "unknown"
	)
end

-- Insufficient funds keeps the offer; buying later works
do
	local offers = Offers.new(20)
	local offer = offers:open(3, CASTER, "Tuna", 14, nil, 48, 0)
	local d, log = deps({ balance = 10 })
	check("insufficient funds", (offers:buy(offer.id, CASTER, 1, d)) == "funds")
	check("offer preserved, nothing delivered", offer.status == "Open" and log.delivered == 0 and log.debits == 0)
	local d2, log2 = deps({ balance = 100 })
	check("buy after topping up", (offers:buy(offer.id, CASTER, 2, d2)) == "bought" and log2.debits == 1)
	local d3 = deps({ notLoaded = true })
	local o2 = offers:open(9, CASTER, "Cod", 1, nil, 1, 0)
	check("money not loaded: offer kept", (offers:buy(o2.id, CASTER, 1, d3)) == "notLoaded" and o2.status == "Open")
end

-- Full / unavailable tank: cancelled, never charged
do
	local offers = Offers.new(20)
	local offer = offers:open(4, CASTER, "Cod", 1, nil, 1, 0)
	local d, log = deps({ reservationOk = false })
	check(
		"tank unavailable -> cancelled",
		(offers:buy(offer.id, CASTER, 1, d)) == "tankUnavailable" and offer.status == "Cancelled"
	)
	check("never charged when the tank can't take it", log.debits == 0 and log.delivered == 0)
end

-- Out of range keeps the offer; expired closes it
do
	local offers = Offers.new(20)
	local offer = offers:open(5, CASTER, "Cod", 1, nil, 1, 0)
	local far, logFar = deps({ inRange = false })
	check(
		"too far",
		(offers:buy(offer.id, CASTER, 1, far)) == "tooFar" and offer.status == "Open" and logFar.debits == 0
	)
	local d, log = deps()
	check("expired at the deadline", (offers:buy(offer.id, CASTER, 20, d)) == "expired" and log.debits == 0)
	check("expired offer closed", offer.status == "Expired")
end

-- Delivery failure refunds exactly the price
do
	for _, mode in ipairs({ "deliverFails", "deliverError" }) do
		local offers = Offers.new(20)
		local offer = offers:open(6, CASTER, "Salmon", 10, "Gold", 30, 0)
		local d, log, bal = deps({ [mode] = true })
		check(mode .. ": reported", (offers:buy(offer.id, CASTER, 1, d)) == "deliveryFailed")
		check(
			mode .. ": refunded in full",
			log.debits == 1 and log.refunds == 1 and log.refunded == 30 and bal() == 100
		)
		check(mode .. ": offer cancelled", offer.status == "Cancelled")
	end
end

-- Pass / timeout / disconnect / feature off: no charge
do
	local offers = Offers.new(20)
	local a = offers:open(1, CASTER, "Cod", 1, nil, 1, 0)
	local b = offers:open(2, CASTER, "Cod", 1, nil, 1, 0)
	local c = offers:open(3, OTHER, "Cod", 1, nil, 1, 5)
	check("pass", offers:pass(a.id, CASTER) == "passed" and a.status == "Passed")
	local d, log = deps()
	check("buy after pass refused", (offers:buy(a.id, CASTER, 1, d)) == "closed" and log.debits == 0)
	local expired = offers:expire(20)
	check("timeout expires only due offers", #expired == 1 and expired[1] == b and c.status == "Open")
	local gone = offers:cancelForUser(OTHER, "left")
	check("disconnect cancels the leaver's offers", #gone == 1 and c.status == "Cancelled")
	local e = offers:open(4, CASTER, "Cod", 1, nil, 1, 30)
	check("feature off cancels everything", #offers:cancelAll("disabled") == 1 and e.status == "Cancelled")
	check("no open offers", offers:openCount() == 0)
	offers:forget(e.id)
	check("forgotten", offers:get(e.id) == nil)
	check(
		"bad prices refused",
		(offers:open(7, CASTER, "Cod", 1, nil, 0, 0)) == nil and (offers:open(7, CASTER, "Cod", 1, nil, 1.5, 0)) == nil
	)
end

-- Randomised clicking: each offer charged at most once, delivered at most once
do
	local rng = makeRng(3)
	local offers = Offers.new(20)
	local charged, delivered = {}, {}
	local openIds = {}
	for step = 1, 4000 do
		local t = step * 0.05
		local op = rng:NextInteger(1, 5)
		if op == 1 then
			local o = offers:open(rng:NextInteger(1, 5), rng:NextInteger(1, 3), "Cod", 1, nil, rng:NextInteger(1, 5), t)
			if o then
				table.insert(openIds, o.id)
			end
		elseif #openIds > 0 then
			local id = openIds[rng:NextInteger(1, #openIds)]
			local user = rng:NextInteger(1, 3)
			if op == 2 or op == 3 then
				local d = {
					inRange = function()
						return rng:NextNumber() > 0.1
					end,
					reservationOk = function()
						return rng:NextNumber() > 0.05
					end,
					debit = function()
						if rng:NextNumber() < 0.2 then
							return false, "funds"
						end
						charged[id] = (charged[id] or 0) + 1
						return true, nil
					end,
					deliver = function()
						if rng:NextNumber() < 0.05 then
							return false
						end
						delivered[id] = (delivered[id] or 0) + 1
						return true
					end,
					refund = function()
						charged[id] -= 1
					end,
				}
				offers:buy(id, user, t, d)
			elseif op == 4 then
				offers:pass(id, user)
			else
				offers:expire(t)
			end
		end
	end
	local ok = true
	for id, n in pairs(charged) do
		if n > 1 or n < 0 or (delivered[id] or 0) > 1 or (n == 1) ~= ((delivered[id] or 0) == 1) then
			ok = false
		end
	end
	check("random clicks: net charge 1 exactly when delivered, never twice", ok)
end

-- Studio test clients (negative UserIds): accepted only when allowed
do
	local live = Offers.new(20)
	check("live: negative caster refused", (live:open(1, -1, "Cod", 1, nil, 1, 0)) == nil)
	check(
		"live: zero/fraction/NaN refused",
		(live:open(1, 0, "Cod", 1, nil, 1, 0)) == nil
			and (live:open(1, 1.5, "Cod", 1, nil, 1, 0)) == nil
			and (live:open(1, 0 / 0, "Cod", 1, nil, 1, 0)) == nil
	)
	local studio = Offers.new(20, true)
	local o = studio:open(1, -1, "Cod", 1, nil, 1, 0)
	check("studio: Player1 (-1) can open an offer", o ~= nil)
	check("studio: zero still refused", (studio:open(2, 0, "Cod", 1, nil, 1, 0)) == nil)
	local d, log = deps()
	check("studio: -2 can't buy -1's fish", (studio:buy(o.id, -2, 1, d)) == "notYours" and log.debits == 0)
	check("studio: -1 buys", (studio:buy(o.id, -1, 1, d)) == "bought" and log.debits == 1)
	-- a negative test user's money works in memory
	local m = newMoney(fakeStore(), "s")
	m:begin(-1)
	check(
		"test user loads (store routing is the service's job)",
		m:attemptLoad(-1) == "ready" and m:balance(-1) == Config.StartingGrant
	)
end

-- Buy reach from the rod stand: prompt distance + slack, nothing beyond
do
	local o = Config.Offer
	local limit = o.PromptDistance + o.ReachSlack
	check("config sane with the prompt distances", (Config.check()))
	check("at the stand", Offers.inReach(0, o.PromptDistance, o.ReachSlack))
	check("at the prompt edge", Offers.inReach(o.PromptDistance, o.PromptDistance, o.ReachSlack))
	check("inside the slack", Offers.inReach(limit, o.PromptDistance, o.ReachSlack))
	check("just beyond the slack", not Offers.inReach(limit + 0.01, o.PromptDistance, o.ReachSlack))
	check("far away (old 100-stud fish range)", not Offers.inReach(100, o.PromptDistance, o.ReachSlack))
	check(
		"NaN / negative / non-number refused",
		not Offers.inReach(0 / 0, 10, 4) and not Offers.inReach(-1, 10, 4) and not Offers.inReach("1", 10, 4)
	)
	check("prompt range is short (<= 15 studs)", o.PromptDistance <= 15)
end

-- Roll chance text: formats a real probability, never invents one
do
	check("25%", Offers.chanceText(0.25) == "25%")
	check("12.5% rounds to 13%", Offers.chanceText(0.125) == "13%")
	check("3.4%", Offers.chanceText(0.034) == "3.4%")
	check("0.45%", Offers.chanceText(0.0045) == "0.45%")
	check("tiny", Offers.chanceText(0.00001) == "<0.01%")
	check("certain", Offers.chanceText(1) == "100%")
	check(
		"nothing shown without a valid probability",
		Offers.chanceText(nil) == nil
			and Offers.chanceText(0) == nil
			and Offers.chanceText(1.2) == nil
			and Offers.chanceText(0 / 0) == nil
			and Offers.chanceText("0.5") == nil
	)
	-- the rod pool: weights w^0.85, chance = weight / total (as rodChance does)
	local weights = { Cod = 50, Salmon = 20, Tuna = 5, Shark = 1 }
	local total, rw = 0, {}
	for name, w in pairs(weights) do
		rw[name] = w ^ 0.85
		total += rw[name]
	end
	local sum = 0
	for name in pairs(weights) do
		sum += rw[name] / total
	end
	check("rod chances sum to 1", math.abs(sum - 1) < 1e-9)
	check("flattened: Shark better than raw odds", rw.Shark / total > 1 / 76)
end

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("money/offers tests failed")
end
