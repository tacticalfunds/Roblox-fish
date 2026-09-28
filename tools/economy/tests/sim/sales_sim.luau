-- Sale payouts through the REAL patched GrinderProcessor and TruckSystem
-- (studio/sales/), with the REAL EconomyService, on the fake engine.
-- FishCaught payloads are exactly what the patched NetLiftScript /
-- HarpoonSystem send. Checks:
--   * who is paid: net player, a bought fish's buyer, the harpoon's bound
--     owner, nobody for an unowned harpoon catch; the carrier never
--   * each piece pays its ledger value once (a fish's value split over its
--     meat pieces), a second sale of the same piece pays nothing
--   * a carrier who respawns or leaves: their pieces are held and come back
--     out of the pipe with the same identity (never lost unpaid)
--   * a full stack: the belt waits, a full pit holds new pieces as data;
--     nothing is destroyed unpaid, everything flows once there is room
--   * the customer route (identity copied to the table clone, one sale)

local Economy, root = installEconomy()
local Pricing = Economy.Pricing
local SS = services.ServerStorage
local RS = services.ReplicatedStorage

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

local A = join(1, "Netter", AWAY) -- steps on the net pad
local B = join(2, "Buyer", AWAY) -- bought a rod fish
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

------------------------------------------------------------ 0) Car Sales hooks kept

do
	-- Car Sales hooks (live TruckSystem): the line only starts once cars are
	-- unlocked (CarSalesServer's paid unlock); CarsMaxQueue caps it
	advance(20)
	check("Car Sales: no trucks while cars are locked", #ws.Trucks:GetChildren() == 0)
	asServer(function()
		workspaceInst:SetAttribute("CarsUnlocked", true)
		workspaceInst:SetAttribute("CarsMaxQueue", 2)
	end)
	advance(40)
	check("Car Sales: unlocked, the line fills up to CarsMaxQueue", #ws.Trucks:GetChildren() == 2)
	asServer(function()
		workspaceInst:SetAttribute("CarsMaxQueue", nil)
	end)
end

------------------------------------------------------------ 1) ownership routes

local value = Pricing.fishValue
local pieceValues = Pricing.pieceValues
check("Cod tier 1 = 1 piece of 4", #pieceValues(1) == 1 and pieceValues(1)[1] == value(1) and value(1) == 4)

catch(A, "Cod", 1, { Source = "Net" }) -- plain net catch: the pad player
catch(A, "Salmon", 10, { OwnerId = 2, Source = "Net" }) -- B's bought fish, netted by A
catch(nil, "Tuna", 14, { Source = "Harpoon" }) -- harpoon, no bound owner
catch(nil, "Eel", 6, { OwnerId = 3, Source = "Harpoon" }) -- harpoon bound to C (OwnerUserId)
local expectPieces = 1 + #pieceValues(10) + #pieceValues(14) + #pieceValues(6)
check(
	"all pieces reach the stack",
	waitFor(function()
		return #stackPieces() == expectPieces
	end, 120)
)
local owners, values = {}, {}
for _, m in ipairs(stackPieces()) do
	local o = m:GetAttribute("OwnerId") or 0
	owners[o] = (owners[o] or 0) + 1
	values[o] = (values[o] or 0) + m:GetAttribute("Value")
end
check("stack: A owns the Cod piece", owners[1] == 1 and values[1] == value(1))
check(
	"stack: B owns the Salmon pieces (bought fish keeps its buyer)",
	owners[2] == #pieceValues(10) and values[2] == value(10)
)
check("stack: C owns the bound-harpoon Eel", owners[3] == #pieceValues(6) and values[3] == value(6))
check("stack: the unowned Tuna has no owner", owners[0] == #pieceValues(14) and values[0] == value(14))
check("nobody paid before a sale", balance(A) == 100 and balance(B) == 100 and balance(C) == 100)

check("carrier hauls everything to the trucks", haul(C, expectPieces))
check("stack empty after hauling", #stackPieces() == 0)
check("A paid the Cod's value once", balance(A) == 100 + value(1))
check("B paid the whole Salmon value (split over its pieces)", balance(B) == 100 + value(10))
check("C paid only for the Eel it owns, nothing for carrying", balance(C) == 100 + value(6))
local stats = Economy.stats()
check(
	"ledger: every piece settled once; the unowned Tuna paid nobody",
	stats.totals.settled == expectPieces and stats.totals.unpaid == #pieceValues(14) and stats.live == 0
)

------------------------------------------------------------ 2) respawn / leave while carrying

local before = { A = balance(A), C = balance(C) }
catch(A, "Pike", 14, { Source = "Net" }) -- 3 pieces for A
check(
	"respawn case: pieces on the stack",
	waitFor(function()
		return #stackPieces() == 3
	end, 60)
)
local ids = {}
for _, m in ipairs(stackPieces()) do
	ids[m:GetAttribute("PieceId")] = true
end
moveTo(C, STACK_SPOT)
waitFor(function()
	return carried(C) == 3
end, 10)
check("carrier holds 3", carried(C) == 3 and #stackPieces() == 0)
respawn(C, AWAY)
advance(0.2)
check(
	"respawn (player present before TruckSystem started): carried pieces are held, not lost",
	Economy.heldCount() == 3
)
check("respawn: carry count reset", carried(C) == 0)
check(
	"respawn: held pieces come back out of the pipe onto the stack",
	waitFor(function()
		return #stackPieces() == 3
	end, 60)
)
local same = true
for _, m in ipairs(stackPieces()) do
	same = same and ids[m:GetAttribute("PieceId")] == true and m:GetAttribute("OwnerId") == 1
end
check("respawn: same pieces, same owner", same and Economy.heldCount() == 0)
check("respawn: nobody paid yet", balance(A) == before.A and balance(C) == before.C)

-- a second carrier leaves the server with pieces: held too
local D = join(4, "Leaver", AWAY)
advance(0.5)
moveTo(D, STACK_SPOT)
waitFor(function()
	return carried(D) == 3
end, 10)
check("leaver holds 3", carried(D) == 3)
leave(D)
advance(0.2)
check("leave: pieces held", Economy.heldCount() == 3)
check(
	"leave: pieces back on the stack",
	waitFor(function()
		return #stackPieces() == 3
	end, 60)
)
check("then hauled and paid to A once", haul(C, 3) and balance(A) == before.A + value(14))

------------------------------------------------------------ 3) customer route (BotSystem / CustomerSystem calls)

catch(A, "Cod", 1, { Source = "Net" })
waitFor(function()
	return #stackPieces() == 1
end, 60)
do
	local meat = stackPieces()[1]
	local id = meat:GetAttribute("PieceId")
	local balA = balance(A)
	asServer(function()
		-- BotSystem: identity copied to the carried clone, stack piece destroyed
		local tags = Economy.readPiece(meat)
		meat:Destroy()
		local c = template:Clone()
		Economy.writePiece(c, tags)
		c.Parent = ws
		check(
			"bot clone keeps the piece's identity",
			c:GetAttribute("PieceId") == id and c:GetAttribute("OwnerId") == 1
		)
		-- CustomerSystem: the one sale
		local paid, amount = Economy.settle(c:GetAttribute("PieceId"), "Customer")
		check("customer sale pays the owner", paid and amount == value(1))
		local again = Economy.settle(id, "Truck")
		check("the same piece can't be sold twice", again == false)
		c:Destroy()
	end)
	check("A paid once for the customer sale", balance(A) == balA + value(1))
end

------------------------------------------------------------ 4) full stack: nothing destroyed unpaid

do
	asServer(function()
		for i = 1, 96 do -- a full stack of old, untracked meat
			local m = template:Clone()
			m:SetAttribute("StackIndex", i - 1)
			m.Parent = meatStack
		end
	end)
	local issuedBefore = Economy.stats().totals.issued
	for i = 1, 8 do
		catch(A, "Marlin" .. i, 19, { Source = "Net" }) -- 5 pieces each
	end
	local n = 8 * #pieceValues(19)
	advance(90)
	local stats2 = Economy.stats()
	local pitObjects = 0
	for _, m in ipairs(pitMeat:GetChildren()) do
		if m:GetAttribute("PieceId") then
			pitObjects += 1
		end
	end
	check("full stack: all pieces issued", stats2.totals.issued - issuedBefore == n)
	check("full stack: the pit stays bounded", pitObjects <= Economy.pipeline().MaxPitObjects)
	check("full stack: overflow held as data", Economy.heldCount() == n - pitObjects)
	check("full stack: nothing reached the full stack", #stackPieces() == 0 and #meatStack:GetChildren() == 96)
	check("full stack: nothing voided or settled", stats2.totals.voided == 0 and stats2.live + stats2.held == n)
	-- make room: everything flows through, each piece once
	asServer(function()
		meatStack:ClearAllChildren()
	end)
	check(
		"room again: every held piece comes out and stacks",
		waitFor(function()
			return #stackPieces() == n
		end, 400)
	)
	local seen, unique = {}, true
	for _, m in ipairs(stackPieces()) do
		local id = m:GetAttribute("PieceId")
		unique = unique and not seen[id]
		seen[id] = true
	end
	check("room again: each piece exactly once", unique and Economy.heldCount() == 0)
end

finish("sales sim")
