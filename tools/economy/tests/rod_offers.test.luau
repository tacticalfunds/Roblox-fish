-- Offline integration test for the rod Buy/Pass slice: the REAL aquarium
-- tank core (SharedTank, capacity 3, reservations), the REAL MoneyStore
-- (fake DataStore) and the REAL Offers state machine, wired the way
-- EconomyService._offerAction / runRodOffer and the patched
-- RodFishingSystem wire them:
--   press -> tank:reserve -> hook (+caster meta) -> offer at the offer price
--   Buy  -> Offers.buy{ inRange, reservationOk = aquarium active,
--                       debit = MoneyStore.tryDebit, deliver = tank:land,
--                       refund = MoneyStore.credit }
--   not bought -> tank:abort (frees the spot; fish gone, never the grinder)
-- Run via run_tests.py. Pure-logic simulation, not a Roblox runtime test.

local Config = require("../src/Config")
local Pricing = require("../src/Pricing")
local MoneyStore = require("../src/MoneyStore")
local Offers = require("../src/Offers")
local AqConfig = require("../src/aquarium/Config")
local SharedTank = require("../src/aquarium/SharedTank")

local failures, passes = 0, 0
local function check(name: string, cond: any)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. name)
	end
end

local CASTER, OTHER = 42, 77

local function world()
	local w = {}
	w.now = 0
	w.store = { data = {}, fail = false }
	function w.store.update(key, transform)
		if w.store.fail then
			error("DataStore down (fake)")
		end
		local r = transform(w.store.data[key])
		if r ~= nil then
			w.store.data[key] = r
		end
		return w.store.data[key]
	end
	w.money = MoneyStore.new(w.store, "job", function()
		return 1000 + w.now
	end)
	w.tank = SharedTank.new(AqConfig)
	w.tank:registerRods({ 1, 2, 3, 4, 5 })
	w.aquariumActive = true
	w.offers = Offers.new(Config.Offer.TimeoutSeconds)
	w.inRange = true
	w.grinder = 0 -- rod fish sent to the grinder (must stay 0)
	function w.join(userId)
		w.money:begin(userId)
		return w.money:attemptLoad(userId)
	end
	-- press: reserve spots for every idle rod (offer mode needs the aquarium)
	function w.press(keys)
		if not w.aquariumActive then
			return {}
		end
		return (w.tank:reserve(keys, w.now))
	end
	-- a reserved rod hooks and reveals a fish, then opens its offer
	function w.reveal(rodKey, caster, fishName, tier)
		w.now += 4 -- cast + bite wait (the live rod hooks >= 3 s after casting)
		local ok = w.tank:hook(rodKey, fishName, w.now, { OwnerId = caster })
		if not ok then
			return nil
		end
		w.now += 5 -- reel + reveal (> LiftSeconds)
		local price = Pricing.offerPrice(tier, nil)
		return (w.offers:open(rodKey, caster, fishName, tier, nil, price, w.now))
	end
	function w.buy(offer, userId)
		return (
			w.offers:buy(offer.id, userId, w.now, {
				inRange = function()
					return w.inRange
				end,
				reservationOk = function()
					return w.aquariumActive
				end,
				debit = function(amount)
					return w.money:tryDebit(userId, amount)
				end,
				deliver = function()
					if not w.aquariumActive then
						return false
					end
					return (w.tank:land(offer.rodKey, w.now))
				end,
				refund = function(amount)
					w.money:credit(userId, amount)
				end,
			})
		)
	end
	-- the rod's cleanup once the offer is resolved (patched runRod)
	function w.finish(offer)
		if offer.status ~= "Bought" then
			w.tank:abort(offer.rodKey)
		end
		w.offers:forget(offer.id)
	end
	function w.count()
		return w.tank:info().count
	end
	function w.free()
		return w.tank:info().free
	end
	function w.healthy(label)
		local ok, why = w.tank:check()
		check(label .. " (" .. tostring(why) .. ")", ok)
	end
	return w
end

-- Starter funds: a new player can buy the first tank upgrade AND keep buying fish
do
	local w = world()
	check("new player loads with the grant", w.join(CASTER) == "ready" and w.money:balance(CASTER) == 100)
	check("grant covers Tank 6 (50) with >= 30 left", 100 - AqConfig.Upgrades.Capacity.Costs[1] >= 30)
end

-- Happy path: price shown = price charged, charged once, delivered once
do
	local w = world()
	w.join(CASTER)
	check("3 of 5 rods reserved (tank capacity 3)", #w.press({ 1, 2, 3, 4, 5 }) == 3)
	local offer = w.reveal(1, CASTER, "Salmon", 10)
	check("offer opened at the server price", offer ~= nil and offer.price == Pricing.offerPrice(10) and offer.price == 17)
	check("tank still empty while the offer waits", w.count() == 0)
	check("buy", w.buy(offer, CASTER) == "bought")
	check("charged exactly the shown price", w.money:balance(CASTER) == 100 - 17)
	check("fish is in the aquarium", w.count() == 1)
	check("repeat click: no second charge", w.buy(offer, CASTER) == "alreadyBought" and w.money:balance(CASTER) == 83)
	check("repeat click: no second fish", w.count() == 1)
	w.finish(offer)
	w.healthy("tank healthy after a purchase")
end

-- Full aquarium: no cast, so no offer and no charge
do
	local w = world()
	w.join(CASTER)
	local reserved = w.press({ 1, 2, 3, 4, 5 })
	for i, key in ipairs(reserved) do
		local offer = w.reveal(key, CASTER, "Cod", 1)
		check("buy fills slot " .. i, w.buy(offer, CASTER) == "bought")
		w.finish(offer)
	end
	check("tank full", w.count() == 3 and w.free() == 0)
	check("next press reserves nothing (no cast, no offer)", #w.press({ 4, 5 }) == 0)
	check("paid only for delivered fish", w.money:balance(CASTER) == 100 - 3 * Pricing.offerPrice(1))
	w.healthy("tank healthy when full")
end

-- Pass: spot freed, fish gone, no charge, no grinder
do
	local w = world()
	w.join(CASTER)
	w.press({ 1 })
	local offer = w.reveal(1, CASTER, "Cod", 1)
	check("one spot held by the offer", w.free() == 2)
	check("pass", w.offers:pass(offer.id, CASTER) == "passed")
	w.finish(offer)
	check("pass frees the spot", w.free() == 3 and w.count() == 0)
	check("pass costs nothing", w.money:balance(CASTER) == 100)
	local late = w.buy(offer, CASTER) -- the record is gone after cleanup
	check("buy after pass refused, no charge", (late == "closed" or late == "unknown") and w.money:balance(CASTER) == 100)
	check("never sent to the grinder", w.grinder == 0)
	w.healthy("tank healthy after pass")
end

-- Timeout: same as pass
do
	local w = world()
	w.join(CASTER)
	w.press({ 2 })
	local offer = w.reveal(2, CASTER, "Cod", 1)
	w.now += Config.Offer.TimeoutSeconds
	check("buy at the deadline is refused", w.buy(offer, CASTER) == "expired")
	w.finish(offer)
	check("timeout frees the spot, no charge", w.free() == 3 and w.money:balance(CASTER) == 100)
end

-- Someone else can't buy the caster's fish
do
	local w = world()
	w.join(CASTER)
	w.join(OTHER)
	w.press({ 1 })
	local offer = w.reveal(1, CASTER, "Tuna", 14)
	check("other player's buy refused", w.buy(offer, OTHER) == "notYours")
	check("nobody charged", w.money:balance(OTHER) == 100 and w.money:balance(CASTER) == 100)
	check("offer still the caster's", offer.status == "Open")
end

-- Insufficient funds keeps the offer (and the spot); topping up works
do
	local w = world()
	w.join(CASTER)
	w.money:tryDebit(CASTER, 90) -- 10 left
	w.press({ 1 })
	local offer = w.reveal(1, CASTER, "Tuna", 14) -- 48
	check("insufficient funds", w.buy(offer, CASTER) == "funds")
	check("offer kept, spot kept, nothing charged", offer.status == "Open" and w.free() == 2 and w.money:balance(CASTER) == 10)
	w.money:credit(CASTER, 40)
	check("buy after topping up", w.buy(offer, CASTER) == "bought" and w.money:balance(CASTER) == 2 and w.count() == 1)
end

-- Out of range keeps the offer
do
	local w = world()
	w.join(CASTER)
	w.press({ 1 })
	local offer = w.reveal(1, CASTER, "Cod", 1)
	w.inRange = false
	check("too far: refused, kept, not charged", w.buy(offer, CASTER) == "tooFar" and offer.status == "Open" and w.money:balance(CASTER) == 100)
end

-- Disconnect mid-offer: cancelled, spot freed, no charge, record untouched
do
	local w = world()
	w.join(CASTER)
	check("save before", w.money:save(CASTER, false))
	w.press({ 1, 2 })
	local a = w.reveal(1, CASTER, "Cod", 1)
	local b = w.reveal(2, CASTER, "Cod", 1)
	local gone = w.offers:cancelForUser(CASTER, "left")
	w.finish(a)
	w.finish(b)
	check("both offers cancelled", #gone == 2 and a.status == "Cancelled" and b.status == "Cancelled")
	check("spots freed", w.free() == 3 and w.count() == 0)
	check("final save ok", w.money:save(CASTER, true))
	check("saved balance unchanged by the cancelled offers", w.store.data[MoneyStore.key(CASTER)].money == 100)
end

-- Aquarium switched off mid-offer: cancelled at Buy, never charged
do
	local w = world()
	w.join(CASTER)
	w.press({ 1 })
	local offer = w.reveal(1, CASTER, "Cod", 1)
	w.aquariumActive = false
	w.tank:shutdown()
	check("aquarium closed: cancelled", w.buy(offer, CASTER) == "tankUnavailable" and offer.status == "Cancelled")
	check("aquarium closed: not charged", w.money:balance(CASTER) == 100)
	check("no press while the aquarium is closed", #w.press({ 1 }) == 0)
end

-- Feature switched off mid-offer: cancelAll, nothing charged or delivered
do
	local w = world()
	w.join(CASTER)
	w.press({ 1, 2 })
	local a = w.reveal(1, CASTER, "Cod", 1)
	local b = w.reveal(2, CASTER, "Cod", 1)
	check("disable cancels both", #w.offers:cancelAll("disabled") == 2)
	w.finish(a)
	w.finish(b)
	check("disable: no charge, no fish, spots freed", w.money:balance(CASTER) == 100 and w.count() == 0 and w.free() == 3)
end

-- Delivery failure (the hook was lost before Buy): refunded in full
do
	local w = world()
	w.join(CASTER)
	w.press({ 1 })
	local offer = w.reveal(1, CASTER, "Salmon", 10)
	w.tank:abort(1) -- e.g. the rod task errored and freed its spot
	check("delivery fails", w.buy(offer, CASTER) == "deliveryFailed")
	check("refunded in full", w.money:balance(CASTER) == 100)
	check("no fish delivered", w.count() == 0)
	w.healthy("tank healthy after failed delivery")
end

-- Money not loaded (DataStore down): offers can't be bought, nothing written
do
	local w = world()
	w.store.fail = true
	check("load errors", w.join(CASTER) == "error")
	w.money:markFailed(CASTER, "error")
	w.press({ 1 })
	local offer = w.reveal(1, CASTER, "Cod", 1)
	check("buy refused while money isn't loaded", w.buy(offer, CASTER) == "notLoaded" and offer.status == "Open")
	check("no fish delivered", w.count() == 0)
	check("nothing written for the unloaded player", next(w.store.data) == nil)
end

-- Rapid clicking across several rods: each fish charged at most once
do
	local w = world()
	w.join(CASTER)
	local keys = w.press({ 1, 2, 3 })
	local list = {}
	for _, k in ipairs(keys) do
		table.insert(list, w.reveal(k, CASTER, "Cod", 5))
	end
	for _ = 1, 10 do
		for _, offer in ipairs(list) do
			w.buy(offer, CASTER)
			w.offers:pass(offer.id, CASTER)
		end
	end
	check("3 fish, charged 3 times", w.count() == 3 and w.money:balance(CASTER) == 100 - 3 * Pricing.offerPrice(5))
	w.healthy("tank healthy after rapid clicks")
end

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("rod offer integration tests failed")
end
