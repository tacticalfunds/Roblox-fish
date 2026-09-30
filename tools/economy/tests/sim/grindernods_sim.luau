-- The patched GrinderUpgradesServer in a LIVE server (not Studio) whose
-- GrinderUpgrades_v1 DataStore is unavailable. Before, it fell back to a
-- memory store (purchases charged, then lost on leave). Now: nothing is
-- loaded or bought (fail closed), no memory store, nothing charged; the
-- player's net isn't published or sold either (their earlier KG buys can't
-- be read, so they can't be adopted). The Money store itself still works.

studioMode.on = false
dsHooks.store = function(name)
	if name == "GrinderUpgrades_v1" then
		error("DataStore unavailable (fake)")
	end
end
local Economy, root = installEconomy()
local RS = services.ReplicatedStorage
local SSS = services.ServerScriptService
local ws = workspaceInst
local KEY = Economy.Config.KeyPrefix
local SIGN = Vector3.new(-42.4489, 12.0365, 206.336)
local PAD = Vector3.new(-60, 8, 170)

current = "server"
script("ModuleScript", "GrinderUpgradesConfig", SOURCES.Grinder_Config, RS)
local netLift = new("Model", "NetLift")
netLift:SetAttribute("MaxWeight", 15)
netLift.Parent = ws
local pad = new("Model", "BladePad")
local touch = part("TouchPart", PAD, pad, Vector3.new(4, 1, 4))
pad.Parent = ws
addTag(pad, "BladePad")
local sign = new("Model", "KGsign")
local board = part("Board Part", SIGN, sign, Vector3.new(8, 4, 0.5))
local cd = new("ClickDetector", "ClickDetector")
cd._props.MaxActivationDistance = 20
cd.Parent = board
sign.Parent = ws
addTag(sign, "KgSign")
current = nil

dsData[KEY .. "1"] = { v = 2, money = 50000 }
local A = join(1, "Live", PAD + Vector3.new(0, 2, 0))
warnings = {}
runScript(script("Script", "NetCapacityServer", SOURCES.Kg_Server, SSS))
runScript(script("Script", "GrinderUpgradesServer", SOURCES.Grinder_Server, SSS))
advance(2)
root:SetAttribute("NetKgOpen", true)
advance(0.1)

local warned = false
for _, w in ipairs(warnings) do
	warned = warned or w:find("can't be loaded or bought on this server", 1, true) ~= nil
end
check("live server, grinder store unavailable: warned, no memory fallback", warned)
check("nothing loaded or published from it", A:GetAttribute("UpgradesLoaded") == nil and A:GetAttribute("BladeTier") == nil)
check("the Money itself loaded (its own store)", Economy.balance(A) == 50000)
asServer(function()
	touch.Touched:Fire(A.Character.HumanoidRootPart)
end)
advance(1)
check("blade pad: nothing happens (nothing loaded - the live script's own early return), not charged",
	Economy.balance(A) == 50000 and A:GetAttribute("BladeTier") == nil)
moveTo(A, SIGN + Vector3.new(0, -7, 6))
asServer(function()
	cd.MouseClick:Fire(A)
end)
advance(1)
check("KG post: earlier buys can't be read, so the net isn't sold (fail closed), not charged",
	lastNotice(A) == "Your net upgrades are still loading - try again in a moment" and Economy.balance(A) == 50000
	and A:GetAttribute("NetKg") == nil)

finish("grinder no-datastore sim")
