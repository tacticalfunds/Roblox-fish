-- Upgrade board, milestone 3 (Meat Price): the REAL EconomyService, the
-- REAL UpgradeBoardServer + UpgradeBoardClient, and the REAL patched
-- GrinderProcessor + TruckSystem (the sales sim's scene). Checks:
--   * Meat Price closed by default (UpgradesOpen); open: 1x -> 2x for $10,
--     money + level in one write; the card shows 2x > 2.5x, $150
--   * an owner's fish is worth x2 AS A WHOLE, multiplied once when the
--     grinder cuts it, then split into its usual pieces; Gold / Silver and
--     tier values on top as before; each piece pays once
--   * only the OWNER's multiplier counts: a fish A nets for B pays B at B's
--     1x; an unowned harpoon fish pays nobody; the carrier is never paid
--   * the multiplier is fixed at the cut: a fish cut before the purchase
--     keeps its old value even if it sells after

local Economy, root = installEconomy()
local Pricing = Economy.Pricing
local SS = services.ServerStorage
local RS = services.ReplicatedStorage
local SSS = services.ServerScriptService
local KEY = Economy.Config.KeyPrefix

------------------------------------------------------------ the scene

current = "server"
local ws = workspaceInst
local grinder = new("Model", "FishGrinder")
local housing = model("Housing", grinder, Vector3.new(0, 5, 0))
grinder:SetAttribute("PipeExit", Vector3.new(0, 4, 4))
grinder:SetAttribute("RPM", 18)
grinder.Parent = ws
local netLift = new("Model", "NetLift")
local fishCaught = new("BindableEvent", "FishCaught")
fishCaught.Parent = netLift
netLift.Parent = ws
local template = part("MeatTemplate", Vector3.new(0, -50, 0), SS, Vector3.new(1.5, 0.3, 1))
local pitMeat = new("Folder", "PitMeat")
pitMeat.Parent = ws
local meatStack = new("Folder", "MeatStack")
meatStack.Parent = ws
local pit = part("Pit", Vector3.new(0, 0, 8), ws)
pit:SetAttribute("BlenderCenter", Vector3.new(0, 1, 8))
pit:SetAttribute("BlenderRadius", 3)
pit:SetAttribute("BeltStart", Vector3.new(4, 1, 8))
pit:SetAttribute("BeltEnd", Vector3.new(9, 1, 8))
pit:SetAttribute("StackOrigin", Vector3.new(12, 1, 8))
pit:SetAttribute("BladeName", "BladeCommon")
model("BladeCommon", ws, Vector3.new(0, 1, 8))

-- trucks: a straight path; the front truck loads at s = 40
local truckPath = script(
	"ModuleScript",
	"TruckPath",
	[[
local P = { LOAD_S = 40, SPACING = 10, TOTAL = 100 }
function P.slot(i) return P.LOAD_S - (i - 1) * P.SPACING end
function P.truckCF(s) return CFrame.new(0, 0, s) end
return P
]],
	RS
)
local truckTypes = new("Folder", "TruckTypes")
local van = model("Van", truckTypes)
part("TubInnerFloor", Vector3.new(0, 1, 0), van)
van:SetAttribute("Weight", 1)
van:SetAttribute("NeedMin", 2)
van:SetAttribute("NeedMax", 2)
van:SetAttribute("BucketOffset", Vector3.new(0, 2, 0))
truckTypes.Parent = SS
new("Folder", "Trucks").Parent = ws
local truckEvents = new("Folder", "TruckEvents")
new("BindableEvent", "MeatDelivered").Parent = truckEvents
new("BindableEvent", "TruckFilled").Parent = truckEvents
truckEvents.Parent = SS
local _ = truckPath
current = nil

local STACK_SPOT = Vector3.new(-78.4, 10.05, 160) -- TruckSystem's STACK_CENTER
local BUCKET = Vector3.new(0, 2, 40) -- truckCF(LOAD_S) * BucketOffset
local AWAY = Vector3.new(200, 0, 200)

-- the carrier is already in the server when TruckSystem starts (loading
-- EconomyService can yield): it must still be bound for respawn cleanup
local C = join(3, "Carrier", AWAY) -- carries meat to the trucks; bound to the harpoon
runScript(script("Script", "GrinderProcessor", SOURCES.Sales_GrinderProcessor, services.ServerScriptService))
runScript(script("Script", "TruckSystem", SOURCES.Sales_TruckSystem, services.ServerScriptService))
advance(0.2)

local MAIN = Vector3.new(-72.84, 21.08, 136.48)
local NEAR_BOARD = MAIN + Vector3.new(0, -7, 6)
local A = join(1, "Netter", NEAR_BOARD) -- steps on the net pad; buys Meat Price
local B = join(2, "Buyer", AWAY) -- bought a rod fish; no Meat Price
advance(1)
check("players loaded", balance(A) == 100 and balance(B) == 100 and balance(C) == 100)

local function stackPieces()
	local out = {}
	for _, m in ipairs(meatStack:GetChildren()) do
		local id = m:GetAttribute("PieceId")
		if id then
			table.insert(out, m)
		end
	end
	return out
end
local function waitFor(cond, limit)
	local t = 0
	while not cond() and t < limit do
		advance(0.5)
		t += 0.5
	end
	return cond()
end
local function catch(player, fishName, tier, meta)
	asServer(function()
		fishCaught:Fire(player, fishName, tier, meta)
	end)
end
local function carried(p)
	return p:GetAttribute("CarryMeat") or 0
end
-- carrier picks up to n pieces at the stack, then stands at the bucket until
-- they are all delivered
local function haul(p, n)
	moveTo(p, STACK_SPOT)
	waitFor(function()
		return carried(p) >= n or #meatStack:GetChildren() == 0
	end, 20)
	moveTo(p, BUCKET)
	local ok = waitFor(function()
		return carried(p) == 0
	end, 120)
	moveTo(p, AWAY)
	return ok
end


-- trucks run (Car Sales' unlock, as the live TruckSystem needs)
asServer(function()
	workspaceInst:SetAttribute("CarsUnlocked", true)
end)
advance(40)

-- the board
current = "server"
local board = new("Model", "Board")
local main = part("Main", MAIN, board, Vector3.new(19.53, 9.34, 0.85))
local surface = new("SurfaceGui", "SurfaceGui")
local bord = new("Frame", "bord3")
new("Frame", "Frame").Parent = bord
bord.Parent = surface
surface.Parent = main
board.Parent = ws
current = nil
runScript(script("Script", "UpgradeBoardServer", SOURCES.Board_Server, SSS))
runAs(A, function()
	runScript(script("LocalScript", "UpgradeBoardClient", SOURCES.Board_Client), A)
end)
advance(1.5)
local function card(p, id)
	local g = p.PlayerGui:FindFirstChild("UpgradeBoard")
	return g and g.bord3:FindFirstChild(id)
end
local function pressCard(p, id)
	click(p, card(p, id).Buy)
	advance(0.7)
end
local value = Pricing.fishValue
-- sells until `pieces` more pieces have been settled; returns each player's gain
local function sellAll(pieces)
	local before = { A = balance(A), B = balance(B), C = balance(C) }
	local target = Economy.stats().totals.settled + pieces
	local n = 0
	while Economy.stats().totals.settled < target and n < 20 do
		waitFor(function()
			return #stackPieces() > 0
		end, 30)
		haul(C, 2)
		n += 1
	end
	advance(2)
	return { A = balance(A) - before.A, B = balance(B) - before.B, C = balance(C) - before.C }
end
local yield = Pricing.meatYield

------------------------------------------------------------ the card

check("Meat Price card: 1x > 2x, SOON while closed", card(A, "MeatPrice").Value.Text == "1x > 2x" and card(A, "MeatPrice").Buy.Price.Text == "SOON")
pressCard(A, "MeatPrice")
check("closed by default: refused, not charged", lastNotice(A) == "Meat Price upgrades open soon" and balance(A) == 100)

-- a fish cut BEFORE the purchase keeps its value
catch(A, "Salmon", 10, { Source = "Net" })
waitFor(function()
	return #stackPieces() >= #Pricing.pieceValues(10)
end, 60)
check("A's first Salmon is cut (on the stack) before A buys", #stackPieces() == #Pricing.pieceValues(10))

root:SetAttribute("UpgradesOpen", true)
advance(0.1)
local writes = 0
dsHooks.before = function()
	writes += 1
end
pressCard(A, "MeatPrice")
dsHooks.before = nil
check("bought: Meat Price 1x → 2x (-$10), one write", lastNotice(A) == "Meat Price 1x → 2x (-$10)" and balance(A) == 90
	and writes == 1 and dsData[KEY .. "1"].upgrades.MeatPrice == 1)
advance(2)
check("card: 2x > 2.5x, $150", card(A, "MeatPrice").Value.Text == "2x > 2.5x" and card(A, "MeatPrice").Buy.Price.Text == "$150")
moveTo(A, AWAY)

local g1 = sellAll(yield(10))
check("the Salmon cut before the purchase paid 1x (" .. value(10) .. ")", g1.A == value(10) and g1.C == 0)

------------------------------------------------------------ after: x2 on the whole fish, once

catch(A, "Salmon", 10, { Source = "Net" })
local g2 = sellAll(yield(10))
check("A's next Salmon (" .. #Pricing.pieceValues(10) .. " pieces) paid 2 x " .. value(10) .. " in all", g2.A == 2 * value(10) and g2.C == 0)

catch(A, "Tuna", 14, { Source = "Net", Variant = "Gold" })
local g3 = sellAll(yield(14))
check("A's Gold Tuna: tier value x Gold (5) x Meat Price (2), once", g3.A == value(14) * 5 * 2)

catch(A, "Salmon", 10, { OwnerId = 2, Source = "Net" }) -- B's bought fish, netted by A
catch(nil, "Tuna", 14, { Source = "Harpoon" }) -- unowned
local g4 = sellAll(yield(10) + yield(14))
check("B's fish netted by A pays B at B's 1x; A gets nothing for it", g4.B == value(10) and g4.A == 0)
check("the unowned harpoon fish paid nobody; the carrier never", g4.C == 0)
local st = Economy.stats()
check("every issued piece sold exactly once; nothing left live, carried or held", st.totals.settled == st.totals.issued
	and st.live == 0 and st.carried == 0 and st.held == 0)

------------------------------------------------------------ with the live blade bonus (GrinderUpgrades)

-- the live EconomyService multiplies each sale by the owner's blade tier
-- (GrinderUpgradesConfig.mult); Meat Price is in the piece's value, cut
-- earlier: both apply, each exactly once
current = "server"
script("ModuleScript", "GrinderUpgradesConfig", SOURCES.Grinder_Config, RS)
A:SetAttribute("BladeTier", 2) -- Uncommon: x1.25
current = nil
local popups = {}
runAs(A, function()
	root.Earned.OnClientEvent:Connect(function(added, route, fishName, variant, kind, value)
		table.insert(popups, { added = added, kind = kind, value = value })
	end)
end)
catch(A, "Salmon", 10, { Source = "Net" })
local g5 = sellAll(yield(10))
local want, pieceSum = 0, 0
for _, v in ipairs(Pricing.pieceValues(10, nil, 2)) do
	want += math.max(1, math.floor(v * 1.25 + 0.5))
	pieceSum += v
end
check("Meat Price 2x (in the piece values) x blade 1.25 (at the sale): " .. want .. " for a " .. value(10) .. " fish", g5.A == want
	and pieceSum == 2 * value(10))
local addedSum, valueSum = 0, 0
for _, pp in ipairs(popups) do
	addedSum += pp.added
	valueSum += pp.value
end
check("the popups show what was really credited (with the blade), one per piece", #popups == yield(10) and addedSum == want
	and valueSum == pieceSum)
local st2 = Economy.stats()
check("still each piece sold once", st2.totals.settled == st2.totals.issued and st2.live == 0)

finish("meat sim")
