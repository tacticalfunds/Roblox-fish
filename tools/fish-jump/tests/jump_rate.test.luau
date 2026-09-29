-- Offline pure-logic test for the JumpRate update: the installed FishJump
-- module (src) against the more-often one (studio/jump-rate). Run:
--   luau tools/fish-jump/tests/jump_rate.test.luau
-- Not a Roblox runtime test (no visuals, splashes or FishSwimClient).

local Before = require("../src/FishJump")
local After = require("../studio/jump-rate/FishJump")

local failures, passes = 0, 0
local function check(name: string, cond: any)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. name)
	end
end
local function none()
	return nil
end
local cb, ca = Before.config(none), After.config(none)
local T0 = 1.7e9

-- only the two period settings differ
check("PeriodMin 16 -> 8, PeriodSpread 12 -> 6", cb.PeriodMin == 16 and cb.PeriodSpread == 12 and ca.PeriodMin == 8 and ca.PeriodSpread == 6)
local same = true
for k, v in pairs(cb) do
	if k ~= "PeriodMin" and k ~= "PeriodSpread" and ca[k] ~= v then
		same = false
		print("  differs: " .. k)
	end
end
check("every other setting unchanged (Chance, Duration, heights, margin, snakes, splash pool)", same)
check("the hash (who jumps when) is the same function", Before.hash01(12345, 7) == After.hash01(12345, 7))

-- simulate FISH fish for SECONDS, sampling at DT: takeoffs, max airborne, gaps
local FISH, SECONDS, DT = 60, 1800, 0.05
local function run(M, cfg)
	local takeoffs, maxAir, minGap, airSum = 0, 0, math.huge, 0
	local inAir, lastTakeoff = {}, {}
	local steps = math.floor(SECONDS / DT)
	for i = 0, steps do
		local t = T0 + i * DT
		local air = 0
		for seed = 1, FISH do
			local u = M.phase(seed, t, cfg)
			if u then
				air += 1
				if not inAir[seed] then
					takeoffs += 1
					if lastTakeoff[seed] then
						minGap = math.min(minGap, t - lastTakeoff[seed])
					end
					lastTakeoff[seed] = t
				end
			end
			inAir[seed] = u ~= nil
		end
		maxAir = math.max(maxAir, air)
		airSum += air
	end
	return takeoffs, maxAir, minGap, airSum / (steps + 1)
end
local nb, airB, gapB, meanB = run(Before, cb)
local na, airA, gapA, meanA = run(After, ca)
local perFishB = FISH * SECONDS / nb
local perFishA = FISH * SECONDS / na
print(string.format("  before: %d jumps (1 per %.1f s per fish), %.2f airborne on average, max %d, min gap %.1f s", nb, perFishB, meanB, airB, gapB))
print(string.format("  after:  %d jumps (1 per %.1f s per fish), %.2f airborne on average, max %d, min gap %.1f s", na, perFishA, meanA, airA, gapA))
check("about twice as many jumps (x1.7 - x2.3)", na / nb >= 1.7 and na / nb <= 2.3)
check("expected rate matches: ~1 per 31 s per fish", perFishA > 24 and perFishA < 40)
check("still staggered: under 2 of 60 fish in the air on average", meanA < 2)
check("peak: at most 10 of 60 in the air at once (splash pool 10 caps the effects)", airA <= 10)
check("a fish never jumps again within 7 s (period >= 8 s, 0.9 s airtime)", gapA >= 7)

-- overrides and switches still work
local off = After.config(function(k)
	return if k == "JumpEnabled" then false else nil
end)
local anyOff = false
for i = 0, 2000 do
	if After.phase(i % 60 + 1, T0 + i * 0.5, off) then
		anyOff = true
	end
end
check("JumpEnabled = false: no jumps", not anyOff)
local zero = After.config(function(k)
	return if k == "JumpChance" then 0 else nil
end)
local nz = run(After, zero)
check("JumpChance = 0: no jumps", nz == 0)

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("jump rate test failed")
end
