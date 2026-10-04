-- RECONSTRUCTED (tools/economy/build/make_box.py): the live BoxMeat pickup as
-- described, not the exact live text. No installer targets this file.
-- Delivery trucks: a line of trucks comes out of Cave1, waits at the U-turn next to the dock,
-- players carry meat from the stack at the end of the conveyor and drop it in the front truck's bucket.
-- When a truck has all the meat it needs it drives around the U-turn into Cave2 and the line moves up.
-- (Trucks are drawn/moved on each client by TruckClient using the "S" attribute; server keeps the logic.)
--
-- [Economy patch v1] Changes vs. the live script are marked "Economy".
-- Players carry the ledger ids of the meat they pick up. Dropping a piece in a
-- truck is that piece's one sale (paid to the piece's owner, not the carrier).
-- If a carrier leaves or respawns, their pieces are held and come back out of
-- the grinder pipe instead of vanishing unpaid. Truck UI is unchanged.
--
-- [MeatGlow patch] Changes marked "MeatGlow": Silver / Gold meat keeps its
-- glow when it is carried, laid out or loaded (display only; the value is in
-- the ledger). Needs ReplicatedStorage.FishVariantVisuals; without it this
-- script behaves exactly like its base version.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")

local Path = require(RS:WaitForChild("TruckPath"))
local truckTypes = SS:WaitForChild("TruckTypes") -- each has Weight / NeedMin / NeedMax attributes
local meatTemplate = SS:WaitForChild("MeatTemplate")
local trucksFolder = workspace:WaitForChild("Trucks")
local meatStack = workspace:WaitForChild("MeatStack")
local events = SS:WaitForChild("TruckEvents")

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
				warn("[TruckSystem] economy not running, original behaviour: " .. tostring(running))
			end
		else
			warn("[TruckSystem] could not load EconomyService, original behaviour: " .. tostring(api))
		end
	end
end

-- MeatGlow: optional effects module (missing -> no glow, base behaviour)
local VariantFx = nil
do
	local mod = game:GetService("ReplicatedStorage"):FindFirstChild("FishVariantVisuals")
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			VariantFx = result
		else
			warn("[MeatGlow] FishVariantVisuals failed to load: " .. tostring(result))
		end
	end
end
local function glow(part, variant)
	if VariantFx and variant then pcall(VariantFx.applyToPart, part, variant) end
end

-- tuning
local MAX_TRUCKS = 5
local TRUCK_DELAY = { 6, 14 } -- seconds between new trucks pulling in
local nextTruckAt = 0
local NEED_MIN, NEED_MAX = 2, 5
local DRIVE_SPEED = 12
local MAX_CARRY = 10
local TRANSFER_EVERY = 0.15
local STACK_CENTER = Vector3.new(-78.4, 10.05, 160)
local STACK_HALF = Vector3.new(6.3, 0, 5.5)   -- pickup area around the end box
local BOX_CENTER = Vector3.new(-37, 10.05, 148.7)
local BOX_HALF = Vector3.new(6, 0, 5)
local boxMeat = workspace:FindFirstChild("BoxMeat") or workspace:WaitForChild("BoxMeat")
local DELIVER_RANGE = 9

local function pickType()
	local list, total = truckTypes:GetChildren(), 0
	for _, t in ipairs(list) do total += t:GetAttribute("Weight") or 1 end
	local r = Random.new():NextNumber(0, total)
	for _, t in ipairs(list) do
		r -= t:GetAttribute("Weight") or 1
		if r <= 0 then return t end
	end
	return list[1]
end
local rng = Random.new()
local queue = {}      -- waiting / loading trucks, front first
local departing = {}

------------------------------------------------------------ GUI
local MEAT_IMAGE = "rbxassetid://128058252479007"
local DOTS = 16
local FILLED, EMPTY = Color3.fromRGB(90, 225, 80), Color3.fromRGB(205, 210, 220)

-- cartoon order bubble: white disc, progress dots around the edge, meat picture, green count badge
local function makeGui(truck)
	local floor = truck:FindFirstChild("TubInnerFloor") or truck.PrimaryPart
	local bb = Instance.new("BillboardGui")
	bb.Name = "NeedGui"
	bb.Size = UDim2.fromScale(4.2, 4.2)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 6.2, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 150
	bb.Parent = floor

	local shadow = Instance.new("Frame")
	shadow.Size = UDim2.fromScale(0.9, 0.9)
	shadow.Position = UDim2.fromScale(0.08, 0.1)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.7
	shadow.Parent = bb
	Instance.new("UICorner", shadow).CornerRadius = UDim.new(1, 0)

	local circle = Instance.new("Frame")
	circle.Name = "Circle"
	circle.Size = UDim2.fromScale(0.9, 0.9)
	circle.Position = UDim2.fromScale(0.05, 0.05)
	circle.BackgroundColor3 = Color3.new(1, 1, 1)
	circle.Parent = bb
	Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)
	local grad = Instance.new("UIGradient", circle)
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(215, 232, 255))
	local stroke = Instance.new("UIStroke", circle)
	stroke.Color = Color3.fromRGB(20, 20, 25)
	stroke.Thickness = 4

	local dots = {}
	for i = 1, DOTS do
		local a = (i - 1) / DOTS * math.pi * 2 - math.pi / 2
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromScale(0.1, 0.1)
		d.Position = UDim2.fromScale(0.5 + math.cos(a) * 0.4, 0.5 + math.sin(a) * 0.4)
		d.BackgroundColor3 = EMPTY
		d.Parent = circle
		Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)
		local ds = Instance.new("UIStroke", d)
		ds.Color = Color3.fromRGB(20, 20, 25)
		ds.Thickness = 1.5
		dots[i] = d
	end

	local meat = Instance.new("ImageLabel")
	meat.Name = "Meat"
	meat.AnchorPoint = Vector2.new(0.5, 0.5)
	meat.Position = UDim2.fromScale(0.5, 0.48)
	meat.Size = UDim2.fromScale(0.58, 0.58)
	meat.BackgroundTransparency = 1
	meat.Image = MEAT_IMAGE
	meat.ScaleType = Enum.ScaleType.Fit
	meat.Parent = circle

	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Size = UDim2.fromScale(0.44, 0.44)
	badge.Position = UDim2.fromScale(0.62, 0.62)
	badge.BackgroundColor3 = Color3.new(1, 1, 1)
	badge.Parent = bb
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
	local bg = Instance.new("UIGradient", badge)
	bg.Rotation = 90
	bg.Color = ColorSequence.new(Color3.fromRGB(150, 255, 90), Color3.fromRGB(40, 185, 50))
	local bs = Instance.new("UIStroke", badge)
	bs.Color = Color3.fromRGB(20, 20, 25)
	bs.Thickness = 3.5
	local num = Instance.new("TextLabel")
	num.Name = "Num"
	num.Size = UDim2.fromScale(0.8, 0.8)
	num.Position = UDim2.fromScale(0.1, 0.08)
	num.BackgroundTransparency = 1
	num.Font = Enum.Font.FredokaOne
	num.TextScaled = true
	num.TextColor3 = Color3.new(1, 1, 1)
	num.Parent = badge
	local ns = Instance.new("UIStroke", num)
	ns.Color = Color3.fromRGB(20, 20, 25)
	ns.Thickness = 2.5

	local function setProgress(frac)
		local n = math.floor(frac * DOTS + 0.5)
		for i, d in ipairs(dots) do d.BackgroundColor3 = i <= n and FILLED or EMPTY end
	end
	setProgress(0)
	return num, setProgress
end

------------------------------------------------------------ TRUCKS
local function spawnTruck()
	local tpl = pickType()
	local m = tpl:Clone()
	local need = rng:NextInteger(tpl:GetAttribute("NeedMin") or NEED_MIN, tpl:GetAttribute("NeedMax") or NEED_MAX)
	m:SetAttribute("Need", need)
	m:SetAttribute("Loaded", 0)
	m:SetAttribute("S", 0)
	m:PivotTo(Path.truckCF(0))
	local t = { model = m, s = 0, need = need, loaded = 0, lastSent = -1, bucketOffset = tpl:GetAttribute("BucketOffset") }
	t.num, t.setProgress = makeGui(m)
	t.num.Text = tostring(need)
	m.Parent = trucksFolder
	table.insert(queue, t)
end

local function depart(t)
	local gui = t.model:FindFirstChild("NeedGui", true)
	if gui then gui:Destroy() end
	for i, q in ipairs(queue) do if q == t then table.remove(queue, i) break end end
	table.insert(departing, t)
end

local function step(t, target, dt)
	local d = target - t.s
	if math.abs(d) < 0.01 then t.s = target return end
	local v = math.min(DRIVE_SPEED, math.abs(d) * 2.5 + 0.5)
	t.s += math.sign(d) * math.min(math.abs(d), v * dt)
end

local sendClock = 0
RunService.Heartbeat:Connect(function(dt)
	for i, t in ipairs(queue) do
		step(t, Path.slot(i), dt)
	end
	for i = #departing, 1, -1 do
		local t = departing[i]
		step(t, Path.TOTAL, dt)
		if t.s >= Path.TOTAL - 0.05 then
			t.model:Destroy()
			table.remove(departing, i)
		end
	end
	sendClock += dt
	if sendClock >= 0.066 then
		sendClock = 0
		for _, list in ipairs({ queue, departing }) do
			for _, t in ipairs(list) do
				if t.s ~= t.lastSent then
					t.lastSent = t.s
					t.model:SetAttribute("S", t.s)
				end
			end
		end
	end
	-- keep the line full
	local last = queue[#queue]
	-- cars only come once someone has bought Car Sales; Max Line + Car Speed upgrades
	local maxQ = workspace:GetAttribute("CarsMaxQueue") or MAX_TRUCKS
	if workspace:GetAttribute("CarsUnlocked") and #queue + #departing < maxQ + 2 and #queue < maxQ and (not last or last.s >= Path.SPACING) and os.clock() >= nextTruckAt then
		spawnTruck()
		local gap = workspace:GetAttribute("CarsGapSeconds")
		if gap then
			nextTruckAt = os.clock() + gap * rng:NextNumber(0.85, 1.15)
		else
			nextTruckAt = os.clock() + rng:NextNumber(TRUCK_DELAY[1], TRUCK_DELAY[2])
		end
	end
end)

------------------------------------------------------------ CARRYING
local carry = {} -- player -> {count, parts, ids}

-- Economy: ledger ids of the meat a player carries (false = untracked piece).
-- A carrier who leaves or respawns gives them back as held pieces.
local function dropCarried(c)
	if Economy and c and c.ids then
		for _, id in ipairs(c.ids) do
			if id then Economy.hold(id) end
		end
		table.clear(c.ids)
	end
end

local function carryVisual(player)
	local c = carry[player]
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local folder = char:FindFirstChild("CarriedMeat")
	if not folder then folder = Instance.new("Folder") folder.Name = "CarriedMeat" folder.Parent = char end
	while #c.parts < c.count do
		local p = meatTemplate:Clone()
		p.Anchored = false
		p.Massless = true
		p.CanCollide = false
		local i = #c.parts
		glow(p, c.glow and c.glow[i + 1]) -- MeatGlow
		p.CFrame = hrp.CFrame * CFrame.new(0, 0.1 + i * 0.3, -1.7) * CFrame.Angles(0, math.rad(90), 0)
		local w = Instance.new("WeldConstraint")
		w.Part0 = hrp w.Part1 = p w.Parent = p
		p.Parent = folder
		table.insert(c.parts, p)
	end
	while #c.parts > c.count do
		table.remove(c.parts):Destroy()
	end
	player:SetAttribute("CarryMeat", c.count)
end

local function flyPart(from, to, height, dur, variant) -- MeatGlow: variant
	local p = meatTemplate:Clone()
	glow(p, variant) -- MeatGlow
	p.CFrame = CFrame.new(from)
	p.Parent = workspace
	task.spawn(function()
		local t = 0
		while t < dur do
			t += RunService.Heartbeat:Wait()
			local u = math.min(t / dur, 1)
			p.CFrame = CFrame.new(from:Lerp(to, u) + Vector3.new(0, height * 4 * u * (1 - u), 0)) * CFrame.Angles(0, u * 6, 0)
		end
		p:Destroy()
	end)
	return dur
end

local function topOfStack(folder)
	local best, bi = nil, -1
	for _, m in ipairs((folder or meatStack):GetChildren()) do
		local i = m:GetAttribute("StackIndex") or 0
		if i > bi then best, bi = m, i end
	end
	return best
end

local function addMeatToTruck(t, n, variant) -- n = 0-based slot; MeatGlow: variant
	local layer = n // 4
	local i = n % 4
	local off = t.bucketOffset + Vector3.new((i % 2 - 0.5) * 1.6, 0.16 + layer * 0.3, (i // 2 - 0.5) * 1.9)
	local p = meatTemplate:Clone()
	p.Name = "LoadedMeat"
	glow(p, variant) -- MeatGlow
	-- server-side the truck stays at its spawn pose; the client moves everything together
	p.CFrame = Path.truckCF(0) * CFrame.new(off) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0)
	p.Parent = t.model
end

local timers = {}
task.spawn(function()
	while true do
		task.wait(TRANSFER_EVERY)
		local front = queue[1]
		local loading = front and math.abs(front.s - Path.LOAD_S) < 0.3 and front.loaded < front.need
		local bucketPos = front and (Path.truckCF(Path.LOAD_S) * CFrame.new(front.bucketOffset)).Position
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not hrp or not hum or hum.Health <= 0 then continue end
			carry[player] = carry[player] or { count = 0, parts = {}, ids = {} }
			local c = carry[player]
			local pos = hrp.Position
			local rel = pos - STACK_CENTER
			-- pick up from the stack, or from the meat box
			local src = nil
			if math.abs(rel.X) <= STACK_HALF.X and math.abs(rel.Z) <= STACK_HALF.Z and math.abs(rel.Y) < 8 then
				src = meatStack
			else
				local relBox = pos - BOX_CENTER
				if math.abs(relBox.X) <= BOX_HALF.X and math.abs(relBox.Z) <= BOX_HALF.Z and math.abs(relBox.Y) < 8 then
					src = boxMeat
				end
			end
			if src and c.count < MAX_CARRY then
				local meat = topOfStack(src)
				if meat then
					local from = meat.Position
					local pieceId = meat:GetAttribute("PieceId") -- Economy
					local variant = meat:GetAttribute("Variant") -- MeatGlow
					meat:Destroy()
					if Economy then
						table.insert(c.ids, if pieceId and Economy.carry(pieceId) then pieceId else false)
					end
					flyPart(from, pos + Vector3.new(0, 0.5 + c.count * 0.3, 0), 2, 0.2, variant)
					c.count += 1
					c.glow = c.glow or {} -- MeatGlow
					c.glow[c.count] = variant or false
					carryVisual(player)
				end
			-- drop into the front truck
			elseif loading and c.count > 0 then
				local d = Vector3.new(pos.X - bucketPos.X, 0, pos.Z - bucketPos.Z).Magnitude
				if d <= DELIVER_RANGE then
					c.count -= 1
					local variant = c.glow and c.glow[c.count + 1] -- MeatGlow: the top piece
					if Economy then Economy.settle(table.remove(c.ids), "Truck") end -- Economy: the one sale
					carryVisual(player)
					local truck = front
					local slotLoaded = truck.loaded
					truck.loaded += 1
					truck.model:SetAttribute("Loaded", truck.loaded)
					truck.num.Text = tostring(truck.need - truck.loaded)
					if truck.setProgress then truck.setProgress(truck.loaded / truck.need) end
					events.MeatDelivered:Fire(player, truck.model)
					local dur = flyPart(pos + Vector3.new(0, 1.5, 0), bucketPos + Vector3.new(0, 0.5, 0), 4, 0.35, variant)
					task.delay(dur, function()
						if truck.model.Parent then addMeatToTruck(truck, slotLoaded, variant) end
					end)
					if truck.loaded >= truck.need then
						events.TruckFilled:Fire(player, truck.need)
						loading = false
						task.delay(0.8, function() depart(truck) end)
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p) dropCarried(carry[p]) carry[p] = nil end)
-- Economy: loading EconomyService (top of this script) can yield, so players
-- may already be in the server here; bind every player exactly once.
local bound = {}
local function bindPlayer(p)
	if bound[p] then return end
	bound[p] = true
	p.CharacterAdded:Connect(function()
		dropCarried(carry[p]) -- Economy: a respawned carrier's pieces are held, not lost
		carry[p] = { count = 0, parts = {}, ids = {} }
		p:SetAttribute("CarryMeat", 0)
	end)
end
Players.PlayerAdded:Connect(bindPlayer)
for _, p in ipairs(Players:GetPlayers()) do bindPlayer(p) end
Players.PlayerRemoving:Connect(function(p) bound[p] = nil end)

