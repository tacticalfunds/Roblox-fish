-- GrinderUpgradesServer: step on the CONVEYOR pad to buy the belt, step on the
-- UPGRADE BLADE pad to buy the next blade tier. Charged through EconomyService,
-- saved in DataStore "GrinderUpgrades_v1". Per player attributes:
--   UpgradesLoaded (bool), OwnsConveyor (bool), BladeTier (1..9)
-- [Economy board] The KG signs are sold by NetCapacityServer now (the one
-- saved net capacity, shared with the upgrade board): this script only
-- reports its saved kg count once per join (EconomyService.adoptLegacyNetKg).
-- Purchases are journaled in the Money record (EconomyService.beginPurchase):
-- the upgrade is saved here WITH its purchase token, and a purchase left
-- open by a shutdown / slow write / crash is settled at the next load from
-- these tokens. No memory store outside Studio; records it can't read are
-- never overwritten.
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

-- Economy board: AUTHORITATIVE reads. GetAsync is cached per server for a
-- few seconds, so after a write that errored (it may have landed) a plain
-- read can return the record from before it. Every read this script decides
-- with (load, delivery read-back, settling an open purchase) bypasses the
-- cache (DataStoreGetOptions.UseCache = false); if that isn't possible the
-- read fails, and the purchase stays open rather than guessed.
local FRESH = nil
do
	local ok, opts = pcall(function()
		local o = Instance.new("DataStoreGetOptions")
		o.UseCache = false
		return o
	end)
	if ok then FRESH = opts end
end
local function readRecord(k, userId)
	if ds and userId > 0 then
		assert(FRESH, "DataStoreGetOptions unavailable - can't read authoritatively")
		return ds:GetAsync(k, FRESH)
	end
	return mem[k]
end

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
		local ok, res = pcall(readRecord, key(p), p.UserId) -- Economy board: authoritative
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

-- Economy board: delivers one purchase. A compare-and-set on the STORED
-- record: only if its conveyor / blade are still what the purchase was
-- priced from (`base`), `apply` is applied to the stored state and written
-- together with the purchase token (the last APPLIED_KEEP, in `applied`:
-- proof of delivery for a Money entry settled later). Everything else in
-- the record (kg, unknown fields) is the store's own, never this server's
-- copy. Returns "saved", state | "stale", state (the store moved on:
-- nothing written) | "unreadable" (nothing written) | "error".
local APPLIED_KEEP = 20
local function deliver(p, base, apply, token)
	local outcome, state = nil, nil
	local ok, err = pcall(update, p, function(old)
		outcome, state = nil, nil
		if not readable(old) then
			outcome = "unreadable"
			return nil
		end
		local cur = clean(old)
		if cur.conveyor ~= base.conveyor or cur.blade ~= base.blade then
			outcome, state = "stale", cur
			return nil
		end
		apply(cur)
		local out = type(old) == "table" and table.clone(old) or {}
		out.conveyor = cur.conveyor
		out.blade = cur.blade
		out.kg = cur.kg
		local applied = type(out.applied) == "table" and table.clone(out.applied) or {}
		table.insert(applied, token)
		while #applied > APPLIED_KEEP do table.remove(applied, 1) end
		out.applied = applied
		outcome, state = "saved", cur
		return out
	end)
	if not ok then
		warn("[GrinderUpgrades] save failed for " .. p.Name .. ": " .. tostring(err))
		return "error"
	end
	return outcome or "error", state
end

-- Economy board: the purchase tokens a record holds
local function hasToken(rec, token)
	return type(rec) == "table" and type(rec.applied) == "table" and table.find(rec.applied, token) ~= nil
end

-- Economy board: this server's copy follows the STORED record (validated)
local function adopt(p, rec)
	if not p.Parent then return end
	data[p] = clean(rec)
	if not readable(rec) then data[p].readOnly = true end
	publish(p)
end

------------------------------------------------------------ purchases
local REASON = { funds = "Not enough Money!", notLoaded = "Money still loading..." }
-- Economy board: the journal's name for this store's purchases
local SOURCE = "GrinderUpgrades"
REASON.unsettled = "Finishing your last purchase - try again in a moment"
REASON.busy = "One moment - still saving"
REASON.notSaved = "Couldn't save the purchase - you were not charged. Try again."

local function buy(p, price, what, apply)
	local d = data[p]
	if not Economy then return end
	if storeOff then Economy.notify(p, "Grinder upgrades are unavailable on this server", "error") return end
	if not d then Economy.notify(p, "Loading your upgrades...", "error") return end
	if d.readOnly then Economy.notify(p, "Your saved grinder upgrades couldn't be read - buying is off this session", "error") return end
	if type(Economy.beginPurchase) ~= "function" then Economy.notify(p, "Grinder upgrades are unavailable right now", "error") return end
	-- Economy board: debit + open entry saved in the Money record first (one write)
	local token, why = Economy.beginPurchase(p, SOURCE, price, what)
	if not token then
		Economy.notify(p, REASON[why] or "Couldn't buy that right now - you were not charged", "error")
		return
	end
	local outcome, state = deliver(p, d, apply, token) -- the upgrade and its token, one write
	local delivered
	if outcome == "saved" then
		delivered = true
	elseif outcome == "stale" or outcome == "unreadable" then
		delivered = false -- nothing was written
	else
		-- a write can error after it landed: read back (authoritatively) whether the token is here
		local ok, rec = pcall(readRecord, key(p), p.UserId)
		if ok then
			delivered = hasToken(rec, token)
			if readable(rec) then state = clean(rec) else outcome = "unreadable" end
		else
			delivered = nil -- can't tell: the open entry is settled from this store later
		end
	end
	-- this server's copy follows the store BEFORE the purchase is closed (and buying unblocked)
	if outcome == "unreadable" then
		if p.Parent and data[p] then data[p].readOnly = true end
	elseif state then
		adopt(p, state)
	end
	Economy.finishPurchase(p, token, delivered) -- kept / refunded / settled later
	if not p.Parent then return end
	if delivered == true then
		Economy.notify(p, "Bought " .. what .. "!", "success")
	elseif outcome == "stale" then
		Economy.notify(p, "Your upgrades had already changed - refreshed, you were refunded", "info")
	elseif delivered == false then
		Economy.notify(p, "Purchase failed, refunded", "error")
	else
		Economy.notify(p, "Checking your purchase - it will be kept or refunded shortly", "info")
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

-- Economy board: how EconomyService reads this store's purchase tokens
-- (to settle a Money entry left open by a shutdown / slow write / crash)
if Economy and type(Economy.registerPurchaseSource) == "function" and not storeOff then
	Economy.registerPurchaseSource(SOURCE, function(userId)
		local ok, rec = pcall(readRecord, "player_" .. userId, userId) -- authoritative
		if not ok then return nil end
		local set = {}
		if type(rec) == "table" and type(rec.applied) == "table" then
			for _, t in ipairs(rec.applied) do
				if type(t) == "string" then set[t] = true end
			end
		end
		return set, rec
	end, function(p, rec)
		-- before an open purchase is closed: this server's copy follows the record
		-- just read (a purchase delivered later is owned here at once, never sold twice)
		if data[p] then adopt(p, rec) end -- not loaded yet: load() reads the store itself
		return true
	end)
end

------------------------------------------------------------ players
Players.PlayerAdded:Connect(load)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(load, p) end
Players.PlayerRemoving:Connect(function(p)
	data[p] = nil
	busy[p] = nil
	last[p] = nil
end)
