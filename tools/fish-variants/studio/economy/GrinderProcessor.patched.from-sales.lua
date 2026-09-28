-- GRINDER -> PIPE -> BLENDER -> CONVEYOR -> STACK
-- 1) Fish land in the grinder: it blends 4s (fast rollers + shake), then meat pops out of the pipe into the blender (Pit).
-- 2) In the blender the blade spins and knocks the meat around (it can't leave the bowl).
-- 3) After 5s in the blender each piece goes onto the conveyor, ONE at a time, rides slowly to the end,
--    and stacks up neatly in the box at the end.
--
-- [FishVariants patch v2] Changes marked "FishVariants": rare Silver/Gold fish.
-- The variant is rolled once when a fish is created and only copied after
-- that; the economy applies its extra value once, when the meat sells.
-- Needs ReplicatedStorage.FishVariants (+ FishVariantVisuals for effects);
-- without them this script behaves exactly like its base version.
--
-- [Economy patch v1] Changes vs. the live script are marked "Economy".
-- With ServerScriptService.EconomyService running, every meat piece gets a ledger
-- record (PieceId; owner and value fixed here) that is paid once when it sells.
-- Nothing is destroyed unpaid any more: when the pit or the stack is full, pieces
-- wait (in the blender queue, or as held ledger data) and come back out of the
-- pipe when there is room. Without EconomyService this runs exactly as before.
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local grinder = workspace:WaitForChild("FishGrinder")
local housing = grinder:WaitForChild("Housing")
local caught = workspace:WaitForChild("NetLift"):WaitForChild("FishCaught")
local meatTemplate = ServerStorage:WaitForChild("MeatTemplate")
local pitMeat = workspace:WaitForChild("PitMeat")
local pit = workspace:WaitForChild("Pit")

-- FishVariants: optional modules (missing -> base behaviour)
local Variants, VariantFx = nil, nil
do
	local rs = game:GetService("ReplicatedStorage")
	local function load(name)
		local mod = rs:FindFirstChild(name)
		if not (mod and mod:IsA("ModuleScript")) then return nil end
		local ok, result = pcall(require, mod)
		if not ok then
			warn("[FishVariants] " .. name .. " failed to load: " .. tostring(result))
			return nil
		end
		return result
	end
	Variants = load("FishVariants")
	if Variants then VariantFx = load("FishVariantVisuals") end
end

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
				warn("[GrinderProcessor] economy not running, original behaviour: " .. tostring(running))
			end
		else
			warn("[GrinderProcessor] could not load EconomyService, original behaviour: " .. tostring(api))
		end
	end
end

-- tuning
local GRIND_TIME = 4        -- seconds in the grinder
local GRIND_RPM = 170
local BLEND_TIME = 5        -- seconds each piece spends in the blender
local BLADE_SPEED = 2.5       -- radians / second
local BELT_SPEED = 2.5      -- studs / second (slow)
local BELT_GAP = 4          -- studs between pieces on the belt
local MAX_STACK = 96

local pipeExit = grinder:GetAttribute("PipeExit")
local center = pit:GetAttribute("BlenderCenter")
local radius = pit:GetAttribute("BlenderRadius")
local beltStart = pit:GetAttribute("BeltStart")
local beltEnd = pit:GetAttribute("BeltEnd")
local stackOrigin = pit:GetAttribute("StackOrigin")
local normalRPM = grinder:GetAttribute("RPM") or 18
local housingRest = housing:GetPivot()
local rng = Random.new()

local function meatFor(tier)
	tier = tier or 1
	if tier <= 5 then return 1 elseif tier <= 13 then return 2 elseif tier <= 18 then return 3 else return 5 end
end

-- small helper: animate a part along an arc
local function hop(part, from, to, height, dur, spin)
	local t = 0
	local r0 = part.CFrame.Rotation
	while t < dur do
		t += RunService.Heartbeat:Wait()
		local u = math.min(t / dur, 1)
		part.CFrame = CFrame.new(from:Lerp(to, u) + Vector3.new(0, height * 4 * u * (1 - u), 0)) * r0 * CFrame.Angles(0, u * (spin or 0), 0)
	end
end

------------------------------------------------------------------ BLADE
local blade = workspace:WaitForChild(pit:GetAttribute("BladeName") or "BladeCommon")
local bladeRest = blade:GetPivot()
local bladeAngle = 0
RunService.Heartbeat:Connect(function(dt)
	bladeAngle = (bladeAngle + dt * BLADE_SPEED) % (math.pi * 2)
	blade:PivotTo(bladeRest * CFrame.Angles(0, bladeAngle, 0))
end)

------------------------------------------------------------------ BLENDER SIM
local inBlender = {} -- meat -> state
local beltQueue = {}

local function addToBlender(meat)
	local rel = meat.Position - center
	inBlender[meat] = {
		r = math.clamp(Vector3.new(rel.X, 0, rel.Z).Magnitude, 0.8, radius),
		a = math.atan2(rel.Z, rel.X),
		vr = 0, y = 0, vy = 0,
		spinV = rng:NextNumber(-8, 8),
		rot = meat.CFrame.Rotation,
		nextHit = rng:NextNumber(0.2, 0.6),
		enter = os.clock(),
	}
end

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for meat, s in pairs(inBlender) do
		if not meat.Parent then inBlender[meat] = nil continue end
		-- swirl with the blade
		s.a += dt * BLADE_SPEED * 0.55
		-- blade whacks: random hop + push in/out
		s.nextHit -= dt
		if s.nextHit <= 0 then
			s.nextHit = rng:NextNumber(0.25, 0.7)
			s.vy = rng:NextNumber(5, 9)
			s.vr = rng:NextNumber(-6, 6)
			s.spinV = rng:NextNumber(-14, 14)
		end
		s.vy -= 40 * dt
		s.y = math.max(0, s.y + s.vy * dt)
		if s.y == 0 then s.vy = 0 end
		s.r += s.vr * dt
		s.vr *= (1 - math.min(1, dt * 3))
		-- keep it inside the bowl
		if s.r > radius then s.r = radius s.vr = -math.abs(s.vr) * 0.6 end
		if s.r < 0.7 then s.r = 0.7 s.vr = math.abs(s.vr) * 0.6 end
		s.rot = s.rot * CFrame.Angles(s.spinV * dt * 0.3, s.spinV * dt, 0)
		local flat = CFrame.Angles(0, select(2, s.rot:ToEulerAnglesYXZ()), 0)
		local tilt = s.y > 0.05 and s.rot or flat
		meat.CFrame = CFrame.new(center + Vector3.new(math.cos(s.a) * s.r, 0.14 + s.y, math.sin(s.a) * s.r)) * tilt
		-- done blending -> queue for the belt
		if now - s.enter >= BLEND_TIME and s.y == 0 and not s.queued then
			s.queued = true
			table.insert(beltQueue, meat)
		end
	end
end)

------------------------------------------------------------------ STACK
local stacked = {}
local function stackSlot(n)
	local layer = n // 8
	local i = n % 8
	return stackOrigin + Vector3.new((i % 4) * 1.75, layer * 0.3, (i // 4) * 2.9)
end

-- Economy: backpressure. A piece goes onto the belt only if the stack will
-- have room for it, and new pieces are shot into the pit only while the pit
-- has room; otherwise they wait (blender queue / held ledger data).
local onBelt = 0
local function stackHasRoom()
	if not Economy then return true end
	local stackFolder = workspace:FindFirstChild("MeatStack") or pitMeat
	return #stackFolder:GetChildren() + onBelt < MAX_STACK
end
local function pitHasRoom()
	local n = 0
	for _, m in ipairs(pitMeat:GetChildren()) do
		if m:GetAttribute("StackIndex") == nil then n += 1 end
	end
	return n < Economy.pipeline().MaxPitObjects
end

------------------------------------------------------------------ BELT (one at a time)
local beltLen = (beltEnd - beltStart).Magnitude
local beltDir = (beltEnd - beltStart).Unit
local lastOnBelt = nil -- {part, startT}

local function runBelt(meat)
	local s = inBlender[meat]
	inBlender[meat] = nil
	if not meat.Parent then return end
	-- flick out of the blender onto the start of the belt
	local flat = CFrame.lookAt(Vector3.zero, beltDir).Rotation
	meat.CFrame = CFrame.new(meat.Position) * flat
	hop(meat, meat.Position, beltStart, 2.5, 0.5, 0)
	local info = { part = meat, t0 = os.clock() }
	lastOnBelt = info
	-- ride the belt slowly
	local d = 0
	while d < beltLen do
		d = math.min(beltLen, d + BELT_SPEED * RunService.Heartbeat:Wait())
		meat.CFrame = CFrame.new(beltStart + beltDir * d) * flat
	end
	-- drop onto the stack (players pick from the top, so the next slot = current count)
	local stackFolder = workspace:FindFirstChild("MeatStack") or pitMeat
	local count = #stackFolder:GetChildren()
	if count >= MAX_STACK then
		-- Economy: never lose unpaid meat - keep the piece as held ledger data
		if Economy then Economy.hold(meat:GetAttribute("PieceId")) end
		meat:Destroy() -- stack is full
		return
	end
	local slot = stackSlot(count)
	meat:SetAttribute("StackIndex", count)
	meat.Parent = stackFolder
	hop(meat, meat.Position, slot, 2, 0.45, 0)
	if meat.Parent == stackFolder then
		meat.CFrame = CFrame.new(slot)
	end
end

task.spawn(function()
	while true do
		task.wait(0.1)
		local first = beltQueue[1]
		if first then
			-- only release when the belt is clear enough
			local clear = true
			if lastOnBelt and lastOnBelt.part.Parent then
				local traveled = (os.clock() - lastOnBelt.t0) * BELT_SPEED
				clear = traveled >= BELT_GAP
			end
			if clear and stackHasRoom() then -- Economy: wait while the stack is full
				table.remove(beltQueue, 1)
				lastOnBelt = { part = first, t0 = os.clock() + 0.5 } -- reserve while it hops on
				onBelt += 1
				task.spawn(function()
					local ok, err = pcall(runBelt, first)
					onBelt -= 1
					if not ok then warn("[GrinderProcessor] belt: " .. tostring(err)) end
				end)
			end
		end
	end
end)

------------------------------------------------------------------ GRINDER -> PIPE -> BLENDER
local function shootMeat(info, pieceId)
	local meat = meatTemplate:Clone()
	meat.Name = "Meat"
	meat:SetAttribute("FromFish", info.fishName)
	meat:SetAttribute("Tier", info.tier)
	if info.player then meat:SetAttribute("OwnerId", info.player.UserId) end
	if Economy and pieceId then Economy.stamp(meat, pieceId) end -- Economy: PieceId, owner, value, variant
	-- FishVariants: a small glow on rare meat (its value is in the ledger)
	if VariantFx and meat:GetAttribute("Variant") then pcall(VariantFx.applyToPart, meat, meat:GetAttribute("Variant")) end
	meat.CFrame = CFrame.new(pipeExit) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0)
	meat.Parent = pitMeat
	local ang = rng:NextNumber(0, math.pi * 2)
	local land = center + Vector3.new(math.cos(ang), 0, math.sin(ang)) * rng:NextNumber(1.5, radius - 0.3) + Vector3.new(0, 0.14, 0)
	hop(meat, pipeExit, land, 3, 0.55, 8)
	addToBlender(meat)
end

local pending = {}
local grinding = false
local function grind()
	grinding = true
	grinder:SetAttribute("RPM", GRIND_RPM)
	grinder:SetAttribute("Blending", true)
	local t = 0
	local conn = RunService.Heartbeat:Connect(function(dt)
		t += dt
		local amp = 0.12
		housing:PivotTo(housingRest * CFrame.new(
			math.noise(t * 25, 1) * amp, math.abs(math.noise(t * 30, 2)) * amp, math.noise(t * 25, 3) * amp
		) * CFrame.Angles(0, math.noise(t * 20, 4) * 0.02, math.noise(t * 20, 5) * 0.015))
	end)
	task.wait(GRIND_TIME)
	conn:Disconnect()
	housing:PivotTo(housingRest)
	grinder:SetAttribute("RPM", normalRPM)
	grinder:SetAttribute("Blending", false)
	local batch = pending
	pending = {}
	grinding = false
	for _, info in ipairs(batch) do
		if Economy then
			-- Economy: one ledger piece per meat piece (same count as meatFor);
			-- pieces the pit has no room for are held as data, not dropped
			for _, pieceId in ipairs(Economy.issueFish(info.player, info.fishName, info.tier, info.meta)) do
				if pitHasRoom() then
					task.spawn(shootMeat, info, pieceId)
					task.wait(0.22)
				else
					Economy.hold(pieceId)
				end
			end
		else
			for i = 1, meatFor(info.tier) do
				task.spawn(shootMeat, info)
				task.wait(0.22)
			end
		end
	end
	if #pending > 0 and not grinding then task.spawn(grind) end
end

caught.Event:Connect(function(player, fishName, tier, meta) -- Economy: meta = { OwnerId, Variant, Source }
	table.insert(pending, { player = player, fishName = fishName, tier = tier, meta = meta })
	if not grinding then task.spawn(grind) end
end)

-- Economy: held pieces (pit/stack was full, or a carrier left) come back out
-- of the pipe, oldest first, whenever the pit has room again.
if Economy then
	task.spawn(function()
		while true do
			task.wait(0.5)
			while pitHasRoom() do
				local piece = Economy.takeHeld()
				if not piece then break end
				task.spawn(shootMeat, { fishName = piece.fishName, tier = piece.tier }, piece.id)
				task.wait(0.22)
			end
		end
	end)
end
