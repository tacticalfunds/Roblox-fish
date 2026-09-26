--!strict
-- Pure 2D helpers on the water plane (x, z). No Roblox types so the sweep and
-- catch rules can be unit-tested offline.

local Geometry = {}

-- Squared distance from point P to segment AB.
function Geometry.pointSegmentDistSq(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local abx, abz = bx - ax, bz - az
	local lenSq = abx * abx + abz * abz
	local t = 0
	if lenSq > 1e-9 then
		t = math.clamp(((px - ax) * abx + (pz - az) * abz) / lenSq, 0, 1)
	end
	local cx, cz = ax + abx * t - px, az + abz * t - pz
	return cx * cx + cz * cz
end

-- Moves (fromX, fromZ) toward (toX, toZ) by at most maxStep.
function Geometry.stepToward(fromX: number, fromZ: number, toX: number, toZ: number, maxStep: number): (number, number)
	local dx, dz = toX - fromX, toZ - fromZ
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist <= maxStep or dist < 1e-9 then
		return toX, toZ
	end
	local s = maxStep / dist
	return fromX + dx * s, fromZ + dz * s
end

-- Pulls (x, z) back inside a circle around (cx, cz).
function Geometry.clampToCircle(x: number, z: number, cx: number, cz: number, radius: number): (number, number)
	local dx, dz = x - cx, z - cz
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist <= radius or dist < 1e-9 then
		return x, z
	end
	local s = radius / dist
	return cx + dx * s, cz + dz * s
end

-- Clamps (x, z) into a centred rectangle of half extents (hx, hz).
function Geometry.clampToRect(x: number, z: number, hx: number, hz: number): (number, number)
	return math.clamp(x, -hx, hx), math.clamp(z, -hz, hz)
end

function Geometry.insideRect(x: number, z: number, hx: number, hz: number): boolean
	return math.abs(x) <= hx and math.abs(z) <= hz
end

return Geometry
