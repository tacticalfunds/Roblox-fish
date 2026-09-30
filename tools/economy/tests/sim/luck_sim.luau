-- Upgrade board, milestone 2 (Rod Luck): the REAL EconomyService
-- (MoneyStore `upgrades`, BoardUpgrades), the REAL UpgradeBoardServer +
-- UpgradeBoardClient and the REAL upgrade-board RodFishingSystem on the fake
-- engine. Every rod catch ends in a rod-fish offer; Economy.runRodOffer is
-- replaced by a recorder (it passes), so each catch's fish and the chance the
-- offer would show are checked. River: Cod (weight 50, tier 1), Salmon
-- (weight 20, tier 10); rod weights w^0.85.
-- Checks:
--   * Rod Luck closed by default (UpgradesOpen); open: $10 for 1x -> 2x,
--     money + level saved in ONE write; card 2x > 2.5x, $75; MAX at 3x
--   * the chance labels are the real odds with the caster's luck: 1x
--     Salmon 0.314, 2x 0.478 (rarest vs commonest weight doubled, renormalised)
--   * luck is the PRESSER's, fixed at the accepted press: buying more during a
--     cast, or a purchase still being saved, changes nothing for that cast
--   * over many casts the lucky caster lands Salmon clearly more often, but
--     not always; another player's casts keep the old odds

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
local L = join(1, "Lucky", NEAR_BOARD)
local N = join(2, "Normal", NEAR_BUTTON + Vector3.new(0, 0, 4))
runScript(script("Script", "UpgradeBoardServer", SOURCES.Board_Server, SSS))
runScript(script("Script", "RodFishingSystem", SOURCES.Board_Fishing, SSS))
for _, p in ipairs({ L, N }) do
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
local function near(a, b)
	return type(a) == "number" and math.abs(a - b) < 0.0005
end
-- rod weights (w^0.85) and the odds
local cod, salmon = 50 ^ 0.85, 20 ^ 0.85
local P1 = salmon / (cod + salmon)
local P2 = salmon * 2 / (cod + salmon * 2)
local P25 = salmon * 2.5 / (cod + salmon * 2.5)
-- one press of the fish button; waits for all three rods' offers
local function cast(p, during)
	local before = #offers
	runAs(p, function()
		pressRemote:FireServer()
	end)
	if during then
		advance(0.1)
		during()
	end
	local t = 0
	while #offers < before + 3 and t < 40 do
		advance(0.5)
		t += 0.5
	end
	advance(2) -- the fish slips off; rods idle
	local out = {}
	for i = before + 1, #offers do
		table.insert(out, offers[i])
	end
	return out
end
local function allChances(list, fishOdds)
	if #list ~= 3 then
		return false
	end
	for _, o in ipairs(list) do
		local want = if o.fish == "Salmon" then fishOdds else 1 - fishOdds
		if not near(o.chance, want) then
			return false
		end
	end
	return true
end

------------------------------------------------------------ the card, closed and open

check("Rod Luck card: 1x > 2x, SOON while closed", value(L, "RodLuck") == "1x > 2x" and price(L, "RodLuck") == "SOON")
check("published: UpgRodLuck 1, next 2, cost 10", L:GetAttribute("UpgRodLuck") == 1 and L:GetAttribute("UpgRodLuckNext") == 2
	and L:GetAttribute("UpgRodLuckCost") == 10)
pressCard(L, "RodLuck")
check("closed by default: refused, not charged", lastNotice(L) == "Rod Luck upgrades open soon" and Economy.balance(L) == 1000)
advance(2)

moveTo(L, NEAR_BUTTON)
advance(0.5)
local base = cast(L)
check("before buying: L's casts show the 1x odds (Salmon " .. string.format("%.3f", P1) .. ")", allChances(base, P1))

root:SetAttribute("UpgradesOpen", true)
advance(0.1)
check("open: the card shows $10", price(L, "RodLuck") == "$10")
pressCard(L, "RodLuck") -- still at the fish button
check("far from the board: refused, not charged", lastNotice(L) == "Walk up to the board" and Economy.balance(L) == 1000)
moveTo(L, NEAR_BOARD)
L.Character.Humanoid.Health = 0
pressCard(L, "RodLuck")
check("dead: refused, not charged", lastNotice(L) == "You can't do that right now" and Economy.balance(L) == 1000)
L.Character.Humanoid.Health = 100
advance(1)
-- re-checked after waiting for a running save: walked away -> refused
local held = false
dsHooks.before = function(key)
	if key == KEY .. "1" and not held then
		held = true
		task.wait(3)
	end
end
local t = 0
while not held and t < 70 do
	advance(0.5)
	t += 0.5
end
click(L, card(L, "RodLuck").Buy)
advance(0.3)
moveTo(L, NEAR_BUTTON)
advance(4)
dsHooks.before = nil
check("walked away while the purchase waited for a save: refused, not charged", held and lastNotice(L) == "Walk up to the board"
	and Economy.balance(L) == 1000 and L:GetAttribute("UpgRodLuck") == 1)
moveTo(L, NEAR_BOARD)
advance(2)
local writes = 0
dsHooks.before = function()
	writes += 1
end
pressCard(L, "RodLuck")
dsHooks.before = nil
check("bought: Rod Luck 1x → 2x (-$10)", lastNotice(L) == "Rod Luck 1x → 2x (-$10)" and Economy.balance(L) == 990)
check("one write: money AND upgrades.RodLuck = 1", writes == 1 and dsData[KEY .. "1"].upgrades.RodLuck == 1 and dsData[KEY .. "1"].money == 990)
advance(2)
check("card: 2x > 2.5x, $75", value(L, "RodLuck") == "2x > 2.5x" and price(L, "RodLuck") == "$75")
check("N's card is N's own: 1x > 2x, $10", value(N, "RodLuck") == "1x > 2x" and price(N, "RodLuck") == "$10")

------------------------------------------------------------ the odds follow the caster, fixed at the press

moveTo(L, NEAR_BUTTON)
advance(0.5)
local lucky = cast(L)
check("L's casts: the 2x odds (Salmon " .. string.format("%.3f", P2) .. ")", allChances(lucky, P2))
local normal = cast(N)
check("N's casts: still the 1x odds", allChances(normal, P1))

-- L buys 2.5x DURING a cast: that cast keeps 2x
local mid = cast(L, function()
	moveTo(L, NEAR_BOARD)
	click(L, card(L, "RodLuck").Buy)
	advance(0.5)
	moveTo(L, NEAR_BUTTON)
end)
check("bought 2x → 2.5x mid-cast", lastNotice(L) == "Rod Luck 2x → 2.5x (-$75)" and Economy.balance(L) == 915)
check("the cast already under way kept 2x", allChances(mid, P2))
local after = cast(L)
check("the next cast uses 2.5x (Salmon " .. string.format("%.3f", P25) .. ")", allChances(after, P25))

-- a purchase still being saved: the cast pressed meanwhile uses the committed value
advance(1)
moveTo(L, NEAR_BOARD)
dsHooks.before = function()
	task.wait(3)
end
click(L, card(L, "RodLuck").Buy)
advance(0.3)
moveTo(L, NEAR_BUTTON)
advance(0.5)
local during = cast(L)
dsHooks.before = nil
advance(3)
check("a cast pressed while 2.5x → 3x was being saved used 2.5x", allChances(during, P25))
check("then the purchase counted: 3x", L:GetAttribute("UpgRodLuck") == 3 and Economy.balance(L) == 615)
moveTo(L, NEAR_BOARD)
advance(2)
check("card at the last level: 3x MAX, MAX", value(L, "RodLuck") == "3x MAX" and price(L, "RodLuck") == "MAX")
pressCard(L, "RodLuck")
check("max: refused, not charged", lastNotice(L) == "Rod Luck is at the maximum (3x)" and Economy.balance(L) == 615)

------------------------------------------------------------ many casts: likelier, never certain

moveTo(L, NEAR_BUTTON)
advance(0.5)
local function salmonShare(p, rounds)
	local n, s = 0, 0
	for _ = 1, rounds do
		for _, o in ipairs(cast(p)) do
			n += 1
			if o.fish == "Salmon" then
				s += 1
			end
		end
	end
	return s / math.max(1, n), n
end
local luckyShare, ln = salmonShare(L, 25)
local normalShare, nn = salmonShare(N, 25)
local P3 = salmon * 3 / (cod + salmon * 3)
print(string.format("  Salmon share: 3x %.3f of %d (expected %.3f) | 1x %.3f of %d (expected %.3f)", luckyShare, ln, P3, normalShare, nn, P1))
check("enough catches", ln >= 60 and nn >= 60)
check("3x lands Salmon clearly more often than 1x", luckyShare > normalShare + 0.15)
check("but not always: Cod still bites for the lucky caster", luckyShare < 0.9)
check("both near their real odds", math.abs(luckyShare - P3) < 0.15 and math.abs(normalShare - P1) < 0.15)

------------------------------------------------------------ spam during a slow save

moveTo(N, NEAR_BOARD)
advance(1)
local remote = root:FindFirstChild("UpgradeAction")
dsHooks.before = function()
	task.wait(3)
end
local answers = {}
for i = 1, 5 do
	runAs(N, function()
		task.spawn(function()
			answers[i] = { remote:InvokeServer("RodLuck") }
		end)
	end)
	advance(0.6) -- past the press gap and the cooldown, while the first save still runs
end
advance(4)
dsHooks.before = nil
local oks = 0
for _, a in ipairs(answers) do
	oks += if a[1] == true then 1 else 0
end
check("5 spaced presses during one slow save: one purchase (1x → 2x), charged once", oks == 1 and N:GetAttribute("UpgRodLuck") == 2
	and Economy.balance(N) == 990 and dsData[KEY .. "2"].upgrades.RodLuck == 1)
moveTo(N, NEAR_BUTTON)
advance(1)

------------------------------------------------------------ rejoin

leave(L)
advance(1)
L = join(1, "Lucky", NEAR_BUTTON)
advance(1)
check("rejoin: Rod Luck 3x and the money back", L:GetAttribute("UpgRodLuck") == 3 and Economy.balance(L) == 615)
local back = cast(L)
check("rejoin: casts use 3x", allChances(back, P3))

finish("luck sim")
