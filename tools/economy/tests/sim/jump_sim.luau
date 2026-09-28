-- River fish jumps (rebased on the live FishSwimClient, which has the
-- harpoon branch): the REAL patched client and the REAL FishJump module on
-- the fake engine. Checks the client runs without errors, fish jump and
-- splash, JumpEnabled = false stops jumps, and net / harpoon launches still
-- work (including a fish caught mid-jump).

current = "server"
local SURFACE = 7.45
local river = new("Folder", "SwimmingFish")
river:SetAttribute("SurfaceY", SURFACE)
river:SetAttribute("MinX", -20)
river:SetAttribute("MaxX", 20)
river:SetAttribute("MinZ", 0)
river:SetAttribute("MaxZ", 2000)
river:SetAttribute("GrinderPos", Vector3.new(0, 20, -10))
river:SetAttribute("JumpChance", 1) -- every period, so the test is deterministic
river.Parent = workspaceInst
script("ModuleScript", "FishJump", SOURCES.Jump_Module, services.ReplicatedStorage)

local fish = {}
for i = 1, 12 do
	local m = new("Model", "Fish" .. i)
	local root = part("Root", Vector3.new(0, SURFACE - 0.6, 0), m, Vector3.new(1, 1, 3))
	part("Tail", Vector3.new(0, SURFACE - 0.6, -1.5), m)
	m._props.PrimaryPart = root
	m:SetAttribute("SwimLen", 4)
	m:SetAttribute("Seed", 1000 + i * 37)
	m:SetAttribute("SpawnT", 0)
	m:SetAttribute("StartZ", 20 + i * 5)
	m:SetAttribute("Speed", 5)
	m:SetAttribute("LaneX", -10 + i)
	m.Parent = river
	fish[i] = m
end
current = nil

local viewer = join(1, "Viewer", Vector3.new(0, 10, 0))
runScript(script("LocalScript", "FishSwimClient", SOURCES.Jump_Client), viewer)
advance(0.5)

local function rootY(m)
	return m.Root.Position.Y
end
local jumped, maxY = {}, -math.huge
local splashSeen = false
for _ = 1, 60 * 5 do -- 60 s, sampled every 0.2 s
	advance(0.2)
	for i, m in ipairs(fish) do
		local y = rootY(m)
		maxY = math.max(maxY, y)
		if y > SURFACE + 0.5 then
			jumped[i] = true
		end
	end
	local splashes = workspaceInst:FindFirstChild("FishJumpSplashes")
	for _, ring in ipairs(splashes and splashes:GetChildren() or {}) do
		if ring.Transparency < 1 then
			splashSeen = true
		end
	end
end
local count = 0
for _ in pairs(jumped) do
	count += 1
end
check("every fish jumped within a minute (JumpChance = 1)", count == #fish)
check("jumps stay low (<= 3.2 studs above the swim line + wobble)", maxY <= SURFACE - 0.6 + 3.2 + 0.3)
check("splash discs appear", splashSeen)
check("fish keep swimming up the river (+Z)", fish[1].Root.Position.Z > 20 + 5 + 5 * 50)

-- a fish netted mid-jump launches from where it is (no snap to the water)
local airborne
for _ = 1, 150 do
	advance(0.1)
	for _, m in ipairs(fish) do
		if rootY(m) > SURFACE + 1 then
			airborne = m
			break
		end
	end
	if airborne then
		break
	end
end
check("found a fish in the air", airborne ~= nil)
if airborne then
	-- sample the launch's first frame (elapsed 0 = the launch start point)
	asServer(function()
		airborne:SetAttribute("CaughtT", workspaceInst:GetServerTimeNow() + 1 / 30)
	end)
	advance(1 / 30)
	check("caught mid-jump: launches from the air, no snap to the water", rootY(airborne) > SURFACE + 0.5)
	advance(1.8)
	local grinder = river:GetAttribute("GrinderPos")
	check("caught fish ends at the grinder", (airborne.Root.Position - grinder).Magnitude < 6)
end

-- the harpoon branch (live) still runs first
do
	local m = fish[2]
	local p = m.Root.Position
	asServer(function()
		m:SetAttribute("HarpoonHit", p)
		m:SetAttribute("HarpoonBack", p + Vector3.new(0, 0, -8))
		m:SetAttribute("HarpoonT", workspaceInst:GetServerTimeNow())
	end)
	advance(2)
	check("harpooned fish pulled to the grinder", (m.Root.Position - river:GetAttribute("GrinderPos")).Magnitude < 6)
end

-- the kill switch applies live
asServer(function()
	river:SetAttribute("JumpEnabled", false)
end)
advance(3) -- let any jump in the air land
local stillJumping = false
for _ = 1, 150 do
	advance(0.2)
	for _, m in ipairs(fish) do
		if m ~= airborne and m ~= fish[2] and rootY(m) > SURFACE + 0.3 then
			stillJumping = true
		end
	end
end
check("JumpEnabled = false: no more jumps", not stillJumping)

finish("jump sim")
