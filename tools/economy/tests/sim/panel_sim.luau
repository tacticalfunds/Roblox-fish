-- The aquarium panel: the REAL patched AquariumCycleServer (v1.2 + panel) and
-- the REAL AquariumPanelClient with the real aquarium modules, on the fake
-- engine, in the live layout: the CountPrompt binding points at
-- Workspace.Model.Road.ProximityPrompt.ProximityPrompt, a disabled prompt on
-- an Attachment with a disabled BillboardGui beside it. Checks:
--   * no default prompt UI (every prompt Custom), one panel, only in range
--   * Release Fish: E, gamepad X, tap; the server still checks everything
--   * one upgrade card at a time, switched by < > / arrow keys / D-pad
--   * paid upgrades absent: "Not available yet", no upgrade prompt exists,
--     nothing can be bought or charged
--   * with a currency binding (later): F buys exactly the card shown, per
--     client; the server charges; far / spoofed triggers charge nothing
--   * placeholder kept hidden while running, binding untouched, all cleaned
--     up on stop (panel, key bindings, prompts, attributes)

local RS = services.ReplicatedStorage
local SSS = services.ServerScriptService
local ws = workspaceInst
local PAD = Vector3.new(26.0539, 10.0348, 197.164)

current = "server"
local aq = new("Folder", "AquariumCycle")
aq:SetAttribute("Enabled", true)
for _, name in ipairs({ "Adapters", "Config", "CycleState", "Messages", "RiverRelease", "SharedTank", "TankPath", "Upgrades" }) do
	script("ModuleScript", name, SOURCES["Aq_" .. name], aq)
end
-- the live scene
local water = part("BaseWater", Vector3.new(40, 8, 190), ws, Vector3.new(16, 8, 10))
local river = new("Folder", "SwimmingFish")
for k, v in pairs({ MinX = -20, MaxX = 20, MinZ = 0, MaxZ = 300, SurfaceY = 7.45 }) do
	river:SetAttribute(k, v)
end
river.Parent = ws
local templates = new("Folder", "SwimTemplates")
local cod = model("Cod", templates, Vector3.new(0, -100, 0))
cod:SetAttribute("SwimLen", 4)
templates.Parent = RS
local road = part("Road", PAD - Vector3.new(0, 1, 0), model("Model", ws, Vector3.new(0, -50, 0)), Vector3.new(20, 1, 20))
local padAtt = new("Attachment", "ProximityPrompt")
padAtt._props.WorldPosition = PAD
padAtt.Parent = road
local placeholder = new("ProximityPrompt", "ProximityPrompt")
placeholder._props.Enabled = false -- "old car prompt disabled"
placeholder._props.KeyboardKeyCode = Enum.KeyCode.E
placeholder._props.MaxActivationDistance = 10
placeholder.Parent = padAtt
local oldBoard = new("BillboardGui", "BillboardGui")
oldBoard._props.Enabled = false
oldBoard.Parent = padAtt
local bindings = new("Folder", "Bindings")
for name, target in pairs({ TankWater = water, River = river, SwimTemplates = templates, CountPrompt = placeholder }) do
	local v = new("ObjectValue", name)
	v._props.Value = target
	v.Parent = bindings
end
bindings.Parent = aq
aq.Parent = RS
current = nil

local function startServer(source)
	local mod
	asServer(function()
		mod = script("ModuleScript", "AquariumCycleServer", source, SSS)
	end)
	local Server
	runAs("server", function()
		Server = requireModule(mod)
		local ok, why = Server.start({ 1, 2, 3, 4, 5 })
		check("aquarium starts" .. (if why then " (" .. why .. ")" else ""), ok == true)
	end)
	advance(0.2)
	return Server, mod
end

local P = join(1, "Near", PAD + Vector3.new(0, 0, 4))
local Q = join(2, "Far", PAD + Vector3.new(0, 0, 60))
for _, pl in ipairs({ P, Q }) do
	runAs(pl, function()
		runScript(script("LocalScript", "AquariumPanelClient", SOURCES.AquariumPanelClient), pl)
	end)
end
local notices = { [P] = {}, [Q] = {} }

local Server, serverModule = startServer(SOURCES.Panel_Server)
for _, pl in ipairs({ P, Q }) do
	runAs(pl, function()
		aq.Notice.OnClientEvent:Connect(function(text)
			table.insert(notices[pl], text)
		end)
	end)
end
advance(0.2)

local function panelOf(pl)
	return pl.PlayerGui:FindFirstChild("AquariumPanel")
end
local function find(pl, name)
	local g = panelOf(pl)
	return g and g:FindFirstChild(name, true)
end
local function text(pl, path)
	local node = panelOf(pl)
	for _, n in ipairs(path) do
		node = node and node:FindFirstChild(n, true)
	end
	return node and node.Text
end
local function promptsAt()
	local out = {}
	for _, c in ipairs(padAtt:GetChildren()) do
		if c.ClassName == "ProximityPrompt" and c ~= placeholder then
			table.insert(out, c)
		end
	end
	return out
end
local function lastNoticeOf(pl)
	return notices[pl][#notices[pl]]
end

------------------------------------------------------------ what exists (paid upgrades NOT installed)

local list = promptsAt()
check("paid upgrades absent: only the Release prompt exists (no F / G prompts)", #list == 1 and list[1].Name == "AquariumRelease")
local release = aq.ReleasePrompt.Value
check("Release prompt: E / ButtonX, Custom style (no default panel)", release.KeyboardKeyCode == Enum.KeyCode.E
	and release.GamepadKeyCode == Enum.KeyCode.ButtonX and release.Style == Enum.ProximityPromptStyle.Custom)
check("prompts sit on the pad attachment (the binding's parent)", release.Parent == padAtt)
check("UpgradesAvailable = false; levels published", aq:GetAttribute("UpgradesAvailable") == false
	and aq:GetAttribute("CapacityLevel") == 1 and aq:GetAttribute("ReleaseRateLevel") == 1)
check("binding untouched", aq.Bindings.CountPrompt.Value == placeholder)
check("placeholder prompt and its billboard stay hidden", placeholder.Enabled == false and oldBoard.Enabled == false)
check("own count billboard (fallback) still there", ws.AquariumCycleRuntime:FindFirstChild("AquariumCount") ~= nil)

------------------------------------------------------------ one panel, in range only

check("near player: one panel", panelOf(P) ~= nil and #P.PlayerGui:GetChildren() == 1)
check("far player: no panel", panelOf(Q) == nil)
check("panel sits on the pad", panelOf(P).Adornee == padAtt and panelOf(P).AlwaysOnTop == true)
check("Release row: [E] Release Fish, tank count", text(P, { "Release", "Action" }) == "Release Fish"
	and text(P, { "Release", "Glyph" }) == "E" and text(P, { "Tank" }) == "0/3 fish in tank")
check("card: Tank Capacity, honest status", text(P, { "Title" }) == "Tank Capacity" and text(P, { "Value" }) == "Now 3 fish"
	and text(P, { "Upgrade", "Action" }) == "Not available yet")
check("unavailable: grey button, no key shown", find(P, "Upgrade"):FindFirstChildOfClass("UIStroke").Color.G < 0.7
	and find(P, "Upgrade").Key.Visible == false)
check("text style: FredokaOne with a dark outline", find(P, "Title").Font == Enum.Font.FredokaOne
	and find(P, "Title"):FindFirstChildOfClass("UIStroke").Thickness >= 2.5)

------------------------------------------------------------ switching cards: arrows, keys, D-pad

click(P, find(P, "Next"))
check("> : Release Amount", text(P, { "Title" }) == "Release Amount" and text(P, { "Value" }) == "Now 1 per release")
click(P, find(P, "Next"))
check("> wraps to Tank Capacity", text(P, { "Title" }) == "Tank Capacity")
pressKey(P, Enum.KeyCode.Left)
check("Left arrow: Release Amount", text(P, { "Title" }) == "Release Amount")
pressKey(P, Enum.KeyCode.DPadRight)
check("D-pad right: Tank Capacity", text(P, { "Title" }) == "Tank Capacity")

------------------------------------------------------------ nothing can be bought

local tankBefore = aq:GetAttribute("TankCapacity")
click(P, find(P, "Upgrade"))
pressPromptKey(P, Enum.KeyCode.F)
advance(0.6)
check("Upgrade tap / F: nothing happens, capacity unchanged", aq:GetAttribute("TankCapacity") == tankBefore and aq:GetAttribute("CapacityLevel") == 1)

------------------------------------------------------------ Release Fish: E, tap; server checks

-- land two fish (one Gold, bought by P) through the rod API
local function landFish(rod, meta)
	runAs("server", function()
		Server.reserve({ { key = rod } }, P)
	end)
	advance(Server and 2.6 or 0)
	runAs("server", function()
		Server.hook(rod, "Cod", meta)
	end)
	advance(1.6)
	runAs("server", function()
		Server.land(rod)
	end)
	advance(0.1)
end
landFish(1, { Variant = "Gold", OwnerId = 1 })
landFish(2, nil)
check("two fish in the tank: panel shows 2/3", aq:GetAttribute("TankCount") == 2 and text(P, { "Tank" }) == "2/3 fish in tank")
local riverBefore = #river:GetChildren()
pressPromptKey(P, Enum.KeyCode.E)
advance(0.2)
check("E releases (server): tank 1/3 on the panel", aq:GetAttribute("TankCount") == 1 and text(P, { "Tank" }) == "1/3 fish in tank")
advance(3.2)
check("released fish swims back into the river", #river:GetChildren() == riverBefore + 1)
local back = river:GetChildren()[#river:GetChildren()]
check("its Variant / OwnerId came back unchanged", back:GetAttribute("Variant") == "Gold" and back:GetAttribute("OwnerId") == 1)
click(P, find(P, "Release"))
advance(0.2)
check("tap during the cooldown: the server refuses and says so", aq:GetAttribute("TankCount") == 1 and lastNoticeOf(P) == "Release is still recharging.")
advance(4)
click(P, find(P, "Release"))
advance(0.2)
check("tap after the cooldown: released", aq:GetAttribute("TankCount") == 0)
-- a far client firing the trigger itself (exploit): refused by the server
landFish(3, nil)
advance(4.5)
asServer(function()
	release.Triggered:Fire(Q)
end)
advance(0.2)
check("spoofed trigger from a far player: refused, nothing released", aq:GetAttribute("TankCount") == 1 and lastNoticeOf(Q) == "Move closer to the aquarium.")

------------------------------------------------------------ gamepad glyphs

promptState[P].inputType = Enum.ProximityPromptInputType.Gamepad
moveTo(P, PAD + Vector3.new(0, 0, 40))
advance(0.1)
check("walk away: panel gone, key bindings gone", panelOf(P) == nil and next(boundActions[P] or {}) == nil)
moveTo(P, PAD + Vector3.new(0, 0, 4))
advance(0.1)
check("walk back (gamepad): panel back with the X button image", panelOf(P) ~= nil and find(P, "Release").Key.Icon.Visible == true)
check("the card you picked is kept", text(P, { "Title" }) == "Tank Capacity")
promptState[P].inputType = Enum.ProximityPromptInputType.Keyboard

------------------------------------------------------------ stop: everything cleaned up

aq:SetAttribute("Enabled", false)
advance(0.2)
check("stop: panel removed on the client", panelOf(P) == nil and next(boundActions[P] or {}) == nil)
check("stop: prompts, refs and panel attributes removed", #promptsAt() == 0 and aq:FindFirstChild("ReleasePrompt") == nil
	and aq:GetAttribute("UpgradesAvailable") == nil and aq:GetAttribute("CapacityLevel") == nil)
check("stop: placeholder back as it was (disabled), binding untouched", placeholder.Enabled == false and oldBoard.Enabled == false
	and aq.Bindings.CountPrompt.Value == placeholder)

------------------------------------------------------------ later: with a currency binding (not installed today)

current = "server"
local charges = {}
local econ = script("ModuleScript", "AquariumEconomy", [[
local charges = {}
return { charges = charges, tryCharge = function(player, amount, why)
	if player:GetAttribute("Broke") then return false end
	table.insert(charges, { player = player, amount = amount, why = why })
	return true
end }
]], SSS)
placeholder._props.Enabled = true -- say someone re-enabled the old car prompt
current = nil
aq:SetAttribute("Enabled", true)
local Server2 = startServer(SOURCES.Panel_Server)
runAs("server", function()
	charges = requireModule(econ).charges
end)
for _, pl in ipairs({ P, Q }) do -- the restart made a new Notice remote
	runAs(pl, function()
		aq.Notice.OnClientEvent:Connect(function(text)
			table.insert(notices[pl], text)
		end)
	end)
end
advance(0.2)
check("with a currency: both upgrade prompts, F / ButtonY, Custom", aq:FindFirstChild("CapacityPrompt") and aq:FindFirstChild("ReleaseRatePrompt")
	and aq.CapacityPrompt.Value.KeyboardKeyCode == Enum.KeyCode.F and aq.ReleaseRatePrompt.Value.GamepadKeyCode == Enum.KeyCode.ButtonY
	and aq.CapacityPrompt.Value.Style == Enum.ProximityPromptStyle.Custom)
check("an enabled placeholder is hidden while running", placeholder._props.Enabled == false)
check("card: price and next value", text(P, { "Value" }) == "3 → 6 fish" and text(P, { "Upgrade", "Action" }) == "Upgrade  $50"
	and find(P, "Upgrade").Key.Visible == true and text(P, { "Upgrade", "Glyph" }) == "F")
moveTo(Q, PAD + Vector3.new(0, 0, -4))
advance(0.2)
click(Q, find(Q, "Next")) -- Q looks at Release Amount, P stays on Tank Capacity
pressPromptKey(P, Enum.KeyCode.F)
advance(0.2)
check("P presses F: Tank Capacity, charged 50 by the server", #charges == 1 and charges[1].player == P and charges[1].amount == 50
	and aq:GetAttribute("CapacityLevel") == 2 and aq:GetAttribute("ReleaseRateLevel") == 1)
check("both panels update: 6 → 10", text(P, { "Value" }) == "6 → 10 fish" and text(Q, { "Title" }) == "Release Amount")
advance(0.6)
click(Q, find(Q, "Upgrade"))
advance(0.2)
check("Q taps Upgrade on Release Amount: that one, charged 40", #charges == 2 and charges[2].player == Q and charges[2].amount == 40
	and aq:GetAttribute("ReleaseRateLevel") == 2 and aq:GetAttribute("CapacityLevel") == 2)
Q:SetAttribute("Broke", true)
advance(0.6)
pressPromptKey(Q, Enum.KeyCode.F)
advance(0.2)
check("can't pay: nothing applied", #charges == 2 and aq:GetAttribute("ReleaseRateLevel") == 2 and lastNoticeOf(Q) == "You can't afford that upgrade yet.")
moveTo(Q, PAD + Vector3.new(0, 0, 60))
advance(0.6)
asServer(function()
	aq.CapacityPrompt.Value.Triggered:Fire(Q)
end)
advance(0.2)
check("spoofed upgrade trigger from far away: not charged", #charges == 2 and aq:GetAttribute("CapacityLevel") == 2)
-- buy Tank Capacity to its max: the card says Maxed and tapping sends nothing
for _ = 1, 2 do
	advance(0.6)
	pressPromptKey(P, Enum.KeyCode.F)
end
advance(0.6)
check("capacity bought to max through F (150 + 400 charged)", aq:GetAttribute("CapacityLevel") == 4 and #charges == 4
	and charges[3].amount == 150 and charges[4].amount == 400)
check("card at max: 15 fish (max), Maxed, grey, no key", text(P, { "Value" }) == "15 fish (max)" and text(P, { "Upgrade", "Action" }) == "Maxed"
	and find(P, "Upgrade").Key.Visible == false)
local noticesBefore = #notices[P]
click(P, find(P, "Upgrade"))
advance(0.2)
check("tapping Maxed sends nothing to the server", #notices[P] == noticesBefore and #charges == 4)
aq:SetAttribute("Enabled", false)
advance(0.2)
check("stop again: the re-enabled placeholder comes back", placeholder._props.Enabled == true and #promptsAt() == 0 and panelOf(P) == nil)

finish("panel sim")
