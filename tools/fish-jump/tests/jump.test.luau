-- Offline pure-logic tests for tools/fish-jump/src/FishJump.luau. Run:
--   luau tools/fish-jump/tests/jump.test.luau
-- Not Roblox runtime tests: no visuals, splashes or FishSwimClient involved.

local FishJump = require("../src/FishJump")

local failures, passes = 0, 0
local function check(name: string, cond: any)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. name)
	end
end

local cfg = FishJump.config(function()
	return nil
end)
local T0 = 1.7e9 -- workspace:GetServerTimeNow() is Unix time

-- Hash: deterministic, in [0, 1), roughly uniform.
do
	local sum, n, inRange = 0, 0, true
	for a = 1, 200 do
		for b = 0, 50 do
			local h = FishJump.hash01(a, b)
			if h < 0 or h >= 1 then
				inRange = false
			end
			sum += h
			n += 1
		end
	end
	check("hash in [0,1)", inRange)
	check("hash roughly uniform", math.abs(sum / n - 0.5) < 0.02)
	check("hash deterministic", FishJump.hash01(1000007, 94444444) == FishJump.hash01(1000007, 94444444))
	check("hash handles huge cycle numbers", FishJump.hash01(3, 2 ^ 40 + 5) >= 0)
end

-- Seeds as they exist in the place: FishSpawner 1..N, aquarium releases 1e6+N.
local seeds = {}
for s = 1, 60 do
	table.insert(seeds, s)
end
for s = 1, 20 do
	table.insert(seeds, 1000000 + s)
end

-- Sparse and staggered: few fish airborne at once, never all together, and
-- every fish does jump now and then.
do
	local maxTogether, airborneSamples, samples = 0, 0, 0
	local jumped = {}
	for step = 0, 12000 do -- 10 minutes at 20 Hz
		local t = T0 + step * 0.05
		local together = 0
		for _, seed in ipairs(seeds) do
			if FishJump.phase(seed, t, cfg) then
				together += 1
				jumped[seed] = true
				airborneSamples += 1
			end
			samples += 1
		end
		maxTogether = math.max(maxTogether, together)
	end
	local fraction = airborneSamples / samples
	local expected = cfg.Chance * cfg.Duration / (cfg.PeriodMin + cfg.PeriodSpread / 2)
	print(
		string.format(
			"jumps: %.2f%% of fish-time airborne (expected ~%.2f%%), max %d of %d at once",
			fraction * 100,
			expected * 100,
			maxTogether,
			#seeds
		)
	)
	check("airborne fraction near expected", math.abs(fraction - expected) < expected * 0.5)
	check("never many fish at once", maxTogether <= 8)
	local count = 0
	for _ in pairs(jumped) do
		count += 1
	end
	check("every fish jumps within 10 minutes", count == #seeds)
end

-- A single jump: u rises smoothly from 0 to 1 over Duration, one cycle id.
do
	local seed = 7
	local start
	for step = 0, 40000 do
		local t = T0 + step * 0.01
		if FishJump.phase(seed, t, cfg) then
			start = t
			break
		end
	end
	check("found a jump", start ~= nil)
	if start then
		local lastU, cycle0, monotonic = -1, nil, true
		local airtime = 0
		for i = 0, 200 do
			local t = start + i * 0.01
			local u, cycle = FishJump.phase(seed, t, cfg)
			if u then
				airtime += 0.01
				cycle0 = cycle0 or cycle
				if u < lastU or cycle ~= cycle0 then
					monotonic = false
				end
				lastU = u
			else
				break
			end
		end
		check("u increases within one cycle", monotonic)
		check("airtime matches Duration", math.abs(airtime - cfg.Duration) < 0.03)
		check(
			"same arc on every client (pure function of time)",
			select(1, FishJump.phase(seed, start + 0.3, cfg)) == select(1, FishJump.phase(seed, start + 0.3, cfg))
		)
	end
end

-- Height is size-aware and bounded; arc starts and ends at the water.
do
	check("small fish min height", FishJump.height(1, cfg) == cfg.MinHeight)
	check("big fish max height", FishJump.height(30, cfg) == cfg.MaxHeight)
	check(
		"bad SwimLen falls back to 4",
		FishJump.height("x", cfg) == math.clamp(4 * cfg.HeightPerStud, cfg.MinHeight, cfg.MaxHeight)
	)
	local h = 2
	local dy0, vy0 = FishJump.offset(0, h, cfg)
	local dyMid, vyMid = FishJump.offset(0.5, h, cfg)
	local dy1, vy1 = FishJump.offset(1, h, cfg)
	check("arc starts at water", dy0 == 0 and vy0 > 0)
	check("arc peaks at height", math.abs(dyMid - h) < 1e-9 and math.abs(vyMid) < 1e-9)
	check("arc lands at water nose down", dy1 == 0 and vy1 < 0)
	local maxDy = 0
	for i = 0, 100 do
		maxDy = math.max(maxDy, (FishJump.offset(i / 100, h, cfg)))
	end
	check("never above jump height", maxDy <= h + 1e-9)
end

-- River-end margin keeps the whole arc in bounds.
do
	check("allowed mid-river", FishJump.allowed(200, 138, 256, cfg))
	check("blocked near start", not FishJump.allowed(140, 138, 256, cfg))
	check("blocked near end", not FishJump.allowed(254, 138, 256, cfg))
	check("blocked without bounds", not FishJump.allowed(200, nil, 256, cfg))
	-- takeoff at the latest allowed z, flying at the fastest speed, still lands inside
	local landZ = (256 - cfg.EdgeMargin) + 6.5 * cfg.Duration
	check("fastest fish lands inside the river", landZ < 256)
end

-- Attribute overrides on the river folder.
do
	local off = FishJump.config(function(k)
		return if k == "JumpEnabled" then false else nil
	end)
	local any = false
	for step = 0, 5000 do
		if FishJump.phase(3, T0 + step * 0.1, off) then
			any = true
		end
	end
	check("JumpEnabled=false stops jumps", not any)
	local clamped = FishJump.config(function(k)
		return if k == "JumpChance" then 7 else nil
	end)
	check("JumpChance clamped", clamped.Chance == 1)
	local scaled = FishJump.config(function(k)
		return if k == "JumpHeightScale" then 2 else nil
	end)
	check("JumpHeightScale scales heights", scaled.MaxHeight == cfg.MaxHeight * 2)
	check("defaults not mutated by overrides", FishJump.Defaults.MaxHeight == cfg.MaxHeight)
	local junk = FishJump.config(function(k)
		return if k == "JumpChance" then 0 / 0 else "nope"
	end)
	check("junk overrides ignored", junk.Chance == cfg.Chance and junk.Enabled == true)
end

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("fish-jump tests failed")
end
