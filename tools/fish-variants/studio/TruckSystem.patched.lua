-- Delivery trucks: a line of trucks comes out of Cave1, waits at the U-turn next to the dock,
-- players carry meat from the stack at the end of the conveyor and drop it in the front truck's bucket.
-- When a truck has all the meat it needs it drives around the U-turn into Cave2 and the line moves up.
-- (Trucks are drawn/moved on each client by TruckClient using the "S" attribute; server keeps the logic.)

--
-- [FishVariants patch v1] Changes vs. the base are marked "FishVariants".
-- Rare Silver/Gold fish: the variant is rolled once when a fish is created
-- and carried unchanged to every meat piece and sale. Needs
-- ReplicatedStorage.FishVariants (and optionally FishVariantVisuals and
-- ServerScriptService.FishPayout); without them this script behaves exactly
-- like the base version. Nothing is paid unless FishPayout is connected.
-- Carried meat now keeps each piece's identity (items list alongside count),
-- so a delivery knows its tier/owner/variant. MeatDelivered gains an optional
-- 3rd argument with that sale info.
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

-- FishVariants: optional modules (missing -> base behaviour)
local Variants, VariantFx, Payout = nil, nil, nil
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
		local p = load(game:GetService("ServerScriptService"), "FishPayout")
		if type(p) == "table" and type(p.onSale) == "function" then Payout = p end
	end
end

-- FishVariants: hand one sale to the payout adapter (exactly once per piece)
local function paySale(info)
	if not Payout then return end
	local ok, err = pcall(Payout.onSale, info)
	if not ok then warn("[FishVariants] FishPayout.onSale failed: " .. tostring(err)) end
end
-- sale metadata read from a meat part BEFORE it is destroyed
local function saleInfoOf(meat, kind)
	if Variants then
		return Variants.saleInfo(function(k) return meat:GetAttribute(k) end, kind)
	end
	return { kind = kind, tier = meat:GetAttribute("Tier"), multiplier = 1 }
end
local queue = {}      -- waiting / loading trucks, front first
local departing = {}

------------------------------------------------------------ GUI
local function makeGui(truck)
	local floor = truck:FindFirstChild("TubInnerFloor") or truck.PrimaryPart
	local bb = Instance.new("BillboardGui")
	bb.Name = "NeedGui"
	bb.Size = UDim2.fromScale(3.6, 3.6)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 150
	bb.Parent = floor

	local circle = Instance.new("Frame")
	circle.Size = UDim2.fromScale(1, 1)
	circle.BackgroundColor3 = Color3.new(1, 1, 1)
	circle.Parent = bb
	Instance.new("UICorner", circle).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke", circle)
	stroke.Color = Color3.fromRGB(70, 200, 70)
	stroke.Thickness = 5

	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(0.8, 0.8)
	vp.Position = UDim2.fromScale(0.1, 0.08)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(200, 200, 200)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.Parent = circle
	local icon = meatTemplate:Clone()
	icon.CFrame = CFrame.Angles(math.rad(55), math.rad(20), 0)
	icon.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 0, 6.2), Vector3.zero)
	cam.Parent = vp
	vp.CurrentCamera = cam

	local badge = Instance.new("Frame")
	badge.Size = UDim2.fromScale(0.46, 0.46)
	badge.Position = UDim2.fromScale(0.62, 0.62)
	badge.BackgroundColor3 = Color3.fromRGB(70, 200, 70)
	badge.Parent = circle
	Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
	local bs = Instance.new("UIStroke", badge)
	bs.Color = Color3.new(1, 1, 1)
	bs.Thickness = 3
	local num = Instance.new("TextLabel")
	num.Name = "Num"
	num.Size = UDim2.fromScale(1, 1)
	num.BackgroundTransparency = 1
	num.Font = Enum.Font.FredokaOne
	num.TextScaled = true
	num.TextColor3 = Color3.new(1, 1, 1)
	num.TextStrokeTransparency = 0.3
	num.Parent = badge
	return num
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
	t.num = makeGui(m)
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
	if #queue + #departing < MAX_TRUCKS + 2 and #queue < MAX_TRUCKS and (not last or last.s >= Path.SPACING) and os.clock() >= nextTruckAt then
		spawnTruck()
		nextTruckAt = os.clock() + rng:NextNumber(TRUCK_DELAY[1], TRUCK_DELAY[2])
	end
end)

------------------------------------------------------------ CARRYING
local carry = {} -- player -> {count, parts, items} (FishVariants: items[i] = sale info of piece i)

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
		p.CFrame = hrp.CFrame * CFrame.new(0, 0.1 + i * 0.3, -1.7) * CFrame.Angles(0, math.rad(90), 0)
		local w = Instance.new("WeldConstraint")
		w.Part0 = hrp w.Part1 = p w.Parent = p
		p.Parent = folder
		local item = c.items and c.items[#c.parts + 1] -- FishVariants: glow for variant pieces
		if item and item.variant and VariantFx then pcall(VariantFx.applyToPart, p, item.variant) end
		table.insert(c.parts, p)
	end
	while #c.parts > c.count do
		table.remove(c.parts):Destroy()
	end
	player:SetAttribute("CarryMeat", c.count)
end

local function flyPart(from, to, height, dur)
	local p = meatTemplate:Clone()
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

local function topOfStack()
	local best, bi = nil, -1
	for _, m in ipairs(meatStack:GetChildren()) do
		local i = m:GetAttribute("StackIndex") or 0
		if i > bi then best, bi = m, i end
	end
	return best
end

local function addMeatToTruck(t, n, item) -- n = 0-based slot; item = FishVariants sale info
	local layer = n // 4
	local i = n % 4
	local off = t.bucketOffset + Vector3.new((i % 2 - 0.5) * 1.6, 0.16 + layer * 0.3, (i // 2 - 0.5) * 1.9)
	local p = meatTemplate:Clone()
	p.Name = "LoadedMeat"
	-- server-side the truck stays at its spawn pose; the client moves everything together
	p.CFrame = Path.truckCF(0) * CFrame.new(off) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0)
	if item and item.variant then
		p:SetAttribute("Variant", item.variant)
		if VariantFx then pcall(VariantFx.applyToPart, p, item.variant) end
	end
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
			carry[player] = carry[player] or { count = 0, parts = {}, items = {} }
			local c = carry[player]
			c.items = c.items or {}
			local pos = hrp.Position
			local rel = pos - STACK_CENTER
			-- pick up from the stack
			if math.abs(rel.X) <= STACK_HALF.X and math.abs(rel.Z) <= STACK_HALF.Z and math.abs(rel.Y) < 8 and c.count < MAX_CARRY then
				local meat = topOfStack()
				if meat then
					local from = meat.Position
					table.insert(c.items, saleInfoOf(meat, "Truck")) -- FishVariants: capture before destroy
					meat:Destroy()
					flyPart(from, pos + Vector3.new(0, 0.5 + c.count * 0.3, 0), 2, 0.2)
					c.count += 1
					carryVisual(player)
				end
			-- drop into the front truck
			elseif loading and c.count > 0 then
				local d = Vector3.new(pos.X - bucketPos.X, 0, pos.Z - bucketPos.Z).Magnitude
				if d <= DELIVER_RANGE then
					c.count -= 1
					-- FishVariants: the piece on top of the carried stack is the one delivered
					local item = table.remove(c.items) or { kind = "Truck", multiplier = 1 }
					item.sellerId = player.UserId
					carryVisual(player)
					local truck = front
					local slotLoaded = truck.loaded
					truck.loaded += 1
					truck.model:SetAttribute("Loaded", truck.loaded)
					truck.num.Text = tostring(truck.need - truck.loaded)
					events.MeatDelivered:Fire(player, truck.model, item)
					paySale(item)
					local dur = flyPart(pos + Vector3.new(0, 1.5, 0), bucketPos + Vector3.new(0, 0.5, 0), 4, 0.35)
					task.delay(dur, function()
						if truck.model.Parent then addMeatToTruck(truck, slotLoaded, item) end
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

Players.PlayerRemoving:Connect(function(p) carry[p] = nil end)
Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function()
		carry[p] = { count = 0, parts = {}, items = {} }
		p:SetAttribute("CarryMeat", 0)
	end)
end)
