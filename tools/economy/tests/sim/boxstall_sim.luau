-- The live TruckSystem as RECONSTRUCTED from Astra's description (BoxMeat
-- pickup + the Sell stall, build/make_box.py), the REAL EconomyService:
--   * meat is picked up from the meat box (Workspace.BoxMeat) as well as the
--     stack, the top piece of whichever you stand at, up to MAX_CARRY
--   * box meat sells at the Sell stall through the same ledger sale (paid
--     once to the owner); trucks still work
-- (Not the exact live text: Astra's merged source replaces it when sent.)

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
current = "server"
local boxMeat = new("Folder", "BoxMeat")
boxMeat.Parent = ws
current = nil
runScript(script("Script", "TruckSystem", SOURCES.Box_Stall_Truck, SSS))
asServer(function()
	ws:SetAttribute("CarsUnlocked", true)
	ws:SetAttribute("CarsMaxQueue", 1)
end)
advance(40)

local BOX_SPOT = Vector3.new(-37, 10.05, 148.7)
local function boxPiece(index, tier)
	return asServer(function()
		local id = Economy.issueFish(owner, "Cod", tier or 1, { Source = "Net" })[1]
		local m = part("Meat", BOX_SPOT + Vector3.new(0, -1, index), nil, Vector3.new(1.5, 0.3, 1))
		Economy.stamp(m, id)
		m:SetAttribute("StackIndex", index)
		m.Parent = boxMeat
		return id
	end)
end

------------------------------------------------------------ the meat box

boxPiece(0, 1)
boxPiece(1, 4)
moveTo(C, BOX_SPOT)
waitFor(function()
	return (C:GetAttribute("CarryMeat") or 0) == 2
end, 10)
check("standing at the meat box picks its pieces up", C:GetAttribute("CarryMeat") == 2 and carriedParts() == 2
	and #boxMeat:GetChildren() == 0)
stackPiece(0, 1)
moveTo(C, STACK_SPOT)
waitFor(function()
	return (C:GetAttribute("CarryMeat") or 0) == 3
end, 10)
check("... and the conveyor's stack still works", C:GetAttribute("CarryMeat") == 3 and #meatStack:GetChildren() == 0)
local before = balance(owner)
moveTo(C, RING + Vector3.new(0, 3, 0))
waitFor(function()
	return (C:GetAttribute("CarryMeat") or 0) == 0
end, 5)
check("box and stack meat sell at the stall: paid once each to the owner", C:GetAttribute("CarryMeat") == 0
	and balance(owner) == before + 2 * Pricing.fishValue(1) + Pricing.fishValue(4) and Economy.heldCount() == 0)
moveTo(C, AWAY)
advance(1)

-- a full load: standing at the box takes no more
for i = 0, 11 do
	boxPiece(i, 1)
end
moveTo(C, BOX_SPOT)
advance(4)
check("at the box with a full load (10): no more picked up", C:GetAttribute("CarryMeat") == 10 and #boxMeat:GetChildren() == 2)

finish("box stall sim")
