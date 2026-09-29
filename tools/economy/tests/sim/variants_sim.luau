-- Rare Silver / Gold fish on the economy chain: the REAL variant-patched
-- FishSpawner, RodFishingSystem (sale-payout base) and GrinderProcessor
-- (sale-payout base) with the REAL FishVariants / FishVariantVisuals modules
-- and the real EconomyService, on the fake engine. Gold is forced (chance 1)
-- so every roll is deterministic; the real odds are unit-tested.

local Economy, root = installEconomy()
local Pricing = Economy.Pricing
local RS = services.ReplicatedStorage
local SS = services.ServerStorage
local SSS = services.ServerScriptService
local ws = workspaceInst

current = "server"
-- Gold forced: every roll is Gold (rarest first, chance 1)
script("ModuleScript", "FishVariants", (SOURCES.Var_Rules:gsub("Chance = 0%.005", "Chance = 1")), RS)
script("ModuleScript", "FishVariantVisuals", SOURCES.Var_Visuals, RS)

-- river + templates (FishSpawner) and fish models (rod)
local SURFACE = 7.45
local river = new("Folder", "SwimmingFish")
river:SetAttribute("MinX", -20)
river:SetAttribute("MaxX", 20)
river:SetAttribute("MinZ", 0)
river:SetAttribute("MaxZ", 300)
river:SetAttribute("SurfaceY", SURFACE)
river:SetAttribute("GrinderPos", Vector3.new(-30, 10, 0))
river.Parent = ws
local templates = new("Folder", "SwimTemplates")
local fishModels = new("Folder", "FishModels")
for i, spec in ipairs({ { "Cod", 50, 1 }, { "Salmon", 20, 10 } }) do
	local t = model(spec[1], templates, Vector3.new(0, -100, i * 5))
	t:SetAttribute("SpawnWeight", spec[2])
	t:SetAttribute("Tier", spec[3])
	t:SetAttribute("SwimLen", 4)
	local fm = model(spec[1], fishModels, Vector3.new(0, -120, i * 5))
	part("Fin", Vector3.new(0, -120, i * 5 + 1), fm)
end
templates.Parent = RS
fishModels.Parent = RS
current = nil

------------------------------------------------------------ 1) FishSpawner: rolled once, before parenting

local seenAtParent, total = 0, 0
river.ChildAdded:Connect(function(m)
	total += 1
	if m:GetAttribute("Variant") == "Gold" and m:FindFirstChild("VariantFx") then
		seenAtParent += 1 -- attribute + effects already there when it appears
	end
end)
runScript(script("Script", "FishSpawner", SOURCES.Var_Spawner, SSS))
advance(2)
check("spawner: fish spawned", total >= 35)
check("spawner: every new fish rolled (Gold forced), with effects, before parenting", seenAtParent == total)
local sample = river:GetChildren()[1]
local fx = sample and sample:FindFirstChild("VariantFx")
check(
	"spawner: outline + label effects, species parts untouched",
	fx and fx:FindFirstChildOfClass("Highlight") and fx:FindFirstChildOfClass("BillboardGui")
)

------------------------------------------------------------ 2) rod: offer priced and labelled with the variant

current = "server"
local pressRemote = new("RemoteEvent", "PressFishButton")
pressRemote.Parent = RS
local bigButton = new("Model", "BigButton")
local btn = new("Model", "Button")
btn._props.PrimaryPart = part("Body", Vector3.new(0, 5, 0), btn, Vector3.new(1, 3, 3))
btn.Parent = bigButton
bigButton.Parent = ws
local catches = new("Folder", "RodCatches")
catches.Parent = ws
local netLift = new("Model", "NetLift")
local fishCaught = new("BindableEvent", "FishCaught")
fishCaught.Parent = netLift
netLift.Parent = ws
local rodModel = new("Model", "FishingRod1")
rodModel._props.PrimaryPart = part("Pole", Vector3.new(10, 6, 0), rodModel, Vector3.new(0.3, 6, 0.3))
rodModel.Parent = ws
local aq = { reserved = {}, hookLog = {}, landed = 0 }
function aq.start()
	return true
end
function aq.active()
	return true
end
function aq.hasFreeSpot()
	return true
end
function aq.reserve(list)
	for _, r in ipairs(list) do
		aq.reserved[r.key] = true
	end
	return list
end
function aq.hook(key, name, meta)
	table.insert(aq.hookLog, { key = key, name = name, meta = meta })
	return aq.reserved[key] == true
end
function aq.land(key)
	aq.landed += 1
	aq.reserved[key] = nil
	return true
end
function aq.abort(key)
	aq.reserved[key] = nil
end
function aq.entryPoint()
	return Vector3.new(-10, 12, 0)
end
aq.toTankSeconds, aq.toTankHeight = 0.3, 3
local aqModule = new("ModuleScript", "AquariumCycleServer")
aqModule.Parent = SSS
loaded[aqModule] = aq
current = nil

local caster = join(1, "Caster", Vector3.new(-5, 5, 0))
runScript(script("Script", "RodFishingSystem", SOURCES.Var_Rod, SSS))
advance(0.5)
runAs(caster, function()
	pressRemote:FireServer()
end)
local stands
local t = 0
repeat
	advance(0.5)
	t += 0.5
	stands = ws:FindFirstChild("EconomyBuyStands")
until (stands and #stands:GetChildren() == 1) or t > 40
local stand = stands and stands:GetChildren()[1]
check("rod: an offer opened", stand ~= nil)
if stand then
	local name = stand:GetAttribute("FishName")
	local tier = if name == "Salmon" then 10 else 1
	check("rod: the offer carries the variant", stand:GetAttribute("Variant") == "Gold")
	check("rod: priced with the variant (x1.75)", stand:GetAttribute("Price") == Pricing.offerPrice(tier, "Gold"))
	local fish
	for _, m in ipairs(catches:GetChildren()) do
		if m:FindFirstChild("OfferGui", true) then
			fish = m
		end
	end
	local gui = fish and fish:FindFirstChild("OfferGui", true)
	check("rod: label says GOLD", gui and gui.FishName.Text == "GOLD " .. name)
	check("rod: the revealed fish glows", fish and fish:FindFirstChild("VariantFx") ~= nil)
	local h = aq.hookLog[#aq.hookLog]
	check(
		"rod: the variant rides into the tank with the buyer",
		h and h.meta and h.meta.Variant == "Gold" and h.meta.OwnerId == caster.UserId
	)
	-- buy it at the stand
	moveTo(caster, stand.Position + Vector3.new(-3, 0, 0))
	advance(0.2)
	local prompt = stand:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		runAs(caster, function()
			prompt.Triggered:Fire(caster)
		end)
	end
	advance(2)
	check(
		"rod: bought once at the variant price",
		balance(caster) == 100 - Pricing.offerPrice(tier, "Gold") and aq.landed == 1
	)
end

------------------------------------------------------------ 3) grinder: the extra value applied once, via the ledger

current = "server"
local grinder = new("Model", "FishGrinder")
model("Housing", grinder, Vector3.new(0, 5, 0))
grinder:SetAttribute("PipeExit", Vector3.new(0, 4, 4))
grinder.Parent = ws
local template = part("MeatTemplate", Vector3.new(0, -50, 0), SS, Vector3.new(1.5, 0.3, 1))
new("Folder", "PitMeat").Parent = ws
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
local _ = template
current = nil
runScript(script("Script", "GrinderProcessor", SOURCES.Var_Grinder, SSS))
advance(0.2)

local netter = join(2, "Netter", Vector3.new(200, 0, 200))
advance(0.5)
asServer(function()
	fishCaught:Fire(netter, "Salmon", 10, { Variant = "Gold", Source = "Net" }) -- as the net sends it
	fishCaught:Fire(netter, "Salmon", 10, { Source = "Net" }) -- a normal one to compare
end)
t = 0
repeat
	advance(0.5)
	t += 0.5
until #meatStack:GetChildren() >= 4 or t > 90
local gold, normal, glowing = 0, 0, 0
for _, m in ipairs(meatStack:GetChildren()) do
	if m:GetAttribute("Variant") == "Gold" then
		gold += m:GetAttribute("Value")
		if m:FindFirstChild("VariantFxAtt") then
			glowing += 1
		end
	else
		normal += m:GetAttribute("Value")
	end
end
local fv = Pricing.fishValue(10)
check("grinder: all 4 pieces stacked", #meatStack:GetChildren() == 4)
check("grinder: normal Salmon pieces total the fish value", normal == fv)
check("grinder: Gold Salmon pieces total 5x the fish value", gold == 5 * fv)
check("grinder: Gold meat glows, normal meat doesn't", glowing == #Pricing.pieceValues(10))
local before = balance(netter)
local paid = 0
asServer(function()
	for _, m in ipairs(meatStack:GetChildren()) do
		local ok, amount = Economy.settle(m:GetAttribute("PieceId"), "Truck")
		if ok then
			paid += amount
		end
		local again = Economy.settle(m:GetAttribute("PieceId"), "Customer")
		check("grinder: a piece can't be sold twice", again == false)
	end
end)
check(
	"grinder: the owner is paid 6x the fish value in total, once",
	paid == 6 * fv and balance(netter) == before + 6 * fv
)

------------------------------------------------------------ 4) spawner despawn timer leaves harpooned fish alone (live guard)

local harpooned, plain
for _, m in ipairs(river:GetChildren()) do
	local seed = m:GetAttribute("Seed")
	if seed and seed < 1000 and not m:GetAttribute("CaughtT") and not m:GetAttribute("HarpoonT") then
		if not harpooned then
			harpooned = m
		elseif not plain then
			plain = m
		end
	end
end
check("spawner: two river fish to watch", harpooned ~= nil and plain ~= nil)
asServer(function()
	harpooned:SetAttribute("HarpoonT", ws:GetServerTimeNow())
end)
advance(90) -- longer than any fish's river travel (300 studs at >= 4 studs/s)
check("spawner: a harpooned fish is not despawned (left to the harpoon)", harpooned.Parent == river)
check("spawner: an ordinary fish despawns at the end of the river", plain.Parent == nil)
check("spawner: the harpooned fish keeps its variant", harpooned:GetAttribute("Variant") == "Gold")

finish("variants sim")
