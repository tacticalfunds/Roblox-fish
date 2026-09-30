-- Upgrade board x the live GrinderUpgrades system: the REAL EconomyService,
-- NetCapacityServer, KgSignClient and the PATCHED GrinderUpgradesServer /
-- GrinderUpgradesClient (studio/grinder, from Astra's live sources) with the
-- live GrinderUpgradesConfig, on the fake engine. Two KG posts tagged KgSign
-- (Board Part ClickDetector, PricePlate.PriceGui.Pill), a conveyor pad and a
-- blade pad. Checks:
--   * earlier KG buys (GrinderUpgrades_v1 kg count) are adopted as the saved
--     netKg = 15 + 5 x kg: once, idempotent on rejoin (never 15 + 5 x kg
--     twice), the old record untouched (unknown fields too)
--   * net purchases wait until that count is reported
--   * ONE seller: a post click (board or plate) charges once, through
--     EconomyService (money + kg in one write); the old store's kg unchanged
--   * ONE plate writer: KgSignClient's per-player text survives the grinder
--     client's 0.25 s refresh loop
--   * no compounding: another change of NetLift.MaxWeight never moves a
--     player's NetMaxWeight
--   * conveyor / blade still work; a failed store write is refunded, also
--     when the player leaves during it (their final Money save waits); a
--     successful write while leaving keeps the debit and the upgrade
--   * an unreadable old record is never overwritten and buys nothing
--   (live server without the DataStore: grindernods_sim)

local Economy, root = installEconomy()
local RS = services.ReplicatedStorage
local SSS = services.ServerScriptService
local ws = workspaceInst
local KEY = Economy.Config.KeyPrefix
local SIGN1 = Vector3.new(-42.4489, 12.0365, 206.336)
local SIGN2 = Vector3.new(22.4984, 11.5565, 206.497)
local PADS = Vector3.new(-60, 8, 170)
local AWAY = Vector3.new(300, 8, 300)

current = "server"
script("ModuleScript", "GrinderUpgradesConfig", SOURCES.Grinder_Config, RS)
new("Folder", "Blades").Parent = RS
model("BladeCommon", ws, Vector3.new(0, 1, 8))
local netLift = new("Model", "NetLift")
netLift:SetAttribute("MaxWeight", 15)
netLift.Parent = ws
local pads = {}
for i, tag in ipairs({ "ConveyorPad", "BladePad" }) do
	local pad = new("Model", tag)
	local touch = part("TouchPart", PADS + Vector3.new(i * 6, 0, 0), pad, Vector3.new(4, 1, 4))
	pad.Parent = ws
	addTag(pad, tag)
	pads[tag] = touch
end
local detectors, pills, platesParts = {}, {}, {}
for i, pos in ipairs({ SIGN1, SIGN2 }) do
	local sign = new("Model", "KGsign")
	local board = part("Board Part", pos, sign, Vector3.new(8, 4, 0.5))
	local cd = new("ClickDetector", "ClickDetector")
	cd._props.MaxActivationDistance = 20
	cd.Parent = board
	local plate = part("PricePlate", pos + Vector3.new(0, 3, 0), sign, Vector3.new(4, 1.5, 0.2))
	local gui = new("SurfaceGui", "PriceGui")
	local pill = new("Frame", "Pill")
	local price = new("TextLabel", "Price")
	price._props.Text = "$100"
	price.Parent = pill
	local info = new("TextLabel", "Info")
	info._props.Text = "NET 15 KG → 20 KG"
	info.Parent = pill
	new("UIStroke", "Border").Parent = pill
	pill.Parent = gui
	gui.Parent = plate
	sign.Parent = ws
	addTag(sign, "KgSign")
	detectors[i] = cd
	pills[i] = pill
	platesParts[i] = plate
end
current = nil

-- the grinder's own store (GrinderUpgrades_v1), apart from the Money store
local G = {}
dsOther.GrinderUpgrades_v1 = G
-- A: 3 earlier KG buys, blade 2, conveyor; B: none; money in the Money record
G["player_1"] = { conveyor = true, blade = 2, kg = 3, extra = "keep me" }
dsData[KEY .. "1"] = { v = 2, money = 30000 }
dsData[KEY .. "2"] = { v = 2, money = 1000 }
-- B's old record loads slowly: B's net must wait for it
local slowB = true
dsHooks.get = function(key, store)
	if store == "GrinderUpgrades_v1" and key == "player_2" and slowB then
		task.wait(4)
	end
end
local A = join(1, "Veteran", SIGN1 + Vector3.new(0, -7, 6))
local B = join(2, "Newbie", SIGN1 + Vector3.new(3, -7, 6))
runScript(script("Script", "NetCapacityServer", SOURCES.Kg_Server, SSS))
runScript(script("Script", "GrinderUpgradesServer", SOURCES.Grinder_Server, SSS))
local function clients(p)
	runAs(p, function()
		runScript(script("LocalScript", "KgSignClient", SOURCES.Kg_Client), p)
		runScript(script("LocalScript", "GrinderUpgradesClient", SOURCES.Grinder_Client), p)
	end)
end
clients(A)
clients(B)
advance(1)

local function seen(p, inst, prop)
	local v
	runAs(p, function()
		v = inst[prop]
	end)
	return v
end
local function clickPost(p, i, onPlate)
	asServer(function()
		if onPlate then
			platesParts[i]:FindFirstChildOfClass("ClickDetector").MouseClick:Fire(p)
		else
			detectors[i].MouseClick:Fire(p)
		end
	end)
	advance(0.7)
end
local function touchPad(p, tag)
	moveTo(p, pads[tag].Position + Vector3.new(0, 2, 0))
	asServer(function()
		pads[tag].Touched:Fire(p.Character.HumanoidRootPart)
	end)
end

for _, w in ipairs(warnings) do print("WARN", w) end
------------------------------------------------------------ adoption

check("A's 3 earlier buys adopted: net 15 + 3 x 5 = 30 kg", A:GetAttribute("NetKg") == 30 and A:GetAttribute("NetKgNext") == 35
	and A:GetAttribute("NetKgCost") == 100)
check("compat attributes from the saved net: NetMaxWeight 30, NetKgBuys 3", A:GetAttribute("NetMaxWeight") == 30
	and A:GetAttribute("NetKgBuys") == 3)
check("blade / conveyor still published by GrinderUpgradesServer", A:GetAttribute("BladeTier") == 2 and A:GetAttribute("OwnsConveyor") == true)
check("shared net follows A's adopted 30 kg", netLift:GetAttribute("MaxWeight") == 30)
check("B's old record still loading: no net published yet", B:GetAttribute("NetKg") == nil)
root:SetAttribute("NetKgOpen", true)
advance(0.1)
clickPost(B, 1)
check("B clicks before their count is in: refused, not charged", lastNotice(B) == "Your net upgrades are still loading - try again in a moment"
	and Economy.balance(B) == 1000)
advance(4)
slowB = false
check("then B's count (none) is in: 15 kg", B:GetAttribute("NetKg") == 15 and B:GetAttribute("NetKgCost") == 10)

------------------------------------------------------------ one seller, one plate writer

local writes = 0
dsHooks.before = function()
	writes += 1
end
clickPost(A, 1)
dsHooks.before = nil
check("A clicks a post: ONE purchase 30 → 35 kg for 100, through EconomyService", lastNotice(A) == "Net capacity 30 → 35 kg (-$100)"
	and Economy.balance(A) == 29900 and A:GetAttribute("NetKg") == 35)
check("saved with the money in one write; the old store's kg untouched", writes == 1 and dsData[KEY .. "1"].netKg == 35
	and dsData[KEY .. "1"].money == 29900 and G["player_1"].kg == 3 and G["player_1"].extra == "keep me")
check("NetMaxWeight = 35 (the saved net, not MaxWeight + buys)", A:GetAttribute("NetMaxWeight") == 35 and A:GetAttribute("NetKgBuys") == 4)
advance(1)
moveTo(A, SIGN2 + Vector3.new(0, -4, 6))
clickPost(A, 2, true)
check("the other post's PRICE PLATE (its ClickDetector made by NetCapacityServer) sells the same net once: 35 → 40 for 150",
	lastNotice(A) == "Net capacity 35 → 40 kg (-$150)" and Economy.balance(A) == 29750)
check("the plate ClickDetector reaches 24 studs, like before", platesParts[2]:FindFirstChildOfClass("ClickDetector").MaxActivationDistance == 24
	and detectors[1].MaxActivationDistance == 24)
advance(2) -- many GrinderUpgradesClient refresh ticks
check("A's plates: NET 40 KG → 45 KG, $225 in green (the only writer; the grinder client's loop leaves them)",
	seen(A, pills[1].Info, "Text") == "NET 40 KG → 45 KG" and seen(A, pills[1].Price, "Text") == "$225"
	and seen(A, pills[1].Price, "TextColor3").G > 0.9 and seen(A, pills[2].Info, "Text") == "NET 40 KG → 45 KG")
check("B's plates show B's own net", seen(B, pills[1].Info, "Text") == "NET 15 KG → 20 KG" and seen(B, pills[1].Price, "Text") == "$10")
check("no floating panels over posts with a plate", A.PlayerGui:FindFirstChild("KgSignPanel") == nil)

-- no compounding
asServer(function()
	netLift:SetAttribute("MaxWeight", 100) -- e.g. another script / server changing it
end)
advance(1)
check("MaxWeight changed elsewhere: A's own NetMaxWeight stays 40 (no base + buys compounding)", A:GetAttribute("NetMaxWeight") == 40
	and A:GetAttribute("NetKg") == 40)

------------------------------------------------------------ conveyor / blade still work

moveTo(B, AWAY)
touchPad(A, "BladePad")
advance(1)
check("blade pad: Rare blade for 15000, saved in the old store (unknown field kept)", A:GetAttribute("BladeTier") == 3
	and Economy.balance(A) == 29750 - 15000 and G["player_1"].blade == 3 and G["player_1"].extra == "keep me"
	and G["player_1"].kg == 3)
advance(2)
-- failed store write: refunded
dsHooks.before = function(key, store)
	if store == "GrinderUpgrades_v1" and key == "player_1" then
		error("DataStore request failed")
	end
end
asServer(function()
	Economy.credit(A, 60000, "test") -- the next blade (Epic) costs 50000
end)
local before = Economy.balance(A)
touchPad(A, "BladePad")
advance(1)
dsHooks.before = nil
check("blade store write fails: refunded, still Rare", lastNotice(A) == "Purchase failed, refunded" and Economy.balance(A) == before
	and A:GetAttribute("BladeTier") == 3)
advance(2)

-- leaving while the (failing) write runs: refund lands BEFORE the final Money save
dsData[KEY .. "3"] = { v = 2, money = 20000 }
G["player_3"] = { blade = 1 }
local C = join(3, "Leaver", AWAY)
clients(C)
advance(1)
dsHooks.before = function(key, store)
	if store == "GrinderUpgrades_v1" and key == "player_3" then
		task.wait(2)
		error("DataStore request failed")
	end
end
touchPad(C, "BladePad")
advance(0.3)
check("C's blade purchase is being written: charged 4000 meanwhile", Economy.balance(C) == 16000)
leave(C)
advance(4)
dsHooks.before = nil
check("C left during a failed write: refunded before the final Money save (20000 saved, blade 1)",
	dsData[KEY .. "3"].money == 20000 and G["player_3"].blade == 1)

-- leaving while a SUCCESSFUL write runs: the debit and the upgrade both stay
dsData[KEY .. "4"] = { v = 2, money = 20000 }
G["player_4"] = { blade = 1 }
local D = join(4, "Leaver2", AWAY)
clients(D)
advance(1)
dsHooks.before = function(key, store)
	if store == "GrinderUpgrades_v1" and key == "player_4" then
		task.wait(2)
	end
end
touchPad(D, "BladePad")
advance(0.3)
leave(D)
advance(4)
dsHooks.before = nil
check("D left during a successful write: charged 4000 and Uncommon kept", dsData[KEY .. "4"].money == 16000 and G["player_4"].blade == 2)

-- an unreadable old record: kept, nothing bought, its net waits
dsData[KEY .. "5"] = { v = 2, money = 20000 }
G["player_5"] = { blade = "shiny", kg = 2, other = 1 }
local E = join(5, "Odd", AWAY)
clients(E)
advance(1)
touchPad(E, "BladePad")
advance(1)
check("unreadable old record: buying is off, record untouched, not charged",
	lastNotice(E) == "Your saved grinder upgrades couldn't be read - buying is off this session" and Economy.balance(E) == 20000
	and G["player_5"].blade == "shiny" and G["player_5"].other == 1)
check("... and its kg isn't adopted: net stays unpublished (fail closed)", E:GetAttribute("NetKg") == nil)

------------------------------------------------------------ rejoin: idempotent

leave(A)
advance(3)
check("A's final save: net 40 kg and the money", dsData[KEY .. "1"].netKg == 40 and dsData[KEY .. "1"].money == 29750 - 15000 + 60000)
A = join(1, "Veteran", SIGN1 + Vector3.new(0, -7, 6))
clients(A)
advance(1.5)
check("rejoin: 40 kg (the old 3 buys are not added again), blade Rare", A:GetAttribute("NetKg") == 40 and A:GetAttribute("BladeTier") == 3
	and G["player_1"].kg == 3)

finish("grinder sim")
