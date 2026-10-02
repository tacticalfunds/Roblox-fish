-- Customers for every player: the REAL spawn loop of the patched CustomerSystem
-- (studio/board/CustomerSystem.lua, from the live MeatGlow version) run on its
-- own against the REAL EconomyService, with the CURRENT (fast-start) tuning.
-- Customers are stubbed (no avatars): each joins the line and leaves after
-- LIFE seconds. Checks:
--   * the rate follows the players: 6 a minute for 1, 18 for 3, capped at 18
--     for 5 (live: ~4 a minute for the whole server)
--   * the Car Sales upgrades' published CustomersPerMin is never lowered
--   * the line never grows past its cap (6, or a higher published one)
--   * without EconomyService, or if its call errors: the original loop
--   * no players: nobody comes
--   * the fast-start prices reach the players (net $10 / $20, board 1.25x ...)

fastStartTuning.on = true
local Economy, root = installEconomy()
Economy.Config.NetKgLegacy = false -- not what this sim is about
local ws = workspaceInst
local Players = services.Players

local src = SOURCES.Board_Customer
local at = src:find("task.wait(4)\nwhile true do", 1, true)
check("the patched CustomerSystem has the spawn loop", at ~= nil)
local chunk = "local Economy, Players, spawnCustomer, line, MAX_IN_LINE, SPAWN_DELAY = ...\n" .. src:sub(at or 1)
check("the loop asks EconomyService.customers()", chunk:find("pcall(Economy.customers)", 1, true) ~= nil)

-- one running copy of the loop; returns its spawn log and line
local function startLoop(economy, life)
	local log, line = {}, {}
	local fn = assert(loadstring(chunk, "=CustomerSystem.loop"))
	setfenv(fn, envFor(script("Script", "CustomerSystem", "")))
	local function spawnCustomer()
		table.insert(log, now)
		local c = {}
		table.insert(line, c)
		task.delay(life.seconds, function()
			local i = table.find(line, c)
			if i then
				table.remove(line, i)
			end
		end)
	end
	runAs("server", function()
		task.spawn(fn, economy, Players, spawnCustomer, line, 4, { 10, 20 })
	end)
	return log, line
end
local function countSince(log, t0)
	local n = 0
	for _, t in ipairs(log) do
		if t >= t0 then
			n += 1
		end
	end
	return n
end
-- customers a minute over `minutes`
local function measure(log, minutes)
	local t0 = now
	advance(minutes * 60)
	return countSince(log, t0) / minutes
end
local function near(x, target)
	return x >= target * 0.85 and x <= target * 1.15
end

------------------------------------------------------------ the rate follows the players

local life = { seconds = 4 }
local log, line = startLoop(Economy, life)
advance(30)
check("no players: nobody comes", #log == 0)

local P = {}
P[1] = join(1, "A", Vector3.new(0, 10, 0))
advance(30)
local r1 = measure(log, 20)
check(("1 player: ~6 a minute (got %.1f; live ~4 for the whole server)"):format(r1), near(r1, 6))
P[2] = join(2, "B", Vector3.new(5, 10, 0))
P[3] = join(3, "C", Vector3.new(10, 10, 0))
advance(20)
local r3 = measure(log, 20)
check(("3 players: ~18 a minute (got %.1f)"):format(r3), near(r3, 18))
P[4] = join(4, "D", Vector3.new(15, 10, 0))
P[5] = join(5, "E", Vector3.new(20, 10, 0))
advance(20)
local r5 = measure(log, 20)
check(("5 players: capped at ~18 (got %.1f)"):format(r5), near(r5, 18))
for i = 5, 2, -1 do
	leave(P[i])
end
advance(30)
local rBack = measure(log, 20)
check(("back to 1 player: ~6 again (got %.1f)"):format(rBack), near(rBack, 6))

------------------------------------------------------------ Car Sales' published rate is never lowered

ws:SetAttribute("CustomersPerMin", 25)
advance(20)
local rPub = measure(log, 20)
check(("Car Sales publishes 25, 1 player: ~25 (got %.1f) - never lowered"):format(rPub), near(rPub, 25))
ws:SetAttribute("CustomersPerMin", 3)
advance(30)
local rLow = measure(log, 20)
check(("a published 3 (below the base): ~6 (got %.1f)"):format(rLow), near(rLow, 6))
ws:SetAttribute("CustomersPerMin", nil)

------------------------------------------------------------ the line cap

life.seconds = 300 -- nobody leaves: the line fills up
advance(120)
check("the line stops at 6 (Config.Customers.LineCap)", #line == 6)
ws:SetAttribute("CustomersLineCap", 8)
advance(120)
check("a published line cap of 8 is used (never lowered)", #line == 8)
ws:SetAttribute("CustomersLineCap", nil)
life.seconds = 4
advance(400) -- the long-lived customers leave
check("the line drains once customers leave", #line <= 2)

------------------------------------------------------------ without EconomyService / a failing call: the original loop

for _, p in ipairs({ P[1] }) do
	leave(p)
end
advance(10)
local plain = startLoop(nil, { seconds = 4 })
local A = join(11, "Solo", Vector3.new(0, 10, 0))
advance(10)
local rPlain = measure(plain, 30)
check(("no EconomyService: the original 10-20 s gap, ~4 a minute (got %.1f)"):format(rPlain), near(rPlain, 4))
local broken = startLoop({ customers = function()
	error("boom")
end }, { seconds = 4 })
local rBroken = measure(broken, 30)
check(("EconomyService.customers errors: the original loop, ~4 a minute (got %.1f)"):format(rBroken), near(rBroken, 4))

------------------------------------------------------------ the fast-start prices reach the player

advance(2)
check("net: 15 → 20 kg for $10, as published", A:GetAttribute("NetKgCost") == 10 and A:GetAttribute("NetKgNext") == 20)
check("Meat Price: 1x → 1.25x for $10", A:GetAttribute("UpgMeatPriceNext") == 1.25 and A:GetAttribute("UpgMeatPriceCost") == 10)
check("Rod Luck: 1x → 1.5x; Faster Reels: 1x → 1.1x", A:GetAttribute("UpgRodLuckNext") == 1.5 and A:GetAttribute("UpgFasterReelsNext") == 1.1)

finish("customers sim")
