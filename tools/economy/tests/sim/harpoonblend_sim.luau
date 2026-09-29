-- Harpoon mid-jump fix: the REAL HarpoonBlend-patched FishSwimClient (on the
-- fish-jump client, and on grinder dwell over it) with the REAL FishJump
-- module. The server aims at the swim line; a fish struck mid-jump must start
-- its pull in the air and ease down onto the rope, not snap to the water.
-- The unpatched jump client is run the same way to show the snap.

local SURFACE = 7.45
local LINE = SURFACE - 0.6 -- the server's aim height (HarpoonSystem fishPos)
local GRINDER = Vector3.new(0, 20, -10)
local PULL = 0.6

local viewerId = 0
local function scenario(label, clientSource, dwell)
	current = "server"
	local old = workspaceInst:FindFirstChild("SwimmingFish")
	if old then old:Destroy() end
	for _, n in ipairs({ "FishJump", "GrinderDwell" }) do
		local m = services.ReplicatedStorage:FindFirstChild(n)
		if m then m:Destroy() end
	end
	local river = new("Folder", "SwimmingFish")
	river:SetAttribute("SurfaceY", SURFACE)
	river:SetAttribute("MinX", -20)
	river:SetAttribute("MaxX", 20)
	river:SetAttribute("MinZ", 0)
	river:SetAttribute("MaxZ", 2000)
	river:SetAttribute("GrinderPos", GRINDER)
	river:SetAttribute("JumpChance", 1)
	river.Parent = workspaceInst
	script("ModuleScript", "FishJump", SOURCES.Jump_Module, services.ReplicatedStorage)
	if dwell then
		script("ModuleScript", "GrinderDwell", SOURCES.Dwell_Module, services.ReplicatedStorage)
	end
	local fish = {}
	for i = 1, 10 do
		local m = new("Model", "Fish" .. i)
		local root = part("Root", Vector3.new(0, LINE, 0), m, Vector3.new(1, 1, 3))
		part("Tail", Vector3.new(0, LINE, -1.5), m)
		m._props.PrimaryPart = root
		m:SetAttribute("SwimLen", 4)
		m:SetAttribute("Seed", 2000 + i * 53)
		m:SetAttribute("SpawnT", 0)
		m:SetAttribute("StartZ", 20 + i * 5)
		m:SetAttribute("Speed", 5)
		m:SetAttribute("LaneX", -10 + i)
		m.Parent = river
		fish[i] = m
	end
	current = nil
	viewerId += 1
	local viewer = join(100 + viewerId, "Viewer" .. viewerId, Vector3.new(0, 10, 0))
	runScript(script("LocalScript", "FishSwimClient", clientSource), viewer)
	advance(0.5)

	local function harpoon(m)
		local p = m.Root.Position
		local hit = Vector3.new(p.X, LINE, p.Z) -- where the server aims
		asServer(function()
			m:SetAttribute("HarpoonHit", hit)
			m:SetAttribute("HarpoonBack", hit + Vector3.new(0, 0, -8))
			m:SetAttribute("HarpoonT", workspaceInst:GetServerTimeNow() + 1 / 30)
		end)
		advance(1 / 30) -- the pull's first frame
		return hit
	end

	-- a fish in the air
	local airborne
	for _ = 1, 400 do
		advance(0.1)
		for _, m in ipairs(fish) do
			if m.Root.Position.Y > SURFACE + 1.2 then
				airborne = m
				break
			end
		end
		if airborne then break end
	end
	check(label .. ": found a fish in the air", airborne ~= nil)
	local result = {}
	if airborne then
		local airY = airborne.Root.Position.Y
		harpoon(airborne)
		result.firstY = airborne.Root.Position.Y
		result.airY = airY
		advance(PULL / 2) -- lt = 0.3: the smoothed pull is exactly halfway
		result.midY = airborne.Root.Position.Y
		advance(PULL / 2 - 2 / 30) -- lt = 0.53: nearly at the rope end
		result.endBack = airborne:GetAttribute("HarpoonBack")
		result.endPos = airborne.Root.Position
		advance(4)
		result.final = airborne.Root.Position
	end
	-- a fish swimming (not jumping): unchanged
	local swimming
	for _, m in ipairs(fish) do
		if m ~= airborne and math.abs(m.Root.Position.Y - LINE) < 0.3 then
			swimming = m
			break
		end
	end
	if swimming then
		local hit = harpoon(swimming)
		result.swimFirst = (swimming.Root.Position - hit).Magnitude
	end
	return result
end

for _, case in ipairs({ { "on fish jumps", SOURCES.Blend_Jump, false }, { "on dwell over jumps", SOURCES.Blend_Dwell, true } }) do
	local label, r = case[1], scenario(case[1], case[2], case[3])
	if r.firstY then
		check(label .. ": struck mid-jump, the pull starts in the air (no snap)", r.firstY > SURFACE + 0.8 and math.abs(r.firstY - r.airY) < 0.6)
		-- halfway: the pull's own 2-stud arc plus half the jump height
		check(label .. ": halfway it has eased half the way down", math.abs(r.midY - (LINE + 2 + 0.5 * (r.firstY - LINE))) < 0.35)
		check(label .. ": near the end of the pull it is at the rope end", (r.endPos - r.endBack).Magnitude < 0.6)
		check(label .. ": then it still ends in the grinder", (r.final - GRINDER).Magnitude < 6)
	end
	check(label .. ": a swimming fish starts exactly at the hit, as before", r.swimFirst ~= nil and r.swimFirst < 0.3)
end

-- the unpatched fish-jump client: the snap this fixes
local r = scenario("unpatched", SOURCES.Jump_Client, false)
check("unpatched: struck mid-jump, it snaps to the water line (the bug)", r.firstY ~= nil and r.firstY < LINE + 0.6)

finish("harpoon blend sim")
