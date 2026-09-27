--!strict
-- GrinderDwell (ModuleScript in ReplicatedStorage). Pure timeline for a fish
-- arriving at the grinder: rise -> fly -> DWELL (settle onto the rollers,
-- tumble and shudder for about a second) -> drop (spiral down, shrinking
-- into the rollers). The single source of truth for every path:
--   * FishSwimClient animates net catches from these numbers,
--   * NetLiftScript fires FishCaught / destroys the fish at serverDelay(),
--   * RodFishingSystem's grinder fallback plays the same dwell + drop.
-- Pure numbers only (no Vector3), so it's tested offline. No gore: the fish
-- just tumbles, shrinks and disappears into the rollers.

local D = {}

-- timeline (seconds). Rise/Fly/Drop match the original FishSwimClient.
D.Rise = 0.12
D.Fly = 0.95
D.Dwell = 1.0
D.Drop = 0.55
D.ServerSlack = 0.03 -- server acts just after the client drop ends (original: 1.65 vs 1.62)

-- placement relative to the verified GrinderPos (where flights land)
D.OffsetY = -0.8 -- rest height on the rollers; raise if fish clip the housing, lower if they hover
D.DropDepth = 3.2 -- end of the drop below GrinderPos (original)
D.DropRadius = 1.2 -- spiral start radius (original)

-- dwell motion
D.SettleSeconds = 0.15 -- ease from GrinderPos down onto the rollers
D.ShudderAmp = 0.12 -- studs; fades in and out so the dwell joins smoothly
D.TumbleSpeed = 4 -- rad/s, slower than the 11 rad/s flight spin
D.DriftFraction = 0.3 -- last part of the dwell drifts to where the spiral starts

function D.total(): number
	return D.Rise + D.Fly + D.Dwell + D.Drop
end

function D.serverDelay(): number
	return D.total() + D.ServerSlack
end

-- Which phase a fish is in `lt` seconds after CaughtT.
-- Returns (name, secondsIntoPhase, fraction 0..1).
function D.phase(lt: number): (string, number, number)
	if lt < D.Rise then
		return "rise", lt, math.max(0, lt) / D.Rise
	end
	lt -= D.Rise
	if lt < D.Fly then
		return "fly", lt, lt / D.Fly
	end
	lt -= D.Fly
	if lt < D.Dwell then
		return "dwell", lt, lt / D.Dwell
	end
	lt -= D.Dwell
	if lt < D.Drop then
		return "drop", lt, lt / D.Drop
	end
	return "done", lt - D.Drop, 1
end

local function smoothstep(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- Dwell offset from GrinderPos at `e` seconds into the dwell, as numbers:
-- settle down to OffsetY, a bounded shudder (zero at both ends), and a drift
-- along +X to the spiral's start point in the last DriftFraction.
function D.dwellOffset(e: number, seed: number): (number, number, number)
	local settle = smoothstep(e / D.SettleSeconds)
	local envelope = math.sin(math.pi * math.clamp(e / D.Dwell, 0, 1))
	local amp = D.ShudderAmp * envelope
	local sx = math.sin(e * 37 + seed) * amp
	local sy = math.abs(math.sin(e * 29 + seed * 1.3)) * amp -- only upward: never sinks into the rollers
	local sz = math.cos(e * 31 + seed * 0.7) * amp
	local driftStart = D.Dwell * (1 - D.DriftFraction)
	local drift = smoothstep((e - driftStart) / (D.Dwell - driftStart))
	return sx + drift * D.DropRadius, D.OffsetY * settle + sy, sz
end

-- Drop offset from GrinderPos at fraction u (0..1): spiral in and down from
-- the dwell rest point to DropDepth below GrinderPos. Returns x, y, z, scale.
-- With OffsetY = 0 this is exactly the original suction formula.
function D.dropOffset(u: number): (number, number, number, number)
	u = math.clamp(u, 0, 1)
	local e = u * u
	local r = D.DropRadius * (1 - u)
	local a = u * math.pi * 5
	local y = D.OffsetY - (D.DropDepth + D.OffsetY) * e
	return math.cos(a) * r, y, math.sin(a) * r, 1 - 0.92 * e
end

return D
