--!strict
-- Pure swim path for fish inside the aquarium, in the tank water's LOCAL
-- space (the client converts with the BaseWater CFrame). Each axis is a sine
-- with a seed-derived frequency and phase, so the path is smooth, never stops,
-- and is bounded by construction: |x| <= hx, |y| <= hy * 0.7, |z| <= hz.

local TankPath = {}

-- Half extents that keep a fish of `fishSize` inside a box of the given size
-- with `margin` studs to spare. Never below 0.25 so tiny tanks still work.
function TankPath.halfExtents(
	sx: number,
	sy: number,
	sz: number,
	margin: number,
	fishSize: number
): (number, number, number)
	local pad = margin + fishSize / 2
	return math.max(0.25, sx / 2 - pad), math.max(0.25, sy / 2 - pad), math.max(0.25, sz / 2 - pad)
end

local function frac(v: number): number
	return v - math.floor(v)
end

-- Seed-derived frequencies (rad/s) and phases.
function TankPath.params(seed: number)
	local a, b, c = frac(seed * 0.6180339), frac(seed * 0.4142135), frac(seed * 0.7320508)
	return {
		fx = 0.16 + 0.12 * a,
		fy = 0.09 + 0.07 * b,
		fz = 0.13 + 0.12 * c,
		px = a * 2 * math.pi,
		py = b * 2 * math.pi,
		pz = c * 2 * math.pi,
	}
end

-- Position and velocity at time t.
function TankPath.at(
	hx: number,
	hy: number,
	hz: number,
	seed: number,
	t: number
): (number, number, number, number, number, number)
	local p = TankPath.params(seed)
	local ay = hy * 0.7
	local x = hx * math.sin(p.fx * t + p.px)
	local y = ay * math.sin(p.fy * t + p.py)
	local z = hz * math.sin(p.fz * t + p.pz)
	local dx = hx * p.fx * math.cos(p.fx * t + p.px)
	local dy = ay * p.fy * math.cos(p.fy * t + p.py)
	local dz = hz * p.fz * math.cos(p.fz * t + p.pz)
	return x, y, z, dx, dy, dz
end

return TankPath
