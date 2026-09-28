-- Grinder dwell: the REAL dwell-patched FishSwimClient (jump version) and
-- the REAL dwell-patched RodFishingSystem (rod-cast version, offers off,
-- aquarium not taking fish -> the grinder fallback) with the REAL
-- GrinderDwell module, on the fake engine. Checks the net-caught and the
-- harpooned fish rest on the rollers ~1 s before spiralling in, and the rod
-- fallback plays the dwell server-side and fires FishCaught exactly once,
-- after the dwell.

local Economy, root = installEconomy()
local RS = services.ReplicatedStorage
local SSS = services.ServerScriptService
local ws = workspaceInst

current = "server"
local dwellModule = script("ModuleScript", "GrinderDwell", SOURCES.Dwell_Module, RS)
local GRINDER = Vector3.new(-30, 10, 0)
local SURFACE = 7.45
local river = new("Folder", "SwimmingFish")
river:SetAttribute("SurfaceY", SURFACE)
river:SetAttribute("MinZ", 0)
river:SetAttribute("MaxZ", 2000)
river:SetAttribute("GrinderPos", GRINDER)
river:SetAttribute("JumpEnabled", false)
river.Parent = ws
local function riverFish(name, seed)
	local m = new("Model", name)
	local r = part("Root", Vector3.new(0, SURFACE - 0.6, 0), m, Vector3.new(1, 1, 3))
	m._props.PrimaryPart = r
	m:SetAttribute("SwimLen", 4)
	m:SetAttribute("Seed", seed)
	m:SetAttribute("SpawnT", 0)
	m:SetAttribute("StartZ", 20)
	m:SetAttribute("Speed", 5)
	m:SetAttribute("LaneX", 0)
	m.Parent = river
	return m
end
local netted = riverFish("Netted", 11)
local harpooned = riverFish("Harpooned", 23)
current = nil

local viewer = join(1, "Viewer", Vector3.new(0, 10, 0))
local D
runAs("server", function()
	D = requireModule(dwellModule)
end)
runScript(script("LocalScript", "FishSwimClient", SOURCES.Dwell_Client), viewer)
advance(0.5)

local function dist(m)
	return (m.Root.Position - GRINDER).Magnitude
end

------------------------------------------------------------ 1) net catch (client)

local caughtAt = workspaceInst:GetServerTimeNow() + 1 / 30
asServer(function()
	netted:SetAttribute("CaughtT", caughtAt)
end)
advance(D.Rise + D.Fly + 0.1)
check("net: landed on the rollers after the flight", dist(netted) < 1.5)
local size0 = netted.Root.Size.Z
local farthest = 0
for _ = 1, 6 do
	advance(0.1)
	farthest = math.max(farthest, dist(netted))
end
check("net: stays on the rollers through the dwell", farthest < 1.6 and netted.Root.Size.Z == size0)
advance(D.Dwell - 0.7 + D.Drop * 0.8)
check("net: then spirals in and shrinks", netted.Root.Size.Z < size0 * 0.6 and netted.Root.Position.Y < GRINDER.Y - 1)
check("net: timeline is 1 s longer than the original", math.abs(D.total() - (0.12 + 0.95 + 0.55) - D.Dwell) < 1e-9)
check("net: the server acts after the client animation ends", D.serverDelay() > D.total())

------------------------------------------------------------ 2) harpooned fish (client, live harpoon branch)

local PULL, TOSS = 0.6, 0.8
local p0 = harpooned.Root.Position
asServer(function()
	harpooned:SetAttribute("HarpoonHit", p0)
	harpooned:SetAttribute("HarpoonBack", p0 + Vector3.new(0, 0, -8))
	harpooned:SetAttribute("HarpoonT", workspaceInst:GetServerTimeNow() + 1 / 30)
end)
advance(PULL + TOSS + 0.1)
check("harpoon: tossed onto the rollers", dist(harpooned) < 1.5)
local hSize = harpooned.Root.Size.Z
local look0 = harpooned.Root.CFrame.LookVector
advance(0.6)
check("harpoon: still resting on the rollers mid-dwell", dist(harpooned) < 1.6 and harpooned.Root.Size.Z == hSize)
check("harpoon: tumbling while it rests", (harpooned.Root.CFrame.LookVector - look0).Magnitude > 0.3)
advance(D.Dwell - 0.7 + 0.4)
check("harpoon: then sucked in", harpooned.Root.Size.Z < hSize * 0.7)

------------------------------------------------------------ 3) rod catch to the grinder (server fallback)

current = "server"
local fishModels = new("Folder", "FishModels")
local templates = new("Folder", "SwimTemplates")
local cod = model("Cod", fishModels, Vector3.new(0, -100, 0))
part("Fin", Vector3.new(0, -100, 1), cod)
local t = new("Model", "Cod")
t:SetAttribute("SpawnWeight", 10)
t:SetAttribute("Tier", 1)
t.Parent = templates
fishModels.Parent = RS
templates.Parent = RS
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
local rod = new("Model", "FishingRod1")
rod._props.PrimaryPart = part("Pole", Vector3.new(10, 6, 0), rod, Vector3.new(0.3, 6, 0.3))
rod.Parent = ws
-- the aquarium is running but has no room: the rod's catch goes to the grinder
local aq = {}
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
	return list
end
function aq.hook()
	return false -- refused: to the grinder
end
function aq.land()
	return false
end
function aq.abort() end
function aq.entryPoint()
	return Vector3.new(0, 0, 0)
end
aq.toTankSeconds, aq.toTankHeight = 0.3, 3
local aqModule = new("ModuleScript", "AquariumCycleServer")
aqModule.Parent = SSS
loaded[aqModule] = aq
root:SetAttribute("RodOffersEnabled", false) -- the pre-economy free path
current = nil

local fired = {}
fishCaught.Event:Connect(function(player, name)
	table.insert(fired, { t = workspaceInst:GetServerTimeNow(), name = name, player = player })
end)
runScript(script("Script", "RodFishingSystem", SOURCES.Dwell_Rod, SSS))
advance(0.3)
local presser = join(2, "Presser", Vector3.new(-5, 5, 0))
advance(0.3)
runAs(presser, function()
	pressRemote:FireServer()
end)
-- wait for the fish to reach the grinder (on the server now)
local arrived
local elapsed = 0
while not arrived and elapsed < 40 do
	advance(0.1)
	elapsed += 0.1
	for _, m in ipairs(catches:GetChildren()) do
		if m.Name == "Cod" and m.PrimaryPart and (m.PrimaryPart.Position - GRINDER).Magnitude < 1.5 then
			arrived = workspaceInst:GetServerTimeNow()
		end
	end
end
check("rod fallback: the fish reaches the grinder", arrived ~= nil)
advance(0.5)
check("rod fallback: nothing ground mid-dwell", #fired == 0)
local onRollers = false
for _, m in ipairs(catches:GetChildren()) do
	if m.Name == "Cod" and m.PrimaryPart and (m.PrimaryPart.Position - GRINDER).Magnitude < 1.6 then
		onRollers = true
	end
end
check("rod fallback: resting on the rollers", onRollers)
advance(D.Dwell + D.Drop)
check(
	"rod fallback: FishCaught fired exactly once, after the dwell",
	#fired == 1 and arrived and fired[1].t - arrived >= D.Dwell - 0.1
)
check("rod fallback: paid to the presser as before (pre-economy path)", #fired == 1 and fired[1].player == presser)
advance(5)
check("rod fallback: still exactly once", #fired == 1)

finish("dwell sim")
