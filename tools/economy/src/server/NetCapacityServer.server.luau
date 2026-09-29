-- NetCapacityServer (Script in ServerScriptService). [Economy net capacity v1]
--
-- The +5 KG signs: EVERY Workspace child named KGsign (the place has two with
-- the same name) whose "Board Part" holds a ClickDetector. A click buys the
-- clicking player's next +5 kg through EconomyService.netKgAction: alive,
-- money loaded, in reach of that sign, one purchase at a time, and saved
-- (money + capacity in one write) before it counts. The result is a toast.
--
-- The net lift is shared: Workspace.NetLift's MaxWeight attribute (read by
-- NetLiftScript's weight gate, the gauge and the net themes) is the highest
-- capacity owned by a player in the server whose money has loaded, never
-- below the place's own MaxWeight. It follows joins (once loaded), purchases
-- and leaves. Only the attribute changes; no fish are touched.
--
-- Without a running EconomyService: the signs do nothing and MaxWeight stays
-- the place's value (fail closed).
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
local function bind(sign: Instance)
	if bound[sign] or sign.Name ~= "KGsign" then
		return
	end
	local board = sign:FindFirstChild("Board Part")
	local detector = board and board:FindFirstChildOfClass("ClickDetector")
	if not (board and board:IsA("BasePart") and detector) then
		warn("[NetCapacity] " .. sign:GetFullName() .. " has no Board Part with a ClickDetector; not bound")
		return
	end
	bound[sign] = true
	detector.MouseClick:Connect(function(player: Player)
		if not Economy then
			return
		end
		local ok, message = Economy.netKgAction(player, function()
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			local reach = detector.MaxActivationDistance + REACH_SLACK + board.Size.Magnitude / 2
			if not (hrp and hrp:IsA("BasePart")) or (hrp.Position - board.Position).Magnitude > reach then
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

for _, child in ipairs(workspace:GetChildren()) do
	bind(child)
end
workspace.ChildAdded:Connect(bind)

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
