-- GrinderUpgradesServer: step on the CONVEYOR pad to buy the belt, step on the
-- UPGRADE BLADE pad to buy the next blade tier. Charged through EconomyService,
-- saved in DataStore "GrinderUpgrades_v1". Per player attributes:
--   UpgradesLoaded (bool), OwnsConveyor (bool), BladeTier (1..9)
-- [Economy board] The KG signs are sold by NetCapacityServer now (the one
-- saved net capacity, shared with the upgrade board): this script only
-- reports its saved kg count once per join (EconomyService.adoptLegacyNetKg).
-- Purchases hold the player's final Money save until the store write is
-- done, refund a failed write, never use a memory store outside Studio
-- and never overwrite a record they can't read.
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
local storeOff = false -- Economy board: live server without its DataStore
do
	local ok, store = pcall(function() return DataStoreService:GetDataStore(STORE_NAME) end)
	if ok and RunService:IsStudio() then
		ok = pcall(function() store:GetAsync("__probe") end)
	end
	if ok then
		ds = store
	elseif RunService:IsStudio() then
		warn("[GrinderUpgrades] DataStore unavailable - using memory (Studio only)")
	else
		-- Economy board: never a memory store in a live server (purchases would vanish on leave)
		storeOff = true
		warn("[GrinderUpgrades] DataStore unavailable - upgrades can't be loaded or bought on this server")
	end
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

local busy = {}

local function publish(p)
	local d = data[p]
	if not d then return end
	p:SetAttribute("OwnsConveyor", d.conveyor == true)
	p:SetAttribute("BladeTier", d.blade)
	-- Economy board: NetKgBuys / NetMaxWeight come from EconomyService (the saved netKg)
	p:SetAttribute("UpgradesLoaded", true)
end

-- Economy board: a record whose fields this script can't read is kept as it
-- is (never overwritten): buying is off for that player this session.
local function whole(x, lo)
	return type(x) == "number" and x == x and x == math.floor(x) and x >= lo
end
local function readable(v)
	if v == nil then return true end
	return type(v) == "table" and (v.conveyor == nil or type(v.conveyor) == "boolean")
		and (v.blade == nil or whole(v.blade, 1)) and (v.kg == nil or whole(v.kg, 0))
end

local function clean(v)
	v = type(v) == "table" and v or {}
	local _, tier = Cfg.blade(v.blade or 1)
	local kg = math.max(0, math.floor(tonumber(v.kg) or 0))
	return { conveyor = v.conveyor == true, blade = tier, kg = kg }
end

local function load(p)
	if storeOff then return end -- Economy board: nothing to load from (and nothing is sold)
	for attempt = 1, 4 do
		local ok, res = pcall(function()
			if ds and p.UserId > 0 then return ds:GetAsync(key(p)) end
			return mem[key(p)]
		end)
		if not p.Parent then return end
		if ok then
			data[p] = clean(res)
			if not readable(res) then
				data[p].readOnly = true
				warn("[GrinderUpgrades] " .. p.Name .. "'s saved upgrades can't be read; kept as they are, buying is off")
			end
			publish(p)
			-- Economy board: earlier KG-sign buys become the saved net capacity (idempotent)
			if Economy and type(Economy.adoptLegacyNetKg) == "function" and readable(res) then
				Economy.adoptLegacyNetKg(p, data[p].kg)
			end
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
	if storeOff then Economy.notify(p, "Grinder upgrades are unavailable on this server", "error") return end
	if not d then Economy.notify(p, "Loading your upgrades...", "error") return end
	if d.readOnly then Economy.notify(p, "Your saved grinder upgrades couldn't be read - buying is off this session", "error") return end
	-- Economy board: the player's final Money save waits for this write, so a
	-- failed write is refunded even if they leave meanwhile
	local release = if type(Economy.holdSave) == "function" then Economy.holdSave(p) else function() end
	local paid, why = Economy.tryDebit(p, price, "GrinderUpgrade:" .. what)
	if not paid then
		release()
		Economy.notify(p, REASON[why] or tostring(why), "error")
		return
	end
	local nextState = table.clone(d)
	apply(nextState)
	local saved = save(p, nextState)
	if saved then
		if p.Parent then
			data[p] = nextState
			publish(p)
			Economy.notify(p, "Bought " .. what .. "!", "success")
		end
	else
		if type(Economy.refundHeld) == "function" then
			Economy.refundHeld(p, price, "GrinderUpgrade:" .. what)
		else
			Economy.refund(p, price, "GrinderUpgrade:" .. what)
		end
		if p.Parent then Economy.notify(p, "Purchase failed, refunded", "error") end
	end
	release()
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

-- Economy board: the KG signs (board + price plate) are NetCapacityServer's

------------------------------------------------------------ players
Players.PlayerAdded:Connect(load)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(load, p) end
Players.PlayerRemoving:Connect(function(p)
	data[p] = nil
	busy[p] = nil
	last[p] = nil
end)
