-- NetCapacityServer (Script in ServerScriptService). [Economy net capacity v3]
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
-- The net is PER PLAYER, as the live NetLiftScript uses it: its weight gate
-- reads the pad player's NetMaxWeight (EconomyService publishes it: that
-- player's own saved capacity) before NetLift.MaxWeight. This script never
-- changes NetLift.MaxWeight: it stays the place's base (15), the limit for
-- anyone whose capacity isn't published yet (money loading, earlier buys not
-- adopted) - never another player's.
--
-- Without a running EconomyService: the signs do nothing (fail closed).
local CollectionService = game:GetService("CollectionService")
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

local REACH_SLACK = 8 -- studs beyond the ClickDetector's own distance (server check)
local CLICK_DISTANCE = 24 -- as GrinderUpgradesServer set it

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
