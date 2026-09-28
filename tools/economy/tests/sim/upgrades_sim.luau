-- Paid aquarium upgrades: the REAL AquariumEconomy (economy version), the
-- REAL EconomyService and the REAL aquarium v1.2 SharedTank, wired exactly
-- as AquariumCycleServer.onUpgrade wires them (the prompt's triggering
-- player pays; the price comes from the tank's own tables).

local Economy = installEconomy()
local RS = services.ReplicatedStorage
local SSS = services.ServerScriptService

current = "server"
local aq = new("Folder", "AquariumCycle")
for _, name in ipairs({
	"Adapters",
	"Config",
	"CycleState",
	"Messages",
	"RiverRelease",
	"SharedTank",
	"TankPath",
	"Upgrades",
}) do
	script("ModuleScript", name, SOURCES["Aq_" .. name], aq)
end
aq.Parent = RS
local adapterModule = script("ModuleScript", "AquariumEconomy", SOURCES.AquariumEconomy, SSS)
current = nil

local P = join(1, "Payer", Vector3.new(0, 0, 0))
local Q = join(2, "Other", Vector3.new(0, 0, 0))
advance(1)

local adapter, AqConfig, SharedTank, Upgrades
runAs("server", function()
	adapter = requireModule(adapterModule)
	AqConfig = requireModule(aq.Config)
	SharedTank = requireModule(aq.SharedTank)
	Upgrades = requireModule(aq.Upgrades)
end)
check("adapter available while the economy runs", type(adapter) == "table" and type(adapter.tryCharge) == "function")

local tank = SharedTank.new(AqConfig)
tank:registerRods({ 1, 2, 3 })
-- AquariumCycleServer.onUpgrade: the triggering player pays
local function buy(player, id)
	return asServer(function()
		return tank:buyUpgrade({
			Economy = {
				tryCharge = function(_owner, amount, why)
					return adapter.tryCharge(player, amount, why) == true
				end,
			},
		}, id)
	end)
end

local cap1 = AqConfig.Upgrades.Capacity.Costs[1]
check("first tank upgrade costs 50 and the grant covers it with money left", cap1 == 50 and 100 - cap1 >= 30)
local ok, _, level = buy(P, "Capacity")
check("capacity upgrade bought", ok and level == 2 and tank:info().capacity == Upgrades.value(AqConfig, "Capacity", 2))
check("charged exactly the listed price", balance(P) == 100 - cap1)
check("another player is not charged", balance(Q) == 100)

-- not enough Money: nothing charged, nothing applied
local cap2 = AqConfig.Upgrades.Capacity.Costs[2]
local ok2, why2 = buy(P, "Capacity")
check("can't afford the next level: refused", not ok2 and why2 == "funds")
check("refused upgrade: level and Money unchanged", tank:info().levels.Capacity == 2 and balance(P) == 100 - cap1)
check("next price is the table's", cap2 == Upgrades.nextCost(AqConfig, "Capacity", 2))

-- another player buys the next level for the shared tank (session-scoped)
asServer(function()
	Economy.credit(Q, cap2, "test")
end)
local ok3, _, level3 = buy(Q, "Capacity")
check("any player can buy the shared tank's next level", ok3 and level3 == 3 and balance(Q) == 100)

-- release rate upgrade and max level
local rr = AqConfig.Upgrades.ReleaseRate.Costs[1]
asServer(function()
	Economy.credit(P, 10000, "test")
end)
local balP = balance(P)
check("release-rate upgrade", (buy(P, "ReleaseRate")) and balance(P) == balP - rr)
local spent = 0
while true do
	local b = balance(P)
	local okM, whyM = buy(P, "Capacity")
	if not okM then
		check("at max: refused as maxed, nothing charged", whyM == "max" and balance(P) == b)
		break
	end
	spent += b - balance(P)
end
check("max level reached", tank:info().levels.Capacity == Upgrades.maxLevel(AqConfig, "Capacity"))
check("unknown upgrade refused", not buy(P, "Nope"))

-- money not loaded: refused with a notice, nothing charged
local R
do
	-- a player whose money never loads (DataStore key locked by another server)
	local key = "player_3"
	dsData[key] = { money = 500, schema = 1, lock = { job = "other-server", t = 1700000000 + 1e9 } }
	R = join(3, "Locked", Vector3.new(0, 0, 0))
	advance(2)
	local okR, whyR = buy(R, "ReleaseRate")
	check("money not loaded: refused", not okR and whyR == "funds")
	check("money not loaded: told why", table.find(notices[R], "Money is still loading - try again in a moment") ~= nil)
	check("money not loaded: nothing written", dsData[key].money == 500)
end

finish("upgrades sim")
