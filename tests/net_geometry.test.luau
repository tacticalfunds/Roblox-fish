-- Offline pure-logic checks for the net's tip-clamping and sector-angle math
-- (src/server/Net.luau). Run with the standalone Luau CLI:
--   luau tests/net_geometry.test.luau
-- These exercise Geometry.luau/GeometryAngle.luau directly and do not touch
-- any Roblox API, so they run outside Studio -- they are NOT a substitute for
-- an in-Studio playtest of casting/sweeping/hauling the net.
local Geometry = require("../src/shared/Geometry")
local GeometryAngle = require("../src/shared/GeometryAngle")

local failures = 0
local function check(name, cond)
	if not cond then
		failures += 1
		print("FAIL: " .. name)
	end
end

-- clampTip reasoning: rect-then-circle in one pass stays inside both when the
-- anchor is inside the rect.
local function clampTip(ax, az, x, z, radius, hx, hz)
	x, z = Geometry.clampToRect(x, z, hx, hz)
	x, z = Geometry.clampToCircle(x, z, ax, az, radius)
	return x, z
end

-- Anchor near a rect edge (the case that broke the old circle-then-rect order).
local hx, hz = 20, 15
local ax, az = 18, 0 -- close to the +X edge
local radius = 10
for _, target in ipairs({
	{ 30, 0 },
	{ 18, 20 },
	{ -5, -5 },
	{ 40, 40 },
	{ 18, 0.1 },
}) do
	local x, z = clampTip(ax, az, target[1], target[2], radius, hx, hz)
	local inRect = math.abs(x) <= hx + 1e-6 and math.abs(z) <= hz + 1e-6
	local distSq = (x - ax) ^ 2 + (z - az) ^ 2
	local inCircle = distSq <= radius * radius + 1e-6
	check(string.format("target (%d,%d) in rect", target[1], target[2]), inRect)
	check(string.format("target (%d,%d) in circle", target[1], target[2]), inCircle)
end

-- Convexity: stepping toward a feasible target from a feasible point stays feasible.
local cx, cz = clampTip(ax, az, 30, 0, radius, hx, hz) -- feasible target
local sx, sz = ax, az -- feasible current point (the anchor itself)
for step = 1, 20 do
	sx, sz = Geometry.stepToward(sx, sz, cx, cz, 1.3)
	local inRect = math.abs(sx) <= hx + 1e-6 and math.abs(sz) <= hz + 1e-6
	local inCircle = (sx - ax) ^ 2 + (sz - az) ^ 2 <= radius * radius + 1e-6
	check("step " .. step .. " stays in rect", inRect)
	check("step " .. step .. " stays in circle", inCircle)
end

-- GeometryAngle: normalize range
check("normalize(0)", GeometryAngle.normalize(0) == 0)
check(
	"normalize(3pi) wraps",
	math.abs(GeometryAngle.normalize(3 * math.pi) - math.pi) < 1e-9
		or math.abs(GeometryAngle.normalize(3 * math.pi) + math.pi) < 1e-9
)
check("delta shortest path", math.abs(GeometryAngle.delta(math.pi - 0.1, -math.pi + 0.1) - 0.2) < 1e-9)

-- withinArc: growing sector in the positive direction
check("start==end includes only that angle (approx)", GeometryAngle.withinArc(0, 0, 0, 0.01))
check("mid of small positive arc", GeometryAngle.withinArc(math.rad(10), 0, math.rad(20), 0.001))
check("outside small positive arc", not GeometryAngle.withinArc(math.rad(30), 0, math.rad(20), 0.001))
check("negative-direction arc", GeometryAngle.withinArc(math.rad(-10), 0, math.rad(-20), 0.001))
check("wraparound arc across +-pi", GeometryAngle.withinArc(math.pi - 0.01, math.rad(170), math.rad(-170), 0.001))

if failures == 0 then
	print("ALL NET GEOMETRY CHECKS PASSED")
else
	print(failures .. " CHECK(S) FAILED")
end
