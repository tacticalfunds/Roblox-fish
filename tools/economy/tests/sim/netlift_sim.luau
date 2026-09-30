-- The net's weight gate is PER PLAYER: Astra's LIVE NetLiftScript (it reads
-- the pad player's NetMaxWeight before NetLift.MaxWeight) with the REAL
-- EconomyService and NetCapacityServer. 30 kg of fish over the net:
--   * A (40 kg saved, adopted) lifts it
--   * B, whose earlier buys aren't adopted yet (nothing published), is held
--     to the BASE 15 kg - never A's 40 (NetCapacityServer no longer raises
--     NetLift.MaxWeight to the highest player)
--   * C (15 kg) is refused; after buying 15 -> 20 -> 25 -> 30 C lifts it
local Economy, root = installEconomy()
local SSS = services.ServerScriptService
local ws = workspaceInst
local KEY = Economy.Config.KeyPrefix
local NET = Vector3.new(0, 5, 100)

current = "server"
local netLift = new("Model", "NetLift")
netLift:SetAttribute("MaxWeight", 15)
local hitbox = part("PadHitbox", NET + Vector3.new(-30, 0, 0), netLift, Vector3.new(6, 1, 6))
part("Pad", NET + Vector3.new(-30, -0.5, 0), netLift, Vector3.new(6, 1, 6))
local prints = new("Folder", "Prints")
part("Print1", NET + Vector3.new(-30, 0, 1), prints)
prints.Parent = netLift
local net = new("Model", "Net")
local netRoot = part("NetRoot", NET, net, Vector3.new(30, 1, 12))
net.Parent = netLift
netLift.Parent = ws
local fish = new("Folder", "SwimmingFish")
fish.Parent = ws
current = nil

local function load30()
	current = "server"
	for _, c in ipairs(fish:GetChildren()) do
		c:Destroy()
	end
	for i = 1, 3 do
		local m = model("Cod", fish, NET + Vector3.new(i, 0, 0))
		m:SetAttribute("SpawnT", now)
		m:SetAttribute("StartZ", NET.Z)
		m:SetAttribute("Speed", 0)
		m:SetAttribute("LaneX", NET.X)
		m:SetAttribute("Seed", 7)
		m:SetAttribute("Weight", 10)
		m:SetAttribute("Tier", 1)
	end
	current = nil
end

dsData[KEY .. "1"] = { v = 2, money = 100, netKg = 40 }
dsData[KEY .. "2"] = { v = 2, money = 100 }
dsData[KEY .. "3"] = { v = 2, money = 1000 }
local A = join(1, "Strong", Vector3.new(0, 5, 0))
local B = join(2, "Pending", Vector3.new(0, 5, 5))
local C = join(3, "Weak", Vector3.new(0, 5, 10))
runScript(script("Script", "NetCapacityServer", SOURCES.Kg_Server, SSS))
local lift = script("Script", "NetLiftScript", SOURCES.NetLift_Live, netLift)
runScript(lift)
advance(1)
-- earlier KG buys: A's (5 buys -> max(40, 40)) and C's (none) reported; B's not yet
asServer(function()
	Economy.adoptLegacyNetKg(A, 5)
	Economy.adoptLegacyNetKg(C, 0)
end)
advance(0.5)
check("published: A 40 kg, C 15 kg; B nothing yet; the base 15", A:GetAttribute("NetMaxWeight") == 40 and C:GetAttribute("NetMaxWeight") == 15
	and B:GetAttribute("NetMaxWeight") == nil and netLift:GetAttribute("MaxWeight") == 15)

local function step(p)
	local lifts, fails = netLift:GetAttribute("LiftId") or 0, netLift:GetAttribute("FailId") or 0
	asServer(function()
		hitbox.Touched:Fire(p.Character.HumanoidRootPart)
	end)
	advance(4)
	return (netLift:GetAttribute("LiftId") or 0) > lifts, (netLift:GetAttribute("FailId") or 0) > fails
end

load30()
local lifted, failed = step(B)
check("B (not adopted yet) on the pad with 30 kg: refused at the BASE 15, not A's 40", not lifted and failed)
lifted, failed = step(C)
check("C (15 kg) on the pad with 30 kg: refused", not lifted and failed)
lifted = step(A)
check("A (40 kg) lifts the same 30 kg", lifted)

-- C buys up to 30 kg (15 -> 20 -> 25 -> 30: 10 + 25 + 50)
root:SetAttribute("NetKgOpen", true)
advance(0.1)
for _ = 1, 3 do
	asServer(function()
		Economy.netKgAction(C, nil)
	end)
	advance(0.7)
end
check("C bought up to 30 kg (85 spent)", C:GetAttribute("NetMaxWeight") == 30 and Economy.balance(C) == 915
	and netLift:GetAttribute("MaxWeight") == 15)
load30()
lifted = step(C)
check("now C lifts 30 kg with their own net", lifted)
load30()
lifted, failed = step(B)
check("B still held to the base (nobody else's net carries over)", not lifted and failed)

finish("netlift sim")
