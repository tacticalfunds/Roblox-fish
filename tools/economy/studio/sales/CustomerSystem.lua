-- Customers: avatars of the server owner's friends walk out of the shops in the city,
-- down the sidewalk to the meat table at the end of the conveyor, buy a piece of meat
-- (if there is any), and walk back into the city.
--
-- [Economy patch v1] Changes vs. the live script are marked "Economy".
-- A customer's purchase is the piece's one sale: EconomyService pays the piece's
-- owner its ledger value. The tier is read before the piece is destroyed.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local SS = game:GetService("ServerStorage")

local folder = workspace:WaitForChild("Customers")
local saleMeat = workspace:WaitForChild("SaleMeat")
local meatTemplate = SS:WaitForChild("MeatTemplate")
local bought = SS:WaitForChild("CustomerEvents"):WaitForChild("CustomerBought")

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
				warn("[CustomerSystem] economy not running, original behaviour: " .. tostring(running))
			end
		else
			warn("[CustomerSystem] could not load EconomyService, original behaviour: " .. tostring(api))
		end
	end
end

-- tuning
local SPAWN_DELAY = { 10, 20 }   -- seconds between new customers
local MAX_IN_LINE = 4
local WAIT_FOR_MEAT = 18         -- how long they wait at the table before giving up
local WALK_SPEED = 9

-- route (sidewalk from the shop doors to the table)
local Y = 9.3
local DOORS = {
	{ door = Vector3.new(-125.6, Y, 185), out = Vector3.new(-126.1, Y, 184) },
	{ door = Vector3.new(-125.6, Y, 202), out = Vector3.new(-126.1, Y, 201) },
}
local CORNER = Vector3.new(-126.1, Y, 163.1)
local DOCK = Vector3.new(-94, Y, 163.1)
local SLOTS = { -- slot 1 is at the sale table, the rest line up behind
	Vector3.new(-94.8, Y, 152.5),
	Vector3.new(-94.8, Y, 157.5),
	Vector3.new(-94.6, Y, 162.4),
	Vector3.new(-98.5, Y, 163.1),
	Vector3.new(-102.5, Y, 163.1),
	Vector3.new(-106.5, Y, 163.1),
	Vector3.new(-110.5, Y, 163.1),
	Vector3.new(-114.5, Y, 163.1),
}
local TABLE_LOOK = Vector3.new(-80, Y, 152.5)

-- R15 default animations
local ANIM_IDLE = "rbxassetid://507766388"
local ANIM_WALK = "rbxassetid://507777826"

pcall(function()
	PhysicsService:RegisterCollisionGroup("Customers")
	PhysicsService:CollisionGroupSetCollidable("Customers", "Customers", false)
end)

------------------------------------------------ friends list
local friendIds = {}
local fetched = false
local function fetchFriends(player)
	if fetched then return end
	fetched = true
	local ok, pages = pcall(function() return Players:GetFriendsAsync(player.UserId) end)
	if ok and pages then
		while true do
			for _, f in ipairs(pages:GetCurrentPage()) do table.insert(friendIds, f.Id) end
			if pages.IsFinished or #friendIds >= 60 then break end
			local ok2 = pcall(function() pages:AdvanceToNextPageAsync() end)
			if not ok2 then break end
		end
	end
	if #friendIds == 0 then table.insert(friendIds, player.UserId) end
end
Players.PlayerAdded:Connect(fetchFriends)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(fetchFriends, p) end

local descCache = {}
local function makeAvatar()
	local id = #friendIds > 0 and friendIds[math.random(1, #friendIds)] or nil
	local desc
	if id then
		desc = descCache[id]
		if not desc then
			local ok, d = pcall(function() return Players:GetHumanoidDescriptionFromUserId(id) end)
			if ok then desc = d descCache[id] = d end
		end
	end
	desc = desc or Instance.new("HumanoidDescription")
	local ok, model = pcall(function() return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15) end)
	if not ok or not model then return nil end
	if id then
		local ok2, name = pcall(function() return Players:GetNameFromUserIdAsync(id) end)
		model.Name = ok2 and name or "Customer"
	else
		model.Name = "Customer"
	end
	local anim = model:FindFirstChild("Animate") if anim then anim:Destroy() end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then p.CollisionGroup = "Customers" end
	end
	return model
end

------------------------------------------------ customer behaviour
local line = {}

local function walkTo(c, pos)
	local hum = c.hum
	if not hum.Parent or hum.Health <= 0 then return false end
	hum:MoveTo(pos)
	local done = false
	local conn = hum.MoveToFinished:Connect(function() done = true end)
	local t = 0
	while not done and t < 12 do t += task.wait(0.1) end
	conn:Disconnect()
	return true
end

local function face(c, target)
	local hrp = c.hrp
	local look = Vector3.new(target.X, hrp.Position.Y, target.Z)
	hrp.CFrame = CFrame.lookAt(hrp.Position, look)
end

local function topOfStack() -- nearest meat on the sale table
	local best, bd = nil, math.huge
	for _, m in ipairs(saleMeat:GetChildren()) do
		if not m:GetAttribute("Sold") then
			local d = (m.Position - SLOTS[1]).Magnitude
			if d < bd then best, bd = m, d end
		end
	end
	if best then best:SetAttribute("Sold", true) end
	return best
end

local function giveMeat(c, meat)
	local from = meat.Position
	meat:Destroy()
	local hand = c.model:FindFirstChild("RightHand") or c.hrp
	local p = meatTemplate:Clone()
	p.Anchored = true
	p.Parent = workspace
	local to = c.hrp.Position + c.hrp.CFrame.LookVector * 1.2 + Vector3.new(0, 0.3, 0)
	local t = 0
	while t < 0.35 do
		t += task.wait()
		local u = math.min(t / 0.35, 1)
		p.CFrame = CFrame.new(from:Lerp(to, u) + Vector3.new(0, 3 * 4 * u * (1 - u), 0)) * CFrame.Angles(0, u * 6, 0)
	end
	-- hold it in front of them
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CFrame = c.hrp.CFrame * CFrame.new(0, 0.2, -1.1) * CFrame.Angles(0, math.rad(90), 0)
	local w = Instance.new("WeldConstraint")
	w.Part0 = c.hrp w.Part1 = p w.Parent = p
	p.Parent = c.model
end

local function reposition()
	for i, c in ipairs(line) do
		if c.state == "queued" and c.slot ~= i then
			c.slot = i
			task.spawn(function()
				walkTo(c, SLOTS[math.min(i, #SLOTS)])
				if i == 1 then face(c, TABLE_LOOK) end
			end)
		end
	end
end

local function leave(c)
	for i, x in ipairs(line) do if x == c then table.remove(line, i) break end end
	c.state = "leaving"
	reposition()
	walkTo(c, DOCK)
	walkTo(c, CORNER)
	walkTo(c, c.route.out)
	walkTo(c, c.route.door)
	c.model:Destroy()
end

local function runCustomer(c)
	walkTo(c, c.route.out)
	walkTo(c, CORNER)
	walkTo(c, DOCK)
	c.state = "queued"
	c.slot = nil
	reposition()
	-- wait until we're at the front and standing at the table
	while c.model.Parent and (line[1] ~= c or (c.hrp.Position - SLOTS[1]).Magnitude > 3) do task.wait(0.3) end
	if not c.model.Parent then return end
	face(c, TABLE_LOOK)
	task.wait(1.2)
	local waited = 0
	while waited < WAIT_FOR_MEAT do
		local meat = topOfStack()
		if meat then
			local tier = meat:GetAttribute("Tier") -- Economy: read before giveMeat destroys it
			if Economy then Economy.settle(meat:GetAttribute("PieceId"), "Customer") end -- Economy: the one sale
			giveMeat(c, meat)
			bought:Fire(c.model.Name, tier)
			task.wait(0.8)
			break
		end
		waited += task.wait(0.5)
	end
	leave(c)
end

local function spawnCustomer()
	local model = makeAvatar()
	if not model then return end
	local route = DOORS[math.random(1, #DOORS)]
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	hum.WalkSpeed = WALK_SPEED
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local up = Vector3.new(0, 2.9, 0)
	model:PivotTo(CFrame.lookAt(route.door + up, route.out + up))
	model.Parent = folder
	pcall(function() hrp:SetNetworkOwner(nil) end)
	-- walk / idle animations
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
	local idleA = Instance.new("Animation") idleA.AnimationId = ANIM_IDLE
	local walkA = Instance.new("Animation") walkA.AnimationId = ANIM_WALK
	local idle = animator:LoadAnimation(idleA)
	local walk = animator:LoadAnimation(walkA)
	idle.Looped = true walk.Looped = true
	idle:Play()
	hum.Running:Connect(function(speed)
		if speed > 0.5 then
			if not walk.IsPlaying then walk:Play(0.2) end
			walk:AdjustSpeed(speed / 12)
		else
			if walk.IsPlaying then walk:Stop(0.25) end
		end
	end)
	local c = { model = model, hum = hum, hrp = hrp, route = route, state = "walking" }
	table.insert(line, c)
	task.spawn(runCustomer, c)
end

task.wait(4)
while true do
	local cap = workspace:GetAttribute("CustomersLineCap") or MAX_IN_LINE
	if #Players:GetPlayers() > 0 and #line < cap then
		spawnCustomer()
	end
	local perMin = workspace:GetAttribute("CustomersPerMin")
	if perMin then
		local gap = 60 / perMin
		task.wait(gap * (0.75 + math.random() * 0.5))
	else
		task.wait(math.random(SPAWN_DELAY[1] * 10, SPAWN_DELAY[2] * 10) / 10)
	end
end
