-- Upgrade board (Net Strength): the REAL UpgradeBoardServer +
-- UpgradeBoardClient, NetCapacityServer + KgSignClient and the REAL
-- EconomyService on the fake engine, in the live layout:
--   the place's four-card art: Workspace["Upgrade board"].Screen and each
--   player's PlayerGui.UpgradeBoardGui (Frames "Net Strength" / "Rod Luck" /
--   "Meat Price" / "Faster Reels", each with Desc, Title, ImageButton Btn >
--   Price, and icon viewports); the OLD Workspace.Board (Main > SurfaceGui >
--   bord3, two old cards) as scenery that must stay untouched; two KGsign
--   posts, each with PricePlate.PriceGui showing "$100" and
--   "NET 15 KG → 20 KG"; a third post whose plate can't be read unambiguously.
-- Checks:
--   * the existing art is bound (nothing created): only Desc and Btn.Price
--     texts change; titles, button image, viewports untouched; the old board
--     neither used nor hidden; a respawn's new gui copy is bound again
--   * Net Strength = the posts' saved capacity: first step $10, one
--     progression whether bought at the board or a post; plates per player
--   * SOON while closed; SAVING... while saving; server answers shown
--     (BOUGHT! / TOO FAR / NEED $ / NOT SAVED / MAX)
--   * far / dead / loading / spam / funds / failed save / max refused, never
--     charged; unknown / bad ids refused; the other three cards stay closed
--     by default (bought and used in luck_sim, meat_sim, reels_sim)
--   * board purchases raise the buyer's own NetMaxWeight; NetLift.MaxWeight
--     (the base) never moves
--   (board missing / duplicated: boardmissing_sim)

local Economy, root = installEconomy()
-- this scene has no GrinderUpgradesServer to report earlier KG-sign buys
-- (grinder_sim covers that): nothing to wait for
Economy.Config.NetKgLegacy = false
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
-- (far from the art screen, so "near the board" can only mean the screen)
local OLD = MAIN + Vector3.new(0, 0, -150)
part("Part", OLD + Vector3.new(0, 5.3, 0), board, Vector3.new(22, 1.3, 1.7))
local main = part("Main", OLD, board, Vector3.new(19.53, 9.34, 0.85))
local surface = new("SurfaceGui", "SurfaceGui")
surface._props.Enabled = true
local bord = new("Frame", "bord3")
new("UIPadding", "UIPadding").Parent = bord
new("UIListLayout", "UIListLayout").Parent = bord
-- a card as the place has it (Workspace inventory): Buy (Price, UIStroke,
-- UIGradient, UICorner), Icons (image), two labels both named "Text"
local function oldCard(title, value, image)
	local card = new("Frame", "Frame")
	card._props.BackgroundTransparency = 1
	local buy = new("TextButton", "Buy")
	buy._props.Position = UDim2.fromScale(0.532, 0.885)
	buy._props.Size = UDim2.fromScale(0.827, 0.12)
	buy._props.BackgroundColor3 = Color3.new(1, 1, 1)
	local price = new("TextLabel", "Price")
	price._props.Text = "$ 120"
	price.Parent = buy
	new("UIStroke", "UIStroke").Parent = buy
	local grad = new("UIGradient", "UIGradient")
	grad:SetAttribute("BoardArt", true) -- marks the place's own gradient
	grad.Parent = buy
	new("UICorner", "UICorner").Parent = buy
	buy.Parent = card
	local icons = new("ImageLabel", "Icons")
	icons._props.Image = image
	icons._props.Position = UDim2.fromScale(0.479, 0.434)
	icons._props.Size = UDim2.fromScale(0.5, 0.5)
	icons.Parent = card
	local t1 = new("TextLabel", "Text")
	t1._props.Text = title
	t1._props.Position = UDim2.fromScale(0.499, 0.093)
	t1.Parent = card
	local t2 = new("TextLabel", "Text")
	t2._props.Text = value
	t2._props.Position = UDim2.fromScale(0.499, 0.742)
	t2.Parent = card
	card.Parent = bord
	return buy
end
local oldBuy = oldCard("Axe Speed", "x1.00 > x1.15", "rbxassetid://75744565067217")
oldCard("Buy Miner", "1/64", "rbxassetid://137299198925368")
bord.Parent = surface
surface.Parent = main
board.Parent = ws
current = nil
-- the board the place really uses: its four-card art screen, at the same spot
local _, boardScreen = upgradeBoard(MAIN)
current = "server"

-- the posts, each with the place's price plate
local detectors, plates = {}, {}
-- a post as the place has it: tagged KgSign, Board Part (ClickDetector) and
-- PricePlate.PriceGui.Pill (Price, Info, Border) - or, for the third post,
-- a plate without a Pill (it keeps the floating panel)
local function post(pos, withPill)
	local sign = new("Model", "KGsign")
	local boardPart = part("Board Part", pos, sign, Vector3.new(8, 4, 0.5))
	local cd = new("ClickDetector", "ClickDetector")
	cd._props.MaxActivationDistance = 20
	cd.Parent = boardPart
	local plate = part("PricePlate", pos + Vector3.new(0, 3, 0), sign, Vector3.new(4, 1.5, 0.2))
	local gui = new("SurfaceGui", "PriceGui")
	local made = {}
	if withPill then
		local pill = new("Frame", "Pill")
		local price = new("TextLabel", "Price")
		price._props.Text = "$100"
		price.Parent = pill
		local info = new("TextLabel", "Info")
		info._props.Text = "NET 15 KG → 20 KG"
		info.Parent = pill
		local border = new("UIStroke", "Border")
		border.Parent = pill
		pill.Parent = gui
		made = { price, info, border }
	else
		local l = new("TextLabel", "TextLabel")
		l._props.Text = "$100"
		l.Parent = gui
		made = { l }
	end
	gui.Parent = plate
	sign.Parent = ws
	if withPill then
		addTag(sign, "KgSign")
	end
	table.insert(detectors, cd)
	table.insert(plates, made)
end
post(SIGN1, true)
post(SIGN2, true)
post(SIGN3, false) -- no Pill: left alone, gets the panel
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
boardArt(A, boardScreen)
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
	return p.PlayerGui:FindFirstChild("UpgradeBoardGui")
end
local function card(p, id)
	return artCard(p, ART_CARD_NAMES[id])
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
check("binds the place's own gui copy (nothing generated)", g ~= nil and A.PlayerGui:FindFirstChild("UpgradeBoard") == nil
	and #g:GetChildren() == 4)
check("the old Workspace.Board: neither used nor hidden, unchanged", seen(A, surface, "Enabled") == true and surface.Enabled == true
	and #bord:GetChildren() == 4 and oldBuy.Price.Text == "$ 120")
check("the art is untouched: titles, button image, icon viewports and gradients as they were", (function()
	for id, name in pairs(ART_CARD_NAMES) do
		local c = card(A, id)
		local f = c.Frame
		local vps = 0
		for _, ch in ipairs(f:GetChildren()) do
			if ch.ClassName == "ViewportFrame" and ch.Name == "IconOutline" and ch:FindFirstChild("IconModel") then
				vps += 1
			end
		end
		if not (f.Title.Text == name and c.Buy.Image == "rbxassetid://77162011310420" and c.Buy.ClassName == "ImageButton"
			and vps == 2 and f:FindFirstChildOfClass("UIGradient") and c.Buy:FindFirstChildOfClass("UIGradient")
			and #f:GetChildren() == 6 and #c.Buy:GetChildren() == 2) then
			return false
		end
	end
	return true
end)())
check("Desc: 15 > 20kg, 1x > 2x, 1x > 2x, 1x > 1.2x", value(A, "NetStrength") == "15 > 20kg" and value(A, "RodLuck") == "1x > 2x"
	and value(A, "MeatPrice") == "1x > 2x" and value(A, "FasterReels") == "1x > 1.2x")
check("closed by default: every card says SOON", price(A, "NetStrength") == "SOON" and price(A, "RodLuck") == "SOON"
	and price(A, "MeatPrice") == "SOON" and price(A, "FasterReels") == "SOON")

-- the posts' plates
check("both posts' plates show A's own step, SOON while closed", seen(A, plates[1][1], "Text") == "SOON" and seen(A, plates[1][2], "Text") == "NET 15 KG → 20 KG"
	and seen(A, plates[2][1], "Text") == "SOON" and seen(A, plates[2][2], "Text") == "NET 15 KG → 20 KG")
check("plates are unchanged in the place (server view)", plates[1][1].Text == "$100" and plates[2][1].Text == "$100")
local panelCount = 0
for _, gui in ipairs(A.PlayerGui:GetChildren()) do
	if gui.Name == "KgSignPanel" then
		panelCount += 1
	end
end
check("posts with a Pill plate get no floating panel; the one without keeps its panel and its plate is left alone", panelCount == 1
	and seen(A, plates[3][1], "Text") == "$100")

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
check("A's own net now 20 kg; the base stays 15", A:GetAttribute("NetMaxWeight") == 20 and netLift:GetAttribute("MaxWeight") == 15)
advance(2)
check("then: 20 > 25kg, $25 on the card and on both plates", value(A, "NetStrength") == "20 > 25kg" and price(A, "NetStrength") == "$25"
	and seen(A, plates[1][1], "Text") == "$25" and seen(A, plates[2][2], "Text") == "NET 20 KG → 25 KG")

-- the same progression at a post
moveTo(A, SIGN1 + Vector3.new(0, -7, 6))
asServer(function()
	detectors[1].MouseClick:Fire(A)
end)
advance(0.6)
check("a post sells the next step of the SAME net: 20 → 25 for $25", lastNotice(A) == "Net capacity 20 → 25 kg (-$25)"
	and Economy.balance(A) == 1965 and A:GetAttribute("NetKg") == 25)
check("the board card follows: 25 > 30kg, $50", value(A, "NetStrength") == "25 > 30kg" and price(A, "NetStrength") == "$50")

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
	and A:GetAttribute("NetKg") == 30 and A:GetAttribute("NetMaxWeight") == 30)
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
check("Faster Reels: closed by default too", lastNotice(A) == "Faster Reels upgrades open soon" and Economy.balance(A) == before)
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
boardArt(B, boardScreen)
clientScripts(B)
advance(1.5)
check("B sees B's own step (45 → 50, $340) on the board and plates; A still sees A's", value(B, "NetStrength") == "45 > 50kg"
	and price(B, "NetStrength") == "$340" and seen(B, plates[1][2], "Text") == "NET 45 KG → 50 KG" and seen(B, plates[1][1], "Text") == "$340"
	and seen(A, plates[1][2], "Text") == "NET 30 KG → 35 KG" and seen(A, plates[1][1], "Text") == "$100")
check("B's own net 45 kg; A's 30; the base 15", B:GetAttribute("NetMaxWeight") == 45 and A:GetAttribute("NetMaxWeight") == 30
	and netLift:GetAttribute("MaxWeight") == 15)
press(B, "NetStrength")
advance(0.3)
check("B presses: NEED $, not charged", price(B, "NetStrength") == "NEED $" and lastNotice(B) == "Not enough money" and Economy.balance(B) == 5)

dsData[KEY .. "3"] = { v = 2, money = 0, netKg = 60, lock = { job = "another-server", t = 1700000000 + 10 ^ 7 } }
local C = join(3, "Loading", NEAR + Vector3.new(-3, 0, 0))
boardArt(C, boardScreen)
clientScripts(C)
advance(1.5)
check("C's money still loading: the card shows ..., its Desc keeps the art's text", price(C, "NetStrength") == "..."
	and value(C, "NetStrength") == "15 >20kg" and seen(C, plates[1][1], "Text") == "...")
press(C, "NetStrength")
advance(0.3)
check("loading: refused (WAIT)", price(C, "NetStrength") == "WAIT" and lastNotice(C) == "Your money is still loading - try again in a moment")

dsData[KEY .. "4"] = { v = 2, money = 5000, netKg = 55 }
local D = join(4, "Maxer", NEAR + Vector3.new(0, 0, 2))
boardArt(D, boardScreen)
clientScripts(D)
advance(1.5)
press(D, "NetStrength")
advance(0.5)
check("D: 55 → 60 kg for $765", lastNotice(D) == "Net capacity 55 → 60 kg (-$765)" and Economy.balance(D) == 4235)
check("D's own net follows the board purchase: 60 kg; nobody else's moves", D:GetAttribute("NetMaxWeight") == 60
	and B:GetAttribute("NetMaxWeight") == 45 and netLift:GetAttribute("MaxWeight") == 15)
advance(2)
check("at the cap: 60kg MAX, MAX on the card and plates", value(D, "NetStrength") == "60kg MAX" and price(D, "NetStrength") == "MAX"
	and seen(D, plates[2][2], "Text") == "NET 60 KG MAX" and seen(D, plates[2][1], "Text") == "MAX")
press(D, "NetStrength")
advance(0.3)
check("at the cap: refused, not charged", lastNotice(D) == "Your net is at the maximum (60 kg)" and Economy.balance(D) == 4235)
leave(D)
advance(0.5)
check("D leaves: the base is still 15", netLift:GetAttribute("MaxWeight") == 15)

------------------------------------------------------------ respawn: Roblox copies the gui again (ResetOnSpawn)

local oldGui = boardGui(A)
current = "server"
oldGui:Destroy()
current = nil
local fresh = boardArt(A, boardScreen)
advance(0.5)
check("a new gui copy is bound with A's values", boardGui(A) == fresh and value(A, "NetStrength") == "30 > 35kg"
	and price(A, "NetStrength") == "$100")
press(A, "NetStrength")
advance(0.6)
check("and its button buys (30 → 35 for $100)", lastNotice(A) == "Net capacity 30 → 35 kg (-$100)" and Economy.balance(A) == 1815)

------------------------------------------------------------ the press bounce (display only)

local function close(a, b)
	return math.abs(a - b) < 1e-9
end
local function sameU2(u, v)
	return close(u.X.Scale, v.X.Scale) and close(u.X.Offset, v.X.Offset) and close(u.Y.Scale, v.Y.Scale) and close(u.Y.Offset, v.Y.Offset)
end
local function tweensOn(btn, from)
	local out = {}
	for i = from + 1, #tweensPlayed do
		if tweensPlayed[i].Instance == btn then
			table.insert(out, tweensPlayed[i])
		end
	end
	return out
end
local luck = card(A, "RodLuck").Buy -- anchored top-left in the art
local luckSize, luckPos = luck.Size, luck.Position
local from = #tweensPlayed
local noticesBefore = #(notices[A] or {})
press(A, "RodLuck")
advance(0.5)
local tw = tweensOn(luck, from)
check("a press bounces its button: down 0.08 s (Quad Out) to 0.92 of its size, back 0.22 s (Back Out)", #tw == 2
	and sameU2(tw[1].Goal.Size, UDim2.new(0.6 * 0.92, 4 * 0.92, 0.22 * 0.92, 2 * 0.92)) and tw[1].TweenInfo.args[1] == 0.08
	and tw[1].TweenInfo.args[2] == Enum.EasingStyle.Quad and tw[2].TweenInfo.args[1] == 0.22
	and tw[2].TweenInfo.args[2] == Enum.EasingStyle.Back and tw[2].TweenInfo.args[3] == Enum.EasingDirection.Out)
check("... around its centre (top-left anchor: moved by 4% of its size)", sameU2(tw[1].Goal.Position,
	UDim2.new(0.2 + 0.6 * 0.04, 4 * 0.04, 0.7 + 0.22 * 0.04, 2 * 0.04)))
check("... and back to exactly its own Size and Position", sameU2(luck.Size, luckSize) and sameU2(luck.Position, luckPos)
	and sameU2(tw[2].Goal.Size, luckSize))
check("one press = one request (the closed answer once), no extra purchase call", #(notices[A] or {}) == noticesBefore + 1
	and lastNotice(A) == "Rod Luck upgrades open soon" and price(A, "RodLuck") == "SOON")
local netBtn = card(A, "NetStrength").Buy -- centre-anchored: only the size changes
from = #tweensPlayed
press(A, "NetStrength")
advance(0.6)
tw = tweensOn(netBtn, from)
check("a centre-anchored button keeps its Position while it shrinks", #tw == 2 and sameU2(tw[1].Goal.Position, UDim2.new(0.5, 0, 0.82, 0)))
advance(2)

-- mid-bounce: a second press restarts it; the first bounce's callbacks do nothing
tweenHold.on = true
from = #tweensPlayed
press(A, "RodLuck")
advance(0.3)
press(A, "RodLuck")
advance(0.3)
tw = tweensOn(luck, from)
check("pressed again mid-bounce: the running bounce is cancelled and a new one starts", #tw == 2 and tw[1].cancelled == true
	and tw[2].held == true and not tw[2].cancelled)
finishHeldTweens()
tw = tweensOn(luck, from)
check("... it finishes once (down, then back), at exactly its own Size and Position", #tw == 3 and sameU2(luck.Size, luckSize)
	and sameU2(luck.Position, luckPos))
advance(2)

-- a respawn (the gui copied again) mid-bounce: the old button is put back, the new one bound
from = #tweensPlayed
press(A, "RodLuck")
advance(0.1)
luck.Size = UDim2.new(0.55, 0, 0.2, 0) -- as if mid-tween
local oldLuck = luck
local gone = boardGui(A)
current = "server"
gone:Destroy()
current = nil
local again = boardArt(A, boardScreen)
advance(0.5)
tw = tweensOn(oldLuck, from)
check("respawn mid-bounce: the bounce is cancelled and the old button restored", #tw == 1 and tw[1].cancelled == true
	and sameU2(oldLuck.Size, luckSize) and sameU2(oldLuck.Position, luckPos))
check("the new copy is bound, its button at its own size", boardGui(A) == again
	and sameU2(card(A, "RodLuck").Buy.Size, UDim2.new(0.6, 4, 0.22, 2)) and price(A, "NetStrength") ~= nil)
tweenHold.on = false
finishHeldTweens()

finish("board sim")
