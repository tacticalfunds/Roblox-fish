-- The REAL RodFishingSystem (rod-cast on top of the sale-payout version)
-- and the REAL RodFishingClient (rod-cast) end to end on the fake engine,
-- with the real EconomyService + EconomyClient and a recording stub
-- aquarium. Checks:
--   * a press casts every eligible rod at once, immediately (CastT0 in the
--     same frame, no press delay, no stagger); spam and a second player
--     can't double-cast; a refused press doesn't animate the button
--   * rods dip toward the water (+X) on the client the moment they cast
--   * offer mode: the hooked fish carries its caster as OwnerId; the caster
--     buys at the rod stand with the prompt; unbought fish are aborted
--   * RodOffersEnabled = false: the old free rod -> aquarium path, no owner

local Economy, root = installEconomy()
local RS = services.ReplicatedStorage
local SSS = services.ServerScriptService
local ws = workspaceInst

------------------------------------------------------------ the scene

current = "server"
local fishModels = new("Folder", "FishModels")
local templates = new("Folder", "SwimTemplates")
for i, spec in ipairs({ { "Cod", 50, 1 }, { "Salmon", 20, 10 }, { "Tuna", 5, 14 } }) do
	local m = model(spec[1], fishModels, Vector3.new(0, -100, i * 5))
	part("Fin", Vector3.new(0, -100, i * 5 + 1), m)
	local t = new("Model", spec[1])
	t:SetAttribute("SpawnWeight", spec[2])
	t:SetAttribute("Tier", spec[3])
	t.Parent = templates
end
fishModels.Parent = RS
templates.Parent = RS
local pressRemote = new("RemoteEvent", "PressFishButton")
pressRemote.Parent = RS

local bigButton = new("Model", "BigButton")
local btn = new("Model", "Button")
local body = part("Body", Vector3.new(0, 5, 0), btn, Vector3.new(1, 3, 3))
btn._props.PrimaryPart = body
btn.Parent = bigButton
bigButton.Parent = ws
new("Folder", "RodCatches").Parent = ws
local netLift = new("Model", "NetLift")
local fishCaught = new("BindableEvent", "FishCaught")
fishCaught.Parent = netLift
netLift.Parent = ws
local river = new("Folder", "SwimmingFish")
river:SetAttribute("GrinderPos", Vector3.new(-30, 10, 0))
river.Parent = ws

-- three rods on the dock, tips out over the river (+X)
local rods = {}
for i, z in ipairs({ -6, 0, 6 }) do
	local rod = new("Model", "FishingRod1")
	local pole = part("Pole", Vector3.new(10, 6, z), rod, Vector3.new(0.3, 6, 0.3))
	rod._props.PrimaryPart = pole
	rod.Parent = ws
	rods[i] = rod
end

-- recording stub aquarium (capacity 3, like the tank)
local aq =
	{ capacity = 3, count = 0, reserved = {}, hooks = {}, hookLog = {}, landed = 0, aborted = 0, reserveCalls = 0 }
local function reservedCount()
	local n = 0
	for _ in pairs(aq.reserved) do
		n += 1
	end
	return n
end
function aq.start()
	return true
end
function aq.active()
	return true
end
function aq.hasFreeSpot()
	return aq.count + reservedCount() < aq.capacity
end
function aq.reserve(list)
	aq.reserveCalls += 1
	local out = {}
	if aq.denyReserve then
		return out -- the spot went elsewhere between the check and the press
	end
	for _, rod in ipairs(list) do
		if aq.count + reservedCount() < aq.capacity and not aq.reserved[rod.key] then
			aq.reserved[rod.key] = true
			table.insert(out, rod)
		end
	end
	return out
end
function aq.hook(key, name, meta)
	if not aq.reserved[key] then
		return false
	end
	aq.hooks[key] = { name = name, meta = meta }
	table.insert(aq.hookLog, { key = key, name = name, meta = meta })
	return true
end
function aq.land(key)
	if not aq.hooks[key] then
		return false
	end
	aq.hooks[key] = nil
	aq.reserved[key] = nil
	aq.count += 1
	aq.landed += 1
	return true
end
function aq.abort(key)
	if aq.reserved[key] then
		aq.aborted += 1
	end
	aq.reserved[key] = nil
	aq.hooks[key] = nil
end
function aq.entryPoint()
	return Vector3.new(-10, 12, 0)
end
aq.toTankSeconds = 0.3
aq.toTankHeight = 3
local aqModule = new("ModuleScript", "AquariumCycleServer")
aqModule.Parent = SSS
loaded[aqModule] = aq
current = nil

local caster = join(1, "Caster", Vector3.new(-20, 5, 0))
local other = join(2, "Other", Vector3.new(-20, 5, 4))
runScript(script("Script", "RodFishingSystem", SOURCES.RodCast_Server, SSS))
runScript(script("LocalScript", "RodFishingClient", SOURCES.RodCast_Client), caster)
advance(0.5)

local function press(p)
	runAs(p, function()
		pressRemote:FireServer()
	end)
end
local function castT0(i)
	return rods[i]:GetAttribute("CastT0")
end

------------------------------------------------------------ 1) immediate cast

local function tipX(i)
	return (rods[i].Pole.CFrame * Vector3.new(0, 3, 0)).X -- the pole's top end
end
local tipX0 = tipX(1)
local pressedBefore = bigButton:GetAttribute("PressedAt")
press(caster)
check("same frame: every rod cast at once (CastT0 on all three)", castT0(1) and castT0(2) and castT0(3))
check("all three got the same cast time (no stagger)", castT0(1) == castT0(2) and castT0(2) == castT0(3))
check("the button animates for others", bigButton:GetAttribute("PressedAt") ~= pressedBefore)
check("one reservation for the press", aq.reserveCalls == 1 and reservedCount() == 3)
local stamp = bigButton:GetAttribute("PressedAt")
press(caster) -- spam
advance(0.7) -- past the per-player cooldown
press(other) -- a second player while every rod is busy
advance(0.3)
check("spam / second player: no second cast", aq.reserveCalls == 1 and bigButton:GetAttribute("PressedAt") == stamp)
check("client: rods dip toward the water (+X) right away", tipX(1) > tipX0 + 0.3)

------------------------------------------------------------ 2) offers at the rod stands

local stands = ws:FindFirstChild("EconomyBuyStands")
local function standsList()
	return stands and stands:GetChildren() or {}
end
local t = 0
while #standsList() < 3 and t < 40 do
	advance(0.5)
	t += 0.5
end
check("three offers open (one per rod)", #standsList() == 3)
check("CastT0 cleared once reeling starts", castT0(1) == nil and castT0(2) == nil and castT0(3) == nil)
local ownerOk = #aq.hookLog == 3
for _, h in ipairs(aq.hookLog) do
	ownerOk = ownerOk and type(h.meta) == "table" and h.meta.OwnerId == caster.UserId
end
check("each hooked fish carries its caster as OwnerId", ownerOk)
check("nothing in the tank before buying", aq.landed == 0)

-- buy the first offer at its rod stand (walk up + E)
local first = standsList()[1]
local price = first:GetAttribute("Price")
local standPos = first.Position
moveTo(caster, standPos + Vector3.new(-3, 0, 0))
advance(0.2)
local prompt = nil
for _, d in ipairs(first:GetChildren()) do
	if d.ClassName == "ProximityPrompt" then
		prompt = d
	end
end
check("the caster's prompt sits on the rod stand", prompt ~= nil)
if prompt then
	runAs(caster, function()
		prompt.Triggered:Fire(caster)
	end)
end
advance(2)
check("bought: charged once, landed in the tank", balance(caster) == 100 - price and aq.landed == 1)

-- the rest time out: aborted, nothing charged
advance(25)
check("unbought fish aborted, not charged", aq.aborted == 2 and balance(caster) == 100 - price and #standsList() == 0)
check("button ready again", bigButton:GetAttribute("Ready") == true)

------------------------------------------------------------ 3) a full tank refuses without animating

aq.count = aq.capacity
local calls = aq.reserveCalls
local stamp2 = bigButton:GetAttribute("PressedAt")
moveTo(caster, Vector3.new(-20, 5, 0))
advance(1)
press(caster)
advance(0.2)
check(
	"full tank: nothing cast, no button animation",
	castT0(1) == nil and aq.reserveCalls == calls and bigButton:GetAttribute("PressedAt") == stamp2
)
aq.count = 0
-- the tank says there's room, but the reservation fails (lost race): the press
-- is refused inside press() -> nothing cast, no animation
aq.denyReserve = true
advance(1)
press(caster)
advance(0.2)
check(
	"lost reservation: nothing cast, no button animation",
	castT0(1) == nil and bigButton:GetAttribute("PressedAt") == stamp2
)
check("lost reservation: button still ready", bigButton:GetAttribute("Ready") == true)
aq.denyReserve = false

------------------------------------------------------------ 4) offers switched off: the old free path

asServer(function()
	root:SetAttribute("RodOffersEnabled", false)
end)
local landed0, log0 = aq.landed, #aq.hookLog
advance(1)
press(caster)
check("offers off: rods still cast immediately", castT0(1) ~= nil)
t = 0
while aq.landed < landed0 + 3 and t < 40 do
	advance(0.5)
	t += 0.5
end
check("offers off: free rod fish land in the tank (pre-economy behaviour)", aq.landed == landed0 + 3)
local noOwner = true
for i = log0 + 1, #aq.hookLog do
	noOwner = noOwner and aq.hookLog[i].meta == nil
end
check("offers off: no owner claimed for free fish", noOwner)
check("offers off: no charge", balance(caster) == 100 - price)

finish("rod sim")
