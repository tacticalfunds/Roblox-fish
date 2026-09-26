-- Pale rope-lattice visuals for a plot's net: a small fixed pool of thin,
-- non-colliding parts (radial "spokes" from the anchor plus chord "rim"
-- segments joining their tips) that are repositioned every update to trace
-- the current circular-sector enclosure. Geometry is pooled per plot and
-- reused for the plot's whole lifetime; nothing here decides gameplay.

local Shared = game:GetService("ReplicatedStorage").FishTycoonShared
local GeometryAngle = require(Shared.GeometryAngle)

local NetVisual = {}

local SPOKES = 7 -- radial ropes, evenly spaced across the current arc
local RIM_SEGMENTS = SPOKES - 1 -- chords joining consecutive spoke tips
local ROPE_COLOR = Color3.fromRGB(232, 232, 222)
local ROPE_TRANSPARENCY = 0.35
local ROPE_DIAMETER = 0.09

local function ropePart(parent: Instance, name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = ROPE_COLOR
	part.Transparency = 1
	part.Size = Vector3.new(0.1, ROPE_DIAMETER, ROPE_DIAMETER)
	part.Parent = parent
	return part
end

-- Places a thin cylinder between two world points (cylinders are long along local X).
local function placeRope(part: Part, a: Vector3, b: Vector3)
	local delta = b - a
	local length = delta.Magnitude
	if length < 1e-3 then
		part.Transparency = 1
		return
	end
	part.Transparency = ROPE_TRANSPARENCY
	part.Size = Vector3.new(length, ROPE_DIAMETER, ROPE_DIAMETER)
	part.CFrame = CFrame.new(a, b) * CFrame.new(0, 0, -length / 2) * CFrame.Angles(0, math.pi / 2, 0)
end

function NetVisual.create(parent: Instance)
	local root = Instance.new("Folder")
	root.Name = "NetVisual"
	local spokes, rim = {}, {}
	for i = 1, SPOKES do
		spokes[i] = ropePart(root, "Spoke" .. i)
	end
	for i = 1, RIM_SEGMENTS do
		rim[i] = ropePart(root, "Rim" .. i)
	end
	root.Parent = parent
	return { root = root, spokes = spokes, rim = rim }
end

-- anchorWorld/tipAngleWorld describe the sector in world space:
--   anchor, radius, startAngle, endAngle are in the zone's local XZ plane;
--   toWorld(localX, localZ) converts a local XZ pair (at the water surface
--   height) to a world position, matching how Net.luau tracks the sector.
function NetVisual.update(
	visual,
	toWorld: (number, number) -> Vector3,
	anchorX: number,
	anchorZ: number,
	radius: number,
	startAngle: number,
	endAngle: number,
	visible: boolean
)
	if not visible or radius < 1e-3 then
		for _, part in ipairs(visual.spokes) do
			part.Transparency = 1
		end
		for _, part in ipairs(visual.rim) do
			part.Transparency = 1
		end
		return
	end

	local span = GeometryAngle.delta(startAngle, endAngle)
	local points = {}
	for i = 1, SPOKES do
		local frac = (i - 1) / (SPOKES - 1)
		local angle = startAngle + span * frac
		points[i] = toWorld(anchorX + math.cos(angle) * radius, anchorZ + math.sin(angle) * radius)
	end
	local anchorWorld = toWorld(anchorX, anchorZ)
	for i, part in ipairs(visual.spokes) do
		placeRope(part, anchorWorld, points[i])
	end
	for i, part in ipairs(visual.rim) do
		placeRope(part, points[i], points[i + 1])
	end
end

function NetVisual.destroy(visual)
	visual.root:Destroy()
end

return NetVisual
