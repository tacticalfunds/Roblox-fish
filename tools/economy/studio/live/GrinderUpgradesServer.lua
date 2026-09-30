-- GrinderUpgradesServer: step on the CONVEYOR pad to buy the belt, step on the
-- UPGRADE BLADE pad to buy the next blade tier. Charged through EconomyService,
-- saved in DataStore "GrinderUpgrades_v1". Per player attributes:
--   UpgradesLoaded (bool), OwnsConveyor (bool), BladeTier (1..9)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")

local Cfg = require(RS:WaitForChild("GrinderUpgradesConfig"))

local Economy
do
	local mod = game:GetService("ServerScriptService"):FindFirstChild("EconomyService")
	local ok, api = pcall(function() return mod and require(mod) end)
	if ok and api then
		pcall(api.start)
		Economy = api
	end
end

------------------------------------------------------------ store
local STORE_NAME = "GrinderUpgrades_v1"
local mem = {}
local ds
do
	local ok, store = pcall(function() return DataStoreService:GetDataStore(STORE_NAME) end)
	if ok and RunService:IsStudio() then
		ok = pcall(function() store:GetAsync("__probe") end)
	end
	if ok then ds = store else warn("[GrinderUpgrades] DataStore unavailable - using memory (Studio only)") end
end

local function key(p) return "player_" .. p.UserId end

local function update(p, transform)
	if ds and p.UserId > 0 then
		return ds:UpdateAsync(key(p), transform)
	end
	local r = transform(mem[key(p)])
	if r ~= nil then mem[key(p)] = r end
	return mem[key(p)]
end

local data = {} -- [player] = { conveyor = bool, blade = number, kg = number }

local netLift = workspace:WaitForChild("NetLift")
local function baseKg()
	return tonumber(netLift:GetAttribute("MaxWeight")) or 15
end
local busy = {}

local function publish(p)
	local d = data[p]
	if not d then return end
	p:SetAttribute("OwnsConveyor", d.conveyor == true)
	p:SetAttribute("BladeTier", d.blade)
	p:SetAttribute("NetKgBuys", d.kg)
	p:SetAttribute("NetMaxWeight", Cfg.netMax(baseKg(), d.kg))
	p:SetAttribute("UpgradesLoaded", true)
end

local function clean(v)
	v = type(v) == "table" and v or {}
	local _, tier = Cfg.blade(v.blade or 1)
	local kg = math.max(0, math.floor(tonumber(v.kg) or 0))
	return { conveyor = v.conveyor == true, blade = tier, kg = kg }
end

local function load(p)
	for attempt = 1, 4 do
		local ok, res = pcall(function()
			if ds and p.UserId > 0 then return ds:GetAsync(key(p)) end
			return mem[key(p)]
		end)
		if not p.Parent then return end
		if ok then
			data[p] = clean(res)
			publish(p)
			return
		end
		warn("[GrinderUpgrades] load failed for " .. p.Name .. ": " .. tostring(res))
		task.wait(attempt * 2)
	end
end

-- Writes the new state; returns true only if it was saved.
local function save(p, newState)
	local ok, err = pcall(update, p, function(old)
		local out = type(old) == "table" and table.clone(old) or {}
		out.conveyor = newState.conveyor
		out.blade = newState.blade
		out.kg = newState.kg
		return out
	end)
	if not ok then warn("[GrinderUpgrades] save failed for " .. p.Name .. ": " .. tostring(err)) end
	return ok
end

------------------------------------------------------------ purchases
local REASON = { funds = "Not enough Money!", notLoaded = "Money still loading..." }

local function buy(p, price, what, apply)
	local d = data[p]
	if not Economy then return end
	if not d then Economy.notify(p, "Loading your upgrades...", "error") return end
	local paid, why = Economy.tryDebit(p, price, "GrinderUpgrade:" .. what)
	if not paid then
		Economy.notify(p, REASON[why] or tostring(why), "error")
		return
	end
	local nextState = table.clone(d)
	apply(nextState)
	local saved = save(p, nextState)
	if not p.Parent then return end
	if saved then
		data[p] = nextState
		publish(p)
		Economy.notify(p, "Bought " .. what .. "!", "success")
	else
		Economy.refund(p, price, "GrinderUpgrade:" .. what)
		Economy.notify(p, "Purchase failed, refunded", "error")
	end
end

local function onConveyorPad(p)
	local d = data[p]
	if d and d.conveyor then return end
	buy(p, Cfg.ConveyorPrice, "Conveyor", function(s) s.conveyor = true end)
end

local function onBladePad(p)
	local d = data[p]
	if not d then return end
	if d.blade >= #Cfg.Blades then Economy.notify(p, "Blade is maxed!", "info") return end
	local nextDef = Cfg.Blades[d.blade + 1]
	buy(p, nextDef.Price, nextDef.Name .. " Blade", function(s) s.blade = d.blade + 1 end)
end

local function onKgSign(p)
	local d = data[p]
	if not d then return end
	local price = Cfg.kgPrice(d.kg)
	buy(p, price, "+" .. Cfg.Kg.Step .. " KG", function(s) s.kg = d.kg + 1 end)
end

------------------------------------------------------------ pads
local last = {} -- [player][pad] = time
local function hookPad(pad, handler)
	local touch = pad:WaitForChild("TouchPart")
	touch.Touched:Connect(function(hit)
		local char = hit.Parent
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local p = hum and hum.Health > 0 and Players:GetPlayerFromCharacter(char)
		if not p or busy[p] then return end
		last[p] = last[p] or {}
		local now = os.clock()
		if last[p][pad] and now - last[p][pad] < 1.5 then return end
		last[p][pad] = now
		busy[p] = true
		local ok, err = pcall(handler, p)
		busy[p] = nil
		if not ok then warn("[GrinderUpgrades] " .. tostring(err)) end
	end)
end

for _, pad in ipairs(CollectionService:GetTagged("ConveyorPad")) do hookPad(pad, onConveyorPad) end
for _, pad in ipairs(CollectionService:GetTagged("BladePad")) do hookPad(pad, onBladePad) end

-- KG signs: click / tap the board (ClickDetector) or its price plate
local lastKg = {}
local function kgClicked(p)
	if busy[p] then return end
	local now = os.clock()
	if lastKg[p] and now - lastKg[p] < 0.4 then return end
	lastKg[p] = now
	busy[p] = true
	local ok, err = pcall(onKgSign, p)
	busy[p] = nil
	if not ok then warn("[GrinderUpgrades] " .. tostring(err)) end
end
for _, sign in ipairs(CollectionService:GetTagged("KgSign")) do
	for _, d in ipairs(sign:GetDescendants()) do
		if d:IsA("ClickDetector") then
			d.MaxActivationDistance = 24
			d.MouseClick:Connect(kgClicked)
		end
	end
	local plate = sign:FindFirstChild("PricePlate")
	if plate and not plate:FindFirstChildOfClass("ClickDetector") then
		local cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 24
		cd.Parent = plate
		cd.MouseClick:Connect(kgClicked)
	end
end
netLift:GetAttributeChangedSignal("MaxWeight"):Connect(function()
	for p in pairs(data) do publish(p) end
end)

------------------------------------------------------------ players
Players.PlayerAdded:Connect(load)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(load, p) end
Players.PlayerRemoving:Connect(function(p)
	data[p] = nil
	busy[p] = nil
	last[p] = nil
	lastKg[p] = nil
end)
