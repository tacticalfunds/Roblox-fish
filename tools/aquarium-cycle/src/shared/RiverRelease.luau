--!strict
-- Pure spawn-attribute maths for putting a released aquarium fish back into
-- Workspace.SwimmingFish. Mirrors FishSpawner.spawnFish exactly (lane, start,
-- end, lifetime) so FishSwimClient animates it and NetLiftScript can net it
-- like any other river fish.

local RiverRelease = {}

export type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number, surfaceY: number }

export type Spawn = {
	SpawnT: number,
	StartZ: number,
	Speed: number,
	LaneX: number,
	Seed: number,
	lifetime: number, -- seconds until it reaches the end of the river
	y: number, -- swim height used for the server-side pivot
}

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Reads the river folder's attributes through `get(name)`. Returns nil and a
-- problem string when any is missing or inconsistent.
function RiverRelease.readBounds(get: (string) -> any): (Bounds?, string?)
	local b = {
		minX = get("MinX"),
		maxX = get("MaxX"),
		minZ = get("MinZ"),
		maxZ = get("MaxZ"),
		surfaceY = get("SurfaceY"),
	}
	-- Iterate the expected names: a missing attribute is nil, which pairs()
	-- would silently skip.
	for _, key in ipairs({ "minX", "maxX", "minZ", "maxZ", "surfaceY" }) do
		if not finite((b :: any)[key]) then
			return nil, "river attribute " .. key .. " missing or not a number"
		end
	end
	if b.minX >= b.maxX or b.minZ >= b.maxZ then
		return nil, "river bounds are empty"
	end
	return b :: Bounds, nil
end

-- rSpeed and rLane are uniform random numbers in [0, 1] supplied by the
-- caller, so this stays deterministic under test.
function RiverRelease.attributes(
	b: Bounds,
	swimLen: any,
	now: number,
	seed: number,
	rSpeed: number,
	rLane: number,
	speedRange: { number }
): Spawn
	local L = if finite(swimLen) and swimLen > 0 then swimLen else 4
	local half = math.max(0, (b.maxX - b.minX) / 2 - L * 0.3 - 1.5)
	local cx = (b.minX + b.maxX) / 2
	local startZ = b.minZ + L / 2
	local endZ = b.maxZ - L / 2
	local speed = speedRange[1] + (speedRange[2] - speedRange[1]) * math.clamp(rSpeed, 0, 1)
	local laneX = cx - half + 2 * half * math.clamp(rLane, 0, 1)
	return {
		SpawnT = now,
		StartZ = startZ,
		Speed = speed,
		LaneX = laneX,
		Seed = seed,
		lifetime = math.max(0, (endZ - startZ) / speed),
		y = b.surfaceY - 0.6,
	}
end

return RiverRelease
