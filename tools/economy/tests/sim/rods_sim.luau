-- Rods milestone 1: the REAL EconomyService (MoneyStore v2 + Rods), the REAL
-- new RodShopServer and the REAL rods RodFishingSystem on the fake engine.
-- Checks:
--   shop  - paid shop closed by default; buy (in range, alive, loaded,
--           stocked) saves money + rod in ONE DataStore write; buying an
--           owned rod equips it free; spam / duplicates while the save is in
--           flight charge once; not enough money; far / dead / loading /
--           forged ids refused; a failed save charges nothing; rejoin
--           restores rods; no EconomyService -> nothing sold, no money writes
--   casts - each press uses the PRESSER's equipped rod for every rod it
--           casts; another player's equip mid-cast changes nothing; waits
--           shrink by BiteWait, never below 2 s; the aquarium still hooks
--           >= 2.5 s after the press

local Economy, root = installEconomy()
local RS = services.ReplicatedStorage
local SSS = services.ServerScriptService
local ws = workspaceInst
local KEY = Economy.Config.KeyPrefix
local SHOP = Vector3.new(-85.5, 12.2, 210.7)

------------------------------------------------------------ shop scene (as in the Studio inventory)

current = "server"
local rodsFolder = new("Folder", "Rods")
for _, spec in ipairs({
	{ "FishingRod1", 100, 1, 3, 8 }, -- legacy Price / StockChance / StockMin / StockMax
	{ "FishingRod4", 750, 0.85, 2, 5 },
	{ "FishingRod3", 3500, 0.55, 1, 3 },
	{ "FishingRod2", 15000, 0.3, 1, 2 },
	{ "FishingRod5", 75000, 0.12, 1, 1 },
}) do
	local m = new("Model", spec[1])
	m:SetAttribute("Price", spec[2])
	m:SetAttribute("StockChance", spec[3])
	m:SetAttribute("StockMin", spec[4])
	m:SetAttribute("StockMax", spec[5])
	m:SetAttribute("Tier", 99) -- legacy, ignored
	m.Parent = rodsFolder
end
rodsFolder.Parent = RS
local shopFolder = new("Folder", "RodShop")
shopFolder:SetAttribute("RestockEvery", 300)
local buyRemote = new("RemoteFunction", "BuyRod")
buyRemote.Parent = shopFolder
shopFolder.Parent = RS
local petShop = new("Model", "Pet Shop")
local shopPart = part("ShopPrompt", SHOP, petShop, Vector3.new(2, 2, 2))
local openPrompt = new("ProximityPrompt", "OpenShopPrompt")
openPrompt._props.MaxActivationDistance = 14
openPrompt.Parent = shopPart
petShop.Parent = ws
current = nil

-- saved records: P rich (v1 record, as the released economy wrote it), R broke-ish
dsData[KEY .. "1"] = { v = 1, money = 10000, granted = true }
dsData[KEY .. "3"] = { v = 1, money = 120, granted = true }
local P = join(1, "Buyer", SHOP + Vector3.new(0, -7, 5))
local R = join(3, "Poor", SHOP + Vector3.new(4, -7, 0))
runScript(script("Script", "RodShopServer", SOURCES.Rods_Shop, SSS))
advance(0.5)

local function buy(p, id)
	local out
	runAs(p, function()
		out = table.pack(buyRemote:InvokeServer(id))
	end)
	advance(0.6) -- past the per-player cooldown
	return out and out[1], out and out[2]
end
local function rec(userId)
	return dsData[KEY .. tostring(userId)]
end

check("rods load: Basic owned + equipped", P:GetAttribute("RodOwned_FishingRod1") == 1 and P:GetAttribute("EquippedRod") == "FishingRod1")
check("v1 record: money unchanged", Economy.balance(P) == 10000)
check("shop shows the rod table prices (legacy ignored)", rodsFolder.FishingRod4:GetAttribute("Price") == 150
	and rodsFolder.FishingRod5:GetAttribute("Price") == 7500 and rodsFolder.FishingRod1:GetAttribute("Price") == 0)
check("benefit shown", rodsFolder.FishingRod5:GetAttribute("Benefit") == "Bites 45% faster" and rodsFolder.FishingRod4:GetAttribute("Benefit") == "Bites 15% faster")
check("Basic and Tiger always in stock", P:GetAttribute("RodStock_FishingRod1") == 1 and P:GetAttribute("RodStock_FishingRod4") == 1)

------------------------------------------------------------ closed by default

local ok, msg = buy(P, "FishingRod4")
check("paid shop closed by default: refused, not charged", ok == false and msg == "The rod shop opens soon" and Economy.balance(P) == 10000)
ok, msg = buy(P, "FishingRod1")
check("Basic (owned): equip works while closed", ok == true and Economy.balance(P) == 10000)

root:SetAttribute("RodShopOpen", true) -- the Studio validation switch
-- the rarer rods are rolled; make this run's roll deterministic
for _, id in ipairs({ "FishingRod3", "FishingRod2", "FishingRod5" }) do
	P:SetAttribute("RodStock_" .. id, 2)
end

------------------------------------------------------------ buying

local writesBefore = 0
local writeLog = {}
dsHooks.before = function(key)
	table.insert(writeLog, { key = key, t = now })
end
ok, msg = buy(P, "FishingRod4")
check("buy Tiger: ok", ok == true and msg == "Bought and equipped Tiger Rod")
check("charged 150, leaderstats follows", Economy.balance(P) == 9850 and P.leaderstats.Money.Value == 9850)
check("saved at once: money AND rod in the record", rec(1).money == 9850 and rec(1).rods.owned.FishingRod4 == true and rec(1).rods.equipped == "FishingRod4")
check("one DataStore write for the purchase", #writeLog == 1)
check("owned + equipped published", P:GetAttribute("RodOwned_FishingRod4") == 1 and P:GetAttribute("EquippedRod") == "FishingRod4")
ok, msg = buy(P, "FishingRod4")
check("buying an owned rod again: equips, no charge", ok == true and Economy.balance(P) == 9850)
ok = buy(P, "FishingRod1")
check("switch back to Basic: free", ok == true and P:GetAttribute("EquippedRod") == "FishingRod1" and Economy.balance(P) == 9850)
ok, msg = buy(P, "FishingRod4")
check("re-equip Tiger: free, says Equipped", ok == true and msg == "Equipped Tiger Rod" and Economy.balance(P) == 9850)

-- spam while the purchase save is in flight (a slow DataStore)
dsHooks.before = function()
	task.wait(1)
end
local results = {}
for i = 1, 4 do
	runAs(P, function()
		results[i] = table.pack(buyRemote:InvokeServer("FishingRod3"))
	end)
end
advance(2)
local oks = 0
for _, r in ipairs(results) do
	if r[1] == true then
		oks += 1
	end
end
check("spam x4 during a slow save: one purchase, charged once", oks == 1 and Economy.balance(P) == 9850 - 600)
check("Coral saved and equipped", rec(1).rods.owned.FishingRod3 == true and P:GetAttribute("EquippedRod") == "FishingRod3")
dsHooks.before = nil
advance(0.6)

-- not enough money
ok, msg = buy(R, "FishingRod4")
check("120 can't buy Tiger (150)", ok == false and msg == "Not enough money" and Economy.balance(R) == 120 and R:GetAttribute("RodOwned_FishingRod4") == nil)

-- too far / dead
moveTo(P, SHOP + Vector3.new(60, -7, 0))
ok, msg = buy(P, "FishingRod2")
check("far from the shop: refused, not charged", ok == false and msg == "Walk back to the rod shop to buy" and Economy.balance(P) == 9250)
ok = buy(P, "FishingRod4")
check("far away: equipping an owned rod still works", ok == true and P:GetAttribute("EquippedRod") == "FishingRod4")
moveTo(P, SHOP + Vector3.new(0, -7, 5))
P.Character.Humanoid.Health = 0
ok, msg = buy(P, "FishingRod2")
check("dead: refused", ok == false and Economy.balance(P) == 9250)
P.Character.Humanoid.Health = 100

-- forged ids
for _, forged in ipairs({ "Magma", "FishingRod9", 5, false, "" }) do
	ok, msg = buy(P, forged)
	check("forged id " .. tostring(forged) .. ": Unknown rod", ok == false and msg == "Unknown rod" and Economy.balance(P) == 9250)
end
runAs(P, function()
	ok, msg = buyRemote:InvokeServer({ "FishingRod5" })
end)
advance(0.6)
check("forged table: refused", ok == false and Economy.balance(P) == 9250)

-- the save fails: nothing charged, nothing owned
dsHooks.before = function()
	error("DataStore request failed")
end
ok, msg = buy(P, "FishingRod2")
check("save fails: refused, told not charged", ok == false and msg == "Couldn't save the purchase - you were not charged. Try again.")
check("save fails: money and rods unchanged", Economy.balance(P) == 9250 and P:GetAttribute("RodOwned_FishingRod2") == nil
	and rec(1).rods.owned.FishingRod2 == nil)
dsHooks.before = nil
ok = buy(P, "FishingRod2")
check("DataStore back: the purchase works", ok == true and Economy.balance(P) == 7250 and rec(1).rods.owned.FishingRod2 == true)

-- sold out (a rolled rod at 0 stock) is refused; owned ones always show
P:SetAttribute("RodStock_FishingRod5", 0)
ok, msg = buy(P, "FishingRod5")
check("Magma out of stock: Sold out", ok == false and msg == "Sold out" and Economy.balance(P) == 7250)

-- money still loading
dsData[KEY .. "4"] = { v = 1, money = 999, lock = { job = "another-server", t = 1700000000 + 10 ^ 7 } }
local L = join(4, "Loading", SHOP + Vector3.new(0, -7, 3))
advance(0.5)
ok, msg = buy(L, "FishingRod4")
check("money still loading: refused, no charge", ok == false and msg == "Your money is still loading - try again in a moment")

------------------------------------------------------------ rejoin

local before = Economy.balance(P)
leave(P)
advance(1)
check("leave: final save has money + rods", rec(1).money == before and rec(1).rods.owned.FishingRod2 and rec(1).rods.equipped == "FishingRod2"
	and rec(1).lock == nil and rec(1).v == 2)
P = join(1, "Buyer", SHOP + Vector3.new(0, -7, 5))
advance(0.5)
check("rejoin: money, rods and equip restored", Economy.balance(P) == before and P:GetAttribute("EquippedRod") == "FishingRod2"
	and P:GetAttribute("RodOwned_FishingRod3") == 1 and P:GetAttribute("RodOwned_FishingRod4") == 1)
check("rejoin: owned rods show in the shop", P:GetAttribute("RodStock_FishingRod2") >= 1 and P:GetAttribute("RodStock_FishingRod3") >= 1)
ok = buy(P, "FishingRod4")
check("rejoin: owned Tiger equips free", ok == true and Economy.balance(P) == before)

------------------------------------------------------------ shared casting: the presser's rod, per cast

current = "server"
local pressRemote = new("RemoteEvent", "PressFishButton")
pressRemote.Parent = RS
local fishModels = new("Folder", "FishModels")
local templates = new("Folder", "SwimTemplates")
for i, spec in ipairs({ { "Cod", 50, 1 }, { "Salmon", 20, 10 } }) do
	local m = model(spec[1], fishModels, Vector3.new(0, -100, i * 5))
	part("Fin", Vector3.new(0, -100, i * 5 + 1), m)
	local tpl = new("Model", spec[1])
	tpl:SetAttribute("SpawnWeight", spec[2])
	tpl:SetAttribute("Tier", spec[3])
	tpl.Parent = templates
end
fishModels.Parent = RS
templates.Parent = RS
local bigButton = new("Model", "BigButton")
local btn = new("Model", "Button")
btn._props.PrimaryPart = part("Body", Vector3.new(0, 5, 0), btn, Vector3.new(1, 3, 3))
btn.Parent = bigButton
bigButton.Parent = ws
local catches = new("Folder", "RodCatches")
catches.Parent = ws
local netLift = new("Model", "NetLift")
new("BindableEvent", "FishCaught").Parent = netLift
netLift.Parent = ws
local river = new("Folder", "SwimmingFish")
river:SetAttribute("GrinderPos", Vector3.new(-30, 10, 0))
river.Parent = ws
local dock = {}
for i, z in ipairs({ -6, 0, 6 }) do
	local rod = new("Model", "FishingRod1")
	rod._props.PrimaryPart = part("Pole", Vector3.new(10, 6, z), rod, Vector3.new(0.3, 6, 0.3))
	rod.Parent = ws
	dock[i] = rod
end
-- stub aquarium with the real rule: a fish is hooked no earlier than 2.5 s after the press
local aq = { reservedAt = {}, early = 0, hooks = 0 }
function aq.start() return true end
function aq.active() return true end
function aq.hasFreeSpot() return true end
function aq.reserve(list)
	for _, rod in ipairs(list) do
		aq.reservedAt[rod.key] = now
	end
	return list
end
function aq.hook(key)
	aq.hooks += 1
	if now - (aq.reservedAt[key] or math.huge) < 2.5 then
		aq.early += 1
		return false
	end
	return true
end
function aq.land() return true end
function aq.abort(key) aq.reservedAt[key] = nil end
function aq.entryPoint() return Vector3.new(-10, 12, 0) end
aq.toTankSeconds, aq.toTankHeight = 0.3, 3
local aqModule = new("ModuleScript", "AquariumCycleServer")
aqModule.Parent = SSS
loaded[aqModule] = aq
current = nil

-- P: Magma; Q: Basic
dsData[KEY .. "2"] = { v = 1, money = 50 }
local Q = join(2, "Other", Vector3.new(-20, 5, 4))
moveTo(P, SHOP + Vector3.new(0, -7, 5))
advance(0.5)
asServer(function()
	Economy.credit(P, 10000, "test")
end)
P:SetAttribute("RodStock_FishingRod5", 1) -- a lucky restock
check("P buys Magma", (buy(P, "FishingRod5")) == true and P:GetAttribute("EquippedRod") == "FishingRod5")
moveTo(P, Vector3.new(-20, 5, 0))
runScript(script("Script", "RodFishingSystem", SOURCES.Rods_Fishing, SSS))
advance(0.5)

-- bite delay per cast: from CastT0 to the bobber's Bite
local bites = {}
catches.ChildAdded:Connect(function(bob)
	local t0 = now
	bob:GetAttributeChangedSignal("Bite"):Connect(function()
		if bob:GetAttribute("Bite") then
			table.insert(bites, now - t0)
		end
	end)
end)
local function press(p)
	runAs(p, function()
		pressRemote:FireServer()
	end)
end
local function waitIdle()
	local t = 0
	while t < 60 and (dock[1]:GetAttribute("CastT0") or dock[1]:GetAttribute("Pulling") or dock[2]:GetAttribute("CastT0") or dock[3]:GetAttribute("Pulling")) do
		advance(0.5)
		t += 0.5
	end
	advance(20) -- offers time out, rods idle
end

local fastBites, slowBites = {}, {}
for round = 1, 6 do
	bites = {}
	press(P)
	check("round " .. round .. ": P's press casts with Magma", dock[1]:GetAttribute("CastRod") == "FishingRod5")
	-- Q equips / P switches mid-cast: this cast keeps Magma
	buy(P, "FishingRod1")
	advance(12)
	for _, b in ipairs(bites) do
		table.insert(fastBites, b)
	end
	buy(P, "FishingRod5")
	waitIdle()
end
bites = {}
for round = 1, 6 do
	bites = {}
	press(Q)
	check("round " .. round .. ": Q's press casts with Basic (P's Magma doesn't carry over)", dock[1]:GetAttribute("CastRod") == "FishingRod1")
	advance(12)
	for _, b in ipairs(bites) do
		table.insert(slowBites, b)
	end
	waitIdle()
end
local function stats(list)
	local lo, hi, sum = math.huge, -math.huge, 0
	for _, v in ipairs(list) do
		lo, hi, sum = math.min(lo, v), math.max(hi, v), sum + v
	end
	return lo, hi, sum / math.max(1, #list)
end
local flo, fhi, fmean = stats(fastBites)
local slo, shi, smean = stats(slowBites)
print(string.format("  Magma bites: n=%d min %.2f max %.2f mean %.2f | Basic: n=%d min %.2f max %.2f mean %.2f", #fastBites, flo, fhi, fmean, #slowBites, slo, shi, smean))
check("casts happened for both", #fastBites >= 12 and #slowBites >= 12)
check("Magma waits: within [2, 9 x 0.55] (+0.2 s cast), switching mid-cast changed nothing", flo >= 2.1 and fhi <= 9 * 0.55 + 0.35)
check("Basic waits: within [3, 9] (+0.2 s cast)", slo >= 3.1 and shi <= 9.35)
check("Magma bites clearly faster on average", fmean < smean * 0.75)
check("the aquarium never saw an early hook (>= 2.5 s after the press)", aq.hooks >= 24 and aq.early == 0)

------------------------------------------------------------ no EconomyService: nothing sold, no money writes

current = "server"
SSS.EconomyService.Parent = nil
current = nil
runScript(script("Script", "RodShopServer", SOURCES.Rods_Shop, SSS))
advance(0.2)
local moneyBefore = P.leaderstats.Money.Value
moveTo(P, SHOP + Vector3.new(0, -7, 5))
ok, msg = buy(P, "FishingRod2")
check("no EconomyService: the shop sells nothing", ok == false and msg == "The rod shop is unavailable right now")
check("no EconomyService: no money written anywhere", P.leaderstats.Money.Value == moneyBefore and P:GetAttribute("Money") == nil)

finish("rods sim")
