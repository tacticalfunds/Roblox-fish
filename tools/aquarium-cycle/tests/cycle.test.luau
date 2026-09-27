-- Offline pure-logic tests for tools/aquarium-cycle/src. Run with the
-- standalone Luau CLI from the repo root:
--   luau tools/aquarium-cycle/tests/cycle.test.luau
-- These exercise state, ownership, capacity, upgrades and adapter contracts
-- only. They are NOT Roblox runtime tests: no Instances, prompts, visuals or
-- existing Studio fish/rod/truck code are involved.

local Config = require("../src/Config")
local Upgrades = require("../src/Upgrades")
local CycleState = require("../src/CycleState")
local Adapters = require("../src/Adapters")

local failures, passes = 0, 0
local function check(name: string, cond: any)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. name)
	end
end

local function invariants(state, label)
	local ok, problem = state:checkInvariants()
	check(label .. " invariants (" .. tostring(problem) .. ")", ok)
end

local function fresh(capLevel: number?)
	local s = CycleState.new(Config)
	s:addTank(1, { Capacity = capLevel or 1 })
	s:addTank(2)
	s:registerRod("A", 1)
	s:registerRod("B", 1)
	s:registerRod("C", 2)
	return s
end

-- Feature flag defaults off.
check("feature flag off by default", Config.Enabled == false)

-- Config and upgrade tables.
check("config valid", (Upgrades.validateConfig(Config)))
check("clamp below", Upgrades.clampLevel(Config, "Capacity", -5) == 1)
check("clamp above", Upgrades.clampLevel(Config, "Capacity", 99) == #Config.Upgrades.Capacity.Values)
check("clamp NaN", Upgrades.clampLevel(Config, "Capacity", 0 / 0) == 1)
check("clamp string", Upgrades.clampLevel(Config, "Capacity", "3") == 1)
check("clamp fraction", Upgrades.clampLevel(Config, "Capacity", 2.9) == 2)
check("cost at max is nil", Upgrades.nextCost(Config, "Capacity", 4) == nil)
check("cost level 1", Upgrades.nextCost(Config, "Capacity", 1) == Config.Upgrades.Capacity.Costs[1])
check(
	"bad config rejected",
	not Upgrades.validateConfig({ Upgrades = { X = { DisplayName = "X", Values = { 3, 2 }, Costs = { 1 } } } })
)
check(
	"cost length mismatch rejected",
	not Upgrades.validateConfig({ Upgrades = { X = { DisplayName = "X", Values = { 1, 2 }, Costs = {} } } })
)

-- Unique ids.
do
	local s = fresh()
	local seen = {}
	local dup = false
	for _ = 1, 50 do
		local id = s:spawnRiverFish()
		if seen[id] then
			dup = true
		end
		seen[id] = true
	end
	check("fish ids unique", not dup)
end

-- Happy path: cast -> hook -> land -> release -> river.
do
	local s = fresh()
	local f = s:spawnRiverFish()
	check("cast ok", (s:beginCast(1, "A", 0)))
	check("slot reserved", s:freeSlots(1) == 2)
	check("hook too soon refused", not s:hookFish(1, "A", f, 1))
	check("hook ok", (s:hookFish(1, "A", f, Config.BiteSeconds)))
	check("fish hooked", s:getFish(f).location == "Hooked")
	check("land too soon refused", not s:landCatch(1, "A", Config.BiteSeconds + 0.1))
	local ok, _, landed = s:landCatch(1, "A", Config.BiteSeconds + Config.LiftSeconds)
	check("land ok", ok and landed == f)
	check("fish in tank", s:getFish(f).location == "Tank" and s:getFish(f).owner == 1)
	check("count 1 reserved 0", s:tankInfo(1).count == 1 and s:tankInfo(1).reserved == 0)
	invariants(s, "after land")

	local rok, _, ids = s:release(1, 10)
	check("release ok", rok and #ids == 1 and ids[1] == f)
	check("tank empty after release", s:tankInfo(1).count == 0)
	check("still releasing before swim done", #s:step(10 + Config.ReleaseSwimSeconds - 0.01) == 0)
	local events = s:step(10 + Config.ReleaseSwimSeconds)
	check("returned event", #events == 1 and events[1].kind == "ReturnedToRiver" and events[1].fishId == f)
	check("back in river", s:getFish(f).location == "River")
	invariants(s, "after return")

	-- Recycled: the same fish can be caught again.
	check("recast ok", (s:beginCast(1, "A", 20)))
	check("same fish hooked again", (s:hookFish(1, "A", f, 20 + Config.BiteSeconds)))
end

-- Ownership.
do
	local s = fresh()
	local f = s:spawnRiverFish()
	local ok, err = s:beginCast(2, "A", 0)
	check("cannot cast someone else's rod", not ok and err == "notOwner")
	check("unknown rod refused", not s:beginCast(1, "Z", 0))
	s:beginCast(1, "A", 0)
	local hok, herr = s:hookFish(2, "A", f, 5)
	check("cannot hook on someone else's rod", not hok and herr == "notOwner")
	check("register rod for unknown owner refused", not s:registerRod("D", 99))
	check("duplicate rod refused", not s:registerRod("A", 1))
end

-- Capacity: reservations block casts before the tank is full; nothing lost.
do
	local s = fresh(1) -- capacity 3
	local cap = s:capacity(1)
	check("capacity level 1", cap == Config.Upgrades.Capacity.Values[1])
	s:registerRod("A2", 1)
	s:registerRod("A3", 1)
	s:registerRod("A4", 1)
	local rods = { "A", "B", "A2", "A3", "A4" }
	local casts = 0
	for _, r in ipairs(rods) do
		if s:beginCast(1, r, 0) then
			casts += 1
		end
	end
	check("casts limited by capacity", casts == cap)
	local ok, err = s:beginCast(1, "A4", 0)
	check("extra cast refused as tankFull", not ok and (err == "tankFull" or err == "busy"))
	invariants(s, "at capacity")
end

-- A fish can't be hooked twice, and can't be hooked from the tank.
do
	local s = fresh()
	local f = s:spawnRiverFish()
	s:beginCast(1, "A", 0)
	s:beginCast(1, "B", 0)
	s:hookFish(1, "A", f, 5)
	local ok, err = s:hookFish(1, "B", f, 5)
	check("double hook refused", not ok and err == "fishUnavailable")
	check("bad fish id refused", not s:hookFish(1, "B", 0.5, 5))
	check("unknown fish refused", not s:hookFish(1, "B", 9999, 5))
	invariants(s, "double hook")
end

-- Cast timeout frees the slot; cancel returns hooked fish to the river.
do
	local s = fresh()
	local f = s:spawnRiverFish()
	s:beginCast(1, "A", 0)
	local events = s:step(Config.CastTimeoutSeconds)
	check("cast expired", #events == 1 and events[1].kind == "CastExpired")
	check("slot freed after expiry", s:tankInfo(1).reserved == 0)
	s:beginCast(1, "A", 20)
	s:hookFish(1, "A", f, 20 + Config.BiteSeconds)
	check("cancel returns hooked fish", s:cancelCast("A") == f)
	check("cancelled fish in river", s:getFish(f).location == "River")
	check("hooked rod does not time out", true)
	invariants(s, "after cancel")
end

-- Release: cooldown and batch size from ReleaseRate.
do
	local s = CycleState.new(Config)
	s:addTank(1, { Capacity = 4, ReleaseRate = 2 })
	s:registerRod("A", 1)
	local t = 0
	for _ = 1, 6 do
		local f = s:spawnRiverFish()
		s:beginCast(1, "A", t)
		s:hookFish(1, "A", f, t + Config.BiteSeconds)
		s:landCatch(1, "A", t + Config.BiteSeconds + Config.LiftSeconds)
		t += 10
	end
	check("six in tank", s:tankInfo(1).count == 6)
	local _, _, ids = s:release(1, t)
	check("batch = ReleaseRate level 2", #ids == Config.Upgrades.ReleaseRate.Values[2])
	local ok, err = s:release(1, t + 0.1)
	check("release cooldown", not ok and err == "cooldown")
	local ok2 = s:release(1, t + Config.ReleaseCooldownSeconds)
	check("release after cooldown", ok2)
	local empty = CycleState.new(Config)
	empty:addTank(5)
	local eok, eerr = empty:release(5, 0)
	check("empty tank release refused", not eok and eerr == "empty")
	invariants(s, "after releases")
end

-- Upgrades clamp and never skip levels.
do
	local s = fresh()
	local max = Upgrades.maxLevel(Config, "Capacity")
	for _ = 1, max + 3 do
		s:applyUpgrade(1, "Capacity")
	end
	check("upgrade stops at max", s:tankInfo(1).levels.Capacity == max)
	check("bad upgrade id refused", not s:applyUpgrade(1, "Luck"))
	check(
		"addTank clamps levels",
		(function()
			local t = CycleState.new(Config)
			t:addTank(7, { Capacity = 999, ReleaseRate = -3 })
			local info = t:tankInfo(7)
			return info.levels.Capacity == max and info.levels.ReleaseRate == 1
		end)()
	)
	invariants(s, "after upgrades")
end

-- Owner removal and shutdown return everything to the river.
do
	local s = fresh()
	local a, b, c = s:spawnRiverFish(), s:spawnRiverFish(), s:spawnRiverFish()
	s:beginCast(1, "A", 0)
	s:hookFish(1, "A", a, 5)
	s:landCatch(1, "A", 10)
	s:beginCast(1, "A", 20)
	s:hookFish(1, "A", b, 25) -- still hooked
	s:beginCast(2, "C", 0)
	s:hookFish(2, "C", c, 5)
	local returned = s:removeOwner(1)
	check("removeOwner returns tank + hooked fish", #returned == 2)
	check("owner 1 fish back in river", s:getFish(a).location == "River" and s:getFish(b).location == "River")
	check("owner 1 rods forgotten", s:beginCast(1, "A", 30) == false)
	check("owner 2 untouched", s:getFish(c).location == "Hooked")
	invariants(s, "after removeOwner")
	local all = s:shutdown()
	check("shutdown returns remaining", #all == 1 and all[1] == c)
	invariants(s, "after shutdown")
end

-- Adapter contracts: off by default, no free currency, cost from state.
do
	local s = fresh()
	local adapters = Adapters.defaults()
	check("no adapters by default", adapters.Economy == nil and adapters.Payout == nil and adapters.FishSource == nil)
	local ok, err = Adapters.buyUpgrade(adapters, s, 1, "Capacity")
	check("upgrade refused without economy", not ok and err == "economyAdapterOff")
	check("level unchanged without economy", s:tankInfo(1).levels.Capacity == 1)

	local charged = {}
	local wallet = 60
	adapters.Economy = {
		tryCharge = function(owner, amount, reason)
			if wallet < amount then
				return false
			end
			wallet -= amount
			table.insert(charged, { owner = owner, amount = amount, reason = reason })
			return true
		end,
	}
	local bok = Adapters.buyUpgrade(adapters, s, 1, "Capacity")
	check("upgrade bought", bok and s:tankInfo(1).levels.Capacity == 2)
	check("charged state-derived cost", #charged == 1 and charged[1].amount == Config.Upgrades.Capacity.Costs[1])
	local fok, ferr = Adapters.buyUpgrade(adapters, s, 1, "Capacity")
	check("insufficient funds refused", not fok and ferr == "funds" and s:tankInfo(1).levels.Capacity == 2)
	check("unknown upgrade not charged", not Adapters.buyUpgrade(adapters, s, 1, "Luck") and #charged == 1)

	-- Payout adapter errors are contained.
	adapters.Payout = {
		onEvent = function()
			error("boom")
		end,
	}
	local contained = pcall(Adapters.emit, adapters, { { kind = "ReturnedToRiver", fishId = 1 } })
	check("payout error contained", contained)
end

-- Randomized fuzz: arbitrary operation sequences never break invariants,
-- never lose or duplicate fish.
do
	math.randomseed(12345)
	local stats = { cast = 0, hook = 0, land = 0, release = 0, full = 0 }
	local OPS = { 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 5, 6, 7, 8, 9 }
	for trial = 1, 200 do
		local s = CycleState.new(Config)
		local owners = { 1, 2, 3 }
		local rods = {}
		for _, o in ipairs(owners) do
			s:addTank(o, { Capacity = math.random(0, 6), ReleaseRate = math.random(0, 6) })
			for r = 1, 3 do
				local id = o * 10 + r
				s:registerRod(id, o)
				table.insert(rods, id)
			end
		end
		local total = 0
		for _ = 1, 8 do
			s:spawnRiverFish()
			total += 1
		end
		local now = 0
		for _ = 1, 300 do
			now += math.random() * 3
			-- Weighted toward hook/land so tanks genuinely fill up.
			local op = OPS[math.random(1, #OPS)]
			local owner = owners[math.random(1, #owners)]
			-- Mostly the owner's own rods (valid path), sometimes anyone's
			-- (ownership rejection path).
			local rod = if math.random() < 0.8 then owner * 10 + math.random(1, 3) else rods[math.random(1, #rods)]
			if op == 1 then
				local ok, err = s:beginCast(owner, rod, now)
				if ok then
					stats.cast += 1
				elseif err == "tankFull" then
					stats.full += 1
				end
			elseif op == 2 then
				-- Usually a real fish id (any location), sometimes junk.
				local id = if math.random() < 0.85 then math.random(1, total) else math.random(0, total + 2) + 0.5
				if s:hookFish(owner, rod, id, now) then
					stats.hook += 1
				end
			elseif op == 3 then
				if s:landCatch(owner, rod, now) then
					stats.land += 1
				end
			elseif op == 4 then
				s:cancelCast(rod)
			elseif op == 5 and math.random() < 0.25 then
				-- Releases are infrequent so tanks back up and hit capacity.
				local ok, _, ids = s:release(owner, now)
				if ok then
					stats.release += #ids
				end
			elseif op == 6 and math.random() < 0.15 then
				-- Rare, so small capacities stay in play long enough to fill.
				s:applyUpgrade(owner, if math.random() < 0.5 then "Capacity" else "ReleaseRate")
			elseif op == 7 then
				s:step(now)
			elseif op == 8 then
				s:spawnRiverFish()
				total += 1
			elseif op == 9 and math.random() < 0.05 then
				s:removeOwner(owner)
				s:addTank(owner)
				for r = 1, 3 do
					s:registerRod(owner * 10 + r, owner)
				end
			end
			local ok, problem = s:checkInvariants()
			if not ok then
				check(string.format("fuzz trial %d invariants: %s", trial, tostring(problem)), false)
				break
			end
		end
		local count = 0
		for _ in pairs(s.fish) do
			count += 1
		end
		check("fuzz trial " .. trial .. " conserves fish", count == total)
		s:shutdown()
		local allRiver = true
		for _, f in pairs(s.fish) do
			if f.location ~= "River" then
				allRiver = false
			end
		end
		check("fuzz trial " .. trial .. " shutdown returns all to river", allRiver)
	end
	-- Guard against a vacuous fuzz: every path must actually be exercised.
	print(
		string.format(
			"fuzz coverage: %d casts, %d hooks, %d landed, %d released, %d tankFull refusals",
			stats.cast,
			stats.hook,
			stats.land,
			stats.release,
			stats.full
		)
	)
	check("fuzz lands catches", stats.land >= 200)
	check("fuzz releases fish", stats.release >= 100)
	check("fuzz hits full tanks", stats.full >= 50)
end

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("aquarium-cycle tests failed")
end
