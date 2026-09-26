--!strict
-- Angle helpers for the net's circular-sector sweep. Kept separate from
-- Geometry.luau (which is plane/segment math) so both stay small and testable.

local GeometryAngle = {}

-- Wraps an angle (radians) into (-pi, pi].
function GeometryAngle.normalize(angle: number): number
	angle = (angle + math.pi) % (2 * math.pi)
	if angle <= 0 then
		angle += 2 * math.pi
	end
	return angle - math.pi
end

-- Shortest signed delta from `from` to `to`, in (-pi, pi].
function GeometryAngle.delta(from: number, to: number): number
	return GeometryAngle.normalize(to - from)
end

-- True when `angle` lies within the arc starting at `lo` and sweeping the
-- shortest way to `hi` (lo/hi need not be normalized or ordered by value).
function GeometryAngle.withinArc(angle: number, lo: number, hi: number, tolerance: number): boolean
	local span = GeometryAngle.delta(lo, hi)
	local toAngle = GeometryAngle.delta(lo, angle)
	if span >= 0 then
		return toAngle >= -tolerance and toAngle <= span + tolerance
	end
	return toAngle <= tolerance and toAngle >= span - tolerance
end

return GeometryAngle
