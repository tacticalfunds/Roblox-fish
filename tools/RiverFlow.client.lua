--[[
	RiverFlow.client.lua - replacement for StarterPlayerScripts.ClearBlueRiverRipples.

	Draws slender white streaks flowing along Workspace.ClearBlueRiver.Water's local
	-X axis (bridge end toward the far bank), instead of the original faint dot ripples.
	Client-only, cosmetic, no remotes. Reads Water's CFrame/Size every frame so the
	effect follows the model if it is moved or resized.

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
local EDGE_FADE_STUDS = 6 -- fade streaks out within this many studs of the ends

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

-- (Re)rolls a streak's length/width/speed/lane and, unless keepX, its start X.
local function respawnStreak(s, size: Vector3, keepX: boolean)
	s.length = rng:NextNumber(LENGTH_MIN, LENGTH_MAX)
	s.width = rng:NextNumber(WIDTH_MIN, WIDTH_MAX)
	s.speed = rng:NextNumber(SPEED_MIN, SPEED_MAX)
	s.lz = rng:NextNumber(-size.Z / 2 + 1, size.Z / 2 - 1)
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
		-- Position each segment along the streak, front (flow-facing) to back.
		local t = (j - 1) / math.max(segCount - 1, 1) -- 0 at front, 1 at back
		local along = -FLOW_DIR * t * s.length -- steps backward from the head, away from flow direction
		local segLx = s.lx + along

		-- Gentle curve: lateral offset varies smoothly along the streak's length.
		local sway = math.sin(clock * s.swaySpeed + s.swayPhase + t * math.pi) * SWAY_AMPLITUDE * s.swaySign
		local segLz = s.lz + sway

		-- Fade near the water's X ends and taper the streak's own head/tail.
		local edgeFade = math.clamp(math.min(halfX - math.abs(segLx), EDGE_FADE_STUDS) / EDGE_FADE_STUDS, 0, 1)
		local tailFade = math.sin(t * math.pi) -- 0 at both ends of the streak, 1 in the middle
		local alpha = edgeFade * (0.35 + 0.65 * tailFade)
		part.Transparency = 1 - math.clamp(alpha, 0, 1) * 0.65 -- min transparency ~0.35 midstream

		local segLen = (s.length / segCount) * 1.15 -- slight overlap so the curve reads as continuous
		part.Size = Vector3.new(segLen, 0.05, s.width)

		-- Orient each segment to face the next point along the sway curve.
		local nextT = math.clamp(t + 1 / math.max(segCount - 1, 1) * 0.35, 0, 1)
		local nextSway = math.sin(clock * s.swaySpeed + s.swayPhase + nextT * math.pi) * SWAY_AMPLITUDE * s.swaySign
		local aheadLx = segLx - FLOW_DIR * 0.5
		local aheadLz = s.lz + nextSway
		local worldPos = cf:PointToWorldSpace(Vector3.new(segLx, topY, segLz))
		local worldAhead = cf:PointToWorldSpace(Vector3.new(aheadLx, topY, aheadLz))
		if (worldAhead - worldPos).Magnitude > 1e-3 then
			part.CFrame = CFrame.lookAt(worldPos, worldAhead)
		else
			part.CFrame = CFrame.new(worldPos)
		end
	end
end

local connection
local function cleanup()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if folder.Parent then
		folder:Destroy()
	end
end

connection = RunService.Heartbeat:Connect(function(dt)
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

water.AncestryChanged:Connect(function()
	if not water:IsDescendantOf(workspace) then
		cleanup()
	end
end)

script.Destroying:Connect(cleanup)
