-- Server: handles the step pad. The net animation + splash runs on each client (NetLiftClient).
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local model = script.Parent
local hitbox = model.PadHitbox
local pad = model.Pad
local prints = model.Prints

local lifted = model:FindFirstChild("NetLifted") or Instance.new("BindableEvent")
lifted.Name = "NetLifted"
lifted.Parent = model

local padRest = pad.CFrame
local printRest = {}
for _, p in ipairs(prints:GetChildren()) do printRest[p] = p.CFrame end
local function pressPad(down)
	local off = down and CFrame.new(0, -0.3, 0) or CFrame.new()
	local info = TweenInfo.new(0.08)
	TweenService:Create(pad, info, { CFrame = off * padRest }):Play()
	for p, cf in pairs(printRest) do TweenService:Create(p, info, { CFrame = off * cf }):Play() end
end

-- fish catching: any fish over the net when it fires gets launched into the grinder
local fishFolder = workspace:WaitForChild("SwimmingFish")
local netRoot = model.Net.NetRoot
local NET_L = model:GetAttribute("NetL") or 34
local NET_W = model:GetAttribute("NetW") or 14
local caughtEvent = model:FindFirstChild("FishCaught") or Instance.new("BindableEvent")
caughtEvent.Name = "FishCaught" -- fires (player, fishName, tier) for each fish that lands in the grinder
caughtEvent.Parent = model

local function fishPos(m, t)
	local seed = m:GetAttribute("Seed") or 1
	local weaveA, weaveF, phase = 0.8 + (seed % 7) * 0.15, 0.35 + (seed % 5) * 0.08, seed * 1.7
	local z = m:GetAttribute("StartZ") + m:GetAttribute("Speed") * (t - m:GetAttribute("SpawnT"))
	local x = m:GetAttribute("LaneX") + weaveA * math.sin(weaveF * t + phase)
	return x, z
end

local function catchFish(player)
	local t = workspace:GetServerTimeNow()
	local c = netRoot.Position
	local count = 0
	for _, m in ipairs(fishFolder:GetChildren()) do
		if m:GetAttribute("SpawnT") and not m:GetAttribute("CaughtT") and not m:GetAttribute("HarpoonT") then
			local x, z = fishPos(m, t)
			if math.abs(x - c.X) <= NET_L / 2 and math.abs(z - c.Z) <= NET_W / 2 then
				m:SetAttribute("CaughtT", t)
				count += 1
				task.delay(1.65, function()
					caughtEvent:Fire(player, m.Name, m:GetAttribute("Tier"))
					if m.Parent then m:Destroy() end
				end)
			end
		end
	end
	return count
end

-- weight system: total weight of the fish over the net (kg)
local function weightOverNet(t)
	local c = netRoot.Position
	local total = 0
	for _, m in ipairs(fishFolder:GetChildren()) do
		if m:GetAttribute("SpawnT") and not m:GetAttribute("CaughtT") and not m:GetAttribute("HarpoonT") then
			local x, z = fishPos(m, t)
			if math.abs(x - c.X) <= NET_L / 2 and math.abs(z - c.Z) <= NET_W / 2 then
				total += m:GetAttribute("Weight") or 1
			end
		end
	end
	return total
end
-- keep a live reading on the model so clients can show it
task.spawn(function()
	while true do
		model:SetAttribute("CurrentWeight", weightOverNet(workspace:GetServerTimeNow()))
		task.wait(0.2)
	end
end)

local CYCLE = 2.3 -- matches the client animation length
local busy = false
hitbox.Touched:Connect(function(hit)
	if busy then return end
	local char = hit.Parent
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local player = hum and Players:GetPlayerFromCharacter(char)
	if not player or hum.Health <= 0 then return end
	busy = true
	pressPad(true)
	local maxW = model:GetAttribute("MaxWeight") or 40
	local w = weightOverNet(workspace:GetServerTimeNow())
	if w > maxW then
		-- too heavy: the net strains, flashes red and stays down
		model:SetAttribute("FailWeight", w)
		model:SetAttribute("FailId", (model:GetAttribute("FailId") or 0) + 1)
		task.wait(1.4)
		pressPad(false)
		task.wait(0.4)
		busy = false
		return
	end
	model:SetAttribute("LiftId", (model:GetAttribute("LiftId") or 0) + 1)
	catchFish(player)
	task.wait(0.1)
	lifted:Fire(player) -- net is up: hook fish catching here
	task.wait(CYCLE - 0.1)
	pressPad(false)
	task.wait(0.3)
	busy = false
end)
