#!/usr/bin/env python3
"""Rod shop UI for rods milestone 1 (StarterGui.ScreenGui.Buttons.Frames.
RodShopFrame.RodShopController).

Patches the EXACT live controller (studio/live/RodShopController.lua, as
Astra sent it on 2026-09-29) into studio/rods/RodShopController.lua. The
picture, restock countdown, open / close and scrolling code are untouched.
Changes, marked "Rods":

  * each card: the rod's real price (the server sets the Price attribute) or
    OWNED; its benefit ("Bites 15% faster", the Benefit attribute); the
    button says what pressing does: BUY / EQUIP / EQUIPPED / SOON (paid shop
    not open: ReplicatedStorage.Economy.RodShopPaidOpen) / SOLD OUT
  * everything refreshes live from the server's attributes (RodOwned_<id>,
    EquippedRod, RodStock_<id>, Price, Benefit, RodShopPaidOpen); nothing is
    captured once
  * pressing: "..." while the server answers (one request per rod at a
    time; pressing the equipped rod sends nothing), then the server's real
    result as short button text (BOUGHT! / EQUIPPED / NEED $ / TOO FAR /
    NOT SAVED / ...) and the full message on a status line under the cards
  * the client decides nothing: the server checks and charges

Usage:  python3 tools/economy/build/make_shop_ui.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = ROOT / "studio" / "live" / "RodShopController.lua"
OUT = ROOT / "studio" / "rods" / "RodShopController.lua"


class Patch:
    def __init__(self, base: str):
        self.src = base

    def rep(self, old: str, new: str) -> None:
        n = self.src.count(old)
        assert n == 1, f"expected 1 match, got {n}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


HEADER = """-- Rod shop UI: opens from the shop stand prompt, shows each rod with price + stock, restock countdown.
--
-- [Economy rods v1] Changes marked "Rods": each card shows the rod's real
-- price and benefit and whether you OWN it / have it EQUIPPED (the server's
-- RodOwned_<id> / EquippedRod attributes); the button says what pressing
-- does (BUY / EQUIP / EQUIPPED / SOON / SOLD OUT), shows "..." while the
-- server answers, then the server's real result; the full message appears
-- on a status line under the cards. The server checks and charges; nothing
-- here decides anything.
"""

SETUP = '''local buyRemote = shop:WaitForChild("BuyRod")

-- Rods: the economy root (RodShopPaidOpen) and a status line under the cards
local econ = RS:FindFirstChild("Economy")
local LIME, GREEN, RED = Color3.fromRGB(120, 255, 40), Color3.fromRGB(120, 255, 120), Color3.fromRGB(255, 90, 90)
local status = Instance.new("TextLabel")
status.Name = "RodShopStatus"
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.Position = UDim2.fromScale(0.5, 0.955)
status.Size = UDim2.fromScale(0.9, 0.065)
status.BackgroundTransparency = 1
status.Font = Enum.Font.FredokaOne
status.TextScaled = true
status.TextColor3 = Color3.new(1, 1, 1)
status.Text = ""
status.ZIndex = 5
do
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = Color3.fromRGB(10, 10, 12)
	st.Parent = status
end
status.Parent = frame
-- the server's replies -> short button text (anything else: TRY AGAIN)
local SHORT = {
	["Not enough money"] = "NEED $",
	["Sold out"] = "SOLD OUT",
	["The rod shop opens soon"] = "SOON",
	["Walk back to the rod shop to buy"] = "TOO FAR",
	["Your money is still loading - try again in a moment"] = "LOADING",
	["Couldn't save the purchase - you were not charged. Try again."] = "NOT SAVED",
	["One moment - still saving"] = "SAVING",
	["Slow down a little"] = "WAIT",
	["You already own that rod"] = "OWNED",
	["You can't do that right now"] = "NOT NOW",
	["The rod shop is unavailable right now"] = "CLOSED",
	["Your saved rods couldn't be read, so buying rods is off this session"] = "UNAVAILABLE",
}
local busy, flash = {}, {} -- rod name -> waiting for the server / { text, untilT }
local statusUntil = 0
local refresh -- defined below
local function paidOpen()
	return econ ~= nil and econ:GetAttribute("RodShopPaidOpen") == true
end
local function showStatus(text, seconds)
	status.Text = text
	statusUntil = os.clock() + seconds
	task.delay(seconds, function()
		if os.clock() >= statusUntil then
			refresh()
		end
	end)
end
-- one request per rod at a time; the equipped rod sends nothing
local function buyPressed(name)
	if busy[name] or player:GetAttribute("EquippedRod") == name then
		return
	end
	busy[name] = true
	refresh()
	local reached, ok, msg = pcall(function()
		return buyRemote:InvokeServer(name)
	end)
	busy[name] = nil
	local text
	if not reached then
		text, msg = "TRY AGAIN", "Couldn't reach the server - try again"
	elseif ok == true then
		text = if type(msg) == "string" and string.sub(msg, 1, 6) == "Bought" then "BOUGHT!" else "EQUIPPED"
	else
		text = SHORT[msg] or "TRY AGAIN"
	end
	flash[name] = { text = text, untilT = os.clock() + 1.6 }
	if type(msg) == "string" then
		showStatus(msg, 3)
	end
	refresh()
	task.delay(1.7, function()
		refresh()
	end)
end
'''

BUY_OLD = '''	buy.Activated:Connect(function()
		click()
		local ok, msg = buyRemote:InvokeServer(rod.Name)
		local label = buy.Price
		local before = label.Text
		label.Text = ok and "BOUGHT!" or (msg == "Not enough money" and "NEED $" or (msg == "Sold out" and "SOLD OUT" or "NO $ YET"))
		task.delay(1.2, function() if label.Parent then label.Text = before end end)
	end)
'''
BUY_NEW = '''	buy.Activated:Connect(function()
		click()
		buyPressed(rod.Name) -- Rods: the server's real answer, see buyPressed
	end)
'''

REFRESH_OLD = '''local function refresh()
	for name, card in pairs(cards) do
		local s = player:GetAttribute("RodStock_" .. name) or 0
		card.Stock.Text = s > 0 and ("x" .. s .. " Stock") or "Out of stock"
		card.Stock.TextColor3 = s > 0 and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 90, 90)
		card.BuyButton.Price.Text = s > 0 and "BUY" or "SOLD OUT"
	end
end
player.AttributeChanged:Connect(function(a) if a:sub(1, 9) == "RodStock_" then refresh() end end)
refresh()
'''
REFRESH_NEW = '''-- Rods: price or OWNED, benefit, and what the button does, all from the
-- server's attributes (they can change while the shop is open)
function refresh()
	local open = paidOpen()
	local now = os.clock()
	for name, card in pairs(cards) do
		local rod = rods:FindFirstChild(name)
		local owned = player:GetAttribute("RodOwned_" .. name) ~= nil
		local equipped = player:GetAttribute("EquippedRod") == name
		local s = player:GetAttribute("RodStock_" .. name) or 0
		local price = rod and rod:GetAttribute("Price") or 0
		local benefit = rod and rod:GetAttribute("Benefit")
		card.Price.Text = if owned then "OWNED" else money(price)
		local soldOut = not owned and s <= 0
		if type(benefit) == "string" then
			card.Stock.Text = if soldOut then benefit .. " - sold out" else benefit
		else
			card.Stock.Text = s > 0 and ("x" .. s .. " Stock") or "Out of stock"
		end
		card.Stock.TextColor3 = if soldOut then RED else GREEN
		local f = flash[name]
		local label
		if busy[name] then
			label = "..."
		elseif f and now < f.untilT then
			label = f.text
		elseif equipped then
			label = "EQUIPPED"
		elseif owned then
			label = "EQUIP"
		elseif not open then
			label = "SOON"
		elseif soldOut then
			label = "SOLD OUT"
		else
			label = "BUY"
		end
		card.BuyButton.Price.Text = label
		card.BuyButton.Price.TextColor3 = if equipped then LIME else Color3.new(1, 1, 1)
	end
	if now >= statusUntil then
		status.Text = if econ == nil
			then "The rod shop is unavailable right now"
			elseif not open then "Buying opens soon - you can equip rods you own"
			else ""
	end
end
player.AttributeChanged:Connect(function(a)
	if a:sub(1, 9) == "RodStock_" or a:sub(1, 9) == "RodOwned_" or a == "EquippedRod" then refresh() end
end)
for _, rod in ipairs(rods:GetChildren()) do
	rod.AttributeChanged:Connect(function(a)
		if a == "Price" or a == "Benefit" then refresh() end
	end)
end
local function watchEconomy(e)
	econ = e
	e:GetAttributeChangedSignal("RodShopPaidOpen"):Connect(refresh)
	refresh()
end
if econ then
	watchEconomy(econ)
else
	RS.ChildAdded:Connect(function(c)
		if c.Name == "Economy" and not econ then watchEconomy(c) end
	end)
end
refresh()
'''


def build() -> str:
    p = Patch(BASE.read_text())
    p.rep("-- Rod shop UI: opens from the shop stand prompt, shows each rod with price + stock, restock countdown.\n", HEADER)
    p.rep('local buyRemote = shop:WaitForChild("BuyRod")\n', SETUP)
    p.rep(BUY_OLD, BUY_NEW)
    p.rep(REFRESH_OLD, REFRESH_NEW)
    src = p.src
    assert "NO $ YET" not in src and "BOUGHT!" in src
    assert "local function fillViewport(vp, rodModel)" in src and 'if prompt.Name == "OpenShopPrompt" then frame.Visible = true end' in src
    return src


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(build())
    print(f"wrote {OUT.relative_to(ROOT.parent.parent)}")


if __name__ == "__main__":
    main()
