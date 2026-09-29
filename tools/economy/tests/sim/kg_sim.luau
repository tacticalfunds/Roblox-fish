-- +5 KG signs: the REAL NetCapacityServer + KgSignClient with the REAL
-- EconomyService (MoneyStore netKg) on the fake engine, in the live layout:
-- TWO Workspace children both named KGsign, each with Board Part.ClickDetector
-- (MaxActivationDistance 20); Workspace.NetLift.MaxWeight = 15. Checks:
--   * both duplicate-named signs are bound; clicks buy for the CLICKER
--   * closed by default; open: +5 kg per purchase at 25, 50, ...; saved with
--     the money in one write; toast + panel say what happened
--   * far / dead / loading / spam / funds / failed save / max refused, never charged
--   * re-checked after waiting for a running save (walk away -> refused)
--   * shared net = highest loaded player's capacity (floor 15): join, buy,
--     leave; fish in the river untouched
--   (no EconomyService: kgnoecon_sim)

local Economy, root = installEconomy()
local SSS = services.ServerScriptService
local ws = workspaceInst
local KEY = Economy.Config.KeyPrefix
local SIGN1 = Vector3.new(-42.4489, 12.0365, 206.336)
local SIGN2 = Vector3.new(22.4984, 11.5565, 206.497)

current = "server"
local netLift = new("Model", "NetLift")
netLift:SetAttribute("MaxWeight", 15)
netLift.Parent = ws
local river = new("Folder", "SwimmingFish")
for i = 1, 6 do
	model("Cod", river, Vector3.new(0, 7, i * 10))
end
river.Parent = ws
local detectors = {}
for i, pos in ipairs({ SIGN1, SIGN2 }) do
	local sign = new("Model", "KGsign") -- both named KGsign, like the place
	local board = part("Board Part", pos, sign, Vector3.new(8, 4, 0.5))
	local cd = new("ClickDetector", "ClickDetector")
	cd._props.MaxActivationDistance = 20
	cd.Parent = board
	local sg = new("SurfaceGui", "SurfaceGui")
	local btn = new("ImageButton", "ImageButton")
	local tl = new("TextLabel", "TextLabel")
	tl._props.Text = "+5 KG"
	tl.Parent = btn
	btn.Parent = sg
	sg.Parent = board
	sign.Parent = ws
	detectors[i] = cd
end
current = nil

dsData[KEY .. "1"] = { v = 2, money = 2000 }
local A = join(1, "Buyer", SIGN1 + Vector3.new(0, -7, 6))
runScript(script("Script", "NetCapacityServer", SOURCES.Kg_Server, SSS))
runAs(A, function()
	runScript(script("LocalScript", "KgSignClient", SOURCES.Kg_Client), A)
end)
advance(0.5)

local function clickSign(p, i)
	asServer(function()
		detectors[i].MouseClick:Fire(p)
	end)
	advance(0.6)
end
local function panels(p)
	local out = {}
	for _, g in ipairs(p.PlayerGui:GetChildren()) do
		if g.Name == "KgSignPanel" then
			table.insert(out, g)
		end
	end
	return out
end
local function panelText(p, name)
	local g = panels(p)[1]
	local l = g and g:FindFirstChild(name, true)
	return l and l.Text
end
local fishBefore = #river:GetChildren()

------------------------------------------------------------ bound, closed by default

check("two panels, one per KGsign (duplicate names both bound)", #panels(A) == 2)
check("loaded: 15 kg published", A:GetAttribute("NetKg") == 15 and A:GetAttribute("NetKgNext") == 20 and A:GetAttribute("NetKgCost") == 25)
check("panel: Your net 15 → 20 kg, SOON, Net now: 15 kg", panelText(A, "Capacity") == "Your net 15 → 20 kg"
	and panelText(A, "Price") == "SOON" and panelText(A, "Shared") == "Net now: 15 kg")
clickSign(A, 1)
check("closed by default: refused, not charged", lastNotice(A) == "Net upgrades open soon" and Economy.balance(A) == 2000
	and netLift:GetAttribute("MaxWeight") == 15)

root:SetAttribute("NetKgOpen", true)
advance(0.1)
check("open: the panel shows the price", panelText(A, "Price") == "$25")

------------------------------------------------------------ buying

local writes = 0
dsHooks.before = function()
	writes += 1
end
clickSign(A, 1)
dsHooks.before = nil
check("sign 1: bought 15 → 20 kg for 25", lastNotice(A) == "Net capacity 15 → 20 kg (-$25)" and Economy.balance(A) == 1975)
check("saved at once: money AND netKg in one write", writes == 1 and dsData[KEY .. "1"].netKg == 20 and dsData[KEY .. "1"].money == 1975)
check("shared net now 20 kg", netLift:GetAttribute("MaxWeight") == 20)
check("panel: 20 → 25 kg, $50, Net now: 20 kg", panelText(A, "Capacity") == "Your net 20 → 25 kg" and panelText(A, "Price") == "$50"
	and panelText(A, "Shared") == "Net now: 20 kg")
moveTo(A, SIGN2 + Vector3.new(0, -7, 6))
clickSign(A, 2)
check("sign 2 (same name) works too: 20 → 25 kg for 50", lastNotice(A) == "Net capacity 20 → 25 kg (-$50)" and Economy.balance(A) == 1925
	and netLift:GetAttribute("MaxWeight") == 25)

-- far / dead
clickSign(A, 1) -- sign 1 is ~65 studs away
check("far from the clicked sign: refused, not charged", lastNotice(A) == "Walk up to the sign" and Economy.balance(A) == 1925)
A.Character.Humanoid.Health = 0
clickSign(A, 2)
check("dead: refused", lastNotice(A) == "You can't do that right now" and Economy.balance(A) == 1925)
A.Character.Humanoid.Health = 100

-- spam during a slow save
dsHooks.before = function()
	task.wait(1.5)
end
for _ = 1, 5 do
	asServer(function()
		detectors[2].MouseClick:Fire(A)
	end)
end
advance(0.2)
asServer(function()
	detectors[2].MouseClick:Fire(A) -- after the cooldown, while the save is still running
end)
advance(2)
dsHooks.before = nil
check("spam x6 during a slow save: one purchase (25 → 30 for 100)", Economy.balance(A) == 1825 and A:GetAttribute("NetKg") == 30)
advance(0.6)

-- failed save
dsHooks.before = function()
	error("DataStore request failed")
end
clickSign(A, 2)
dsHooks.before = nil
check("save fails: refused, not charged, still 30 kg", lastNotice(A) == "Couldn't save the upgrade - you were not charged. Try again."
	and Economy.balance(A) == 1825 and A:GetAttribute("NetKg") == 30 and netLift:GetAttribute("MaxWeight") == 30)

-- re-checked after waiting for a running autosave
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
asServer(function()
	detectors[2].MouseClick:Fire(A)
end)
advance(0.3)
moveTo(A, SIGN2 + Vector3.new(90, -7, 0))
advance(4)
dsHooks.before = nil
check("walked away while the purchase waited for a save: refused, not charged", held and lastNotice(A) == "Walk up to the sign"
	and Economy.balance(A) == 1825 and A:GetAttribute("NetKg") == 30)
moveTo(A, SIGN2 + Vector3.new(0, -7, 6))
advance(0.6)

------------------------------------------------------------ the shared net: join, leave

dsData[KEY .. "2"] = { v = 2, money = 0, netKg = 45 }
local B = join(2, "Strong", SIGN1 + Vector3.new(0, -7, 6))
advance(0.5)
check("B joins with 45 kg saved: shared net 45", netLift:GetAttribute("MaxWeight") == 45)
clickSign(B, 1)
check("B can't afford 45 → 50 (225): refused", lastNotice(B) == "Not enough money" and B:GetAttribute("NetKg") == 45)
dsData[KEY .. "3"] = { v = 2, money = 0, netKg = 60, lock = { job = "another-server", t = 1700000000 + 10 ^ 7 } }
local C = join(3, "Loading", SIGN1 + Vector3.new(2, -7, 6))
advance(0.5)
check("a player whose money is still loading doesn't raise the net", netLift:GetAttribute("MaxWeight") == 45)
clickSign(C, 1)
check("loading: refused", lastNotice(C) == "Your money is still loading - try again in a moment")
-- B's final save is slow (as a real DataStore call): the net must drop at once anyway
dsHooks.before = function(key)
	if key == KEY .. "2" then
		task.wait(2)
	end
end
leave(B)
advance(0.1)
check("B leaves (final save still running): back to A's 30 kg at once", netLift:GetAttribute("MaxWeight") == 30)
advance(2.5)
dsHooks.before = nil
leave(A)
advance(0.5)
check("A leaves: back to the place's 15 kg", netLift:GetAttribute("MaxWeight") == 15)
check("no fish were touched by any of it", #river:GetChildren() == fishBefore)

------------------------------------------------------------ the cap

dsData[KEY .. "4"] = { v = 2, money = 5000, netKg = 55 }
local D = join(4, "Maxer", SIGN1 + Vector3.new(0, -7, 6))
runAs(D, function()
	runScript(script("LocalScript", "KgSignClient", SOURCES.Kg_Client), D)
end)
advance(0.5)
clickSign(D, 1)
check("55 → 60 kg for 1150", lastNotice(D) == "Net capacity 55 → 60 kg (-$1150)" and Economy.balance(D) == 3850)
clickSign(D, 1)
check("at 60: refused, not charged", lastNotice(D) == "Your net is at the maximum (60 kg)" and Economy.balance(D) == 3850)
check("panel: MAX", panelText(D, "Capacity") == "Your net 60 kg" and panelText(D, "Price") == "MAX")
check("rejoin keeps it", dsData[KEY .. "4"].netKg == 60)

finish("kg sim")
