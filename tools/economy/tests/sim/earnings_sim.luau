-- The "+$" earnings popup: the REAL EconomyService tells a piece's owner
-- when it sells; the REAL EconomyClient shows it. Checks:
--   * only the owner sees it (never the carrier, nobody for unowned meat)
--   * the amount is exactly what was paid, once (a second sale shows nothing)
--   * quick sales add up into one popup, then it hides and starts fresh
--   * Gold / Silver meat tints it; the route is named
--   * EarningsPopup = false: still paid, no popup
--   * junk sent to the client is ignored

local Economy, root = installEconomy()

local owner = join(1, "Owner", Vector3.new(0, 5, 0))
local carrier = join(2, "Carrier", Vector3.new(5, 5, 0))
advance(0.5)

local function popup(p)
	local gui = p.PlayerGui:FindFirstChild("EconomyNotices")
	local frame = gui and gui:FindFirstChild("Earnings")
	return frame, frame and frame:FindFirstChild("Amount"), frame and frame:FindFirstChild("Detail")
end
local function issue(p, name, tier, meta)
	return asServer(function()
		return Economy.issueFish(p, name, tier, meta)
	end)
end
local function rgb(c, r, g, b)
	return c and math.abs(c.R * 255 - r) < 0.5 and math.abs(c.G * 255 - g) < 0.5 and math.abs(c.B * 255 - b) < 0.5
end
local function sell(id, route)
	return asServer(function()
		return Economy.settle(id, route)
	end)
end

check("the service made Economy.Earned", root:FindFirstChild("Earned") ~= nil)
local frame, amount, detail = popup(owner)
check("the popup exists, hidden", frame ~= nil and frame.Visible == false)

------------------------------------------------------------ one sale

local ids = issue(owner, "Salmon", 10, { Source = "Net" })
check("fish cut into several pieces", #ids >= 2)
local before = balance(owner)
local paid, amt = sell(ids[1], "Customer")
check("owner paid", paid == true and amt > 0 and balance(owner) == before + amt)
check("owner sees +$ exactly the amount", frame.Visible and amount.Text == "+$" .. amt)
check("detail names the fish and where it sold", detail.Text == "Salmon sold to a customer")
local carrierFrame = popup(carrier)
check("the carrier sees nothing", carrierFrame.Visible == false)

-- a second sale of the same piece pays and shows nothing
local tweens = #tweensPlayed
paid = sell(ids[1], "Truck")
check("resale pays nothing and adds nothing", paid == false and amount.Text == "+$" .. amt and #tweensPlayed == tweens)

------------------------------------------------------------ quick sales add up

local total = amt
for i = 2, #ids do
	local _, a = sell(ids[i], "Truck")
	total += a
	advance(0.3)
end
check("quick sales add up into one popup", amount.Text == "+$" .. total)
check("and count the pieces", detail.Text == #ids .. " pieces sold")
advance(3)
check("hides after the last sale", frame.Visible == false)

------------------------------------------------------------ variants tint it; a fresh run starts from 0

local gold = issue(owner, "Cod", 1, { Source = "Net", Variant = "Gold" })
local _, ga = sell(gold[1], "Truck")
check("new run starts from zero", amount.Text == "+$" .. ga)
check("Gold meat: gold popup", rgb(amount.TextColor3, 255, 205, 40))
check("Gold named, truck route", detail.Text == "Gold Cod sold to a truck")
-- a plain sale 2 s later joins the run: still gold, and the first sale's
-- timer doesn't hide it early
advance(2)
local more = issue(owner, "Cod", 1, { Source = "Net" })
local _, ma = sell(more[1], "Truck")
check("a plain sale in a gold run keeps it gold", rgb(amount.TextColor3, 255, 205, 40) and amount.Text == "+$" .. (ga + ma))
advance(1.5)
check("the popup stays 2.5 s after the LAST sale", frame.Visible == true)
advance(1.5)
check("then hides", frame.Visible == false)
local plain = issue(owner, "Cod", 1, { Source = "Net" })
sell(plain[1], "Customer")
check("plain meat: green again", rgb(amount.TextColor3, 90, 235, 90))
advance(3)

------------------------------------------------------------ nobody / absent owner / switched off

local unowned = issue(nil, "Cod", 1, { Source = "Harpoon" })
local tw = #tweensPlayed
paid = sell(unowned[1], "Truck")
check("unowned harpoon meat: pays nobody, no popup anywhere", paid == false and #tweensPlayed == tw and frame.Visible == false and carrierFrame.Visible == false)

root:SetAttribute("EarningsPopup", false)
local off = issue(owner, "Cod", 1, { Source = "Net" })
before = balance(owner)
paid, amt = sell(off[1], "Truck")
check("popup off: still paid", paid == true and balance(owner) == before + amt)
check("popup off: nothing shown", frame.Visible == false)
root:SetAttribute("EarningsPopup", nil)

------------------------------------------------------------ junk from the network is ignored

for _, args in ipairs({ { "5" }, { -3 }, { 0 / 0 }, { math.huge }, { nil } }) do
	asServer(function()
		root.Earned:FireClient(owner, table.unpack(args, 1, 1), "Truck", "Cod")
	end)
end
check("junk amounts show nothing", frame.Visible == false)
asServer(function()
	root.Earned:FireClient(owner, 7, { "x" }, 42, "Platinum")
end)
check("junk labels fall back safely", frame.Visible and amount.Text == "+$7" and detail.Text == "Meat sold")
check("unknown variant isn't tinted", rgb(amount.TextColor3, 90, 235, 90))
advance(3)

------------------------------------------------------------ owner left: the sale still settles, nothing errors

local later = issue(owner, "Cod", 1, { Source = "Net" })
leave(owner)
paid = sell(later[1], "Truck")
check("owner gone: not paid here, no error", paid == false)

finish("earnings sim")
