-- The saved customer upgrades (Customer Speed, Customer Line) through the
-- REAL EconomyService: bought with EconomyService.upgradeAction (the same
-- path, checks and one atomic money + levels write as the board upgrades),
-- saved in the Money record's `upgrades`, and read by
-- EconomyService.customers() (what CustomerSystem asks every spawn):
--   * closed (UpgradesOpen) / not enough money / failed save: refused, not charged
--   * Customer Speed 6 -> 9 a minute for $25, one write, toast in "/min"
--   * solo: 9 a minute; with a second player at the base: 9 + 6 = 15
--   * Customer Line 6 -> 7 -> 8, then MAX; the server's line is the largest
--   * the levels come back after a rejoin; a player who left stops counting
--   * a player still loading counts at the base

local Economy, root = installEconomy()
local KEY = Economy.Config.KeyPrefix
dsData[KEY .. "1"] = { v = 2, money = 1000 }
dsData[KEY .. "2"] = { v = 2, money = 5 }
local A = join(1, "Buyer", Vector3.new(0, 10, 0))
advance(2)

local function buy(p, id)
	local ok, msg
	runAs("server", function()
		ok, msg = Economy.upgradeAction(p, id, nil)
	end)
	advance(0.6)
	return ok, msg
end
local function customers()
	local r, c
	runAs("server", function()
		r, c = Economy.customers()
	end)
	return r, c
end

------------------------------------------------------------ closed / funds / failed save

local ok, msg = buy(A, "CustomerSpeed")
check("closed by default (UpgradesOpen): refused, not charged", ok == false and msg == "Customer Speed upgrades open soon"
	and Economy.balance(A) == 1000)
root:SetAttribute("UpgradesOpen", true)
local r0, c0 = customers()
check("solo at the base: 6 a minute, 6 in line", r0 == 6 and c0 == 6)
check("published for display: UpgCustomerSpeed 6 > 9 for $25; UpgCustomerLine 6 > 7 for $40",
	A:GetAttribute("UpgCustomerSpeed") == 6 and A:GetAttribute("UpgCustomerSpeedNext") == 9 and A:GetAttribute("UpgCustomerSpeedCost") == 25
	and A:GetAttribute("UpgCustomerLine") == 6 and A:GetAttribute("UpgCustomerLineNext") == 7 and A:GetAttribute("UpgCustomerLineCost") == 40)

dsHooks.before = function()
	error("DataStore request failed")
end
ok, msg = buy(A, "CustomerSpeed")
dsHooks.before = nil
check("save fails: refused, not charged, still 6 a minute", ok == false and Economy.balance(A) == 1000 and (customers()) == 6)

------------------------------------------------------------ buying

local writes = 0
dsHooks.before = function()
	writes += 1
end
ok, msg = buy(A, "CustomerSpeed")
dsHooks.before = nil
check("Customer Speed 6/min -> 9/min for $25, the toast says so", ok == true and msg == "Customer Speed 6/min → 9/min (-$25)"
	and Economy.balance(A) == 975)
check("saved at once: money AND the level in one write", writes == 1 and dsData[KEY .. "1"].money == 975
	and dsData[KEY .. "1"].upgrades.CustomerSpeed == 1)
check("solo: 9 customers a minute now", (customers()) == 9)
ok, msg = buy(A, "CustomerLine")
check("Customer Line 6 -> 7 in line for $40", ok == true and msg == "Customer Line 6 in line → 7 in line (-$40)"
	and Economy.balance(A) == 935 and select(2, customers()) == 7)
ok = buy(A, "CustomerLine")
check("... 7 -> 8 for $120", ok == true and Economy.balance(A) == 815 and select(2, customers()) == 8)
ok, msg = buy(A, "CustomerLine")
check("at the sidewalk's 8: refused as the maximum, not charged", ok == false and msg == "Customer Line is at the maximum (8 in line)"
	and Economy.balance(A) == 815)

------------------------------------------------------------ the shared scene

local B = join(2, "Second", Vector3.new(5, 10, 0))
advance(2)
local r2, c2 = customers()
check("a second player at the base: 9 + 6 = 15 a minute; the line is the larger (8)", r2 == 15 and c2 == 8)
ok, msg = buy(B, "CustomerSpeed")
check("B can't afford it ($5): refused, not charged", ok == false and msg == "Not enough money" and Economy.balance(B) == 5)
leave(A)
advance(2)
local r3, c3 = customers()
check("A leaves: A's levels stop counting (B alone: 6 a minute, 6 in line)", r3 == 6 and c3 == 6)

------------------------------------------------------------ rejoin

dsData[KEY .. "3"] = { v = 2, money = 0, lock = { job = "another-server", t = 1700000000 + 10 ^ 7 } }
local C = join(3, "Loading", Vector3.new(10, 10, 0))
advance(2)
check("a player still loading counts at the base (6 + 6 = 12)", (customers()) == 12)
leave(C)
A = join(1, "Buyer", Vector3.new(0, 10, 0))
advance(2)
local r4, c4 = customers()
check("A rejoins: the saved levels are back (9 + 6 = 15 a minute, line 8)", r4 == 15 and c4 == 8
	and A:GetAttribute("UpgCustomerSpeed") == 9 and A:GetAttribute("UpgCustomerLine") == 8)

finish("customer upgrades sim")
