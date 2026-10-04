-- Offline tests: the customers' rate and line size (Sales.customers, what
-- EconomyService.customers() gives CustomerSystem). Run via run_tests.py.
-- Covers: a rate per player up to Max, the Car Sales upgrades' published
-- values never lowered, junk published values ignored, Config.check guards.

local Config = require("../src/Config")
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

local C = Config.Customers
check("config check passes", Config.check() == true)
check("tuning: 6 a minute per player, up to 24, line 6 .. 8", C.PerPlayer == 6 and C.Max == 24 and C.LineCap == 6 and C.LineMax == 8)

local function rate(players, published, cap)
	local r, c = Sales.customers(players, published, cap, C)
	return r, c
end

------------------------------------------------------------ per player, up to Max

local r, c = rate(1, nil, nil)
check("1 player, nothing published: 6 a minute (live was ~4 for the whole server), line 6", r == 6 and c == 6)
check("2 players: 12 a minute", (rate(2, nil, nil)) == 12)
check("3 players: 18 a minute", (rate(3, nil, nil)) == 18)
check("5 players: capped at Max (24)", (rate(5, nil, nil)) == 24)
check("0 players (the loop doesn't spawn then anyway): counted as 1", (rate(0, nil, nil)) == 6)
check("a fractional player count rounds down", (rate(2.9, nil, nil)) == 12)

------------------------------------------------------------ Car Sales' published values are never lowered

check("published 10 a minute, 1 player: 10 (used per player)", (rate(1, 10, nil)) == 10)
check("published 10, 3 players: 24 (Max)", (rate(3, 10, nil)) == 24)
check("published 25 (above Max), 1 player: 25 - never lowered", (rate(1, 25, nil)) == 25)
check("published 25, 4 players: 25 (Max lifts to the published rate, no more)", (rate(4, 25, nil)) == 25)
check("published 3 (below the base): the base 6", (rate(1, 3, nil)) == 6)
local _, c8 = rate(1, nil, 8)
local _, c2 = rate(1, nil, 2)
check("published line 8: 8; published line 2: at least 6", c8 == 8 and c2 == 6)

------------------------------------------------------------ junk published values are ignored

local junk = { 0 / 0, math.huge, -5, 0, "12", true, {} }
local ok = true
for _, v in ipairs(junk) do
	local jr, jc = rate(2, v, v)
	ok = ok and jr == 12 and jc == 6
end
check("NaN / inf / negative / zero / non-numbers published: ignored", ok)
local nr = rate(0 / 0, nil, nil)
check("a NaN player count: counted as 1", nr == 6)

------------------------------------------------------------ each player's saved customer upgrades

local function each(speeds, lines, published, cap)
	return Sales.customers(speeds, published, cap, C, lines)
end
local r1, c1 = each({ 9 }, { 7 })
check("solo with Customer Speed 9 and Line 7: 9 a minute, 7 in line", r1 == 9 and c1 == 7)
local r2, c2 = each({ 20, 6 }, { 6, 8 })
check("two players (20 and 6 a minute, lines 6 and 8): the sum 24 (Max) and the largest line 8", r2 == 24 and c2 == 8)
local r3 = each({ 12, 6 }, { 6, 6 })
check("12 + 6 = 18 a minute (under Max)", r3 == 18)
local r4, c4 = each({ 3, 0 / 0 }, { 99, "x" })
check("each player counts at least the base; a line above the sidewalk's 8 is held to 8; junk ignored", r4 == 12 and c4 == 8)
local r5, c5 = each({}, {})
check("nobody listed: one player's base (6, line 6)", r5 == 6 and c5 == 6)
local r6, c6 = each({ 9 }, { 7 }, 25, 8)
check("Car Sales' published values still never lowered (25 a minute, line 8)", r6 == 25 and c6 == 8)

------------------------------------------------------------ Config.check guards

local saved = { C.PerPlayer, C.Max, C.LineCap }
C.PerPlayer = 0
check("config check: PerPlayer 0 refused", Config.check() == false)
C.PerPlayer, C.Max = 6, 4
check("config check: Max below PerPlayer refused", Config.check() == false)
C.Max, C.LineMax = 24, 9
check("config check: a line longer than the 8 slots refused", Config.check() == false)
C.LineMax = 8
C.PerPlayer, C.Max, C.LineCap = saved[1], saved[2], saved[3]
check("config check passes again", Config.check() == true)

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("customers tests failed")
end
