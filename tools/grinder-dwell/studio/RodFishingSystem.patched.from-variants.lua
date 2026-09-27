-- Red button fishing: press the big red button -> every idle rod on the pads casts a line into the river,
-- waits a random time, then reels up a fish that spins on the line as a black silhouette,
-- cycling through different fish before the real one is revealed in full color.
-- The button stays locked until at least one rod has come back up.
--
-- [AquariumCycle patch v1] Changes vs. the original are marked "AquariumCycle".
-- When ServerScriptService.AquariumCycleServer is installed and enabled, rod
-- catches go into the aquarium instead of the grinder: a tank spot is reserved
-- for each rod before it casts, and rods with no free spot stay idle. If the
-- module is missing, disabled, or fails at any step, catches go to the grinder
-- exactly as before. The original source is backed up in
-- ServerStorage.AquariumCycleBackup by the installer.
--
-- [GrinderDwell patch v1] When a rod catch goes to the grinder (aquarium off
-- or refusing), the fish also rests on the rollers ~1 s, then spirals in and
-- shrinks, before FishCaught fires once. Aquarium routing is unchanged.

--
-- [FishVariants patch v1] Changes vs. the base are marked "FishVariants".
-- Rare Silver/Gold fish: the variant is rolled once when a fish is created
-- and carried unchanged to every meat piece and sale. Needs
-- ReplicatedStorage.FishVariants (and optionally FishVariantVisuals and
-- ServerScriptService.FishPayout); without them this script behaves exactly
-- like the base version. Nothing is paid unless FishPayout is connected.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local button = workspace:WaitForChild("BigButton")
local btnModel = button:WaitForChild("Button")
local fishModels = RS:WaitForChild("FishModels")
local swimTemplates = RS:WaitForChild("SwimTemplates")
local catches = workspace:WaitForChild("RodCatches")
local netLift = workspace:WaitForChild("NetLift")
local fishCaught = netLift:WaitForChild("FishCaught")
local grinderPos = workspace:WaitForChild("SwimmingFish"):GetAttribute("GrinderPos")

-- tuning
local WAIT_RANGE = { 3, 9 }   -- seconds a line sits in the water
local WATER_Y = 7.45
local CAST_DIST = 10          -- how far out the bobber lands
local HANG = 4                -- line length when the fish is shown
local FISH_SIZE = 3.2         -- longest side of the fish on the line
local SHOW_TIME = 2.5         -- how long the revealed fish hangs before going to the grinder

------------------------------------------------------------ rarity
local pool, total = {}, 0
for _, t in ipairs(swimTemplates:GetChildren()) do
	local w = t:GetAttribute("SpawnWeight") or 0
	if w > 0 and fishModels:FindFirstChild(t.Name) then total += w table.insert(pool, { name = t.Name, w = w }) end
end
local function pickFish()
	local r = math.random() * total
	for _, e in ipairs(pool) do r -= e.w if r <= 0 then return e.name end end
	return pool[1].name
end

------------------------------------------------------------ rods
local rods = {}
for _, m in ipairs(workspace:GetChildren()) do
	if m.Name == "FishingRod1" and m:IsA("Model") then
		-- tip = highest corner of the rod
		local best, bp, bpart = -math.huge, nil, nil
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then
				for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
					local c = p.CFrame * Vector3.new(sx * p.Size.X / 2, sy * p.Size.Y / 2, sz * p.Size.Z / 2)
					if c.Y > best then best, bp, bpart = c.Y, c, p end
				end end end
			end
		end
		local att = Instance.new("Attachment")
		att.Name = "LineTip"
		att.Parent = bpart
		att.WorldPosition = bp
		m:SetAttribute("RestPivot", m:GetPivot())
		table.insert(rods, { model = m, tip = bp, tipAtt = att, state = "idle" })
	end
end
table.sort(rods, function(a, b) return a.tip.Z < b.tip.Z end)

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

------------------------------------------------------------ aquarium (AquariumCycle)
local Aquarium = nil -- nil = original behaviour (every catch goes to the grinder)
do
	local keys = {}
	for i, rod in ipairs(rods) do
		rod.key = i
		table.insert(keys, i)
	end
	local mod = game:GetService("ServerScriptService"):FindFirstChild("AquariumCycleServer")
	if mod and mod:IsA("ModuleScript") then
		local ok, api = pcall(require, mod)
		if ok and type(api) == "table" then
			local ran, started, why = pcall(api.start, keys)
			if ran and started then
				Aquarium = api
			elseif not ran then
				warn("[RodFishingSystem] aquarium failed to start, using the grinder: " .. tostring(started))
			elseif why ~= "disabled" then
				warn("[RodFishingSystem] aquarium not started, using the grinder: " .. tostring(why))
			end
		else
			warn("[RodFishingSystem] could not load AquariumCycleServer, using the grinder: " .. tostring(api))
		end
	end
end

------------------------------------------------------------ button look / lock
local btnParts = {}
for _, p in ipairs(btnModel:GetDescendants()) do
	if p:IsA("BasePart") then btnParts[p] = { cf = p.CFrame, color = p.Color } end
end
local ready = true
local function setReady(v)
	ready = v
	button:SetAttribute("Ready", v)
	for p, d in pairs(btnParts) do
		p.Color = v and d.color or d.color:Lerp(Color3.new(0.25, 0.05, 0.05), 0.45)
	end
end
local function anyIdle()
	for _, r in ipairs(rods) do if r.state == "idle" then return true end end
	return false
end

------------------------------------------------------------ helpers
local function line(att0, att1)
	local b = Instance.new("Beam")
	b.Attachment0 = att0 b.Attachment1 = att1
	b.Width0 = 0.08 b.Width1 = 0.08
	b.FaceCamera = true
	b.Color = ColorSequence.new(Color3.fromRGB(245, 245, 245))
	b.Transparency = NumberSequence.new(0.1)
	b.CurveSize0 = 0 b.CurveSize1 = 0
	b.Segments = 12
	return b
end

local function makeBobber()
	local m = Instance.new("Model") m.Name = "Bobber"
	local red = Instance.new("Part")
	red.Name = "Red" red.Shape = Enum.PartType.Ball red.Size = Vector3.new(0.7, 0.7, 0.7)
	red.Color = Color3.fromRGB(235, 40, 40) red.Material = Enum.Material.SmoothPlastic
	red.Anchored = true red.CanCollide = false red.CanQuery = false red.CanTouch = false
	red.Parent = m
	local white = red:Clone() white.Name = "White" white.Size = Vector3.new(0.5, 0.5, 0.5) white.Color = Color3.new(1, 1, 1) white.Parent = m
	local att = Instance.new("Attachment") att.Name = "LineEnd" att.Position = Vector3.new(0, 0.35, 0) att.Parent = red
	m.PrimaryPart = red
	return m, att
end

local function setBobber(m, pos)
	m.Red.CFrame = CFrame.new(pos)
	m.White.CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0))
end

local function arc(from, to, dur, height, fn)
	local t = 0
	while t < dur do
		t += RunService.Heartbeat:Wait()
		local u = math.min(t / dur, 1)
		fn(from:Lerp(to, u) + Vector3.new(0, height * 4 * u * (1 - u), 0), u)
	end
end

-- a fish model ready to hang on the line (nose up), optionally blacked out
local function fishOnLine(name, black)
	local m = fishModels[name]:Clone()
	local _, size = m:GetBoundingBox()
	local k = FISH_SIZE / math.max(size.X, size.Y, size.Z)
	m:ScaleTo(m:GetScale() * k)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false d.CanQuery = false d.CanTouch = false
			if black then
				d.Color = Color3.fromRGB(12, 12, 16)
				d.Material = Enum.Material.SmoothPlastic
				d.MaterialVariant = ""
				d.Transparency = 0
			end
		elseif black and (d:IsA("Texture") or d:IsA("Decal")) then
			d:Destroy()
		end
	end
	if black then
		local hl = Instance.new("Highlight")
		hl.FillTransparency = 1
		hl.OutlineColor = Color3.new(1, 1, 1)
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = m
	end
	local _, s2 = m:GetBoundingBox()
	local att = Instance.new("Attachment") att.Name = "Mouth" att.Position = Vector3.new(0, 0, -s2.Z / 2) att.Parent = m.PrimaryPart
	return m, att, s2.Z
end

------------------------------------------------------------ one rod's catch
local function runRod(rod, player)
	rod.state = "busy"
	local tip = rod.tip
	local out = Vector3.new(1, 0, 0) -- the river is toward +X
	local landing = Vector3.new(tip.X, WATER_Y, tip.Z) + out * CAST_DIST + Vector3.new(0, 0, math.random(-15, 15) / 10)

	-- 1) cast
	local bob, bobAtt = makeBobber()
	rod.temp = { bob = bob } -- AquariumCycle: cleaned up if this task errors
	setBobber(bob, tip)
	bob.Parent = catches
	local beam = line(rod.tipAtt, bobAtt) beam.Parent = bob.Red
	arc(tip, landing, 0.55, 3, function(p) setBobber(bob, p) end)
	setBobber(bob, landing)
	bob:SetAttribute("BobBase", landing)
	bob:SetAttribute("Bob", true)

	-- 2) wait for a bite (a couple of little dips near the end)
	task.wait(math.random(WAIT_RANGE[1] * 10, WAIT_RANGE[2] * 10) / 10)
	bob:SetAttribute("Bite", true)
	task.wait(0.6)

	-- 3) reel it up slowly (clients move the fish + bend the rod)
	bob:SetAttribute("Bob", false)
	local hangTop = tip - Vector3.new(0, HANG, 0)
	local finalName = pickFish()
	-- FishVariants: roll once for this newly caught fish
	local variant = Variants and Variants.roll(math.random()) or nil
	-- AquariumCycle: put this fish in the spot reserved when the button was pressed
	local toTank = false
	if Aquarium then
		toTank = Aquarium.hook(rod.key, finalName, { Variant = variant }) -- FishVariants: variant rides along
		if not toTank then Aquarium.abort(rod.key) end
	end
	local REEL = 3.4
	local t0 = workspace:GetServerTimeNow()
	rod.model:SetAttribute("PullT0", t0)
	rod.model:SetAttribute("Pulling", true)

	-- 4) spin through black silhouettes of different fish, slowing down
	local shown, lastName
	local function show(name, black)
		if shown then shown:Destroy() end
		local m, mouth, len = fishOnLine(name, black)
		local top = hangTop - Vector3.new(0, len / 2, 0)
		local fromPos = landing + Vector3.new(0, len / 2 - 0.6, 0)
		local u = math.clamp((workspace:GetServerTimeNow() - t0) / REEL, 0, 1)
		m:PivotTo(CFrame.new(fromPos:Lerp(top, u)) * CFrame.Angles(math.rad(90), 0, 0))
		m:SetAttribute("From", fromPos)
		m:SetAttribute("To", top)
		m:SetAttribute("T0", t0)
		m:SetAttribute("Dur", REEL)
		m:SetAttribute("Spin", true)
		m.Parent = catches
		beam.Attachment1 = mouth
		shown = m
		rod.temp.shown = m -- AquariumCycle
	end
	bob.Red.Transparency = 1 bob.White.Transparency = 1
	local delay = 0.07
	for i = 1, 12 do
		local name
		repeat name = pool[math.random(1, #pool)].name until name ~= lastName or #pool < 2
		lastName = name
		show(name, true)
		task.wait(delay)
		delay *= 1.22
	end
	show(finalName, true)
	task.wait(math.max(0.45, REEL - (workspace:GetServerTimeNow() - t0)))
	rod.model:SetAttribute("Pulling", false)
	-- 5) reveal in full color with a little pop
	show(finalName, false)
	-- FishVariants: the glow appears only on the full-colour reveal, not the silhouettes
	if variant and VariantFx then pcall(VariantFx.applyToFish, shown, variant) end
	-- little extra yank up on the reveal
	do
		local now = workspace:GetServerTimeNow()
		local toPos = shown:GetAttribute("To")
		shown:SetAttribute("From", toPos)
		shown:SetAttribute("To", toPos + Vector3.new(0, 1.3, 0))
		shown:SetAttribute("T0", now)
		shown:SetAttribute("Dur", 0.3)
		rod.model:SetAttribute("PullT0", now)
		rod.model:SetAttribute("Pulling", true)
		task.delay(0.3, function() rod.model:SetAttribute("Pulling", false) end)
	end
	local base = shown:GetScale()
	for i = 1, 6 do
		shown:ScaleTo(base * (1 + math.sin(i / 6 * math.pi) * 0.25))
		RunService.Heartbeat:Wait()
	end
	shown:ScaleTo(base)
	task.wait(SHOW_TIME)

	-- 6) fling it into the aquarium (AquariumCycle), or into the grinder as before
	--    (it turns into meat like the net catches)
	shown:SetAttribute("Spin", false)
	beam:Destroy()
	local fish = shown
	local start = fish:GetPivot()
	local tankPos = toTank and Aquarium.active() and Aquarium.entryPoint()
	if tankPos then
		arc(start.Position, tankPos, Aquarium.toTankSeconds, Aquarium.toTankHeight, function(p, u)
			fish:PivotTo(CFrame.new(p) * start.Rotation * CFrame.Angles(u * 12, u * 8, 0))
		end)
		fish:Destroy()
		bob:Destroy()
		if not Aquarium.land(rod.key) then
			-- the aquarium was switched off mid-catch: the fish goes to the grinder instead
			local tpl = swimTemplates:FindFirstChild(finalName)
			fishCaught:Fire(player, finalName, tpl and tpl:GetAttribute("Tier") or 1, { Variant = variant, Source = "Rod" })
		end
	else
		if Aquarium then Aquarium.abort(rod.key) end
		arc(start.Position, grinderPos, 1.1, 10, function(p, u)
			fish:PivotTo(CFrame.new(p) * start.Rotation * CFrame.Angles(u * 12, u * 8, 0))
		end)
		-- GrinderDwell: rest and tumble on the rollers, then spiral in and shrink
		if Dwell and fish.Parent then
			local rot0 = start.Rotation * CFrame.Angles(12, 8, 0)
			local baseScale = fish:GetScale()
			local t = 0
			while t < Dwell.Dwell + Dwell.Drop and fish.Parent do
				t += RunService.Heartbeat:Wait()
				if t < Dwell.Dwell then
					local ox, oy, oz = Dwell.dwellOffset(t, rod.key)
					fish:PivotTo(CFrame.new(grinderPos + Vector3.new(ox, oy, oz)) * rot0 * CFrame.Angles(t * Dwell.TumbleSpeed, 0, 0))
				else
					local u = math.min(1, (t - Dwell.Dwell) / Dwell.Drop)
					local ox, oy, oz, scale = Dwell.dropOffset(u)
					fish:PivotTo(CFrame.new(grinderPos + Vector3.new(ox, oy, oz)) * rot0
						* CFrame.Angles(Dwell.Dwell * Dwell.TumbleSpeed, u * math.pi * 6, 0))
					fish:ScaleTo(baseScale * scale)
				end
			end
		end
		fish:Destroy()
		bob:Destroy()
		local tpl = swimTemplates:FindFirstChild(finalName)
		fishCaught:Fire(player, finalName, tpl and tpl:GetAttribute("Tier") or 1, { Variant = variant, Source = "Rod" })
	end

	rod.state = "idle"
end

-- AquariumCycle: a rod task that errors cleans up its bobber/fish, frees its
-- tank spot and goes back to idle instead of leaving the rod stuck busy
local function safeRunRod(rod, player)
	local ok, err = xpcall(runRod, debug.traceback, rod, player)
	if not ok then
		warn("[RodFishingSystem] rod catch failed: " .. tostring(err))
		for _, inst in pairs(rod.temp or {}) do
			if typeof(inst) == "Instance" and inst.Parent then inst:Destroy() end
		end
		rod.model:SetAttribute("Pulling", false)
	end
	rod.temp = nil
	if Aquarium then Aquarium.abort(rod.key) end -- no-op after a normal landing
	rod.state = "idle"
end

------------------------------------------------------------ pressing the button
local function press(player)
	if not ready then return end
	if not anyIdle() then return end
	local toCast = {}
	for _, rod in ipairs(rods) do
		if rod.state == "idle" then table.insert(toCast, rod) end
	end
	-- AquariumCycle: reserve a tank spot for each rod BEFORE any rod starts;
	-- rods beyond the free spots stay idle
	if Aquarium and Aquarium.active() then
		toCast = Aquarium.reserve(toCast, player)
		if #toCast == 0 then return end
	end
	setReady(false)
	for _, rod in ipairs(toCast) do rod.state = "busy" end
	local pending = 0
	for _, rod in ipairs(toCast) do
		pending += 1
		task.spawn(function()
			safeRunRod(rod, player)
			-- unlock as soon as any rod is back
			if not ready then setReady(true) end
		end)
		task.wait(0.12)
	end
end

-- clicks come from the client (it raycasts only against the button, so nothing can block it)
local PRESS_DELAY = 0.45   -- small pause after the click before the rods cast
local COOLDOWN = 0.6
local lastPress = {}
RS:WaitForChild("PressFishButton").OnServerEvent:Connect(function(player)
	local now = os.clock()
	if lastPress[player] and now - lastPress[player] < COOLDOWN then return end
	lastPress[player] = now
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or (hrp.Position - btnModel:GetPivot().Position).Magnitude > 80 then return end
	if not ready or not anyIdle() then return end
	-- AquariumCycle: with the tank full, tell the presser instead of casting
	if Aquarium and Aquarium.active() and not Aquarium.hasFreeSpot(player) then return end
	button:SetAttribute("PressedAt", workspace:GetServerTimeNow())
	task.delay(PRESS_DELAY, function() press(player) end)
end)
Players.PlayerRemoving:Connect(function(p) lastPress[p] = nil end)
setReady(true)
