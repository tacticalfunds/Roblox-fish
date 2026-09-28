-- Offline pure-logic tests for the shared-scene integration helpers
-- (SharedTank, RiverRelease, TankPath, Messages). Run via run_tests.py.
-- Not Roblox runtime tests.

local Config = require("../src/Config")
local SharedTank = require("../src/SharedTank")
local RiverRelease = require("../src/RiverRelease")
local TankPath = require("../src/TankPath")
local Messages = require("../src/Messages")

local failures, passes = 0, 0
local function check(name: string, cond: any)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. name)
	end
end

local function healthy(tank, label)
	local ok, problem = tank:check()
	check(label .. " (" .. tostring(problem) .. ")", ok)
end

local RODS = { 1, 2, 3, 4, 5 }
local BITE = Config.BiteSeconds
local LIFT = Config.LiftSeconds

local function fresh()
	local tank = SharedTank.new(Config)
	check("five rods registered", tank:registerRods(RODS) == 5)
	return tank
end

-- One physical tank: default capacity 3, never per player.
do
	local tank = fresh()
	local info = tank:info()
	check("default capacity 3", info.capacity == 3 and info.free == 3 and not info.full)
	check("duplicate rod registration ignored", tank:registerRods({ 1 }) == 0)
end

-- Reserve BEFORE rod tasks: 5 idle rods, 3 slots -> exactly 3 may cast.
do
	local tank = fresh()
	local reserved, reason = tank:reserve(RODS, 0)
	check("reserve limited to capacity", #reserved == 3 and reason == nil)
	check("reserves first rods in order", reserved[1] == 1 and reserved[3] == 3)
	check("tank full while reserved", tank:info().full)
	local again, why = tank:reserve({ 4, 5 }, 0)
	check("full tank refuses more casts", #again == 0 and why == "tankFull")
	local busy, bwhy = SharedTank.new(Config), nil
	busy:registerRods({ 1 })
	busy:reserve({ 1 }, 0)
	_, bwhy = busy:reserve({ 1 }, 0)
	check("busy rod refusal reason", bwhy == "busy")
	healthy(tank, "after reserve")
end

-- Hook / land and names.
do
	local tank = fresh()
	tank:reserve({ 1, 2 }, 0)
	check("hook needs a name", not tank:hook(1, "", BITE))
	check("hook too soon refused", not tank:hook(1, "Cod", BITE - 0.1))
	healthy(tank, "refused hooks leave no fish")
	local ok, _, id = tank:hook(1, "Cod", BITE)
	check("hook ok", ok and type(id) == "number")
	check("unreserved rod cannot hook", not tank:hook(3, "Cod", BITE))
	local lok, _, lid, name = tank:land(1, BITE + LIFT)
	check("land ok with name", lok and lid == id and name == "Cod")
	check("count 1 reserved 1", tank:info().count == 1 and tank:info().reserved == 1)
	check("land without hook refused", not tank:land(2, BITE + LIFT))
	healthy(tank, "after land")
end

-- Abort paths (rod errors / fallback).
do
	local tank = fresh()
	tank:reserve({ 1, 2, 3 }, 0)
	check("abort waiting rod frees slot", tank:abort(1) and tank:info().reserved == 2)
	tank:hook(2, "Salmon", BITE)
	check("abort hooked rod", tank:abort(2) and tank:info().reserved == 1)
	check("aborted fish forgotten", next(tank.names) == nil)
	check("abort idle rod is a no-op", tank:abort(2) == false)
	tank:hook(3, "Pike", BITE)
	tank:land(3, BITE + LIFT)
	check("abort after land is a no-op", tank:abort(3) == false and tank:info().count == 1)
	healthy(tank, "after aborts")
end

-- Release -> step hands the fish back to the river with its name.
do
	local tank = fresh()
	tank:reserve({ 1 }, 0)
	tank:hook(1, "Koi", BITE)
	tank:land(1, BITE + LIFT)
	local rok, _, fish = tank:release(10)
	check("release ok", rok and #fish == 1 and fish[1].name == "Koi")
	check("released fish frees a slot", tank:info().count == 0 and tank:info().free == 3)
	check("nothing handed off early", #tank:step(10 + Config.ReleaseSwimSeconds - 0.01) == 0)
	local handed = tank:step(10 + Config.ReleaseSwimSeconds)
	check("handed off with name", #handed == 1 and handed[1].name == "Koi" and handed[1].id == fish[1].id)
	check("handed-off fish untracked", next(tank.state.fish) == nil and next(tank.names) == nil)
	local eok, ereason = tank:release(30)
	check("empty release reason", not eok and ereason == "empty")
	healthy(tank, "after hand-off")
end

-- Shutdown: tank + releasing fish go to the river; rod fish are forgotten.
do
	local tank = fresh()
	tank:reserve({ 1, 2, 3 }, 0)
	for _, r in ipairs({ 1, 2 }) do
		tank:hook(r, "Fish" .. r, BITE)
		tank:land(r, BITE + LIFT)
	end
	tank:hook(3, "OnLine", BITE)
	tank:release(10) -- one fish now releasing
	local out = tank:shutdown()
	check("shutdown returns tank + releasing fish", #out == 2)
	local names = {}
	for _, f in ipairs(out) do
		names[f.name] = true
	end
	check("shutdown keeps names", names.Fish1 and names.Fish2)
	check("rod fish not returned to river", not names.OnLine)
	check("nothing tracked after shutdown", next(tank.state.fish) == nil and next(tank.names) == nil)
	local reserved, why = tank:reserve(RODS, 20)
	check("stopped refuses casts", #reserved == 0 and why == "stopped")
	check("stopped refuses release", select(2, tank:release(20)) == "stopped")
	check("shutdown idempotent", #tank:shutdown() == 0)
end

-- Meta pass-through (e.g. rare-fish Variant): whitelisted, carried unchanged
-- rod -> tank -> river and through shutdown, cleared on abort.
do
	local tank = fresh()
	tank:reserve({ 1, 2, 3 }, 0)
	tank:hook(1, "Koi", BITE, { Variant = "Gold", SpawnT = 5, Evil = "x" })
	local _, _, _, name, meta = tank:land(1, BITE + LIFT)
	check("land returns meta", name == "Koi" and meta and meta.Variant == "Gold")
	check("non-whitelisted keys dropped", meta and meta.SpawnT == nil and meta.Evil == nil)
	tank:hook(2, "Cod", BITE, nil)
	local _, _, _, _, noMeta = tank:land(2, BITE + LIFT)
	check("no meta stays nil", noMeta == nil)
	tank:hook(3, "Eel", BITE, { Variant = "Silver" })
	tank:abort(3)
	check("abort clears meta", next(tank.meta) ~= nil and tank.meta[3] == nil)
	healthy(tank, "meta bookkeeping")
	local _, _, fish = tank:release(10)
	check("release batch carries meta", fish[1].meta and fish[1].meta.Variant == "Gold")
	local handed = tank:step(10 + Config.ReleaseSwimSeconds)
	check("hand-off to river keeps variant", #handed == 1 and handed[1].meta.Variant == "Gold")
	local out = tank:shutdown()
	check("shutdown hands back plain fish without meta", #out == 1 and out[1].name == "Cod" and out[1].meta == nil)
	check("meta cleared after shutdown", next(tank.meta) == nil)
	local long = SharedTank.new(Config)
	long:registerRods({ 1 })
	long:reserve({ 1 }, 0)
	long:hook(1, "X", BITE, { Variant = string.rep("a", 40) })
	check("oversized meta values dropped", long.meta[next(long.meta) or 0] == nil)
end

-- v1.2: the buyer (OwnerId) rides rod -> tank -> river with the fish
do
	local tank = fresh()
	tank:reserve({ 1, 2 }, 0)
	tank:hook(1, "Salmon", BITE, { OwnerId = 4242 })
	tank:hook(2, "Cod", BITE, { OwnerId = -1, Variant = "Silver" }) -- Studio test client
	local _, _, _, _, m1 = tank:land(1, BITE + LIFT)
	local _, _, _, _, m2 = tank:land(2, BITE + LIFT)
	check("owner kept on land", m1 and m1.OwnerId == 4242)
	check("test-client owner + variant kept", m2 and m2.OwnerId == -1 and m2.Variant == "Silver")
	-- releases go out one batch at a time: release until both are back in the river
	local owners, handed = {}, {}
	local t = 10
	while #handed < 2 and t < 10000 do
		local _, _, fish = tank:release(t)
		for _, f in ipairs(fish) do
			owners[f.name] = f.meta and f.meta.OwnerId
		end
		t += Config.ReleaseSwimSeconds + 100
		for _, h in ipairs(tank:step(t)) do
			table.insert(handed, h)
		end
	end
	check("release carries each fish's own buyer", owners.Salmon == 4242 and owners.Cod == -1)
	local ok = #handed == 2
	for _, h in ipairs(handed) do
		ok = ok and h.meta ~= nil and h.meta.OwnerId == (if h.name == "Salmon" then 4242 else -1)
	end
	check("hand-off to the river keeps the buyer", ok)
	local bad = fresh()
	bad:reserve({ 1 }, 0)
	bad:hook(1, "Eel", BITE, { OwnerId = 0 / 0 })
	check("NaN owner dropped", bad.meta[next(bad.meta) or 0] == nil)
	healthy(tank, "owner bookkeeping")
end

-- Upgrades: unavailable without currency, never free.
do
	local tank = fresh()
	local ok, reason = tank:buyUpgrade({}, "Capacity")
	check("upgrade unavailable without economy", not ok and reason == "economyAdapterOff")
	check("capacity unchanged", tank:info().capacity == 3)
	local charged = 0
	local adapters = {
		Economy = {
			tryCharge = function(_, amount)
				charged += amount
				return true
			end,
		},
	}
	check("upgrade with economy", (tank:buyUpgrade(adapters, "Capacity")))
	check("charged table cost", charged == Config.Upgrades.Capacity.Costs[1] and tank:info().capacity == 6)
end

-- Messages cover every refusal code the controller can surface.
for _, code in ipairs({
	"tankFull",
	"empty",
	"cooldown",
	"economyAdapterOff",
	"max",
	"funds",
	"stopped",
	"badUpgrade",
	"tooFar",
}) do
	check("message for " .. code, Messages.forReason(code) ~= Messages.Fallback)
end
check("unknown reason falls back", Messages.forReason("???") == Messages.Fallback)

-- RiverRelease mirrors FishSpawner and stays inside the river.
do
	local attrs = { MinX = -28.503, MaxX = 4.625, MinZ = 138.051, MaxZ = 256.141, SurfaceY = 7.3928 }
	local b = RiverRelease.readBounds(function(k)
		return attrs[k]
	end)
	check("live river attributes accepted", b ~= nil)
	check("missing attribute rejected", RiverRelease.readBounds(function(k)
		return if k == "SurfaceY" then nil else attrs[k]
	end) == nil)
	check("empty bounds rejected", RiverRelease.readBounds(function(k)
		return if k == "MaxX" then -30 else attrs[k]
	end) == nil)
	if b then
		local inside, positive = true, true
		for _, L in ipairs({ 2, 4, 7, 12 }) do
			for _, r in ipairs({ 0, 0.25, 0.5, 1 }) do
				local s = RiverRelease.attributes(b, L, 100, 7, r, r, Config.Scene.RiverSpeed)
				if s.LaneX < b.minX or s.LaneX > b.maxX then
					inside = false
				end
				if s.lifetime <= 0 or s.Speed < 4 or s.Speed > 6.5 then
					positive = false
				end
			end
		end
		check("lanes inside river", inside)
		check("lifetime and speed sane", positive)
		local s = RiverRelease.attributes(b, 4, 50, 9, 0, 0.5, { 4, 6.5 })
		check(
			"matches spawner start/lane formula",
			s.StartZ == b.minZ + 2 and math.abs(s.LaneX - (b.minX + b.maxX) / 2) < 1e-9
		)
		check("spawn time and seed passed through", s.SpawnT == 50 and s.Seed == 9)
		local bad = RiverRelease.attributes(b, "x", 0, 1, 0.5, 0.5, { 4, 6.5 })
		check("bad SwimLen falls back to 4", bad.StartZ == b.minZ + 2)
	end
end

-- TankPath is bounded and smooth for the live BaseWater size.
do
	local hx, hy, hz = TankPath.halfExtents(28.256, 20.515, 28.256, Config.Scene.TankMargin, Config.Scene.TankFishSize)
	check("half extents positive", hx > 1 and hy > 1 and hz > 1)
	check("tiny tank still positive", select(1, TankPath.halfExtents(1, 1, 1, 2, 3)) == 0.25)
	local bounded, smooth = true, true
	for seed = 1, 60 do
		local px, py, pz = TankPath.at(hx, hy, hz, seed, 0)
		for step = 1, 400 do
			local t = step * 0.05
			local x, y, z = TankPath.at(hx, hy, hz, seed, t)
			if math.abs(x) > hx + 1e-9 or math.abs(y) > hy + 1e-9 or math.abs(z) > hz + 1e-9 then
				bounded = false
			end
			if math.sqrt((x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2) > 0.5 then
				smooth = false
			end
			px, py, pz = x, y, z
		end
	end
	check("tank path bounded", bounded)
	check("tank path smooth (no jumps between frames)", smooth)
end

-- Fuzz the live flow: presses reserve idle rods, rods bite/land/error at
-- random times, players release, the flag may be switched off. Every hooked
-- fish must end up exactly once as: aborted, handed to the river, handed back
-- at shutdown, or still in the tank.
do
	math.randomseed(777)
	local totals = { reserved = 0, landed = 0, handed = 0, full = 0 }
	for trial = 1, 150 do
		local tank = fresh()
		local rodState = {} -- key -> "idle" | { phase, t }
		for _, r in ipairs(RODS) do
			rodState[r] = "idle"
		end
		local fate = {} -- id -> "hooked" | "tank" | "aborted" | "river" | "shutdown"
		local now = 0
		local broken = nil
		for _ = 1, 250 do
			now += math.random() * 1.5
			local op = math.random(1, 10)
			if op <= 2 then
				local idle = {}
				for _, r in ipairs(RODS) do
					if rodState[r] == "idle" then
						table.insert(idle, r)
					end
				end
				local reserved, why = tank:reserve(idle, now)
				if why == "tankFull" then
					totals.full += 1
				end
				for _, r in ipairs(reserved) do
					rodState[r] = { phase = "cast", t = now, wait = 3 + math.random() * 6 }
					totals.reserved += 1
				end
			elseif op <= 6 then
				local r = RODS[math.random(1, #RODS)]
				local st = rodState[r]
				if type(st) == "table" then
					if math.random() < 0.05 then
						-- rod task error: exception-safe cleanup
						if st.id then
							fate[st.id] = "aborted"
						end
						tank:abort(r)
						rodState[r] = "idle"
					elseif st.phase == "cast" and now >= st.t + st.wait then
						local ok, _, id = tank:hook(r, "F", now)
						if ok then
							fate[id] = "hooked"
							rodState[r] = { phase = "hooked", t = now, id = id }
						end
					elseif st.phase == "hooked" and now >= st.t + 5 then
						local ok, _, id = tank:land(r, now)
						if ok then
							fate[id] = "tank"
							totals.landed += 1
						end
						rodState[r] = "idle"
					end
				end
			elseif op <= 7 then
				tank:release(now)
			else
				for _, h in ipairs(tank:step(now)) do
					if fate[h.id] ~= "tank" then
						broken = "handed off a fish that wasn't in the tank"
					end
					fate[h.id] = "river"
					totals.handed += 1
				end
			end
			local ok, problem = tank:check()
			if not ok then
				broken = problem
			end
			if broken then
				break
			end
		end
		for _, h in ipairs(tank:shutdown()) do
			if fate[h.id] ~= "tank" then
				broken = broken or "shutdown returned a fish that wasn't in the tank"
			end
			fate[h.id] = "shutdown"
		end
		for _, r in ipairs(RODS) do
			local st = rodState[r]
			if type(st) == "table" and st.id and fate[st.id] == "hooked" then
				fate[st.id] = "aborted" -- rod script falls back to the grinder
			end
		end
		for id, f in pairs(fate) do
			if f == "hooked" or f == "tank" then
				broken = broken or ("fish " .. id .. " unaccounted for after shutdown (" .. f .. ")")
			end
		end
		check("live-flow fuzz trial " .. trial .. " " .. tostring(broken), broken == nil)
	end
	print(
		string.format(
			"live-flow fuzz: %d reservations, %d landed, %d handed to river, %d full-tank refusals",
			totals.reserved,
			totals.landed,
			totals.handed,
			totals.full
		)
	)
	check("fuzz lands fish", totals.landed >= 300)
	check("fuzz returns fish to river", totals.handed >= 100)
	check("fuzz hits a full tank", totals.full >= 50)
end

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("shared tests failed")
end
