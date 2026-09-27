-- Offline timing/continuity tests for tools/grinder-dwell/src/GrinderDwell.luau.
--   luau tools/grinder-dwell/tests/dwell.test.luau
-- Not Roblox runtime tests.

local D = require("../src/GrinderDwell")

local failures, passes = 0, 0
local function check(name: string, cond: any)
	if cond then
		passes += 1
	else
		failures += 1
		print("FAIL: " .. name)
	end
end

-- Timeline
check("dwell is about one second", math.abs(D.Dwell - 1) < 0.05)
check("original flight/drop timings kept", D.Rise == 0.12 and D.Fly == 0.95 and D.Drop == 0.55)
check("total = rise + fly + dwell + drop", math.abs(D.total() - 2.62) < 1e-9)
check("server acts after the client drop ends", D.serverDelay() > D.total() and D.serverDelay() - D.total() < 0.1)
check("server delay was 1.65 without dwell", math.abs(D.serverDelay() - D.Dwell - 1.65) < 1e-9)

-- Phases partition the timeline in order
do
	local order = { rise = 1, fly = 2, dwell = 3, drop = 4, done = 5 }
	local last, ok = 1, true
	for i = 0, 300 do
		local name, e, u = D.phase(i / 100)
		if order[name] < last or e < 0 or u < 0 or u > 1 then
			ok = false
		end
		last = order[name]
	end
	check("phases progress in order", ok)
	check("rise at 0", (D.phase(0)) == "rise")
	check("fly after rise", (D.phase(D.Rise + 0.01)) == "fly")
	check("dwell after fly", (D.phase(D.Rise + D.Fly + 0.01)) == "dwell")
	check("drop after dwell", (D.phase(D.Rise + D.Fly + D.Dwell + 0.01)) == "drop")
	check("done after total", (D.phase(D.total() + 0.001)) == "done")
end

-- Continuity: dwell starts where the flight ends (GrinderPos), ends where the
-- spiral starts; no frame-to-frame jump anywhere from dwell through drop.
do
	local x0, y0, z0 = D.dwellOffset(0, 3)
	check("dwell starts at GrinderPos", math.abs(x0) + math.abs(y0) + math.abs(z0) < 1e-9)
	local xe, ye, ze = D.dwellOffset(D.Dwell, 3)
	local dx, dy, dz = D.dropOffset(0)
	check("dwell ends where the drop starts", math.abs(xe - dx) + math.abs(ye - dy) + math.abs(ze - dz) < 1e-6)
	local _, yEnd, _, sEnd = D.dropOffset(1)
	check("drop ends at the original depth", math.abs(yEnd + D.DropDepth) < 1e-9 and math.abs(sEnd - 0.08) < 1e-9)

	-- Per-frame movement at 60 fps, measured per phase. The dwell must be calm;
	-- the drop is the ORIGINAL suction whirl (5*pi rad in 0.55 s at a 1.2-stud
	-- radius, ~0.6 studs/frame by design), so it's checked against that speed.
	local function at(lt, seed)
		local name, e, u = D.phase(lt)
		if name == "dwell" then
			local x, y, z = D.dwellOffset(e, seed)
			return x, y, z, name
		end
		local x, y, z = D.dropOffset(u)
		return x, y, z, name
	end
	local worstDwell, worstDrop = 0, 0
	for seed = 1, 20 do
		local px, py, pz = 0, 0, 0 -- flight ends exactly at GrinderPos
		for i = 1, math.floor((D.Dwell + D.Drop) * 60) do
			local lt = D.Rise + D.Fly + i / 60
			local x, y, z, name = at(lt, seed)
			local move = math.sqrt((x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2)
			if name == "dwell" then
				worstDwell = math.max(worstDwell, move)
			else
				worstDrop = math.max(worstDrop, move)
			end
			px, py, pz = x, y, z
		end
	end
	local whirl = D.DropRadius * 5 * math.pi / D.Drop / 60 + 0.05 -- original spiral speed per frame
	print(
		string.format(
			"largest per-frame move: dwell %.3f studs, drop %.3f studs (whirl ~%.3f)",
			worstDwell,
			worstDrop,
			whirl
		)
	)
	check("dwell is calm (per-frame move < 0.2 studs at 60 fps)", worstDwell < 0.2)
	check("drop never faster than the original whirl", worstDrop <= whirl)
end

-- Stays on top of the rollers during the dwell (after settling): never below
-- the rest height, never more than the shudder amplitude above it.
do
	local ok = true
	for seed = 1, 30 do
		for i = 0, 100 do
			local e = D.SettleSeconds + (D.Dwell - D.SettleSeconds) * i / 100
			local _, y = D.dwellOffset(e, seed)
			if y < D.OffsetY - 1e-9 or y > D.OffsetY + D.ShudderAmp + 1e-9 then
				ok = false
			end
		end
	end
	check("dwell height stays on the rollers", ok)
	local maxSide = 0
	for i = 0, 100 do
		local x, _, z = D.dwellOffset(i / 100 * D.Dwell, 7)
		maxSide = math.max(maxSide, math.abs(z), math.abs(x) - D.DropRadius)
	end
	check("dwell stays within the mouth", maxSide <= D.ShudderAmp + 1e-9)
end

-- Overlapping catches: pure per-fish state (seed + time), nothing shared.
do
	local a1 = { D.dwellOffset(0.5, 1) }
	local _ = { D.dwellOffset(0.5, 99) }
	local a2 = { D.dwellOffset(0.5, 1) }
	check("per-fish results independent of other fish", a1[1] == a2[1] and a1[2] == a2[2] and a1[3] == a2[3])
end

-- With OffsetY = 0 the drop is exactly the original suction formula.
do
	local saved = D.OffsetY
	D.OffsetY = 0
	local same = true
	for i = 0, 20 do
		local u = i / 20
		local x, y, z, s = D.dropOffset(u)
		local e = u * u
		local r = 1.2 * (1 - u)
		local a = u * math.pi * 5
		if
			math.abs(x - math.cos(a) * r) > 1e-9
			or math.abs(y + 3.2 * e) > 1e-9
			or math.abs(z - math.sin(a) * r) > 1e-9
			or math.abs(s - (1 - 0.92 * e)) > 1e-9
		then
			same = false
		end
	end
	D.OffsetY = saved
	check("drop matches the original formula at OffsetY 0", same)
end

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then
	error("grinder-dwell tests failed")
end
