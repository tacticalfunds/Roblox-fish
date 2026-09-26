--[[
	InstallFishingNet.lua - one-shot, opt-in Studio installer for a decorative
	woven fishing-net funnel beside the grinder. MAP ASSET ONLY: this places a
	static, non-colliding model. It does not touch gameplay, scripts, remotes,
	or any prototype source under src/ (including src/server/Net.luau's
	runtime NetVisual, which this does not replace or interact with).

	HOW TO RUN: paste this whole file into the Studio Command Bar (edit mode)
	and press Enter. It never runs automatically.

	Matches the reference image: ONE rounded tan spool post with a brown cross
	handle at the dock edge, and a single woven cream mesh cone/funnel hanging
	from it - a wide mouth rim right at the post, tapering and drooping down
	and out over the water to a narrow, partly-submerged far end (a wind-sock
	shape), NOT a flat curtain between two posts and NOT a radial fan.

	What it adds (and nothing else):
	  * Workspace.FishingNet                      (Model)
	      - Post   : the spool bollard (body + cap + cross handle)
	      - Rigging: a few short ropes from the post to the mouth rim
	      - Mesh (Folder) : the tapered tube - mouth/tip hem hoops plus
	        diagonal crossings wrapped around the cone, forming small diamond
	        holes along its length.

	Placement is computed from the LIVE Workspace.FishGrinder bounding box and
	Workspace.ClearBlueRiver.Water CFrame/Size (read at run time, not
	hardcoded), so it adapts if either has moved since these notes were
	written. It aborts without changing anything if either source object is
	missing, or if Workspace.FishingNet already exists. Undo: one
	ChangeHistoryService recording ("Install FishingNet").

	TUNABLES (edit these constants only):
		POST_GAP          - studs between the grinder's edge and the post
		MOUTH_RADIUS/TIP_RADIUS - net radius at the post end vs. the far end
		REACH_Z           - how far the net extends into the river, studs
		LATERAL_DRIFT     - sideways drift along the post-to-tip run, studs
		DROOP             - total vertical drop from mouth to tip, studs
		MOUTH_HEIGHT      - studs the mouth sits above the water surface
		ROWS / RING_SEGMENTS - lattice density along the cone / around it
		POST_BANK_INSET   - how far the post sits in from the water's bank edge
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local POST_GAP = 1.5
local MOUTH_RADIUS = 2.2
local TIP_RADIUS = 0.35
local REACH_Z = 10
local LATERAL_DRIFT = 3
local DROOP = 6
local DROOP_POWER = 1.6 -- >1: net hangs nearly level near the post, then curves down toward the tip
local MOUTH_HEIGHT = 1
local ROWS = 10
local RING_SEGMENTS = 14
local POST_BANK_INSET = 1.5

local POST_RADIUS = 0.9
local POST_BOTTOM_OFFSET = -1 -- studs below the water surface the post is "planted"
local POST_TOP_OFFSET = 2.5 -- studs above the water surface the post stands
local CAP_RADIUS = 1.15
local CAP_HEIGHT = 0.35
local HANDLE_LENGTH = 1.6
local HANDLE_RADIUS = 0.12

local ROPE_HEM_DIAMETER = 0.16
local ROPE_DIAMETER = 0.07
local RIGGING_DIAMETER = 0.1
local ROPE_COLOR = Color3.fromRGB(232, 222, 195) -- pale cream
local POST_COLOR = Color3.fromRGB(196, 165, 116) -- tan
local HANDLE_COLOR = Color3.fromRGB(118, 76, 44) -- brown

if workspace:FindFirstChild("FishingNet") then
	warn("[InstallFishingNet] Workspace.FishingNet already exists - aborting, nothing changed.")
	return
end

local grinder = workspace:FindFirstChild("FishGrinder")
if not grinder then
	warn("[InstallFishingNet] Workspace.FishGrinder not found - aborting, nothing changed.")
	return
end

local riverModel = workspace:FindFirstChild("ClearBlueRiver")
local water = riverModel and riverModel:FindFirstChild("Water")
if not (water and water:IsA("BasePart")) then
	warn("[InstallFishingNet] Workspace.ClearBlueRiver.Water not found - aborting, nothing changed.")
	return
end

-- Read the grinder's live bounding box (works whether it's a Model or a lone part).
local grinderCFrame: CFrame
local grinderSize = Vector3.new(4, 4, 4)
if grinder:IsA("Model") then
	grinderCFrame, grinderSize = grinder:GetBoundingBox()
elseif grinder:IsA("BasePart") then
	grinderCFrame, grinderSize = grinder.CFrame, grinder.Size
else
	local part = grinder:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		warn("[InstallFishingNet] Workspace.FishGrinder has no BasePart to measure - aborting, nothing changed.")
		return
	end
	grinderCFrame, grinderSize = part.CFrame, part.Size
end

local waterCFrame, waterSize = water.CFrame, water.Size
local grinderLocal = waterCFrame:PointToObjectSpace(grinderCFrame.Position)

-- Which side of the water the dock/grinder (and so the post) sit on.
local bankSign = if grinderLocal.Z >= 0 then 1 else -1
local postLocalZ = bankSign * (waterSize.Z / 2 - POST_BANK_INSET)
local postX = grinderLocal.X + grinderSize.X / 2 + POST_GAP

local surfaceLocalY = waterSize.Y / 2
local postHeight = POST_TOP_OFFSET - POST_BOTTOM_OFFSET
local postCenterLocalY = surfaceLocalY + (POST_BOTTOM_OFFSET + POST_TOP_OFFSET) / 2

local function toWorld(lx: number, ly: number, lz: number): Vector3
	return waterCFrame:PointToWorldSpace(Vector3.new(lx, ly, lz))
end

local recording
local ok = pcall(function()
	recording = ChangeHistoryService:TryBeginRecording("Install FishingNet")
end)
if not ok or not recording then
	recording = nil
	pcall(function()
		ChangeHistoryService:SetWaypoint("Before Install FishingNet")
	end)
end

local function anchoredPart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	return part
end

-- A cylinder standing vertically in world space, sized `length` along its axis.
local function verticalCylinder(name: string, worldCenter: Vector3, length: number, radius: number, color: Color3): Part
	local part = anchoredPart(name)
	part.Shape = Enum.PartType.Cylinder
	part.Color = color
	part.Size = Vector3.new(length, radius * 2, radius * 2)
	part.CFrame = CFrame.new(worldCenter) * CFrame.Angles(0, 0, math.pi / 2)
	return part
end

-- A thin rope segment between two world points (any orientation).
local function rope(name: string, a: Vector3, b: Vector3, diameter: number): Part
	local part = anchoredPart(name)
	part.Shape = Enum.PartType.Cylinder
	part.Color = ROPE_COLOR
	local length = math.max((b - a).Magnitude, 0.02)
	part.Size = Vector3.new(length, diameter, diameter)
	part.CFrame = CFrame.new(a, b) * CFrame.new(0, 0, -length / 2) * CFrame.Angles(0, math.pi / 2, 0)
	return part
end

local function buildPost(): Model
	local model = Instance.new("Model")
	model.Name = "Post"
	local center = toWorld(postX, postCenterLocalY, postLocalZ)

	local body = verticalCylinder("Body", center, postHeight, POST_RADIUS, POST_COLOR)
	body.Parent = model

	local capCenter = center + Vector3.new(0, postHeight / 2 + CAP_HEIGHT / 2, 0)
	local cap = verticalCylinder("Cap", capCenter, CAP_HEIGHT, CAP_RADIUS, POST_COLOR)
	cap.Parent = model

	local handleCenter = capCenter + Vector3.new(0, CAP_HEIGHT / 2 + HANDLE_RADIUS, 0)
	local handleX = anchoredPart("HandleX")
	handleX.Shape = Enum.PartType.Cylinder
	handleX.Color = HANDLE_COLOR
	handleX.Size = Vector3.new(HANDLE_LENGTH, HANDLE_RADIUS * 2, HANDLE_RADIUS * 2)
	handleX.CFrame = CFrame.new(handleCenter)
	handleX.Parent = model

	local handleZ = anchoredPart("HandleZ")
	handleZ.Shape = Enum.PartType.Cylinder
	handleZ.Color = HANDLE_COLOR
	handleZ.Size = Vector3.new(HANDLE_LENGTH, HANDLE_RADIUS * 2, HANDLE_RADIUS * 2)
	handleZ.CFrame = CFrame.new(handleCenter) * CFrame.Angles(0, math.pi / 2, 0)
	handleZ.Parent = model

	model.PrimaryPart = body
	model:SetAttribute("CapCenter", capCenter)
	return model
end

-- Local-space (x, y, z) of the cone's centreline at length fraction t in
-- [0, 1]: 0 at the mouth (right at the post), 1 at the tapered far tip. The Y
-- droop uses DROOP_POWER > 1 so the net hangs almost level near the post and
-- curves downward more steeply toward the tip, like a weighted sock, not a
-- straight rigid cone.
local function centrelineLocal(t: number): (number, number, number)
	local lx = postX + LATERAL_DRIFT * t
	local lz = postLocalZ - bankSign * REACH_Z * t
	local ly = surfaceLocalY + MOUTH_HEIGHT - DROOP * (t ^ DROOP_POWER)
	return lx, ly, lz
end

local function radiusAt(t: number): number
	return MOUTH_RADIUS + (TIP_RADIUS - MOUTH_RADIUS) * t
end

local function ringPoint(t: number, col: number): Vector3
	local lx, ly, lz = centrelineLocal(t)
	local center = toWorld(lx, ly, lz)
	local angle = (2 * math.pi * col) / RING_SEGMENTS
	local r = radiusAt(t)
	-- Rings are horizontal circles in world space: a simple, robust
	-- approximation of a perpendicular-to-path cross-section that still reads
	-- correctly as a tapered, drooping cone from a fixed elevated camera.
	return center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
end

local function buildMesh(parent: Instance, postCapCenter: Vector3)
	local mesh = Instance.new("Folder")
	mesh.Name = "Mesh"
	mesh.Parent = parent

	local grid = table.create(ROWS)
	for row = 0, ROWS - 1 do
		local t = row / (ROWS - 1)
		local points = table.create(RING_SEGMENTS)
		for col = 0, RING_SEGMENTS - 1 do
			points[col + 1] = ringPoint(t, col)
		end
		grid[row + 1] = points
	end

	-- Thicker mouth and tip hem hoops (closed rings).
	for _, rowIndex in ipairs({ 1, ROWS }) do
		local points = grid[rowIndex]
		for col = 1, RING_SEGMENTS do
			local nextCol = col % RING_SEGMENTS + 1
			rope("Hem", points[col], points[nextCol], ROPE_HEM_DIAMETER).Parent = mesh
		end
	end

	-- Diagonal crossings wrap around the cone (column wraps modulo
	-- RING_SEGMENTS) to form the diamond/square holes of a woven net; this is
	-- the whole visible mesh interior - deliberately no straight lengthwise
	-- struts, so it reads as netting rather than a filled sheet or a fan.
	for row = 1, ROWS - 1 do
		for col = 1, RING_SEGMENTS do
			local nextCol = col % RING_SEGMENTS + 1
			rope("Diagonal", grid[row][col], grid[row + 1][nextCol], ROPE_DIAMETER).Parent = mesh
			rope("Diagonal", grid[row][nextCol], grid[row + 1][col], ROPE_DIAMETER).Parent = mesh
		end
	end

	-- A few rigging lines from the spool's cap down to the mouth rim, as if
	-- the net were hung from the post.
	local mouthPoints = grid[1]
	local rigCount = 4
	for i = 0, rigCount - 1 do
		local col = math.floor(i * RING_SEGMENTS / rigCount) + 1
		rope("Rigging", postCapCenter, mouthPoints[col], RIGGING_DIAMETER).Parent = mesh
	end
end

local summary
local built, buildErr = pcall(function()
	local model = Instance.new("Model")
	model.Name = "FishingNet"

	local post = buildPost()
	post.Parent = model
	buildMesh(model, post:GetAttribute("CapCenter"))

	model.PrimaryPart = post.PrimaryPart
	model:SetAttribute("InstallerVersion", 2)
	model.Parent = workspace

	summary = {
		Post = toWorld(postX, postCenterLocalY, postLocalZ),
		Mouth = toWorld(centrelineLocal(0)),
		Tip = toWorld(centrelineLocal(1)),
		BankSign = bankSign,
		Segments = RING_SEGMENTS * 2 + (ROWS - 1) * RING_SEGMENTS * 2 + 4,
	}
end)

if recording then
	ChangeHistoryService:FinishRecording(
		recording,
		if built then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
	)
elseif built then
	pcall(function()
		ChangeHistoryService:SetWaypoint("Install FishingNet")
	end)
end

if not built then
	warn("[InstallFishingNet] Failed: " .. tostring(buildErr))
	return
end

print(
	string.format(
		"[InstallFishingNet] Installed Workspace.FishingNet\n  Post %s  (bank side local Z sign %d)\n  Mouth %s (radius %g)  ->  Tip %s (radius %g)\n  %d lattice segments.",
		tostring(summary.Post),
		summary.BankSign,
		tostring(summary.Mouth),
		MOUTH_RADIUS,
		tostring(summary.Tip),
		TIP_RADIUS,
		summary.Segments
	)
)
return summary
