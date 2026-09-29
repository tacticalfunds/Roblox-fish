-- The Money HUD: the REAL new MoneyController (both HUD copies) against the
-- REAL EconomyService. Checks:
--   * the live controller (as Astra sent it) never updates the label here:
--     it waits forever on the missing ReplicatedStorage.FormatModule
--   * "Loading..." until leaderstats.Money exists, then the authoritative
--     balance; follows every change; both HUD copies agree
--   * a save that won't load: stays "Loading...", no errors
--   * LocalPlayer.Money (the old, absent value) is ignored
--   * abbreviations never round up; FormatModule used when it exists and
--     works, and ignored when it errors
--   * multiplier labels: hidden while their inputs are missing (nothing
--     invented), the old formulas when the inputs appear, hidden again when
--     they go; a broken RebirthDefinitions hides only the rebirth label

local Economy, root = installEconomy()

local function hud(p, parent)
	local frame = new("Frame", "MoneyFrame")
	local function label(name, text)
		local l = new("TextLabel", name)
		l._props.Text = text
		l._props.Visible = true
		l.Parent = frame
		return l
	end
	local labels = {
		Money = label("Money", "$0"),
		FriendsMulti = label("FriendsMulti", "x1"),
		VIPMulti = label("VIPMulti", "x1"),
		Rebirth = label("RebirthMulti", "x1"),
		Robux = label("RobuxMulti", "x1"),
	}
	frame.Parent = parent or p.PlayerGui
	runAs(p, function()
		runScript(script("LocalScript", "MoneyController", SOURCES.MoneyController, frame), p)
	end)
	return labels
end

------------------------------------------------------------ the live script: stuck on FormatModule

local oldP = join(10, "OldHud", Vector3.new(0, 5, 0))
local oldFrame = new("Frame", "MoneyFrame")
local oldMoney = new("TextLabel", "Money")
oldMoney._props.Text = "$0"
oldMoney.Parent = oldFrame
for _, n in ipairs({ "FriendsMulti", "VIPMulti" }) do
	new("TextLabel", n).Parent = oldFrame
end
oldFrame.Parent = oldP.PlayerGui
runAs(oldP, function()
	runScript(script("LocalScript", "MoneyController", SOURCES.Live_MoneyController, oldFrame), oldP)
end)
advance(3)
check("live controller: Money loaded on the server", balance(oldP) == 100)
check("live controller: the label never shows it (waits on FormatModule)", oldMoney.Text == "$0")

------------------------------------------------------------ loading, then the authoritative balance

local p = join(1, "Player", Vector3.new(0, 5, 0))
local a = hud(p)
local b = hud(p, new("Folder", "Frames"))
advance(0.5)
check("loaded: the starting balance", a.Money.Text == "$100" and b.Money.Text == "$100")
local ids = asServer(function()
	return Economy.issueFish(p, "Salmon", 10, { Source = "Net" })
end)
local _, amt = asServer(function()
	return Economy.settle(ids[1], "Customer")
end)
check("a sale shows in both copies", a.Money.Text == "$" .. (100 + amt) and b.Money.Text == a.Money.Text)
asServer(function()
	return Economy.tryDebit(p, 50, "test")
end)
check("a purchase shows", a.Money.Text == "$" .. (50 + amt) and b.Money.Text == a.Money.Text)
check("it is exactly leaderstats.Money", a.Money.Text == "$" .. p.leaderstats.Money.Value)

------------------------------------------------------------ nothing invented

for _, key in ipairs({ "FriendsMulti", "VIPMulti", "Rebirth", "Robux" }) do
	check("no inputs: " .. key .. " hidden", a[key].Visible == false and b[key].Visible == false)
end
check("no inputs: texts left alone", a.FriendsMulti.Text == "x1" and a.Robux.Text == "x1")

------------------------------------------------------------ the old LocalPlayer.Money is ignored

local legacy = new("NumberValue", "Money")
legacy._props.Value = 999999
legacy.Parent = p
check("LocalPlayer.Money ignored", a.Money.Text == "$" .. p.leaderstats.Money.Value)

------------------------------------------------------------ leaderstats.Money goes away and comes back

local stat = p.leaderstats.Money
stat.Parent = nil
check("Money value removed: back to Loading...", a.Money.Text == "Loading...")
stat.Parent = p.leaderstats
check("and back", a.Money.Text == "$" .. stat.Value)

------------------------------------------------------------ a save that won't load

local KEY = Economy.Config.KeyPrefix
dsData[KEY .. "2"] = { v = 1, money = 500, lock = { job = "another-server", t = 1700000000 + 10 ^ 7 } }
local stuck = join(2, "Stuck", Vector3.new(5, 5, 0))
local s = hud(stuck)
advance(10)
check("locked save: Loading..., never a number", balance(stuck) == nil and s.Money.Text == "Loading...")
dsData[KEY .. "2"].lock = nil
advance(35)
check("the save loads later: its balance appears", balance(stuck) == 500 and s.Money.Text == "$500")

------------------------------------------------------------ abbreviations (truncated, never rounded up)

local function showing(userId, money)
	dsData[KEY .. userId] = { v = 1, money = money }
	local q = join(userId, "P" .. userId, Vector3.new(0, 5, 0))
	local h = hud(q)
	advance(0.5)
	return h.Money.Text
end
check("999 -> $999", showing(20, 999) == "$999")
check("1000 -> $1K", showing(21, 1000) == "$1K")
check("1234 -> $1.23K", showing(22, 1234) == "$1.23K")
check("999999 -> $999.99K (not $1000K)", showing(23, 999999) == "$999.99K")
check("1250000 -> $1.25M", showing(24, 1250000) == "$1.25M")
check("10500000 -> $10.5M", showing(25, 10500000) == "$10.5M")
check("the balance limit -> $1T", showing(26, Economy.Config.MaxBalance) == "$1T")

------------------------------------------------------------ FormatModule: used when it works, ignored when it errors

local fm = script("ModuleScript", "FormatModule", [[
local M = {}
function M:AbbreviateNumbers(n) return "F" .. tostring(n) end
return M
]], services.ReplicatedStorage)
check("working FormatModule is used", showing(30, 1234) == "$F1234")
fm:Destroy()
script("ModuleScript", "FormatModule", [[
local M = {}
function M:AbbreviateNumbers(n) error("broken") end
return M
]], services.ReplicatedStorage)
check("erroring FormatModule: own format", showing(31, 1234) == "$1.23K")
services.ReplicatedStorage.FormatModule:Destroy()

------------------------------------------------------------ multipliers when their inputs exist (the old formulas)

local modules = new("Folder", "Modules")
script("ModuleScript", "RebirthDefinitions", [[
local M = {}
function M:GetMultiplier(r) return 1 + r * 0.5 end
return M
]], modules)
modules.Parent = services.ReplicatedStorage
local m = join(40, "Multi", Vector3.new(0, 5, 0))
local h = hud(m)
advance(0.5)
check("module alone, no Rebirths value: still hidden", h.Rebirth.Visible == false)
local function value(class, name, v, parent)
	local x = new(class, name)
	x._props.Value = v
	x.Parent = parent or m
	return x
end
local rebirths = value("IntValue", "Rebirths", 3)
check("Rebirths appears: x2.5", h.Rebirth.Visible == true and h.Rebirth.Text == "x2.5")
rebirths.Value = 4
check("Rebirths changes: x3", h.Rebirth.Text == "x3")
local friends = value("NumberValue", "FriendsMultiplier", 1.1)
check("friends x1.1", h.FriendsMulti.Visible == true and h.FriendsMulti.Text == "x1.1")
local vip = value("BoolValue", "VIP", false)
check("VIP off: x1", h.VIPMulti.Visible == true and h.VIPMulti.Text == "x1")
vip.Value = true
check("VIP on: x1.25", h.VIPMulti.Text == "x1.25")
local upgrades = new("Folder", "Upgrades")
upgrades.Parent = m
check("Upgrades without RobuxMultiplier: hidden", h.Robux.Visible == false)
local robux = value("IntValue", "RobuxMultiplier", 3, upgrades)
check("RobuxMultiplier 3: x8", h.Robux.Visible == true and h.Robux.Text == "x8")
robux.Value = 40
check("clamped at 2^15", h.Robux.Text == "x32768")
friends.Parent = nil
check("FriendsMultiplier removed: hidden again", h.FriendsMulti.Visible == false)
local wrongVip = new("StringValue", "VIP")
vip.Parent = nil
wrongVip.Parent = m
check("VIP that isn't a BoolValue: hidden, not x1", h.VIPMulti.Visible == false)
check("money unaffected by multipliers", h.Money.Text == "$100" and balance(m) == 100)

-- a RebirthDefinitions that errors hides only the rebirth label
modules.RebirthDefinitions:Destroy()
script("ModuleScript", "RebirthDefinitions", [[
local M = {}
function M:GetMultiplier(r) error("broken") end
return M
]], modules)
local m2 = join(41, "Multi2", Vector3.new(0, 5, 0))
value("IntValue", "Rebirths", 3, m2)
value("NumberValue", "FriendsMultiplier", 2, m2)
local h2 = hud(m2)
advance(0.5)
check("broken RebirthDefinitions: rebirth hidden", h2.Rebirth.Visible == false)
check("the others still work", h2.FriendsMulti.Visible == true and h2.FriendsMulti.Text == "x2" and h2.Money.Text == "$100")

finish("money hud sim")
