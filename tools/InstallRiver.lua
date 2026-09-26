--[[
	InstallRiver.lua - one-shot, opt-in Studio installer for a Part-based "clear blue river".

	HOW TO RUN: paste this whole file into the Studio Command Bar (edit mode) and press Enter.
	It never runs automatically.

	What it adds (and nothing else):
	  * Workspace.ClearBlueRiver                                  (Model)
	      - Water       : one translucent, non-colliding, non-query body part, top face = surface Y 5.35
	      - SwimBounds  : invisible, non-colliding, non-query volume for future scripted fish
	  * StarterPlayer.StarterPlayerScripts.ClearBlueRiverRipples  (LocalScript, client-only highlights)

	It aborts without changing anything if either object already exists. It does not edit
	Terrain, Lighting, existing parts or scripts (Workspace.FishGrinder and the bridge are untouched).
	Undo: one ChangeHistoryService recording ("Install ClearBlueRiver"), so Ctrl+Z removes both.

	NOTE: this is custom Part water. It does NOT give native Humanoid swimming (that only
	happens in Terrain water). Characters walk on the channel bed through the water body
	because the Water part has CanCollide = false.

	Geometry (studs, world space, axis-aligned):
	  Surface Y 5.35, water body Y 2.45..5.35, X -33..133, Z -195.95..-162.5
	  (channel bed max top Y 2.37285, sand bank top 5.89389, bridge bottom 7.03).
	  SwimBounds Y 2.85..4.95, X -31..131, Z -194.45..-164.0.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local StarterPlayer = game:GetService("StarterPlayer")

local MODEL_NAME = "ClearBlueRiver"
local SCRIPT_NAME = "ClearBlueRiverRipples"

local SURFACE_Y = 5.35
local BODY_BOTTOM_Y = 2.45
local MIN_X, MAX_X = -33, 133
local MIN_Z, MAX_Z = -195.95, -162.5

local SWIM_MIN = Vector3.new(-31, 2.85, -194.45)
local SWIM_MAX = Vector3.new(131, 4.95, -164.0)

local starterScripts = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
if not starterScripts then
	warn("[InstallRiver] StarterPlayer.StarterPlayerScripts not found - aborting, nothing changed.")
	return
end
if workspace:FindFirstChild(MODEL_NAME) then
	warn("[InstallRiver] Workspace." .. MODEL_NAME .. " already exists - aborting, nothing changed.")
	return
end
if starterScripts:FindFirstChild(SCRIPT_NAME) then
	warn("[InstallRiver] StarterPlayerScripts." .. SCRIPT_NAME .. " already exists - aborting, nothing changed.")
	return
end

local RIPPLE_SOURCE = [==[
-- ClearBlueRiverRipples: client-only, subtle drifting surface highlights for Workspace.ClearBlueRiver.
-- Highlights are positioned relative to the Water part every frame, so they follow the model if it moves.
-- Purely cosmetic: no remotes, no gameplay. Created by tools/InstallRiver.lua.
local RunService = game:GetService("RunService")

local MAX_HIGHLIGHTS = 18 -- hard cap on effect parts
local river = workspace:WaitForChild("ClearBlueRiver", 30)
local water = river and river:WaitForChild("Water", 30)
if not (water and water:IsA("BasePart")) then
	return
end

local folder = Instance.new("Folder")
folder.Name = "LocalRipples"
folder.Parent = river

local rng = Random.new()
local highlights = {}

local function respawn(h, anywhere)
	local size = water.Size
	h.lx = anywhere and rng:NextNumber(-size.X / 2, size.X / 2) or -size.X / 2
	h.lz = rng:NextNumber(-size.Z / 2 + 2, size.Z / 2 - 2)
	h.speed = rng:NextNumber(1.2, 2.6)
	h.phase = rng:NextNumber(0, math.pi * 2)
	h.part.Size = Vector3.new(rng:NextNumber(3, 6), 0.05, rng:NextNumber(0.25, 0.5))
end

for i = 1, MAX_HIGHLIGHTS do
	local part = Instance.new("Part")
	part.Name = "Ripple" .. i
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(225, 250, 255)
	part.Transparency = 1
	part.Parent = folder
	local h = { part = part }
	respawn(h, true)
	highlights[i] = h
end

local clock = 0
local connection
local function cleanup()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	folder:Destroy()
end

connection = RunService.Heartbeat:Connect(function(dt)
	if not water.Parent or not folder.Parent then
		cleanup()
		return
	end
	clock += dt
	local cf = water.CFrame
	local size = water.Size
	local halfX = size.X / 2
	local topY = size.Y / 2 + 0.03
	for _, h in ipairs(highlights) do
		h.lx += h.speed * dt
		if h.lx > halfX then
			respawn(h, false)
		end
		-- fade in/out at the channel ends and twinkle gently; never below 0.7 transparency
		local edge = math.clamp(math.min(h.lx + halfX, halfX - h.lx) / 8, 0, 1)
		local twinkle = 0.5 + 0.5 * math.sin(clock * 1.3 + h.phase)
		h.part.Transparency = 1 - 0.28 * edge * twinkle
		h.part.CFrame = cf * CFrame.new(h.lx, topY, h.lz + math.sin(clock * 0.8 + h.phase) * 0.4)
	end
end)

water.AncestryChanged:Connect(function()
	if not water:IsDescendantOf(workspace) then
		cleanup()
	end
end)
]==]

local recording
local ok = pcall(function()
	recording = ChangeHistoryService:TryBeginRecording("Install ClearBlueRiver")
end)
if not ok or not recording then
	recording = nil
	pcall(function()
		ChangeHistoryService:SetWaypoint("Before Install ClearBlueRiver")
	end)
end

local function basePart(name, size, cframe)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cframe
	return part
end

local summary
local built, buildErr = pcall(function()
	local model = Instance.new("Model")
	model.Name = MODEL_NAME

	local bodyHeight = SURFACE_Y - BODY_BOTTOM_Y
	local water = basePart(
		"Water",
		Vector3.new(MAX_X - MIN_X, bodyHeight, MAX_Z - MIN_Z),
		CFrame.new((MIN_X + MAX_X) / 2, BODY_BOTTOM_Y + bodyHeight / 2, (MIN_Z + MAX_Z) / 2)
	)
	-- Single translucent layer (no stacked surface sheet) so submerged fish stay visible.
	water.Material = Enum.Material.SmoothPlastic
	water.Color = Color3.fromRGB(45, 175, 215)
	water.Transparency = 0.5
	water.Reflectance = 0
	water.Parent = model

	local swimSize = SWIM_MAX - SWIM_MIN
	local swim = basePart("SwimBounds", swimSize, CFrame.new((SWIM_MIN + SWIM_MAX) / 2))
	swim.Transparency = 1
	swim:SetAttribute("SwimMin", SWIM_MIN)
	swim:SetAttribute("SwimMax", SWIM_MAX)
	swim:SetAttribute("SurfaceY", SURFACE_Y)
	swim:SetAttribute("BedTopY", 2.37285)
	swim:SetAttribute("Note", "World-space at install time; if the model is moved, use this part's CFrame/Size instead")
	swim.Parent = model

	model:SetAttribute("SurfaceY", SURFACE_Y)
	model:SetAttribute("NativeSwimming", false)
	model:SetAttribute("InstallerVersion", 1)
	model.PrimaryPart = water
	model.Parent = workspace

	local ripples = Instance.new("LocalScript")
	ripples.Name = SCRIPT_NAME
	ripples.Source = RIPPLE_SOURCE
	ripples.Parent = starterScripts

	summary = {
		Water = {
			Min = Vector3.new(MIN_X, BODY_BOTTOM_Y, MIN_Z),
			Max = Vector3.new(MAX_X, SURFACE_Y, MAX_Z),
			Transparency = 0.5,
		},
		SwimBounds = { Min = SWIM_MIN, Max = SWIM_MAX },
		Script = ripples:GetFullName(),
	}
end)

if recording then
	ChangeHistoryService:FinishRecording(
		recording,
		if built then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
	)
elseif built then
	pcall(function()
		ChangeHistoryService:SetWaypoint("Install ClearBlueRiver")
	end)
end

if not built then
	warn("[InstallRiver] Failed: " .. tostring(buildErr))
	return
end

print(
	string.format(
		"[InstallRiver] Installed Workspace.%s\n  Water body X %g..%g  Y %g..%g  Z %g..%g  (transparency 0.5, CanCollide/CanQuery/CanTouch false)\n  SwimBounds  %s .. %s  (attributes SwimMin, SwimMax, SurfaceY, BedTopY)\n  Client ripples: %s (max 18 highlight parts)\n  Custom water: no native Humanoid swimming.",
		MODEL_NAME,
		MIN_X,
		MAX_X,
		BODY_BOTTOM_Y,
		SURFACE_Y,
		MIN_Z,
		MAX_Z,
		tostring(SWIM_MIN),
		tostring(SWIM_MAX),
		summary.Script
	)
)
return summary
