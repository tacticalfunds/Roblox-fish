-- Harpoon gun: every few seconds it aims at a fish in the river (prefers better fish), fires the harpoon
-- on a rope, drags the fish back, then flings it into the grinder (it becomes meat like any other catch).
-- (Later this can be a Robux upgrade: just gate the loop below.)
--
-- [Economy patch v1] Changes vs. the live script are marked "Economy".
-- Targeting is effectively random (random score, slightly prefers closer fish);
-- it is NOT rarity-biased despite the note above. Each catch sends
-- { OwnerId, Variant, Source = "Harpoon" }: the owner is the fish's buyer if it
-- has one, else the player explicitly bound in HarpoonGun's OwnerUserId attribute,
-- else nobody (the meat sells but pays no one - never an arbitrary player).
-- Shots are skipped while EconomyService reports the meat pipeline saturated.
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")

local gunModel = workspace:WaitForChild("HarpoonGun")
local gun = gunModel:WaitForChild("Gun")
local harpoon = gun:WaitForChild("Harpoon")
local fishFolder = workspace:WaitForChild("SwimmingFish")
local fishCaught = workspace:WaitForChild("NetLift"):WaitForChild("FishCaught")

-- Economy: optional money service (missing or not running -> original behaviour)
local Economy = nil
do
	local mod = game:GetService("ServerScriptService"):FindFirstChild("EconomyService")
	if mod and mod:IsA("ModuleScript") then
		local ok, api = pcall(require, mod)
		if ok and type(api) == "table" then
			local ran, running = pcall(api.start)
			if ran and running then
				Economy = api
			else
				warn("[HarpoonSystem] economy not running, original behaviour: " .. tostring(running))
			end
		else
			warn("[HarpoonSystem] could not load EconomyService, original behaviour: " .. tostring(api))
		end
	end
end

-- Economy: who is paid for a harpooned fish (see header)
local function harpoonMeta(fish)
	local owner = fish:GetAttribute("OwnerId")
	if type(owner) ~= "number" then
		local bound = gunModel:GetAttribute("OwnerUserId")
		owner = if type(bound) == "number" then bound else nil
	end
	return { OwnerId = owner, Variant = fish:GetAttribute("Variant"), Source = "Harpoon" }
end

-- tuning
local FIRE_EVERY = { 2, 3.5 }  -- seconds between shots
local RANGE = 60
local AIM_TIME, FLY_TIME = 0.2, 0.25
local PULL, TOSS, SUCK = 0.6, 0.8, 0.45   -- must match FishSwimClient

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
-- GrinderDwell: the client rests a harpooned fish on the rollers first
local HARPOON_DWELL = if Dwell then Dwell.Dwell else 0
local surfaceY = fishFolder:GetAttribute("SurfaceY")

local pin = gun:WaitForChild("PivotPin").Position
local barrelDir = gun:WaitForChild("Barrel").CFrame.RightVector
if barrelDir.X > 0 then barrelDir = -barrelDir end -- barrel points toward the river (-X)
local restAim = CFrame.lookAt(pin, pin + barrelDir)
local gunRest = gun:GetPivot()
local gunRel = restAim:ToObjectSpace(gunRest)
local muzzleAtt = gun:WaitForChild("MuzzleRing"):WaitForChild("Muzzle")
local ropeAtt = harpoon:WaitForChild("Shaft"):WaitForChild("RopeAttach")
local nose = harpoon:WaitForChild("TipPoint")

local function aimAt(target)
	gun:PivotTo(CFrame.lookAt(pin, target) * gunRel)
end
local currentAim = pin + barrelDir * 10
local function turnTo(target, dur)
	local from = currentAim
	local t = 0
	while t < dur do
		t += RunService.Heartbeat:Wait()
		local u = math.min(t / dur, 1)
		u = u * u * (3 - 2 * u)
		aimAt(from:Lerp(target, u))
	end
	currentAim = target
end

local function fishPos(m, t)
	local seed = m:GetAttribute("Seed") or 1
	local weaveA, weaveF, phase = 0.8 + (seed % 7) * 0.15, 0.35 + (seed % 5) * 0.08, seed * 1.7
	local z = m:GetAttribute("StartZ") + m:GetAttribute("Speed") * (t - m:GetAttribute("SpawnT"))
	local x = m:GetAttribute("LaneX") + weaveA * math.sin(weaveF * t + phase)
	return Vector3.new(x, surfaceY - 0.6, z)
end

local function pickTarget()
	local now = workspace:GetServerTimeNow()
	local tHit = now + AIM_TIME + FLY_TIME
	local best, bestScore, bestPos
	for _, m in ipairs(fishFolder:GetChildren()) do
		if m:GetAttribute("SpawnT") and not m:GetAttribute("CaughtT") and not m:GetAttribute("HarpoonT") then
			local p = fishPos(m, tHit)
			local d = (p - pin).Magnitude
			if d <= RANGE and p.Z > fishFolder:GetAttribute("MinZ") + 4 and p.Z < fishFolder:GetAttribute("MaxZ") - 4 then
				local score = math.random() * 10 - d * 0.05 -- any fish, slightly prefers closer ones
				if not best or score > bestScore then best, bestScore, bestPos = m, score, p end
			end
		end
	end
	return best, bestPos, tHit
end

-- harpoon parts relative to its nose, so we can fly it around and put it back
local function harpoonParts()
	local list = {}
	for _, p in ipairs(harpoon:GetDescendants()) do if p:IsA("BasePart") then table.insert(list, p) end end
	return list
end
local hParts = harpoonParts()

local function fire()
	local fish, hit, tHit = pickTarget()
	if not fish then return end
	-- aim
	turnTo(hit, AIM_TIME)
	-- snapshot the loaded harpoon
	local aimDir = (hit - nose.Position).Unit
	local frame0 = CFrame.lookAt(nose.Position, nose.Position + aimDir)
	local rel = {}
	for _, p in ipairs(hParts) do rel[p] = frame0:ToObjectSpace(p.CFrame) end
	local function placeHarpoon(noseFrame)
		for _, p in ipairs(hParts) do p.CFrame = noseFrame * rel[p] end
	end
	-- rope
	local rope = Instance.new("Beam")
	rope.Attachment0 = muzzleAtt rope.Attachment1 = ropeAtt
	rope.Width0 = 0.12 rope.Width1 = 0.12
	rope.Color = ColorSequence.new(Color3.fromRGB(235, 225, 200))
	rope.FaceCamera = true rope.Segments = 10 rope.CurveSize0 = 0.6 rope.CurveSize1 = -0.6
	rope.Parent = gun
	-- fly
	local start = frame0.Position
	local t = 0
	while t < FLY_TIME do
		t += RunService.Heartbeat:Wait()
		local u = math.min(t / FLY_TIME, 1)
		local p = start:Lerp(hit, u) + Vector3.new(0, math.sin(u * math.pi) * 0.8, 0)
		placeHarpoon(CFrame.lookAt(p, p + aimDir))
	end
	-- hit! the client drags the fish back along the rope and tosses it into the grinder
	if fish.Parent then
		local back = muzzleAtt.WorldPosition + aimDir * 1.5
		fish:SetAttribute("HarpoonHit", hit)
		fish:SetAttribute("HarpoonBack", back)
		fish:SetAttribute("HarpoonT", workspace:GetServerTimeNow())
		-- reel the harpoon (with the fish) back in
		t = 0
		while t < PULL do
			t += RunService.Heartbeat:Wait()
			local u = math.min(t / PULL, 1)
			u = u * u * (3 - 2 * u)
			local p = hit:Lerp(back, u) + Vector3.new(0, math.sin(u * math.pi) * 2, 0)
			placeHarpoon(CFrame.lookAt(p, p + aimDir))
		end
		task.delay(TOSS + HARPOON_DWELL + SUCK, function() -- GrinderDwell
			fishCaught:Fire(nil, fish.Name, fish:GetAttribute("Tier") or 1, harpoonMeta(fish)) -- Economy: owner payload
			if fish.Parent then fish:Destroy() end
		end)
	end
	rope:Destroy()
	placeHarpoon(frame0) -- harpoon back in the barrel
	task.wait(0.1)
	turnTo(pin + barrelDir * 10, 0.25)
end

task.wait(5)
while true do
	task.wait(math.random(FIRE_EVERY[1] * 10, FIRE_EVERY[2] * 10) / 10)
	if Economy and Economy.saturated() then continue end -- Economy: grinder backed up, skip this shot
	local ok, err = pcall(fire)
	if not ok then warn("Harpoon: " .. tostring(err)) end
end
