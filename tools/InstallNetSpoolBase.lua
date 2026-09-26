--[[
	InstallNetSpoolBase.lua - one-shot, opt-in Studio installer for the net
	spool BASE prop only (see the reference image): a wide low round tan
	foot, a tall gently tapered tan/brown upright body, a narrow top collar,
	and a chunky rounded brown X/cross handle. MAP PROP ONLY - no net, ropes,
	mesh, fish, or gameplay of any kind, and no other object is touched.

	HOW TO RUN: paste this whole file into the Studio Command Bar (edit mode)
	and press Enter. It never runs automatically.

	This does not read any other object in the map (unlike
	InstallFishingNet.lua): it has no placement reference to match yet, so it
	builds standing at the world origin (foot resting on Y=0) for Astra to
	drag into place in Studio afterward. It aborts without changing anything
	if Workspace.NetSpoolBase already exists. Undo: one ChangeHistoryService
	recording ("Install NetSpoolBase").

	TUNABLES (edit these constants only):
		FOOT_RADIUS/HEIGHT           - the wide low round foot
		BODY_BOTTOM_RADIUS/TOP_RADIUS/HEIGHT/SEGMENTS
		                             - the tapered upright body (SEGMENTS
		                               stacked cylinders approximate the taper;
		                               Roblox has no native frustum part)
		COLLAR_RADIUS/HEIGHT         - the narrow rim just under the handle
		HANDLE_LENGTH/RADIUS         - the chunky cross handle bars
		BODY_COLOR / HANDLE_COLOR
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local FOOT_RADIUS = 1.4
local FOOT_HEIGHT = 0.35

local BODY_BOTTOM_RADIUS = 0.95
local BODY_TOP_RADIUS = 0.75
local BODY_HEIGHT = 2.3
local BODY_SEGMENTS = 4 -- stacked cylinders approximating a gentle taper

local COLLAR_RADIUS = 0.85
local COLLAR_HEIGHT = 0.18

local HANDLE_LENGTH = 1.7
local HANDLE_RADIUS = 0.22

local BODY_COLOR = Color3.fromRGB(200, 160, 108) -- tan/caramel
local COLLAR_COLOR = Color3.fromRGB(178, 138, 90) -- slightly darker tan
local HANDLE_COLOR = Color3.fromRGB(122, 72, 42) -- brown

if workspace:FindFirstChild("NetSpoolBase") then
	warn("[InstallNetSpoolBase] Workspace.NetSpoolBase already exists - aborting, nothing changed.")
	return
end

local recording
local ok = pcall(function()
	recording = ChangeHistoryService:TryBeginRecording("Install NetSpoolBase")
end)
if not ok or not recording then
	recording = nil
	pcall(function()
		ChangeHistoryService:SetWaypoint("Before Install NetSpoolBase")
	end)
end

local function anchoredPart(name: string, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = true
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	return part
end

-- A cylinder standing vertically in world space, sized `length` along its axis.
local function verticalCylinder(name: string, worldCenter: Vector3, length: number, radius: number, color: Color3): Part
	local part = anchoredPart(name, color)
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(length, radius * 2, radius * 2)
	part.CFrame = CFrame.new(worldCenter) * CFrame.Angles(0, 0, math.pi / 2)
	return part
end

local function roundedTip(name: string, worldCenter: Vector3, radius: number, color: Color3): Part
	local part = anchoredPart(name, color)
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	part.CFrame = CFrame.new(worldCenter)
	return part
end

local summary
local built, buildErr = pcall(function()
	local model = Instance.new("Model")
	model.Name = "NetSpoolBase"

	local y = FOOT_HEIGHT / 2 -- foot rests on Y = 0
	local foot = verticalCylinder("Foot", Vector3.new(0, y, 0), FOOT_HEIGHT, FOOT_RADIUS, BODY_COLOR)
	foot.Parent = model
	y += FOOT_HEIGHT / 2

	-- Stack BODY_SEGMENTS cylinders of shrinking radius: the simplest
	-- primitive-only approximation of a gentle taper (Roblox has no frustum
	-- part), each seated flush on the one below it.
	local segmentHeight = BODY_HEIGHT / BODY_SEGMENTS
	for i = 1, BODY_SEGMENTS do
		local t0 = (i - 1) / BODY_SEGMENTS
		local t1 = i / BODY_SEGMENTS
		local segmentRadius = (BODY_BOTTOM_RADIUS + (BODY_TOP_RADIUS - BODY_BOTTOM_RADIUS) * (t0 + t1) / 2)
		local center = Vector3.new(0, y + segmentHeight / 2, 0)
		local segment = verticalCylinder("Body" .. i, center, segmentHeight, segmentRadius, BODY_COLOR)
		segment.Parent = model
		y += segmentHeight
	end

	local collar =
		verticalCylinder("Collar", Vector3.new(0, y + COLLAR_HEIGHT / 2, 0), COLLAR_HEIGHT, COLLAR_RADIUS, COLLAR_COLOR)
	collar.Parent = model
	y += COLLAR_HEIGHT

	local handleCenter = Vector3.new(0, y + HANDLE_RADIUS, 0)
	local handleX = anchoredPart("HandleX", HANDLE_COLOR)
	handleX.Shape = Enum.PartType.Cylinder
	handleX.Size = Vector3.new(HANDLE_LENGTH, HANDLE_RADIUS * 2, HANDLE_RADIUS * 2)
	handleX.CFrame = CFrame.new(handleCenter)
	handleX.Parent = model

	local handleZ = anchoredPart("HandleZ", HANDLE_COLOR)
	handleZ.Shape = Enum.PartType.Cylinder
	handleZ.Size = Vector3.new(HANDLE_LENGTH, HANDLE_RADIUS * 2, HANDLE_RADIUS * 2)
	handleZ.CFrame = CFrame.new(handleCenter) * CFrame.Angles(0, math.pi / 2, 0)
	handleZ.Parent = model

	-- Rounded tips on the four handle ends, matching the reference's domed X.
	local half = HANDLE_LENGTH / 2
	local offsets =
		{ Vector3.new(half, 0, 0), Vector3.new(-half, 0, 0), Vector3.new(0, 0, half), Vector3.new(0, 0, -half) }
	for i, offset in ipairs(offsets) do
		roundedTip("HandleTip" .. i, handleCenter + offset, HANDLE_RADIUS, HANDLE_COLOR).Parent = model
	end

	model.PrimaryPart = foot
	model:SetAttribute("InstallerVersion", 1)
	model:PivotTo(CFrame.new(0, 0, 0))
	model.Parent = workspace

	summary = { TotalHeight = y + HANDLE_RADIUS * 2, FootRadius = FOOT_RADIUS }
end)

if recording then
	ChangeHistoryService:FinishRecording(
		recording,
		if built then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
	)
elseif built then
	pcall(function()
		ChangeHistoryService:SetWaypoint("Install NetSpoolBase")
	end)
end

if not built then
	warn("[InstallNetSpoolBase] Failed: " .. tostring(buildErr))
	return
end

print(
	string.format(
		"[InstallNetSpoolBase] Installed Workspace.NetSpoolBase at the world origin (foot resting on Y=0).\n  Total height ~%.2f studs, foot radius %.2f studs. Drag it into place in Studio.",
		summary.TotalHeight,
		summary.FootRadius
	)
)
return summary
