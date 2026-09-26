--[[
	RiverFlow.client.lua - replacement for StarterPlayerScripts.ClearBlueRiverRipples.

	Draws slender white ribbons that visibly undulate (not rigid segments) while
	drifting along Workspace.ClearBlueRiver.Water's local -X axis. Client-only,
	cosmetic, no remotes. Reads Water's CFrame/Size every frame so the effect
	follows the model if it is moved or resized.

	HOW THE CURVE WORKS (chained, tangent-continuous cubic Beams):
	Each streak is POINTS_PER_STREAK Attachments (parented directly to Water, so
	their local-space Position/CFrame track Water automatically) joined by
	POINTS_PER_STREAK-1 Beams. Every Attachment's CFrame is oriented to the
	curve's own analytic tangent at that point (from curveInfo below), and a
	beam's two ends pull their Bezier control point along that SAME shared
	tangent with opposite sign (Attachment0: +segLen/3, Attachment1: -segLen/3).
	Because adjacent beams share both the attachment AND its tangent, the whole
	chain reads as one smooth curve with no visible joints or kinks - a rigid
	polyline would show a kink at every attachment; this cannot, by construction.
	The lateral shape itself is a travelling sine wave evaluated along each
	streak's own length (see curveInfo), so crests visibly slide along the
	ribbon while the ribbon as a whole drifts downstream.

	TUNING NOTE: CurveSize pulls a beam's control point along its attachment's
	local Z axis. The signs above assume Roblox's usual "+Z axis = backward"
	convention; if a Studio test shows the curve bowing the wrong way, flip
	CURVE_SIGN below (it will still be smooth either way, just mirrored).

	TUNING (edit these constants only):
		STREAK_COUNT        - number of ribbons alive at once
		POINTS_PER_STREAK   - control points per ribbon (N-1 beams each)
		SPEED_MIN/MAX       - downstream drift, studs/second, along local -X
		LENGTH_MIN/MAX      - ribbon length in studs
		WIDTH_MIN/MAX       - ribbon width in studs at its widest (mid-ribbon)
		WAVE_AMPLITUDE_*    - lateral undulation size, studs
		WAVE_COUNT_*        - full sine cycles along one ribbon's length
		WAVE_SPEED_*        - cycles/second the crest slides along the ribbon
		TRANSPARENCY_MID_*  - Beam.Transparency at the most-opaque (mid) point
		FLOW_DIR            - +1 or -1 along local X; -1 = toward local -X
]]

local RunService = game:GetService("RunService")

local STREAK_COUNT = 32
local POINTS_PER_STREAK = 5
local SPEED_MIN, SPEED_MAX = 5, 9
local LENGTH_MIN, LENGTH_MAX = 5, 11
local WIDTH_MIN, WIDTH_MAX = 0.10, 0.20
local WAVE_AMPLITUDE_MIN, WAVE_AMPLITUDE_MAX = 0.35, 0.8
local WAVE_COUNT_MIN, WAVE_COUNT_MAX = 1.0, 2.2
local WAVE_SPEED_MIN, WAVE_SPEED_MAX = 0.4, 0.9
local TRANSPARENCY_MID_MIN, TRANSPARENCY_MID_MAX = 0.3, 0.55
local FLOW_DIR = -1
local SURFACE_LIFT = 0.03 -- studs above the water's top face
local EDGE_FADE_STUDS = 6 -- fade ribbons out within this many studs of the water's X ends
local BEAM_SEGMENTS = 8 -- per beam piece; plenty smooth for a 1-3 stud arc
local CURVE_SIGN = 1 -- flip to -1 in Studio if the curve bows the wrong way (see header)

local FOLDER_NAME = "LocalFlowLines"
local OLD_FOLDER_NAME = "LocalRipples"
local OWNER_TAG = "RiverFlowOwner" -- attribute marking objects this script created

assert(STREAK_COUNT * POINTS_PER_STREAK < 400, "RiverFlow: instance budget exceeded")

local river = workspace:WaitForChild("ClearBlueRiver", 30)
local water = river and river:WaitForChild("Water", 30)
if not (water and water:IsA("BasePart")) then
	return
end

-- Remove the previous ripple folder only if it was created by our own prior
-- script (tagged with the same owner attribute), never an unrelated folder.
local oldFolder = river:FindFirstChild(OLD_FOLDER_NAME)
if oldFolder and oldFolder:GetAttribute(OWNER_TAG) then
	oldFolder:Destroy()
end
-- Guard against a duplicate run of this same script (beams folder + any
-- attachments a previous run parented directly onto Water).
local existingFolder = river:FindFirstChild(FOLDER_NAME)
if existingFolder and existingFolder:GetAttribute(OWNER_TAG) then
	existingFolder:Destroy()
end
for _, child in ipairs(water:GetChildren()) do
	if child:IsA("Attachment") and child:GetAttribute(OWNER_TAG) then
		child:Destroy()
	end
end

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder:SetAttribute(OWNER_TAG, true)
folder.Parent = river

local rng = Random.new()

local function newAttachment(): Attachment
	local att = Instance.new("Attachment")
	att.Name = "FlowPoint"
	att:SetAttribute(OWNER_TAG, true)
	att.Parent = water
	return att
end

local function newBeam(a0: Attachment, a1: Attachment): Beam
	local beam = Instance.new("Beam")
	beam.Name = "Flow"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.LightEmission = 0
	beam.LightInfluence = 1
	beam.Texture = ""
	beam.Segments = BEAM_SEGMENTS
	beam.Color = ColorSequence.new(Color3.new(1, 1, 1))
	beam.Parent = folder
	return beam
end

local streaks = {}

for _ = 1, STREAK_COUNT do
	local points, beams = {}, {}
	for k = 1, POINTS_PER_STREAK do
		points[k] = newAttachment()
	end
	for k = 1, POINTS_PER_STREAK - 1 do
		beams[k] = newBeam(points[k], points[k + 1])
	end
	table.insert(streaks, { points = points, beams = beams })
end

-- (Re)rolls a streak's shape/speed/lane and, unless keepX, its head X.
local function respawnStreak(s, size: Vector3, keepX: boolean)
	s.length = rng:NextNumber(LENGTH_MIN, LENGTH_MAX)
	s.width = rng:NextNumber(WIDTH_MIN, WIDTH_MAX)
	s.speed = rng:NextNumber(SPEED_MIN, SPEED_MAX)
	s.amplitude = rng:NextNumber(WAVE_AMPLITUDE_MIN, WAVE_AMPLITUDE_MAX)
	s.waveCount = rng:NextNumber(WAVE_COUNT_MIN, WAVE_COUNT_MAX)
	s.waveSpeed = rng:NextNumber(WAVE_SPEED_MIN, WAVE_SPEED_MAX) * (if rng:NextNumber() < 0.5 then -1 else 1)
	s.phase = rng:NextNumber(0, math.pi * 2)
	s.targetTransparency = rng:NextNumber(TRANSPARENCY_MID_MIN, TRANSPARENCY_MID_MAX)
	-- Keep the whole undulation range inside the water's Z bounds, with margin.
	local swayRoom = math.max(size.Z / 2 - 1 - s.amplitude, 0.1)
	s.lz0 = rng:NextNumber(-swayRoom, swayRoom)
	if not keepX then
		s.lx = rng:NextNumber(-size.X / 2, size.X / 2)
	elseif FLOW_DIR < 0 then
		s.lx = size.X / 2
	else
		s.lx = -size.X / 2
	end
end

for _, s in ipairs(streaks) do
	respawnStreak(s, water.Size, false)
end

local clock = 0

-- Local-space (Water frame) position and tangent direction of the curve at
-- parameter t in [0, 1]: 0 at the ribbon's head (leading edge, in the flow
-- direction), 1 at its tail. Both are analytic, so every point (including the
-- two ends) gets an exact, non-degenerate tangent - no finite differencing.
local function curveInfo(s, t: number): (number, number, number, number)
	local lx = s.lx - FLOW_DIR * t * s.length
	local theta = 2 * math.pi * (s.waveCount * t - s.waveSpeed * clock) + s.phase
	local lz = s.lz0 + math.sin(theta) * s.amplitude

	local dlxdt = -FLOW_DIR * s.length
	local dlzdt = math.cos(theta) * s.amplitude * (2 * math.pi * s.waveCount)
	return lx, lz, dlxdt, dlzdt
end

-- 0 at both ends of the ribbon, 1 at its middle: used for both width and
-- transparency so they taper together and never show a bare rigid tip.
local function taper(t: number): number
	return math.sin(t * math.pi)
end

local function updateStreak(s, size: Vector3, dt: number)
	s.lx += FLOW_DIR * s.speed * dt
	local halfX = size.X / 2
	local halfZ = size.Z / 2
	local wrapped = (FLOW_DIR < 0 and s.lx < -halfX) or (FLOW_DIR > 0 and s.lx > halfX)
	if wrapped then
		respawnStreak(s, size, true)
	end

	local topY = size.Y / 2 + SURFACE_LIFT
	local n = #s.points
	local positions = table.create(n)
	for k = 1, n do
		local t = (k - 1) / (n - 1)
		local lx, lz, tx, tz = curveInfo(s, t)
		lz = math.clamp(lz, -halfZ + 0.2, halfZ - 0.2) -- bank containment guard against float drift
		local tlen = math.sqrt(tx * tx + tz * tz)
		tx, tz = tx / tlen, tz / tlen
		local pos = Vector3.new(lx, topY, lz)
		positions[k] = pos
		s.points[k].CFrame = CFrame.lookAt(pos, pos + Vector3.new(tx, 0, tz))
	end

	for k = 1, n - 1 do
		local t0, t1 = (k - 1) / (n - 1), k / (n - 1)
		local segLen = (positions[k + 1] - positions[k]).Magnitude
		local beam = s.beams[k]
		beam.CurveSize0 = CURVE_SIGN * segLen / 3
		beam.CurveSize1 = -CURVE_SIGN * segLen / 3
		beam.Width0 = s.width * taper(t0)
		beam.Width1 = s.width * taper(t1)

		local midLx0 = positions[k].X
		local midLx1 = positions[k + 1].X
		local edgeFade0 = math.clamp(math.min(halfX - math.abs(midLx0), EDGE_FADE_STUDS) / EDGE_FADE_STUDS, 0, 1)
		local edgeFade1 = math.clamp(math.min(halfX - math.abs(midLx1), EDGE_FADE_STUDS) / EDGE_FADE_STUDS, 0, 1)
		local tr0 = 1 - (1 - s.targetTransparency) * taper(t0) * edgeFade0
		local tr1 = 1 - (1 - s.targetTransparency) * taper(t1) * edgeFade1
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, tr0),
			NumberSequenceKeypoint.new(1, tr1),
		})
	end
end

local heartbeatConnection: RBXScriptConnection? = nil
local ancestryConnection: RBXScriptConnection? = nil
local destroyingConnection: RBXScriptConnection? = nil

local function cleanup()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
	if ancestryConnection then
		ancestryConnection:Disconnect()
		ancestryConnection = nil
	end
	if destroyingConnection then
		destroyingConnection:Disconnect()
		destroyingConnection = nil
	end
	if folder.Parent then
		folder:Destroy() -- takes every Beam with it
	end
	for _, s in ipairs(streaks) do
		for _, att in ipairs(s.points) do
			att:Destroy() -- Attachments live on Water, not in folder; clean them explicitly
		end
	end
end

heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
	if not water.Parent or not folder.Parent then
		cleanup()
		return
	end
	clock += dt
	local size = water.Size
	for _, s in ipairs(streaks) do
		updateStreak(s, size, dt)
	end
end)

ancestryConnection = water.AncestryChanged:Connect(function()
	if not water:IsDescendantOf(workspace) then
		cleanup()
	end
end)

destroyingConnection = script.Destroying:Connect(cleanup)
