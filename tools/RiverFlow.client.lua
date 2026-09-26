--[[
	RiverFlow.client.lua - replacement for StarterPlayerScripts.ClearBlueRiverRipples.

	Draws slender white streaks flowing along Workspace.ClearBlueRiver.Water's local
	-X axis (bridge end toward the far bank), instead of the original faint dot ripples.
	Client-only, cosmetic, no remotes. Reads Water's CFrame/Size every frame so the
	effect follows the model if it is moved or resized.

	Each streak is SEGMENTS_PER_STREAK connected parts. Segment j spans the curve
	between t0=(j-1)/N and t1=j/N (N = SEGMENTS_PER_STREAK), so segment j's tail
	endpoint is exactly segment j+1's head endpoint: the pieces visibly connect.
	Each segment is sized Size.X = width, Size.Z = endpoint distance (plus a small
	overlap so seams don't gap), and oriented with CFrame.lookAt(midpoint, endpoint,
	water.CFrame.UpVector) so its length (local Z, per lookAt's -Z-to-target
	convention combined with the size axis below) tracks the local-X current.

	TUNING (edit these constants only):
		STREAK_COUNT     - number of streaks alive at once (kept under the part cap)
		SEGMENTS_PER_STREAK - short connected pieces forming each streak's curve
		SPEED_MIN/MAX    - studs/second along local -X
		LENGTH_MIN/MAX   - total streak length in studs
		WIDTH_MIN/MAX    - streak width in studs
		FLOW_DIR         - +1 or -1 along local X; -1 = toward local -X (bridge -> far bank)
]]

local RunService = game:GetService("RunService")

local STREAK_COUNT = 40
local SEGMENTS_PER_STREAK = 3
local SPEED_MIN, SPEED_MAX = 5, 9
local LENGTH_MIN, LENGTH_MAX = 4, 10
local WIDTH_MIN, WIDTH_MAX = 0.12, 0.28
local FLOW_DIR = -1
local SWAY_AMPLITUDE = 0.9 -- studs of lateral bend across a streak's length
local SWAY_SPEED_MIN, SWAY_SPEED_MAX = 0.5, 1.1 -- radians/second for the sway phase
local SURFACE_LIFT = 0.03 -- studs above the water's top face
local EDGE_FADE_STUDS = 6 -- fade streaks out within this many studs of the water's X ends
local SEGMENT_OVERLAP = 1.15 -- >1 so adjacent segments overlap slightly instead of leaving seams

local FOLDER_NAME = "LocalFlowLines"
local OLD_FOLDER_NAME = "LocalRipples"
local OWNER_TAG = "RiverFlowOwner" -- attribute marking folders this script created

assert(STREAK_COUNT * SEGMENTS_PER_STREAK < 150, "RiverFlow: part budget exceeded")

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
-- Guard against a duplicate run of this same script.
local existing = river:FindFirstChild(FOLDER_NAME)
if existing and existing:GetAttribute(OWNER_TAG) then
	existing:Destroy()
end

local folder = Instance.new("Folder")
folder.Name = FOLDER_NAME
folder:SetAttribute(OWNER_TAG, true)
folder.Parent = river

local rng = Random.new()

local function newSegmentPart(): Part
	local part = Instance.new("Part")
	part.Name = "Flow"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(255, 255, 255)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = 1
	part.Parent = folder
	return part
end

local streaks = {}

-- (Re)rolls a streak's length/width/speed/lane and, unless keepX, its head X.
local function respawnStreak(s, size: Vector3, keepX: boolean)
	s.length = rng:NextNumber(LENGTH_MIN, LENGTH_MAX)
	s.width = rng:NextNumber(WIDTH_MIN, WIDTH_MAX)
	s.speed = rng:NextNumber(SPEED_MIN, SPEED_MAX)
	-- Keep the whole sway range inside the water's Z bounds, with a small margin.
	local swayRoom = math.max(size.Z / 2 - 1 - SWAY_AMPLITUDE, 0.1)
	s.lz = rng:NextNumber(-swayRoom, swayRoom)
	s.swaySpeed = rng:NextNumber(SWAY_SPEED_MIN, SWAY_SPEED_MAX)
	s.swayPhase = rng:NextNumber(0, math.pi * 2)
	s.swaySign = if rng:NextNumber() < 0.5 then -1 else 1
	if not keepX then
		s.lx = rng:NextNumber(-size.X / 2, size.X / 2)
	elseif FLOW_DIR < 0 then
		s.lx = size.X / 2
	else
		s.lx = -size.X / 2
	end
end

for i = 1, STREAK_COUNT do
	local segments = {}
	for j = 1, SEGMENTS_PER_STREAK do
		segments[j] = newSegmentPart()
	end
	local s = { segments = segments }
	respawnStreak(s, water.Size, false)
	streaks[i] = s
end

local clock = 0

-- Local-space (x, z) of the curve at parameter t in [0, 1]: 0 at the streak's
-- head (leading edge, in the flow direction), 1 at its tail.
local function curvePoint(s, t: number): (number, number)
	local along = -FLOW_DIR * t * s.length -- steps backward from the head, away from the flow direction
	local lx = s.lx + along
	local sway = math.sin(clock * s.swaySpeed + s.swayPhase + t * math.pi) * SWAY_AMPLITUDE * s.swaySign
	return lx, s.lz + sway
end

local function updateStreak(s, cf: CFrame, size: Vector3, dt: number)
	s.lx += FLOW_DIR * s.speed * dt
	local halfX = size.X / 2
	local wrapped = (FLOW_DIR < 0 and s.lx < -halfX) or (FLOW_DIR > 0 and s.lx > halfX)
	if wrapped then
		respawnStreak(s, size, true)
	end

	local topY = size.Y / 2 + SURFACE_LIFT
	local segCount = #s.segments
	for j, part in ipairs(s.segments) do
		local t0 = (j - 1) / segCount
		local t1 = j / segCount
		local lx0, lz0 = curvePoint(s, t0)
		local lx1, lz1 = curvePoint(s, t1)
		local p0 = cf:PointToWorldSpace(Vector3.new(lx0, topY, lz0))
		local p1 = cf:PointToWorldSpace(Vector3.new(lx1, topY, lz1))
		local midpoint = p0:Lerp(p1, 0.5)
		local segLen = (p1 - p0).Magnitude

		-- Fade near the water's X ends and taper the streak's own head/tail.
		local midT = (t0 + t1) / 2
		local midLx = (lx0 + lx1) / 2
		local edgeFade = math.clamp(math.min(halfX - math.abs(midLx), EDGE_FADE_STUDS) / EDGE_FADE_STUDS, 0, 1)
		local tailFade = math.sin(midT * math.pi) -- 0 at both ends of the streak, 1 in the middle
		local alpha = edgeFade * (0.35 + 0.65 * tailFade)
		part.Transparency = 1 - math.clamp(alpha, 0, 1) * 0.65 -- min transparency ~0.35 midstream

		part.Size = Vector3.new(s.width, 0.05, math.max(segLen * SEGMENT_OVERLAP, 0.05))
		if segLen > 1e-4 then
			part.CFrame = CFrame.lookAt(midpoint, p1, water.CFrame.UpVector)
		else
			part.CFrame = CFrame.new(midpoint)
		end
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
		folder:Destroy()
	end
end

heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
	if not water.Parent or not folder.Parent then
		cleanup()
		return
	end
	clock += dt
	local cf, size = water.CFrame, water.Size
	for _, s in ipairs(streaks) do
		updateStreak(s, cf, size, dt)
	end
end)

ancestryConnection = water.AncestryChanged:Connect(function()
	if not water:IsDescendantOf(workspace) then
		cleanup()
	end
end)

destroyingConnection = script.Destroying:Connect(cleanup)
