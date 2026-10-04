-- The Sell stall: the REAL stall-patched TruckSystem with the REAL
-- EconomyService, in the live layout: an unnamed Workspace Model with a Circle
-- (the red ring, (-63.05, 11.23, 243.60), 6.74 x 1.92 x 6.74) and a Touch part
-- and a "Sell" label; a Sell NPC (Workspace.Sell) and a Circle + "Sell"
-- decoration without a Touch part, neither to be mistaken for it; the meat stack; a truck waiting.
-- Checks:
--   * standing in the ring sells every carried piece, one per tick, each the
--     same ledger sale as a truck (paid once to the OWNER, never the carrier;
--     the exact piece values; nothing left carried or held; visuals cleared)
--   * a sold piece can't be sold again; an untracked piece sells for nothing
--   * just outside the ring, far above it, or dead: nothing sold
--   * trucks still work with this version
--   * two rings: no stall (warned), nothing sold there

local Economy = installEconomy()
local Pricing = Economy.Pricing
local RS = services.ReplicatedStorage
local SS = services.ServerStorage
local SSS = services.ServerScriptService
local ws = workspaceInst

local RING = Vector3.new(-63.0507, 11.2302, 243.5997)
local STACK_SPOT = Vector3.new(-78.4, 10.05, 160)
local BUCKET = Vector3.new(0, 2, 40)
local AWAY = Vector3.new(200, 0, 200)

local owner = join(1, "Owner", Vector3.new(300, 5, 300))
local C = join(3, "Carrier", AWAY)
advance(1)

local function waitFor(cond, limit)
	local t = 0
	while not cond() and t < limit do
		advance(0.25)
		t += 0.25
	end
	return cond()
end

------------------------------------------------------------ scene

current = "server"
local meatStack = new("Folder", "MeatStack")
meatStack.Parent = ws
part("MeatTemplate", Vector3.new(0, -50, 0), SS, Vector3.new(1.5, 0.3, 1))
script("ModuleScript", "TruckPath", [[
local P = { LOAD_S = 40, SPACING = 10, TOTAL = 100 }
function P.slot(i) return P.LOAD_S - (i - 1) * P.SPACING end
function P.truckCF(s) return CFrame.new(0, 0, s) end
return P
]], RS)
local truckTypes = new("Folder", "TruckTypes")
local van = model("Van", truckTypes)
part("TubInnerFloor", Vector3.new(0, 1, 0), van)
van:SetAttribute("Weight", 1)
van:SetAttribute("NeedMin", 6)
van:SetAttribute("NeedMax", 6)
van:SetAttribute("BucketOffset", Vector3.new(0, 2, 0))
truckTypes.Parent = SS
new("Folder", "Trucks").Parent = ws
local truckEvents = new("Folder", "TruckEvents")
new("BindableEvent", "MeatDelivered").Parent = truckEvents
new("BindableEvent", "TruckFilled").Parent = truckEvents
truckEvents.Parent = SS

-- the stall, as the place has it
local function stallModel(at)
	local m = new("Model", "Model")
	part("Circle", at, m, Vector3.new(6.7376, 1.9231, 6.7376))
	part("Touch", at + Vector3.new(0.05, 0, 0), m, Vector3.new(4.0053, 7.0843, 6.8771))
	local sign = part("Sell", at + Vector3.new(0, 6, -4), m, Vector3.new(4, 1, 0.2))
	local gui = new("SurfaceGui", "SurfaceGui")
	local text = new("TextLabel", "Text")
	text._props.Text = "Sell"
	text.Parent = gui
	gui.Parent = sign
	m.Parent = ws
	return m
end
local stall = stallModel(RING)
-- a decoration elsewhere with a Circle and a "Sell" sign but no Touch part: not the stall
local decoy = new("Model", "Model")
part("Circle", RING + Vector3.new(0, 0, -80), decoy, Vector3.new(4, 1, 4))
local decoyText = new("TextLabel", "Text")
decoyText._props.Text = "Sell"
decoyText.Parent = decoy
decoy.Parent = ws
-- the Sell NPC (not the stall)
local npc = new("Model", "Sell")
part("HumanoidRootPart", RING + Vector3.new(20, 3, 0), npc)
local tag = new("TextLabel", "Text")
tag._props.Text = "Sell"
tag.Parent = npc
npc.Parent = ws
current = nil

local function stackPiece(index, tier)
	return asServer(function()
		local id = Economy.issueFish(owner, "Cod", tier or 1, { Source = "Net" })[1]
		local m = part("Meat", Vector3.new(-80, 9, 161 + index), nil, Vector3.new(1.5, 0.3, 1))
		Economy.stamp(m, id)
		m:SetAttribute("StackIndex", index)
		m.Parent = meatStack
		return id
	end)
end
local function pickUp(n)
	moveTo(C, STACK_SPOT)
	waitFor(function()
		return (C:GetAttribute("CarryMeat") or 0) == n
	end, 10)
	moveTo(C, AWAY)
	advance(0.5)
end
local function carriedParts()
	local f = C.Character:FindFirstChild("CarriedMeat")
	return f and #f:GetChildren() or 0
end

warnings = {}
runScript(script("Script", "TruckSystem", SOURCES.Stall_Truck, SSS))
asServer(function()
	ws:SetAttribute("CarsUnlocked", true)
	ws:SetAttribute("CarsMaxQueue", 1)
end)
advance(40)

------------------------------------------------------------ selling at the stall

local ids = { stackPiece(0, 1), stackPiece(1, 4), stackPiece(2, 10) }
pickUp(3)
check("the carrier holds three of the owner's pieces", C:GetAttribute("CarryMeat") == 3 and carriedParts() == 3)
local ownerBefore, carrierBefore = balance(owner), balance(C)
local value = 0
for _, t in ipairs({ 1, 4 }) do
	value += Pricing.fishValue(t)
end
value += Pricing.pieceValues(10)[1]
moveTo(C, RING + Vector3.new(1, 3, 1)) -- standing in the ring (root part ~3 above it)
waitFor(function()
	return (C:GetAttribute("CarryMeat") or 0) == 0
end, 5)
advance(0.5)
check("standing in the red ring sells every carried piece", C:GetAttribute("CarryMeat") == 0 and carriedParts() == 0)
check("paid once each to the OWNER, the exact piece values; the carrier gets nothing", balance(owner) == ownerBefore + value
	and balance(C) == carrierBefore)
check("nothing held or left over", Economy.heldCount() == 0)
local again = asServer(function()
	return Economy.settle(ids[1], "Stall")
end)
check("a sold piece can't be sold again", again == false and balance(owner) == ownerBefore + value)
moveTo(C, AWAY)
advance(1)

-- just outside the ring, far above it, dead
stackPiece(0, 1)
pickUp(1)
local before = balance(owner)
moveTo(C, RING + Vector3.new(6.7376 / 2 + 2.5, 3, 0))
advance(2)
check("just outside the ring (radius + 2.5): nothing sold", C:GetAttribute("CarryMeat") == 1 and balance(owner) == before)
moveTo(C, RING + Vector3.new(0, 15, 0))
advance(2)
check("right above it, 15 studs up: nothing sold", C:GetAttribute("CarryMeat") == 1)
C.Character.Humanoid.Health = 0
moveTo(C, RING + Vector3.new(0, 3, 0))
advance(2)
check("dead in the ring: nothing sold", C:GetAttribute("CarryMeat") == 1 and balance(owner) == before)
C.Character.Humanoid.Health = 100
advance(2)
check("alive again in the ring: sold, paid to the owner", C:GetAttribute("CarryMeat") == 0 and balance(owner) == before + Pricing.fishValue(1))
moveTo(C, AWAY)
advance(1)

-- an untracked piece (no ledger id): sells for nothing
asServer(function()
	local m = part("Meat", Vector3.new(-80, 9, 161), nil, Vector3.new(1.5, 0.3, 1))
	m:SetAttribute("StackIndex", 0)
	m.Parent = meatStack
end)
pickUp(1)
before = balance(owner)
moveTo(C, RING + Vector3.new(0, 3, 0))
waitFor(function()
	return (C:GetAttribute("CarryMeat") or 0) == 0
end, 5)
check("an untracked piece leaves the hands but pays nobody", C:GetAttribute("CarryMeat") == 0 and balance(owner) == before)
moveTo(C, AWAY)
advance(1)

------------------------------------------------------------ trucks still work

stackPiece(0, 1)
pickUp(1)
before = balance(owner)
local truck = ws.Trucks:GetChildren()[1]
moveTo(C, BUCKET)
waitFor(function()
	return (C:GetAttribute("CarryMeat") or 0) == 0
end, 10)
check("a truck still takes the piece (one sale, paid to the owner)", truck and truck:GetAttribute("Loaded") == 1
	and balance(owner) == before + Pricing.fishValue(1))
moveTo(C, AWAY)
advance(1)

------------------------------------------------------------ two rings: no stall

current = "server"
stallModel(RING + Vector3.new(40, 0, 0))
stall.Parent = nil -- the first ring goes; a second, separate scene check follows
stallModel(RING)
current = nil
advance(6)
stackPiece(0, 1)
pickUp(1)
before = balance(owner)
moveTo(C, RING + Vector3.new(0, 3, 0))
advance(3)
check("two rings in the place: neither sells (nothing guessed)", C:GetAttribute("CarryMeat") == 1 and balance(owner) == before)
local warned = false
for _, w in ipairs(warnings) do
	warned = warned or w:find("Sell stall: expected exactly one ring", 1, true) ~= nil
end
check("... and says why", warned)

finish("stall sim")
