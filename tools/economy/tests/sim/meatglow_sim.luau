-- Variant glow on MOVED meat: the REAL MeatGlow-patched TruckSystem and
-- BotSystem (and the patched CustomerSystem giveMeat) with the REAL
-- FishVariantVisuals + EconomyService. A Gold piece keeps its glow through
-- every fresh clone (carried stack, flights, truck load, bot carry, sale
-- table, customer's hand); plain meat never glows; value and payment are
-- unchanged; without the visuals module nothing glows and nothing breaks.

local Economy = installEconomy()
local Pricing = Economy.Pricing
local RS = services.ReplicatedStorage
local SS = services.ServerStorage
local SSS = services.ServerScriptService
local ws = workspaceInst

local owner = join(1, "Owner", Vector3.new(200, 5, 200))
local C = join(3, "Carrier", Vector3.new(200, 0, 200))

local function visuals(on)
	current = "server"
	for _, n in ipairs({ "FishVariants", "FishVariantVisuals" }) do
		local old = RS:FindFirstChild(n)
		if old then old:Destroy() end
	end
	if on then
		script("ModuleScript", "FishVariants", SOURCES.Var_Rules, RS)
		script("ModuleScript", "FishVariantVisuals", SOURCES.Var_Visuals, RS)
	end
	current = nil
end
local function glows(p)
	return p ~= nil and p:FindFirstChild("VariantFxAtt") ~= nil
end
local function waitFor(cond, limit)
	local t = 0
	while not cond() and t < limit do
		advance(0.25)
		t += 0.25
	end
	return cond()
end
-- one piece of the owner's meat on top of the stack (as the grinder leaves it)
local function stackPiece(stack, index, variant)
	return asServer(function()
		local id = Economy.issueFish(owner, "Cod", 1, { Source = "Net", Variant = variant })[1]
		local m = part("Meat", Vector3.new(-80, 9, 161 + index), nil, Vector3.new(1.5, 0.3, 1))
		Economy.stamp(m, id)
		m:SetAttribute("StackIndex", index)
		m.Parent = stack
		return id
	end)
end

------------------------------------------------------------ scene: stack, template, trucks

current = "server"
local meatStack = new("Folder", "MeatStack")
meatStack.Parent = ws
local template = part("MeatTemplate", Vector3.new(0, -50, 0), SS, Vector3.new(1.5, 0.3, 1))
script(
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
van:SetAttribute("NeedMin", 4)
van:SetAttribute("NeedMax", 4)
van:SetAttribute("BucketOffset", Vector3.new(0, 2, 0))
truckTypes.Parent = SS
new("Folder", "Trucks").Parent = ws
local truckEvents = new("Folder", "TruckEvents")
new("BindableEvent", "MeatDelivered").Parent = truckEvents
new("BindableEvent", "TruckFilled").Parent = truckEvents
truckEvents.Parent = SS
current = nil

local STACK_SPOT = Vector3.new(-78.4, 10.05, 160)
local BUCKET = Vector3.new(0, 2, 40)
local AWAY = Vector3.new(200, 0, 200)

------------------------------------------------------------ 1) trucks: carried stack, flights, loaded meat

visuals(true)
local flyers = { glow = 0, plain = 0 }
ws.ChildAdded:Connect(function(p)
	if p.Name == "MeatTemplate" then -- flyPart's clone (glow is applied before parenting)
		if glows(p) then flyers.glow += 1 else flyers.plain += 1 end
	end
end)
local truckScript = script("Script", "TruckSystem", SOURCES.MG_Truck, SSS)
runScript(truckScript)
asServer(function()
	ws:SetAttribute("CarsUnlocked", true)
	ws:SetAttribute("CarsMaxQueue", 1)
end)
advance(40)
check("a truck is waiting", #ws.Trucks:GetChildren() == 1)

local plainId = stackPiece(meatStack, 0, nil)
local goldId = stackPiece(meatStack, 1, "Gold") -- on top: picked first
moveTo(C, STACK_SPOT)
waitFor(function() return (C:GetAttribute("CarryMeat") or 0) == 2 end, 10)
local carriedFolder = C.Character:FindFirstChild("CarriedMeat")
local held = carriedFolder and carriedFolder:GetChildren() or {}
check("carrier holds both pieces", #held == 2)
local glowing = 0
for _, p in ipairs(held) do
	if glows(p) then glowing += 1 end
end
check("carried stack: exactly the Gold piece glows", glowing == 1)
check("pick-up flights: the Gold one glows, the plain one doesn't", flyers.glow == 1 and flyers.plain == 1)

local before = balance(owner)
moveTo(C, BUCKET)
waitFor(function() return (C:GetAttribute("CarryMeat") or 0) == 0 end, 20)
advance(1)
moveTo(C, AWAY)
local truck = ws.Trucks:GetChildren()[1]
local loadedGlow, loaded = 0, 0
for _, p in ipairs(truck and truck:GetChildren() or {}) do
	if p.Name == "LoadedMeat" then
		loaded += 1
		if glows(p) then loadedGlow += 1 end
	end
end
check("both pieces loaded, only the Gold one glows in the truck", loaded == 2 and loadedGlow == 1)
check("delivery flights: one more Gold flight", flyers.glow == 2 and flyers.plain == 2)
check(
	"payment unchanged: Gold x5 + plain, once each",
	balance(owner) == before + 5 * Pricing.fishValue(1) + Pricing.fishValue(1)
)
local _ = plainId and goldId

-- the carried glow list stays in step when pieces leave from the top
local g2 = stackPiece(meatStack, 0, "Gold")
local p2 = stackPiece(meatStack, 1, nil) -- on top: picked first
moveTo(C, STACK_SPOT)
waitFor(function() return (C:GetAttribute("CarryMeat") or 0) == 2 end, 10)
moveTo(C, AWAY)
held = C.Character.CarriedMeat:GetChildren()
check("second load: the plain piece (picked first) doesn't glow, the Gold one on it does", #held == 2 and not glows(held[1]) and glows(held[2]))
local _ = g2 and p2
respawn(C, AWAY)
advance(0.5)
check("respawn while carrying: pieces held, as before", Economy.heldCount() == 2)
truckScript:Destroy()

------------------------------------------------------------ 2) the Blender Bot (recovery version) and the sale table

-- a fresh stack per scene: a Destroy()ed script's threads keep running in
-- the fake engine, so an old bot must not see the new scene's meat
local function botScene()
	current = "server"
	for _, n in ipairs({ "Blender Bot", "SaleMeat", "SaleTable", "MeatStack" }) do
		local old = ws:FindFirstChild(n)
		if old then old:Destroy() end
	end
	meatStack = new("Folder", "MeatStack")
	meatStack.Parent = ws
	local bot = model("Blender Bot", ws, Vector3.new(-84.5, 10, 156))
	new("Folder", "SaleMeat").Parent = ws
	local tbl = part("SaleTable", Vector3.new(-80, 8, 152), ws)
	tbl:SetAttribute("SlotCount", 2)
	tbl:SetAttribute("Slot1", Vector3.new(-82, 9, 152))
	tbl:SetAttribute("Slot2", Vector3.new(-82, 9, 150))
	current = nil
	return bot
end
local function carriedByBot()
	for _, c in ipairs(ws:GetChildren()) do
		if c.Name == "CarriedMeat" then return c end
	end
	return nil
end

for _, label in ipairs({ "bot", "sales" }) do
	botScene()
	local sc = script("Script", "BotSystem", SOURCES["MG_Bot_" .. label], SSS)
	runScript(sc)
	local id = stackPiece(meatStack, 0, "Gold")
	waitFor(function() return carriedByBot() ~= nil end, 30)
	check(label .. " bot: the carried Gold piece glows", glows(carriedByBot()))
	waitFor(function() return #ws.SaleMeat:GetChildren() == 1 end, 30)
	local onTable = ws.SaleMeat:GetChildren()[1]
	check(label .. " bot: on the table it still glows, same piece", glows(onTable) and onTable:GetAttribute("PieceId") == id)
	onTable:Destroy()
	stackPiece(meatStack, 0, nil)
	waitFor(function() return #ws.SaleMeat:GetChildren() == 1 end, 30)
	check(label .. " bot: plain meat doesn't glow", not glows(ws.SaleMeat:GetChildren()[1]))
	sc:Destroy()
end

------------------------------------------------------------ 3) the customer's hand (patched giveMeat, run on its own)

do
	local src = SOURCES.MG_Customer
	local load = src:match("(%-%- MeatGlow: optional effects module.-)%-%- tuning")
	local give = src:match("(local function giveMeat%(c, meat%).-\nend\n)")
	check("customer: the patch has the loader and giveMeat", load ~= nil and give ~= nil)
	local chunk = "local meatTemplate = ...\n" .. (load or "") .. (give or "") .. "return giveMeat\n"
	local fn = assert(loadstring(chunk, "=giveMeat"))
	setfenv(fn, envFor(script("Script", "CustomerSystem", "")))
	local giveMeat = asServer(fn, template)
	local function customer()
		current = "server"
		local m = model("Friend", ws, Vector3.new(-94.8, 9.3, 152.5))
		local hrp = part("HumanoidRootPart", Vector3.new(-94.8, 9.3, 152.5), m)
		current = nil
		return { model = m, hrp = hrp }
	end
	for _, case in ipairs({ { "Gold", true }, { nil, false } }) do
		local cust = customer()
		local meat = asServer(function()
			local p = template:Clone()
			p:SetAttribute("Variant", case[1])
			p.Parent = ws
			return p
		end)
		runAs("server", function()
			task.spawn(giveMeat, cust, meat)
		end)
		advance(1)
		local inHand
		for _, ch in ipairs(cust.model:GetChildren()) do
			if ch.Name == "MeatTemplate" then inHand = ch end
		end
		check("customer: " .. tostring(case[1]) .. " piece in hand " .. (if case[2] then "glows" else "doesn't glow"),
			inHand ~= nil and glows(inHand) == case[2])
	end
end

------------------------------------------------------------ 4) without FishVariantVisuals: no glow, no errors

visuals(false)
botScene()
local sc = script("Script", "BotSystem", SOURCES.MG_Bot_bot, SSS)
runScript(sc)
stackPiece(meatStack, 0, "Gold")
waitFor(function() return #ws.SaleMeat:GetChildren() == 1 end, 30)
check("no visuals module: the bot still works, nothing glows", #ws.SaleMeat:GetChildren() == 1 and not glows(ws.SaleMeat:GetChildren()[1]))
sc:Destroy()

finish("meat glow sim")
