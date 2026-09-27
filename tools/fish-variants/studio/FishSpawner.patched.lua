-- Spawns a steady stream of fish that all swim the same way up the river (toward +Z).
-- Rarity: each template in ReplicatedStorage.SwimTemplates has a SpawnWeight attribute (edit to tune odds).
-- Movement is animated on clients (FishSwimClient) from these attributes:
--   SpawnT, StartZ, Speed, LaneX, Seed   -> z = StartZ + Speed * (serverTime - SpawnT)

--
-- [FishVariants patch v1] Changes vs. the base are marked "FishVariants".
-- Rare Silver/Gold fish: the variant is rolled once when a fish is created
-- and carried unchanged to every meat piece and sale. Needs
-- ReplicatedStorage.FishVariants (and optionally FishVariantVisuals and
-- ServerScriptService.FishPayout); without them this script behaves exactly
-- like the base version. Nothing is paid unless FishPayout is connected.
local RS = game:GetService("ReplicatedStorage")
local templates = RS:WaitForChild("SwimTemplates")
local folder = workspace:WaitForChild("SwimmingFish")

local SPAWN_EVERY = { 0.35, 0.7 } -- seconds between spawns (random in range)
local MAX_FISH = 60
local SPEED = { 4, 6.5 }         -- studs per second

local minX, maxX = folder:GetAttribute("MinX"), folder:GetAttribute("MaxX")
local minZ, maxZ = folder:GetAttribute("MinZ"), folder:GetAttribute("MaxZ")
local surfaceY = folder:GetAttribute("SurfaceY")
local rng = Random.new()

-- FishVariants: optional modules (missing -> base behaviour)
local Variants, VariantFx = nil, nil
do
	local rs = game:GetService("ReplicatedStorage")
	local function load(parent, name)
		local mod = parent:FindFirstChild(name)
		if not (mod and mod:IsA("ModuleScript")) then return nil end
		local ok, result = pcall(require, mod)
		if not ok then
			warn("[FishVariants] " .. name .. " failed to load: " .. tostring(result))
			return nil
		end
		return result
	end
	Variants = load(rs, "FishVariants")
	if Variants then
		VariantFx = load(rs, "FishVariantVisuals")
	end
end

local pool, total = {}, 0
for _, t in ipairs(templates:GetChildren()) do
	local w = t:GetAttribute("SpawnWeight") or 0
	if w > 0 then
		total += w
		table.insert(pool, { t = t, w = w })
	end
end

-- cap how many "good" fish can be in the river at once
local LIMITS = {
	{ minTier = 10, max = 3 }, -- Salmon and up: at most 3 at a time
	{ minTier = 16, max = 1 }, -- Golden Koi and up: only 1 at a time
}
local function countTier(minTier)
	local n = 0
	for _, m in ipairs(folder:GetChildren()) do
		if (m:GetAttribute("Tier") or 1) >= minTier and not m:GetAttribute("CaughtT") then n += 1 end
	end
	return n
end
local function allowed(t)
	local tier = t:GetAttribute("Tier") or 1
	for _, l in ipairs(LIMITS) do
		if tier >= l.minTier and countTier(l.minTier) >= l.max then return false end
	end
	return true
end
local function pickRaw()
	local r = rng:NextNumber(0, total)
	for _, e in ipairs(pool) do
		r -= e.w
		if r <= 0 then return e.t end
	end
	return pool[1].t
end
local function pick()
	for _ = 1, 10 do
		local t = pickRaw()
		if allowed(t) then return t end
	end
	-- fall back to the most common fish
	local best = pool[1]
	for _, e in ipairs(pool) do if e.w > best.w then best = e end end
	return best.t
end

local seed = 0
local function spawnFish()
	local tpl = pick()
	local m = tpl:Clone()
	local L = m:GetAttribute("SwimLen") or 4
	local half = (maxX - minX) / 2 - L * 0.3 - 1.5
	local cx = (minX + maxX) / 2
	local startZ = minZ + L / 2
	local endZ = maxZ - L / 2
	local speed = rng:NextNumber(SPEED[1], SPEED[2])
	local laneX = cx + rng:NextNumber(-half, half)
	seed += 1
	m:SetAttribute("SpawnT", workspace:GetServerTimeNow())
	m:SetAttribute("StartZ", startZ)
	m:SetAttribute("Speed", speed)
	m:SetAttribute("LaneX", laneX)
	m:SetAttribute("Seed", seed)
	m:PivotTo(CFrame.lookAt(Vector3.new(laneX, surfaceY - 0.6, startZ), Vector3.new(laneX, surfaceY - 0.6, startZ + 1)))
	-- FishVariants: roll once for this new fish, before parenting
	if Variants then
		local variant = Variants.roll(rng:NextNumber())
		if variant then
			m:SetAttribute("Variant", variant)
			if VariantFx then pcall(VariantFx.applyToFish, m, variant) end
		end
	end
	m.Parent = folder
	task.delay((endZ - startZ) / speed, function()
		if m.Parent and not m:GetAttribute("CaughtT") then m:Destroy() end
	end)
end

-- pre-fill the river so it isn't empty at server start
local now = workspace:GetServerTimeNow()
for i = 1, 35 do
	spawnFish()
	local last = folder:GetChildren()[#folder:GetChildren()]
end
for _, m in ipairs(folder:GetChildren()) do
	local sp = m:GetAttribute("Speed")
	local travel = ((maxZ - 2) - m:GetAttribute("StartZ")) / sp
	local age = rng:NextNumber(0, travel * 0.95)
	m:SetAttribute("SpawnT", now - age)
	task.delay(travel - age, function() if m.Parent and not m:GetAttribute("CaughtT") then m:Destroy() end end)
end

while true do
	task.wait(rng:NextNumber(SPAWN_EVERY[1], SPAWN_EVERY[2]))
	if #folder:GetChildren() < MAX_FISH then
		spawnFish()
	end
end
