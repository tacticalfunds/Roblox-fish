-- Upgrade board, milestone 1 (Net Strength): the REAL UpgradeBoardServer +
-- UpgradeBoardClient, NetCapacityServer + KgSignClient and the REAL
-- EconomyService on the fake engine, in the live layout:
--   Workspace.Board (Model) > Main (Part) > SurfaceGui > bord3 with a
--   UIPadding, a UIListLayout and TWO cards both named "Frame", each with
--   two TextLabels both named "Text" (Axe Speed / x1.00 > x1.15 and
--   Buy Miner / 1/64, $ 120); two KGsign posts, each with PricePlate.PriceGui
--   showing "$100" and "NET15KG->20KG"; a third post whose plate can't be
--   read unambiguously (two prices).
-- Checks:
--   * four cards (Net Strength / Rod Luck / Meat Price / Faster Reels) in a
--     2x2 grid on a per-player copy; the place's board only hidden per client
--   * Net Strength = the posts' saved capacity: first step $10, one
--     progression whether bought at the board or a post; plates per player
--   * SOON while closed; SAVING... while saving; server answers shown
--     (BOUGHT! / TOO FAR / NEED $ / NOT SAVED / MAX); the price red when short
--   * far / dead / loading / spam / funds / failed save / max refused, never
--     charged; unknown / bad ids refused; the other three cards sell nothing
--   * shared NetLift.MaxWeight follows board purchases
--   (board missing / duplicated: boardmissing_sim)

local Economy, root = installEconomy()
local SSS = services.ServerScriptService
local ws = workspaceInst
local KEY = Economy.Config.KeyPrefix
local MAIN = Vector3.new(-72.84, 21.08, 136.48)
local NEAR = MAIN + Vector3.new(0, -7, 6)
local SIGN1 = Vector3.new(-42.4489, 12.0365, 206.336)
local SIGN2 = Vector3.new(22.4984, 11.5565, 206.497)
local SIGN3 = Vector3.new(80, 11.5, 206.5)

current = "server"
local netLift = new("Model", "NetLift")
netLift:SetAttribute("MaxWeight", 15)
netLift.Parent = ws

-- the board as it is in the place
local board = new("Model", "Board")
part("Part", MAIN + Vector3.new(0, 5.3, 0), board, Vector3.new(22, 1.3, 1.7))
local main = part("Main", MAIN, board, Vector3.new(19.53, 9.34, 0.85))
local surface = new("SurfaceGui", "SurfaceGui")
surface._props.Enabled = true
local bord = new("Frame", "bord3")
new("UIPadding", "UIPadding").Parent = bord
new("UIListLayout", "UIListLayout").Parent = bord
local function oldCard(title, value)
	local card = new("Frame", "Frame")
	local buy = new("TextButton", "Buy")
	local price = new("TextLabel", "Price")
	price._props.Text = "$ 120"
	price.Parent = buy
	buy.Parent = card
	new("ImageLabel", "Icons").Parent = card
	local t1 = new("TextLabel", "Text")
	t1._props.Text = title
	t1.Parent = card
	local t2 = new("TextLabel", "Text")
	t2._props.Text = value
	t2.Parent = card
	card.Parent = bord
	return buy
end
local oldBuy = oldCard("Axe Speed", "x1.00 > x1.15")
oldCard("Buy Miner", "1/64")
bord.Parent = surface
surface.Parent = main
board.Parent = ws

-- the posts, each with the place's price plate
local detectors, plates = {}, {}
local function post(pos, labels)
	local sign = new("Model", "KGsign")
	local boardPart = part("Board Part", pos, sign, Vector3.new(8, 4, 0.5))
	local cd = new("ClickDetector", "ClickDetector")
	cd._props.MaxActivationDistance = 20
	cd.Parent = boardPart
	local plate = part("PricePlate", pos + Vector3.new(0, 3, 0), sign, Vector3.new(4, 1.5, 0.2))
	local gui = new("SurfaceGui", "PriceGui")
	local frame = new("Frame", "Frame")
	local made = {}
	for _, text in ipairs(labels) do
		local l = new("TextLabel", "TextLabel")
		l._props.Text = text
		l.Parent = frame
		table.insert(made, l)
	end
	frame.Parent = gui
	gui.Parent = plate
	sign.Parent = ws
	table.insert(detectors, cd)
	table.insert(plates, made)
end
post(SIGN1, { "$100", "NET15KG->20KG" })
post(SIGN2, { "$100", "NET15KG->20KG" })
post(SIGN3, { "$100", "$5", "NET15KG->20KG" }) -- can't tell which price: left alone
current = nil

dsData[KEY .. "1"] = { v = 2, money = 2000 }
local A = join(1, "Buyer", NEAR)
runScript(script("Script", "NetCapacityServer", SOURCES.Kg_Server, SSS))
runScript(script("Script", "UpgradeBoardServer", SOURCES.Board_Server, SSS))
local function clientScripts(p)
	runAs(p, function()
		runScript(script("LocalScript", "KgSignClient", SOURCES.Kg_Client), p)
		runScript(script("LocalScript", "UpgradeBoardClient", SOURCES.Board_Client), p)
	end)
end
clientScripts(A)
advance(1.5)

-- what player p sees (client-local changes included)
local function seen(p, inst, prop)
	local v
	runAs(p, function()
		v = inst[prop]
	end)
	return v
end
local function boardGui(p)
	return p.PlayerGui:FindFirstChild("UpgradeBoard")
end
local function card(p, id)
	local g = boardGui(p)
	return g and g.bord3:FindFirstChild(id)
end
local function value(p, id)
	local c = card(p, id)
	return c and c.Value.Text
end
local function price(p, id)
	local c = card(p, id)
	return c and c.Buy.Price.Text
end
local function press(p, id)
	click(p, card(p, id).Buy)
end
local remote = root:FindFirstChild("UpgradeAction")

------------------------------------------------------------ the board

check("server made ReplicatedStorage.Economy.UpgradeAction (not saved)", remote ~= nil and remote.ClassName == "RemoteFunction" and remote.Archivable == false)
local g = boardGui(A)
check("a per-player copy of the board's SurfaceGui, on Main", g ~= nil and g.ClassName == "SurfaceGui" and g.Adornee == main and g.ResetOnSpawn == false)
check("the place's board: hidden for A only, never changed", seen(A, surface, "Enabled") == false and surface.Enabled == true
	and #bord:GetChildren() == 4 and oldBuy.Price.Text == "$ 120")
local copy = g.bord3
local order, oldLeft = {}, false
for _, c in ipairs(copy:GetChildren()) do
	if c.ClassName == "Frame" then
		table.insert(order, c.LayoutOrder .. ":" .. c.Name .. ":" .. c.Title.Text)
		oldLeft = oldLeft or c.Name == "Frame"
	end
end
table.sort(order)
check("four cards: Net Strength, Rod Luck, Meat Price, Faster Reels", table.concat(order, ",")
	== "1:NetStrength:Net Strength,2:RodLuck:Rod Luck,3:MeatPrice:Meat Price,4:FasterReels:Faster Reels")
check("old cards and list layout gone from the copy; a 2x2 grid; padding kept", not oldLeft and copy:FindFirstChildOfClass("UIListLayout") == nil
	and copy:FindFirstChildOfClass("UIGridLayout") ~= nil and copy:FindFirstChildOfClass("UIPadding") ~= nil)
local grid = copy:FindFirstChildOfClass("UIGridLayout")
check("grid cells fit two by two", grid.CellSize.X.Scale * 2 + grid.CellPadding.X.Scale <= 1 and grid.CellSize.Y.Scale * 2 + grid.CellPadding.Y.Scale <= 1)
check("each card: icon, white outlined title and value, green Buy with a price", (function()
	for _, id in ipairs({ "NetStrength", "RodLuck", "MeatPrice", "FasterReels" }) do
		local c = card(A, id)
		if not (c.Icon.Text ~= "" and c.Title:FindFirstChildOfClass("UIStroke") and c.Value:FindFirstChildOfClass("UIStroke")
			and c.Title.TextColor3.R == 1 and c.Buy:FindFirstChildOfClass("UIGradient") and c.Buy.Price) then
			return false
		end
	end
	return true
end)())
check("card colours: pink, lime, cyan, amber", card(A, "NetStrength").BackgroundColor3.R > card(A, "NetStrength").BackgroundColor3.G
	and card(A, "RodLuck").BackgroundColor3.G > card(A, "RodLuck").BackgroundColor3.R
	and card(A, "MeatPrice").BackgroundColor3.B > card(A, "MeatPrice").BackgroundColor3.R
	and card(A, "FasterReels").BackgroundColor3.R > card(A, "FasterReels").BackgroundColor3.B)
check("values: 15kg > 20kg, 1x > 2x, 1x > 2x, 1x > 1.2x", value(A, "NetStrength") == "15kg > 20kg" and value(A, "RodLuck") == "1x > 2x"
	and value(A, "MeatPrice") == "1x > 2x" and value(A, "FasterReels") == "1x > 1.2x")
check("closed by default: every card says SOON", price(A, "NetStrength") == "SOON" and price(A, "RodLuck") == "SOON"
	and price(A, "MeatPrice") == "SOON" and price(A, "FasterReels") == "SOON")

-- the posts' plates
check("both posts' plates show A's own step, SOON while closed", seen(A, plates[1][1], "Text") == "SOON" and seen(A, plates[1][2], "Text") == "NET15KG->20KG"
	and seen(A, plates[2][1], "Text") == "SOON" and seen(A, plates[2][2], "Text") == "NET15KG->20KG")
check("plates are unchanged in the place (server view)", plates[1][1].Text == "$100" and plates[2][1].Text == "$100")
local panelCount = 0
for _, gui in ipairs(A.PlayerGui:GetChildren()) do
	if gui.Name == "KgSignPanel" then
		panelCount += 1
	end
end
check("posts with a readable plate get no floating panel; the ambiguous one keeps its panel", panelCount == 1
	and seen(A, plates[3][1], "Text") == "$100" and seen(A, plates[3][2], "Text") == "$5")

press(A, "NetStrength")
advance(0.3)
check("closed: refused, SOON, not charged", lastNotice(A) == "Net upgrades open soon" and price(A, "NetStrength") == "SOON"
	and Economy.balance(A) == 2000)
advance(2)

root:SetAttribute("NetKgOpen", true)
advance(0.1)
check("net open: Net Strength $10 (first step); the other three still SOON", price(A, "NetStrength") == "$10"
	and price(A, "RodLuck") == "SOON" and price(A, "MeatPrice") == "SOON" and seen(A, plates[1][1], "Text") == "$10")

------------------------------------------------------------ buying at the board

local writes = 0
dsHooks.before = function()
	writes += 1
	task.wait(0.5)
end
press(A, "NetStrength")
advance(0.1)
check("while the server saves: SAVING...", price(A, "NetStrength") == "SAVING...")
advance(0.6)
dsHooks.before = nil
check("bought 15 → 20 kg for $10, the toast says so", lastNotice(A) == "Net capacity 15 → 20 kg (-$10)" and Economy.balance(A) == 1990)
check("BOUGHT! on the button for a moment", price(A, "NetStrength") == "BOUGHT!")
check("saved at once: money AND netKg in one write", writes == 1 and dsData[KEY .. "1"].netKg == 20 and dsData[KEY .. "1"].money == 1990)
check("shared net now 20 kg", netLift:GetAttribute("MaxWeight") == 20)
advance(2)
check("then: 20kg > 25kg, $25 on the card and on both plates", value(A, "NetStrength") == "20kg > 25kg" and price(A, "NetStrength") == "$25"
	and seen(A, plates[1][1], "Text") == "$25" and seen(A, plates[2][2], "Text") == "NET20KG->25KG")

-- the same progression at a post
moveTo(A, SIGN1 + Vector3.new(0, -7, 6))
asServer(function()
	detectors[1].MouseClick:Fire(A)
end)
advance(0.6)
check("a post sells the next step of the SAME net: 20 → 25 for $25", lastNotice(A) == "Net capacity 20 → 25 kg (-$25)"
	and Economy.balance(A) == 1965 and A:GetAttribute("NetKg") == 25)
check("the board card follows: 25kg > 30kg, $50", value(A, "NetStrength") == "25kg > 30kg" and price(A, "NetStrength") == "$50")

-- far from the board (at the post now)
press(A, "NetStrength")
advance(0.3)
check("far from the board: refused, TOO FAR, not charged", lastNotice(A) == "Walk up to the board" and price(A, "NetStrength") == "TOO FAR"
	and Economy.balance(A) == 1965)
moveTo(A, NEAR)
advance(2)

-- dead
A.Character.Humanoid.Health = 0
press(A, "NetStrength")
advance(0.3)
check("dead: refused, not charged", lastNotice(A) == "You can't do that right now" and Economy.balance(A) == 1965)
A.Character.Humanoid.Health = 100
advance(2)

-- spam during a slow save: the client sends one request per card at a time,
-- and the server takes one purchase at a time anyway
dsHooks.before = function()
	task.wait(1.5)
end
for _ = 1, 5 do
	press(A, "NetStrength")
end
local direct = {}
for _ = 1, 3 do
	runAs(A, function()
		task.spawn(function()
			table.insert(direct, { remote:InvokeServer("NetStrength") })
		end)
	end)
end
advance(2)
dsHooks.before = nil
advance(0.5)
check("spam (5 presses + 3 direct calls) during a slow save: one purchase (25 → 30 for $50)", Economy.balance(A) == 1915
	and A:GetAttribute("NetKg") == 30 and #direct == 3 and direct[1][1] == false and direct[2][1] == false and direct[3][1] == false)
advance(2)

-- failed save
dsHooks.before = function()
	error("DataStore request failed")
end
press(A, "NetStrength")
advance(0.3)
dsHooks.before = nil
check("save fails: NOT SAVED, not charged, still 30 kg", price(A, "NetStrength") == "NOT SAVED"
	and lastNotice(A) == "Couldn't save the upgrade - you were not charged. Try again." and Economy.balance(A) == 1915
	and A:GetAttribute("NetKg") == 30 and netLift:GetAttribute("MaxWeight") == 30)
advance(2)

-- re-checked after waiting for a running autosave: walked away -> refused
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
press(A, "NetStrength")
advance(0.3)
moveTo(A, NEAR + Vector3.new(80, 0, 0))
advance(4)
dsHooks.before = nil
check("walked away while the purchase waited for a save: refused, not charged", held and lastNotice(A) == "Walk up to the board"
	and Economy.balance(A) == 1915 and A:GetAttribute("NetKg") == 30)
moveTo(A, NEAR)
advance(2)

------------------------------------------------------------ the other cards, bad requests

local before = Economy.balance(A)
press(A, "RodLuck")
advance(0.3)
check("Rod Luck: its paid upgrades are closed by default (UpgradesOpen), not charged", lastNotice(A) == "Rod Luck upgrades open soon"
	and price(A, "RodLuck") == "SOON" and Economy.balance(A) == before)
advance(0.5)
press(A, "MeatPrice")
advance(0.3)
check("Meat Price: closed by default too (UpgradesOpen), not charged", lastNotice(A) == "Meat Price upgrades open soon"
	and price(A, "MeatPrice") == "SOON" and Economy.balance(A) == before)
advance(0.5)
press(A, "FasterReels")
advance(0.3)
check("Faster Reels: coming soon", lastNotice(A) == "Faster Reels upgrades are coming soon" and Economy.balance(A) == before)
advance(0.5)
local answers = {}
runAs(A, function()
	for _, id in ipairs({ "Hack", 5, { "NetStrength" } }) do
		table.insert(answers, { remote:InvokeServer(id) })
		task.wait(0.3)
	end
end)
advance(1.5)
check("unknown / non-string ids: refused, nothing charged", #answers == 3 and answers[1][1] == false and answers[1][2] == "Unknown upgrade"
	and answers[2][2] == "Unknown upgrade" and answers[3][2] == "Unknown upgrade" and Economy.balance(A) == before)
local quick = {}
runAs(A, function()
	table.insert(quick, { remote:InvokeServer("RodLuck") })
	table.insert(quick, { remote:InvokeServer("RodLuck") })
end)
check("presses faster than the server's gap: the second is refused", quick[2] and quick[2][2] == "Slow down a little")
advance(1)

------------------------------------------------------------ another player: funds, loading, per-player plates, max

dsData[KEY .. "2"] = { v = 2, money = 5, netKg = 45 }
local B = join(2, "Short", NEAR + Vector3.new(3, 0, 0))
clientScripts(B)
advance(1.5)
check("B sees B's own step (45 → 50, $340) on the board and plates; A still sees A's", value(B, "NetStrength") == "45kg > 50kg"
	and price(B, "NetStrength") == "$340" and seen(B, plates[1][2], "Text") == "NET45KG->50KG" and seen(B, plates[1][1], "Text") == "$340"
	and seen(A, plates[1][2], "Text") == "NET30KG->35KG" and seen(A, plates[1][1], "Text") == "$100")
local short = card(B, "NetStrength").Buy.Price.TextColor3
check("B can't afford it: the price is red", short.R > 0.9 and short.G < 0.5)
check("shared net: B's 45 kg", netLift:GetAttribute("MaxWeight") == 45)
press(B, "NetStrength")
advance(0.3)
check("B presses: NEED $, not charged", price(B, "NetStrength") == "NEED $" and lastNotice(B) == "Not enough money" and Economy.balance(B) == 5)

dsData[KEY .. "3"] = { v = 2, money = 0, netKg = 60, lock = { job = "another-server", t = 1700000000 + 10 ^ 7 } }
local C = join(3, "Loading", NEAR + Vector3.new(-3, 0, 0))
clientScripts(C)
advance(1.5)
check("C's money still loading: the card shows ...", price(C, "NetStrength") == "..." and seen(C, plates[1][1], "Text") == "...")
press(C, "NetStrength")
advance(0.3)
check("loading: refused (WAIT)", price(C, "NetStrength") == "WAIT" and lastNotice(C) == "Your money is still loading - try again in a moment")

dsData[KEY .. "4"] = { v = 2, money = 5000, netKg = 55 }
local D = join(4, "Maxer", NEAR + Vector3.new(0, 0, 2))
clientScripts(D)
advance(1.5)
press(D, "NetStrength")
advance(0.5)
check("D: 55 → 60 kg for $765", lastNotice(D) == "Net capacity 55 → 60 kg (-$765)" and Economy.balance(D) == 4235)
check("shared net follows the board purchase: 60 kg", netLift:GetAttribute("MaxWeight") == 60)
advance(2)
check("at the cap: 60kg MAX, MAX on the card and plates", value(D, "NetStrength") == "60kg MAX" and price(D, "NetStrength") == "MAX"
	and seen(D, plates[2][2], "Text") == "NET60KG MAX" and seen(D, plates[2][1], "Text") == "MAX")
press(D, "NetStrength")
advance(0.3)
check("at the cap: refused, not charged", lastNotice(D) == "Your net is at the maximum (60 kg)" and Economy.balance(D) == 4235)
leave(D)
advance(0.5)
check("D leaves: the shared net drops back to B's 45", netLift:GetAttribute("MaxWeight") == 45)

------------------------------------------------------------ the board streams out and back

current = "server"
board.Parent = nil
current = nil
advance(1.5)
check("board gone: A's copy removed", boardGui(A) == nil)
current = "server"
board.Parent = ws
current = nil
advance(1.5)
check("board back: drawn again with A's values", boardGui(A) ~= nil and value(A, "NetStrength") == "30kg > 35kg" and price(A, "NetStrength") == "$100")

finish("board sim")
