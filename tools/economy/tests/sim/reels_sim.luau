-- Upgrade board, milestone 4 (Faster Reels): the REAL EconomyService, the
-- REAL UpgradeBoardServer + UpgradeBoardClient and the REAL upgrade-board
-- RodFishingSystem on the fake engine (the luck sim's scene). Per cast it
-- measures each rod's reel (Pulling on -> off on the rod model), the Dur the
-- clients animate the rising fish over, and the bite wait. Checks:
--   * Faster Reels closed by default; open: 1x -> 1.2x for $10, money +
--     level in one write; card 1.2x > 1.35x, $100
--   * the caster's reel: 3.4 s at 1x, 3.4 / 1.2 at 1.2x - the server's
--     timing AND the Dur the clients animate with; fixed at the press
--   * the bite wait is NOT shortened by it (that is the rod's benefit)
--   * another player's casts keep 3.4 s

math.randomseed(20260930)
local Economy, root = installEconomy()
local RS = services.ReplicatedStorage
local SSS = services.ServerScriptService
local ws = workspaceInst
local KEY = Economy.Config.KeyPrefix
local MAIN = Vector3.new(-72.84, 21.08, 136.48)
local NEAR_BOARD = MAIN + Vector3.new(0, -7, 6)
local NEAR_BUTTON = Vector3.new(-20, 5, 0)

current = "server"
-- the board
local board = new("Model", "Board")
local main = part("Main", MAIN, board, Vector3.new(19.53, 9.34, 0.85))
local surface = new("SurfaceGui", "SurfaceGui")
local bord = new("Frame", "bord3")
new("UIListLayout", "UIListLayout").Parent = bord
new("Frame", "Frame").Parent = bord
bord.Parent = surface
surface.Parent = main
board.Parent = ws
-- the fishing scene (as in rods_sim)
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
local aq = {}
function aq.start() return true end
function aq.active() return true end
function aq.hasFreeSpot() return true end
function aq.reserve(list) return list end
function aq.hook() return true end
function aq.land() return true end
function aq.abort() end
function aq.entryPoint() return Vector3.new(-10, 12, 0) end
aq.toTankSeconds, aq.toTankHeight = 0.3, 3
local aqModule = new("ModuleScript", "AquariumCycleServer")
aqModule.Parent = SSS
loaded[aqModule] = aq
current = nil

dsData[KEY .. "1"] = { v = 2, money = 1000 }
dsData[KEY .. "2"] = { v = 2, money = 1000 }
local F = join(1, "Fast", NEAR_BOARD)
local N = join(2, "Normal", NEAR_BUTTON + Vector3.new(0, 0, 4))
runScript(script("Script", "UpgradeBoardServer", SOURCES.Board_Server, SSS))
runScript(script("Script", "RodFishingSystem", SOURCES.Board_Fishing, SSS))
for _, p in ipairs({ F, N }) do
	runAs(p, function()
		runScript(script("LocalScript", "UpgradeBoardClient", SOURCES.Board_Client), p)
	end)
end
advance(1.5)

-- every catch: which fish, whose cast, the chance the offer shows
local offers = {}
Economy.runRodOffer = function(args)
	table.insert(offers, { fish = args.fishName, caster = args.caster, chance = args.chance })
	return false -- passed: the fish slips back into the water
end
local function card(p, id)
	local g = p.PlayerGui:FindFirstChild("UpgradeBoard")
	return g and g.bord3:FindFirstChild(id)
end
local function value(p, id)
	return card(p, id).Value.Text
end
local function price(p, id)
	return card(p, id).Buy.Price.Text
end
local function pressCard(p, id)
	click(p, card(p, id).Buy)
	advance(0.7)
end
-- one press of the fish button: per rod, the fish's reel Dur, the reel's
-- real length (Pulling on -> off) and the bite wait (cast -> Bite)
local function cast(p, during)
	local before = #offers
	local reels, durs, bites = {}, {}, {}
	local conns = {}
	for _, rod in ipairs(dock) do
		local pullStart = nil
		table.insert(conns, rod:GetAttributeChangedSignal("Pulling"):Connect(function()
			if rod:GetAttribute("Pulling") and not pullStart then
				pullStart = now
			elseif not rod:GetAttribute("Pulling") and pullStart and not reels[rod] then
				reels[rod] = now - pullStart
			end
		end))
	end
	table.insert(conns, catches.ChildAdded:Connect(function(m)
		local d = m:GetAttribute("Dur")
		if type(d) == "number" then
			table.insert(durs, d)
		end
		if m.Name == "Bobber" then
			local t0 = now
			m:GetAttributeChangedSignal("Bite"):Connect(function()
				if m:GetAttribute("Bite") then
					table.insert(bites, now - t0)
				end
			end)
		end
	end))
	runAs(p, function()
		pressRemote:FireServer()
	end)
	if during then
		advance(0.1)
		during()
	end
	local t = 0
	while #offers < before + 3 and t < 40 do
		advance(0.05)
		t += 0.05
	end
	advance(2)
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	local out = {}
	for _, v in pairs(reels) do
		table.insert(out, v)
	end
	return out, durs, bites
end
local function all(list, pred)
	if #list == 0 then
		return false
	end
	for _, v in ipairs(list) do
		if not pred(v) then
			return false
		end
	end
	return true
end
local function about(x, want)
	return math.abs(x - want) <= 0.12
end

------------------------------------------------------------ the card

local function value(p, id)
	return card(p, id).Value.Text
end
check("Faster Reels card: 1x > 1.2x, SOON while closed", value(F, "FasterReels") == "1x > 1.2x" and price(F, "FasterReels") == "SOON")
pressCard(F, "FasterReels")
check("closed by default: refused, not charged", lastNotice(F) == "Faster Reels upgrades open soon" and Economy.balance(F) == 1000)
advance(1)

moveTo(F, NEAR_BUTTON)
advance(0.5)
local r0, d0, b0 = cast(F)
check("before buying: each rod reels for 3.4 s", #r0 == 3 and all(r0, function(x)
	return about(x, 3.4)
end))
check("before buying: the clients animate over Dur 3.4", all(d0, function(x)
	return x == 3.4
end))

root:SetAttribute("UpgradesOpen", true)
advance(0.1)
moveTo(F, NEAR_BOARD)
local writes = 0
dsHooks.before = function()
	writes += 1
end
pressCard(F, "FasterReels")
dsHooks.before = nil
check("bought: Faster Reels 1x → 1.2x (-$10), one write", lastNotice(F) == "Faster Reels 1x → 1.2x (-$10)" and Economy.balance(F) == 990
	and writes == 1 and dsData[KEY .. "1"].upgrades.FasterReels == 1)
advance(2)
check("card: 1.2x > 1.35x, $100", value(F, "FasterReels") == "1.2x > 1.35x" and price(F, "FasterReels") == "$100")

moveTo(F, NEAR_BUTTON)
advance(0.5)
local fastReels, fastDurs, fastBites = {}, {}, {}
for _ = 1, 8 do
	local r, d, b = cast(F)
	table.move(r, 1, #r, #fastReels + 1, fastReels)
	table.move(d, 1, #d, #fastDurs + 1, fastDurs)
	table.move(b, 1, #b, #fastBites + 1, fastBites)
end
check("1.2x: every reel takes 3.4 / 1.2 = 2.83 s", #fastReels == 24 and all(fastReels, function(x)
	return about(x, 3.4 / 1.2)
end))
check("1.2x: the clients animate over the same Dur", all(fastDurs, function(x)
	return math.abs(x - 3.4 / 1.2) < 1e-9
end))
local lo = math.huge
for _, b in ipairs(fastBites) do
	lo = math.min(lo, b)
end
print(string.format("  1.2x reels: %d bites, shortest wait %.2f s", #fastBites, lo))
check("the bite wait is untouched (Basic rod: never under 3 s)", #fastBites == 24 and lo >= 3.0)
local nr = cast(N)
check("N's casts keep 3.4 s", #nr == 3 and all(nr, function(x)
	return about(x, 3.4)
end))

-- bought mid-cast: that cast keeps its speed
local mid = cast(F, function()
	moveTo(F, NEAR_BOARD)
	click(F, card(F, "FasterReels").Buy)
	advance(0.5)
	moveTo(F, NEAR_BUTTON)
end)
check("bought 1.2x → 1.35x mid-cast", lastNotice(F) == "Faster Reels 1.2x → 1.35x (-$100)" and Economy.balance(F) == 890)
check("the cast already under way kept 1.2x", #mid == 3 and all(mid, function(x)
	return about(x, 3.4 / 1.2)
end))
local nextCast = cast(F)
check("the next cast reels at 1.35x", #nextCast == 3 and all(nextCast, function(x)
	return about(x, 3.4 / 1.35)
end))

finish("reels sim")
