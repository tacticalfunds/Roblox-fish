-- Animates the fish stream: every fish swims up the river (toward +Z) with a body-wave wiggle.
-- Position comes from server time + attributes set by FishSpawner, so all players see the same thing.
-- Fish that get a CaughtT attribute (set by the net) are launched in an arc into the grinder.
--
-- [GrinderDwell patch v1] Changes marked "GrinderDwell": with
-- ReplicatedStorage.GrinderDwell installed, a launched fish lands on the
-- rollers, tumbles/shudders there for about a second, then spirals in and
-- shrinks. The timeline comes from that module (NetLiftScript uses the same
-- numbers). Without it the launch is exactly the original.
--
-- [FishJump patch v1] Changes vs. the original are marked "FishJump". With
-- ReplicatedStorage.FishJump installed, fish occasionally jump out of the water
-- (visual only: the same x/z lane path, so net catches and rewards are
-- unchanged) with a small splash on takeoff and landing. Without the module
-- this script behaves exactly like the original.
local RunService = game:GetService("RunService")
local folder = workspace:WaitForChild("SwimmingFish")
local surfaceY = folder:GetAttribute("SurfaceY")

local LAUNCH_RISE, LAUNCH_FLY, LAUNCH_DROP = 0.12, 0.95, 0.55

-- GrinderDwell: optional ~1 s tumble on the rollers before the pull-in
-- (missing module -> original timing)
local Dwell = nil
do
	local mod = game:GetService("ReplicatedStorage"):FindFirstChild("GrinderDwell")
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok and type(m) == "table" then
			Dwell = m
		else
			warn("[GrinderDwell] failed to load, using original timing: " .. tostring(m))
		end
	end
end
if Dwell then LAUNCH_RISE, LAUNCH_FLY, LAUNCH_DROP = Dwell.Rise, Dwell.Fly, Dwell.Drop end
local DWELL = if Dwell then Dwell.Dwell else 0
local TUMBLE = if Dwell then Dwell.TumbleSpeed else 0

------------------------------------------------ jumps (FishJump)
local Jump, jumpCfg = nil, nil
do
	local mod = game:GetService("ReplicatedStorage"):FindFirstChild("FishJump")
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok and type(m) == "table" then
			Jump = m
			jumpCfg = m.config(function(name) return folder:GetAttribute(name) end)
		else
			warn("[FishSwimClient] FishJump failed to load; no jumps: " .. tostring(m))
		end
	end
end
local riverMinZ, riverMaxZ = folder:GetAttribute("MinZ"), folder:GetAttribute("MaxZ")
if Jump then
	-- JumpEnabled / JumpChance / JumpHeightScale on SwimmingFish apply live
	folder.AttributeChanged:Connect(function(name)
		if name:sub(1, 4) == "Jump" then
			local splashOn = jumpCfg.Splash
			jumpCfg = Jump.config(function(n) return folder:GetAttribute(n) end)
			jumpCfg.Splash = splashOn -- the splash pool is built once at startup
		end
	end)
end

-- pooled splash discs, reused (never more than SplashPool at once)
local SPLASH_TIME = 0.5
local splashPool, activeSplashes = {}, {}
if Jump and jumpCfg.Splash then
	local splashFolder = Instance.new("Folder")
	splashFolder.Name = "FishJumpSplashes"
	for _ = 1, jumpCfg.SplashPool do
		local ring = Instance.new("Part")
		ring.Name = "Splash"
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Material = Enum.Material.SmoothPlastic
		ring.Color = Color3.fromRGB(235, 248, 255)
		ring.Transparency = 1
		ring.Size = Vector3.new(0.08, 1, 1)
		ring.CFrame = CFrame.new(0, -1000, 0)
		ring.Parent = splashFolder
		table.insert(splashPool, ring)
	end
	splashFolder.Parent = workspace
	script.Destroying:Connect(function() splashFolder:Destroy() end)
end

local function splash(x, z, L)
	local ring = table.remove(splashPool)
	if not ring then return end
	table.insert(activeSplashes, { ring = ring, t0 = os.clock(), x = x, z = z, r = math.clamp(L * 0.5, 1, 3) })
end

local function updateSplashes()
	local now = os.clock()
	for i = #activeSplashes, 1, -1 do
		local s = activeSplashes[i]
		local u = (now - s.t0) / SPLASH_TIME
		if u >= 1 then
			s.ring.Transparency = 1
			s.ring.CFrame = CFrame.new(0, -1000, 0)
			table.insert(splashPool, s.ring)
			table.remove(activeSplashes, i)
		else
			local d = s.r * (1 + 3 * u)
			s.ring.Size = Vector3.new(0.08, d, d)
			s.ring.CFrame = CFrame.new(s.x, surfaceY + 0.05, s.z) * CFrame.Angles(0, 0, math.pi / 2)
			s.ring.Transparency = 0.35 + 0.65 * u
		end
	end
end

local fishes = {}

local function swimPos(f, t)
	local age = t - f.spawnT
	local z = f.startZ + f.speed * age
	local x = f.laneX + f.weaveA * math.sin(f.weaveF * t + f.phase)
	local y = surfaceY - 0.6 + 0.12 * math.sin(t * 1.7 + f.phase)
	local dx = f.weaveA * f.weaveF * math.cos(f.weaveF * t + f.phase)
	return Vector3.new(x, y, z), Vector3.new(dx, 0, f.speed)
end

-- Jump-adjusted position/direction at `time` (pure: no splashes). x/z are
-- untouched; only height and nose pitch change. Returns pos, dir, u, cycle.
local function jumpAt(f, time, pos, dir)
	if f.snake and jumpCfg.SkipSnakes then return pos, dir, nil, nil end
	local u, cycle = Jump.phase(f.seed, time, jumpCfg)
	-- judge the river-end margin at takeoff, so a jump never gets cut off mid-air
	if not u or not Jump.allowed(pos.Z - f.speed * u * jumpCfg.Duration, riverMinZ, riverMaxZ, jumpCfg) then
		return pos, dir, nil, cycle
	end
	local dy, vy = Jump.offset(u, f.jumpH, jumpCfg)
	return pos + Vector3.new(0, dy, 0), Vector3.new(dir.X, vy, dir.Z), u, cycle
end

local function addFish(m)
	if fishes[m] then return end
	local root = m:WaitForChild("Root", 5)
	if not root or not m.Parent then return end
	local L = m:GetAttribute("SwimLen") or 4
	local seed = m:GetAttribute("Seed") or 1
	local f = {
		model = m, L = L,
		vertical = m:GetAttribute("Vertical") == true,
		snake = m.Name == "CrystalSerpent",
		spawnT = m:GetAttribute("SpawnT"), startZ = m:GetAttribute("StartZ"),
		speed = m:GetAttribute("Speed"), laneX = m:GetAttribute("LaneX"),
		caughtT = m:GetAttribute("CaughtT"),
		weaveA = 0.8 + (seed % 7) * 0.15, weaveF = 0.35 + (seed % 5) * 0.08, phase = seed * 1.7,
		spinAxis = Vector3.new(math.sin(seed), 0.6, math.cos(seed * 1.3)).Unit,
		parts = {}, rels = {}, zs = {}, sizes = {},
	}
	f.omega = math.clamp(7 * math.sqrt(3 / L), 3, 9)
	f.k = 2 * math.pi / (L * 1.2)
	f.B = (f.snake and 0.13 or 0.08) * L
	f.seed = seed -- FishJump
	f.jumpH = Jump and Jump.height(L, jumpCfg) -- FishJump
	local rootCF = root.CFrame
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then
			local rel = rootCF:ToObjectSpace(p.CFrame)
			table.insert(f.parts, p)
			table.insert(f.rels, rel)
			table.insert(f.zs, rel.Position.Z)
			table.insert(f.sizes, p.Size)
		end
	end
	m:GetAttributeChangedSignal("SpawnT"):Connect(function() f.spawnT = m:GetAttribute("SpawnT") end)
	m:GetAttributeChangedSignal("CaughtT"):Connect(function() f.caughtT = m:GetAttribute("CaughtT") end)
	fishes[m] = f
end

for _, m in ipairs(folder:GetChildren()) do task.spawn(addFish, m) end
folder.ChildAdded:Connect(function(m) task.spawn(addFish, m) end)
folder.ChildRemoved:Connect(function(m) fishes[m] = nil end)

local allParts, allCFs = {}, {}
local function push(p, cf) table.insert(allParts, p) table.insert(allCFs, cf) end

RunService.RenderStepped:Connect(function()
	local t = workspace:GetServerTimeNow()
	local grinder = folder:GetAttribute("GrinderPos")
	table.clear(allParts) table.clear(allCFs)
	if Jump then updateSplashes() end -- FishJump
	for m, f in pairs(fishes) do
		if not m.Parent then fishes[m] = nil continue end
		local L, B, k, w = f.L, f.B, f.k, f.omega

		if f.caughtT and grinder then
			-- LAUNCHED: pop up with the net, arc into the grinder, tumble, drop in
			local lt = t - f.caughtT
			local p0, dir0 = swimPos(f, f.caughtT)
			-- FishJump: launch from wherever the fish was in its jump (no snap back to the water)
			if Jump then p0, dir0 = jumpAt(f, f.caughtT, p0, dir0) end
			local top = p0 + Vector3.new(0, 6, 0)
			local pos
			if lt < LAUNCH_RISE then
				local e = 1 - (1 - lt / LAUNCH_RISE) ^ 3
				pos = p0:Lerp(top, e)
			elseif lt < LAUNCH_RISE + LAUNCH_FLY then
				local u = (lt - LAUNCH_RISE) / LAUNCH_FLY
				pos = top:Lerp(grinder, u) + Vector3.new(0, 9 * 4 * u * (1 - u), 0)
			elseif lt < LAUNCH_RISE + LAUNCH_FLY + DWELL then
				-- GrinderDwell: settle onto the rollers, tumble and shudder there
				local ox, oy, oz = Dwell.dwellOffset(lt - LAUNCH_RISE - LAUNCH_FLY, f.phase)
				pos = grinder + Vector3.new(ox, oy, oz)
			elseif Dwell then
				-- GrinderDwell: spiral in from the rollers while shrinking
				local ox, oy, oz, scale = Dwell.dropOffset((lt - LAUNCH_RISE - LAUNCH_FLY - DWELL) / LAUNCH_DROP)
				pos = grinder + Vector3.new(ox, oy, oz)
				f.suck = scale
			else
				-- SUCKED IN: spiral down into the rollers while spinning and shrinking
				local u = math.clamp((lt - LAUNCH_RISE - LAUNCH_FLY) / LAUNCH_DROP, 0, 1)
				local e = u * u
				local r = 1.2 * (1 - u)
				local a = u * math.pi * 5
				pos = grinder + Vector3.new(math.cos(a) * r, -3.2 * e, math.sin(a) * r)
				f.suck = 1 - 0.92 * e
			end
			local s = f.suck or 1
			local startRot = CFrame.lookAt(p0, p0 + dir0).Rotation
			local rot
			if f.suck then
				local u = math.clamp((lt - LAUNCH_RISE - LAUNCH_FLY - DWELL) / LAUNCH_DROP, 0, 1) -- GrinderDwell
				local flightEnd = startRot * CFrame.fromAxisAngle(f.spinAxis, LAUNCH_FLY * 11 + DWELL * TUMBLE)
				local dive = CFrame.Angles(0, u * math.pi * 6, 0) * CFrame.Angles(math.rad(-80), 0, 0) -- whirl nose-first down
				rot = flightEnd:Lerp(dive, math.min(1, u * 2.5))
			else
				-- GrinderDwell: fast spin in flight, slower tumble on the rollers
				local flight = math.min(math.max(0, lt - LAUNCH_RISE), LAUNCH_FLY)
				local tumble = math.max(0, lt - LAUNCH_RISE - LAUNCH_FLY)
				rot = startRot * CFrame.fromAxisAngle(f.spinAxis, flight * 11 + tumble * TUMBLE)
			end
			local base = rot + pos
			local flap = math.sin(t * 25) * 0.35 -- panicked tail flap
			for i, p in ipairs(f.parts) do
				local zr = f.zs[i]
				local weight = math.clamp((zr + 0.1 * L) / (0.6 * L), 0, 1)
				local rel = f.rels[i]
				if s < 1 then
					p.Size = f.sizes[i] * s
					rel = CFrame.new(rel.Position * s) * rel.Rotation
				end
				push(p, base * CFrame.new(flap * weight * L * 0.12 * s, 0, 0) * rel)
			end
			continue
		end

		local pos, dir = swimPos(f, t)
		if Jump then -- FishJump
			local u, cycle
			pos, dir, u, cycle = jumpAt(f, t, pos, dir)
			if u then
				if f.jumpCycle ~= cycle then
					f.jumpCycle = cycle
					-- splash only for jumps seen taking off, not ones already in the air on join
					f.splashCycle = if u < 0.25 then cycle else nil
					if f.splashCycle and jumpCfg.Splash then splash(pos.X, pos.Z, L) end
				end
				f.airborne = true
			elseif f.airborne then
				f.airborne = false
				if jumpCfg.Splash and f.splashCycle ~= nil and f.splashCycle == f.jumpCycle then splash(pos.X, pos.Z, L) end
			end
		end
		local base = CFrame.lookAt(pos, pos + dir)
		for i, p in ipairs(f.parts) do
			local zr = f.zs[i]
			local weight
			if f.snake then
				weight = 0.35 + 0.65 * math.clamp((zr + L / 2) / L, 0, 1)
			else
				weight = math.clamp((zr + 0.1 * L) / (0.6 * L), 0, 1) ^ 1.5
			end
			local phase = w * t - k * zr
			local off = B * weight * math.sin(phase)
			local ang = -B * weight * k * math.cos(phase)
			local rel = f.rels[i]
			local cf
			if f.vertical then
				cf = CFrame.new(0, off, 0) * CFrame.new(rel.Position) * CFrame.Angles(ang, 0, 0) * rel.Rotation
			else
				cf = CFrame.new(off, 0, 0) * CFrame.new(rel.Position) * CFrame.Angles(0, -ang, 0) * rel.Rotation
			end
			push(p, base * cf)
		end
	end
	if #allParts > 0 then
		workspace:BulkMoveTo(allParts, allCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end)
