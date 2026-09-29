-- Rod shop UI: the REAL patched RodShopController (and, for comparison, the
-- LIVE one) against the REAL RodShopServer + EconomyService on the fake
-- engine. Checks:
--   * cards: real price or OWNED, benefit, button = what pressing does
--     (BUY / EQUIP / EQUIPPED / SOON / SOLD OUT), all live from attributes
--   * pressing: "..." while the server answers, one request per rod, the
--     equipped rod sends nothing, then the server's real answer (short on
--     the button, full on the status line), then the live state again
--   * the live controller collapses real refusals into "NO $ YET"

local Economy, root = installEconomy()
local RS = services.ReplicatedStorage
local SSS = services.ServerScriptService
local ws = workspaceInst
local KEY = Economy.Config.KeyPrefix
local SHOP = Vector3.new(-85.5, 12.2, 210.7)

current = "server"
local rodsFolder = new("Folder", "Rods")
for i, spec in ipairs({
	{ "FishingRod1", "Common", "Basic Rod", 1, 1 },
	{ "FishingRod4", "Uncommon", "Tiger Rod", 2, 0.85 },
	{ "FishingRod3", "Rare", "Coral Rod", 3, 0.55 },
	{ "FishingRod2", "Epic", "Tide Rod", 4, 0.3 },
	{ "FishingRod5", "Legendary", "Magma Rod", 5, 0.12 },
}) do
	local m = model(spec[1], rodsFolder, Vector3.new(0, -200, i * 4))
	m:SetAttribute("Rarity", spec[2])
	m:SetAttribute("DisplayName", spec[3])
	m:SetAttribute("Order", spec[4])
	m:SetAttribute("StockChance", spec[5])
	m:SetAttribute("Price", 99999) -- legacy value until the server sets the real one
end
rodsFolder.Parent = RS
local shopFolder = new("Folder", "RodShop")
shopFolder:SetAttribute("RestockEvery", 300)
local buyRemote = new("RemoteFunction", "BuyRod")
buyRemote.Parent = shopFolder
shopFolder.Parent = RS
local petShop = new("Model", "Pet Shop")
local shopPart = part("ShopPrompt", SHOP, petShop, Vector3.new(2, 2, 2))
local openPrompt = new("ProximityPrompt", "OpenShopPrompt")
openPrompt._props.MaxActivationDistance = 14
openPrompt.Parent = shopPart
petShop.Parent = ws
current = nil

-- the RodShopFrame as in the Studio inventory (the parts the controller uses)
local function shopGui(p)
	current = "server"
	local frame = new("Frame", "RodShopFrame")
	frame._props.Visible = false
	local scroll = new("ScrollingFrame", "ScrollingFrame")
	local layout = new("UIListLayout", "UIListLayout")
	layout._props.AbsoluteContentSize = Vector2.new(0, 400)
	layout.Parent = scroll
	local tpl = new("Frame", "CarTemplate")
	tpl._props.Visible = false
	for _, n in ipairs({ "Rarity", "Mutation", "Price" }) do
		local l = new("TextLabel", n)
		l._props.Text = ""
		l.Parent = tpl
	end
	local vp = new("ViewportFrame", "ViewportFrame")
	vp._props.Position = UDim2.fromScale(0.5, 0.38)
	vp._props.ZIndex = 1
	vp.Parent = tpl
	local buy = new("ImageButton", "BuyButton")
	local bl = new("TextLabel", "Price")
	bl._props.Text = "BUY"
	bl.Parent = buy
	buy.Parent = tpl
	tpl.Parent = scroll
	scroll.Parent = frame
	local timer = new("ImageButton", "RestockTimer")
	new("TextLabel", "TextLabel").Parent = timer
	timer.Parent = frame
	new("TextButton", "CloseButton").Parent = frame
	frame.Parent = p.PlayerGui
	current = nil
	return frame
end

dsData[KEY .. "1"] = { v = 1, money = 1000 }
dsData[KEY .. "2"] = { v = 1, money = 1000 }
local P = join(1, "Shopper", SHOP + Vector3.new(0, -7, 5))
local Old = join(2, "OldUi", SHOP + Vector3.new(4, -7, 0))
runScript(script("Script", "RodShopServer", SOURCES.Rods_Shop, SSS))
advance(0.5)
-- count what reaches the server
local invokes = 0
local serverHandler = buyRemote._props.OnServerInvoke
buyRemote._props.OnServerInvoke = function(...)
	invokes += 1
	return serverHandler(...)
end
for _, p in ipairs({ P, Old }) do
	for _, id in ipairs({ "FishingRod3", "FishingRod2", "FishingRod5" }) do
		p:SetAttribute("RodStock_" .. id, 1) -- deterministic stock for this run
	end
end
local frame = shopGui(P)
runScript(script("LocalScript", "RodShopController", SOURCES.Rods_ShopUI, frame), P)
local oldFrame = shopGui(Old)
runScript(script("LocalScript", "RodShopController", SOURCES.Live_RodShopController, oldFrame), Old)
advance(0.5)

local function card(f, id)
	return f.ScrollingFrame:FindFirstChild(id)
end
local function btn(f, id)
	return card(f, id).BuyButton.Price.Text
end
local function status()
	return frame.RodShopStatus.Text
end
local function press(p, f, id)
	click(p, card(f, id).BuyButton)
end

------------------------------------------------------------ what the cards say (paid shop closed)

check("five cards", #frame.ScrollingFrame:GetChildren() >= 6 and card(frame, "FishingRod5") ~= nil)
check("Tiger: real price, benefit, SOON while the paid shop is closed", card(frame, "FishingRod4").Price.Text == "$150"
	and card(frame, "FishingRod4").Stock.Text == "Bites 15% faster" and btn(frame, "FishingRod4") == "SOON")
check("Basic: OWNED, EQUIPPED", card(frame, "FishingRod1").Price.Text == "OWNED" and btn(frame, "FishingRod1") == "EQUIPPED")
check("Magma: $7,500, Bites 45% faster", card(frame, "FishingRod5").Price.Text == "$7,500" and card(frame, "FishingRod5").Stock.Text == "Bites 45% faster")
check("status says buying opens soon", status() == "Buying opens soon - you can equip rods you own")
local n0 = invokes
press(P, frame, "FishingRod1")
advance(0.2)
check("pressing the equipped rod sends nothing", invokes == n0)

------------------------------------------------------------ open: BUY, then the real results

root:SetAttribute("RodShopOpen", true)
advance(0.1)
check("paid shop opens: BUY (live), status cleared", btn(frame, "FishingRod4") == "BUY" and status() == "")
dsHooks.before = function()
	task.wait(2) -- a slow save
end
press(P, frame, "FishingRod4")
advance(0.3)
check("while the server answers: ...", btn(frame, "FishingRod4") == "...")
local n1 = invokes
press(P, frame, "FishingRod4")
advance(0.1)
check("a second press while waiting sends nothing", invokes == n1)
advance(2)
dsHooks.before = nil
check("bought: BOUGHT! and the server's message", btn(frame, "FishingRod4") == "BOUGHT!" and status() == "Bought and equipped Tiger Rod")
check("charged once", Economy.balance(P) == 850)
advance(1.8)
check("then the live state: Tiger OWNED / EQUIPPED, Basic EQUIP", card(frame, "FishingRod4").Price.Text == "OWNED"
	and btn(frame, "FishingRod4") == "EQUIPPED" and btn(frame, "FishingRod1") == "EQUIP")
press(P, frame, "FishingRod1")
advance(0.2)
check("equip Basic: EQUIPPED, no charge", btn(frame, "FishingRod1") == "EQUIPPED" and status() == "Equipped Basic Rod" and Economy.balance(P) == 850)
advance(1.8)
check("Tiger back to EQUIP", btn(frame, "FishingRod4") == "EQUIP")

press(P, frame, "FishingRod5")
advance(0.2)
check("can't afford Magma: NEED $ + the real message", btn(frame, "FishingRod5") == "NEED $" and status() == "Not enough money")
advance(1.8)
dsHooks.before = function()
	error("DataStore request failed")
end
press(P, frame, "FishingRod3")
advance(0.2)
check("save fails: NOT SAVED + 'you were not charged'", btn(frame, "FishingRod3") == "NOT SAVED"
	and status() == "Couldn't save the purchase - you were not charged. Try again." and Economy.balance(P) == 850)
dsHooks.before = nil
advance(1.8)
check("then BUY again (still not owned)", btn(frame, "FishingRod3") == "BUY" and card(frame, "FishingRod3").Price.Text == "$600")
moveTo(P, SHOP + Vector3.new(80, -7, 0))
press(P, frame, "FishingRod3")
advance(0.2)
check("far away: TOO FAR + the real message", btn(frame, "FishingRod3") == "TOO FAR" and status() == "Walk back to the rod shop to buy")
moveTo(P, SHOP + Vector3.new(0, -7, 5))
advance(3.5)
check("status clears after a few seconds", status() == "")

------------------------------------------------------------ live updates

P:SetAttribute("RodStock_FishingRod2", 0)
advance(0.1)
check("Tide out of stock: SOLD OUT, red note", btn(frame, "FishingRod2") == "SOLD OUT"
	and card(frame, "FishingRod2").Stock.Text == "Bites 35% faster - sold out")
current = "server"
rodsFolder.FishingRod2:SetAttribute("Price", 2500)
current = nil
advance(0.1)
check("a price change shows at once (not captured once)", card(frame, "FishingRod2").Price.Text == "$2,500")
root:SetAttribute("RodShopOpen", false)
advance(0.1)
check("shop closed again: SOON, owned rods still EQUIP", btn(frame, "FishingRod3") == "SOON" and btn(frame, "FishingRod4") == "EQUIP")
root:SetAttribute("RodShopOpen", true)

------------------------------------------------------------ opening / closing

runAs(P, function()
	services.ProximityPromptService.PromptTriggered:Fire(openPrompt)
end)
check("the shop prompt opens the frame", frame.Visible == true)
click(P, frame.CloseButton)
runAs(P, function()
	frame.CloseButton.MouseButton1Click:Fire()
end)
check("X closes it", frame.Visible == false)

------------------------------------------------------------ the live controller (what Studio has now)

moveTo(Old, SHOP + Vector3.new(80, -7, 0))
press(Old, oldFrame, "FishingRod3")
advance(0.2)
check("LIVE controller: 'Walk back to the rod shop' becomes NO $ YET (the reported bug)", btn(oldFrame, "FishingRod3") == "NO $ YET")
check("LIVE controller: no OWNED / EQUIPPED anywhere", oldFrame.ScrollingFrame.FishingRod1.BuyButton.Price.Text ~= "EQUIPPED")

finish("shop ui sim")
