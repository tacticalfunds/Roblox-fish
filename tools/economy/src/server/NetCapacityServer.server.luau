-- NetCapacityServer (Script in ServerScriptService). [Economy net capacity v2]
--
-- The +5 KG signs: every sign tagged KgSign (CollectionService, as the place
-- has them) and every Workspace child named KGsign - the same two posts,
-- each bound once. Every ClickDetector in a sign counts (its board), and its
-- PricePlate gets one if it has none (as GrinderUpgradesServer used to do);
-- MaxActivationDistance 24. A click buys the clicking player's next +5 kg
-- through EconomyService.netKgAction: alive, money loaded, earlier KG-sign
-- buys adopted, in reach of the clicked part, one purchase at a time, and
-- saved (money + capacity in one write) before it counts. The result is a
-- toast. This is the ONLY KG-sign seller (GrinderUpgradesServer no longer is).
--
-- The net lift is shared: Workspace.NetLift's MaxWeight attribute (read by
-- NetLiftScript's weight gate, the gauge and the net themes) is the highest
-- capacity owned by a player in the server whose money has loaded, never
-- below the place's own MaxWeight. It follows joins (once loaded), purchases
-- and leaves. Only the attribute changes; no fish are touched.
--
-- Without a running EconomyService: the signs do nothing and MaxWeight stays
-- the place's value (fail closed).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Economy = nil
do
	local mod = ServerScriptService:FindFirstChild("EconomyService")
	if mod and mod:IsA("ModuleScript") then
		local ok, api = pcall(require, mod)
		if ok and type(api) == "table" then
			local ran, running = pcall(api.start)
			if ran and running and type(api.netKgAction) == "function" then
				Economy = api
			else
				warn("[NetCapacity] economy not running: the +5 KG signs do nothing (" .. tostring(running) .. ")")
			end
		else
			warn("[NetCapacity] could not load EconomyService: the +5 KG signs do nothing (" .. tostring(api) .. ")")
		end
	else
		warn("[NetCapacity] no EconomyService: the +5 KG signs do nothing")
	end
end

local netLift = workspace:WaitForChild("NetLift")
-- the place's own capacity: the shared net never goes below it
local FLOOR = netLift:GetAttribute("MaxWeight")
if type(FLOOR) ~= "number" then
	FLOOR = 15
end
local REACH_SLACK = 8 -- studs beyond the ClickDetector's own distance (server check)
local CLICK_DISTANCE = 24 -- as GrinderUpgradesServer set it

------------------------------------------------------------ the shared net

local function sharedMax(leaving: Player?): number
	local best = FLOOR
	if Economy then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= leaving then
				local kg = Economy.netKg(p)
				if type(kg) == "number" and kg > best then
					best = kg
				end
			end
		end
	end
	return best
end

local function update(leaving: Player?)
	local v = sharedMax(leaving)
	if netLift:GetAttribute("MaxWeight") ~= v then
		netLift:SetAttribute("MaxWeight", v)
	end
end

------------------------------------------------------------ the signs

local bound = {}
local function click(detector: ClickDetector, part: BasePart)
	detector.MouseClick:Connect(function(player: Player)
		if not Economy then
			return
		end
		local ok, message = Economy.netKgAction(player, function()
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local reach = detector.MaxActivationDistance + REACH_SLACK + part.Size.Magnitude / 2
			if not (hrp and hrp:IsA("BasePart")) or not part:IsDescendantOf(workspace)
				or (hrp.Position - part.Position).Magnitude > reach then
				return false, "Walk up to the sign"
			end
			return true, nil
		end)
		Economy.notify(player, message, if ok then "success" else "warn")
		if ok then
			update()
		end
	end)
end
local function bind(sign: Instance)
	if bound[sign] then
		return
	end
	local plate = sign:FindFirstChild("PricePlate")
	if plate and plate:IsA("BasePart") and not plate:FindFirstChildOfClass("ClickDetector") then
		local cd = Instance.new("ClickDetector")
		cd.Parent = plate
	end
	local count = 0
	for _, d in ipairs(sign:GetDescendants()) do
		if d:IsA("ClickDetector") and d.Parent and d.Parent:IsA("BasePart") then
			d.MaxActivationDistance = CLICK_DISTANCE
			click(d, d.Parent)
			count += 1
		end
	end
	if count == 0 then
		warn("[NetCapacity] " .. sign:GetFullName() .. " has no ClickDetector on a part; not bound")
		return
	end
	bound[sign] = true
end

for _, sign in ipairs(CollectionService:GetTagged("KgSign")) do
	bind(sign)
end
CollectionService:GetInstanceAddedSignal("KgSign"):Connect(bind)
for _, child in ipairs(workspace:GetChildren()) do
	if child.Name == "KGsign" then
		bind(child)
	end
end
workspace.ChildAdded:Connect(function(child)
	if child.Name == "KGsign" then
		bind(child)
	end
end)

------------------------------------------------------------ players

local function watch(player: Player)
	-- EconomyService publishes NetKg once the player's money has loaded, and on every purchase
	player:GetAttributeChangedSignal("NetKg"):Connect(function()
		update()
	end)
	update()
end
Players.PlayerAdded:Connect(watch)
for _, p in ipairs(Players:GetPlayers()) do
	watch(p)
end
Players.PlayerRemoving:Connect(function(player)
	update(player)
end)
update()
