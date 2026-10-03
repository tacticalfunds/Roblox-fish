#!/usr/bin/env python3
"""Dry-runs the REAL InstallRodOffers.lua / UninstallRodOffers.lua under the
Luau CLI against a tiny fake Studio DataModel (Instances with Name, Parent,
Source, attributes, Clone/Destroy; a ChangeHistoryService stub).

Also dry-runs UpdateRodPrompt.lua / RollbackRodPrompt.lua against a place
set up by the REAL 8cb2554 installer (read from git): update, refusals,
rollback to exactly 8cb2554, then the original uninstall chain.

Checks: a mismatched live source or a missing aquarium changes nothing;
another script creating leaderstats blocks the install; a clean install
patches both scripts, adds every object tagged, backs up Before/After; a
second install refuses; uninstall restores the exact live sources and
removes only tagged objects; an edited target blocks uninstall.

Usage:  python3 tools/economy/tests/run_installer_sim.py [path/to/luau]
Fake-DataModel simulation only; not a Roblox runtime test.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

PRELUDE = r"""
local failures, passes = 0, 0
local function check(name, cond)
	if cond then passes += 1 else failures += 1 print("FAIL: " .. name) end
end
local warnings = {}
local function warn(msg) table.insert(warnings, tostring(msg)) end
local function print(...) end

local Inst = {}
Inst.__index = function(self, k)
	local v = rawget(Inst, k)
	if v ~= nil then return v end
	local p = rawget(self, "_props")
	if k == "Parent" then return rawget(self, "_parent") end
	if p[k] ~= nil then return p[k] end
	return self:FindFirstChild(k)
end
Inst.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			for i, c in ipairs(old._children) do if c == self then table.remove(old._children, i) break end end
		end
		rawset(self, "_parent", v)
		if v then table.insert(v._children, self) end
	else
		rawget(self, "_props")[k] = v
	end
end
local CLASS_ISA = {
	Script = { Script = true, BaseScript = true, LuaSourceContainer = true },
	LocalScript = { LocalScript = true, Script = true, BaseScript = true, LuaSourceContainer = true },
	ModuleScript = { ModuleScript = true, LuaSourceContainer = true },
}
local function new(className, name)
	local o = setmetatable({ _props = { ClassName = className, Name = name or className }, _children = {}, _attrs = {} }, Inst)
	return o
end
function Inst:IsA(c) return c == "Instance" or self.ClassName == c or (CLASS_ISA[self.ClassName] or {})[c] == true end
function Inst:GetChildren() return table.clone(self._children) end
function Inst:GetDescendants()
	local out = {}
	local function walk(o) for _, c in ipairs(o._children) do table.insert(out, c) walk(c) end end
	walk(self)
	return out
end
function Inst:FindFirstChild(n) for _, c in ipairs(self._children) do if c.Name == n then return c end end return nil end
function Inst:FindFirstChildOfClass(cl) for _, c in ipairs(self._children) do if c.ClassName == cl then return c end end return nil end
function Inst:GetAttribute(k) return self._attrs[k] end
function Inst:SetAttribute(k, v) self._attrs[k] = v end
function Inst:GetFullName() local p = self.Parent if p and p.ClassName ~= "DataModel" then return p:GetFullName() .. "." .. self.Name end return self.Name end
function Inst:IsDescendantOf(a) local p = self.Parent while p do if p == a then return true end p = p.Parent end return false end
function Inst:Destroy() self.Parent = nil end
function Inst:Clone()
	local c = new(self.ClassName, self.Name)
	for k, v in pairs(self._props) do c._props[k] = v end
	for k, v in pairs(self._attrs) do c._attrs[k] = v end
	for _, ch in ipairs(self._children) do ch:Clone().Parent = c end
	return c
end

local Instance = { new = function(className) return new(className) end }
local Enum = { FinishRecordingOperation = { Commit = "Commit", Cancel = "Cancel" } }

local function makeGame()
	local game = new("DataModel", "game")
	local services = {}
	for _, n in ipairs({ "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer", "Workspace", "StarterGui", "ReplicatedFirst" }) do
		local s = new(n, n) s.Parent = game services[n] = s
	end
	new("StarterPlayerScripts", "StarterPlayerScripts").Parent = services.StarterPlayer
	local history = { commits = 0 }
	services.RunService = { running = false }
	function services.RunService:IsRunning() return self.running end
	services.ChangeHistoryService = {
		TryBeginRecording = function(_, name) return "rec" end,
		FinishRecording = function(_, id, op) if op == "Commit" then history.commits += 1 end end,
		SetWaypoint = function() end,
	}
	function game:GetService(n) return services[n] end
	return game, services, history
end

local LIVE = { RodFishingSystem = __RFS__, RodShopServer = __SHOP__ }

local function scene(opts)
	opts = opts or {}
	local game, s, history = makeGame()
	local rfs = new("Script", "RodFishingSystem") rfs.Source = opts.rfs or LIVE.RodFishingSystem rfs.Parent = s.ServerScriptService
	local shop = new("Script", "RodShopServer") shop.Source = LIVE.RodShopServer shop.Parent = s.ServerScriptService
	if not opts.noAquarium then
		local acs = new("ModuleScript", "AquariumCycleServer") acs.Source = "return {}" acs.Parent = s.ServerScriptService
		local aq = new("Folder", "AquariumCycle") aq:SetAttribute("Enabled", true) aq.Parent = s.ReplicatedStorage
	end
	if opts.otherMoney then
		local m = new("Script", "Leaderboard") m.Source = 'local ls = Instance.new("Folder") ls.Name = "leaderstats"' m.Parent = s.ServerScriptService
	end
	return game, s, history, rfs, shop
end

local function snapshot(game)
	local out = {}
	for _, d in ipairs(game:GetDescendants()) do
		table.insert(out, d:GetFullName() .. "|" .. tostring(d._props.Source))
	end
	table.sort(out)
	return table.concat(out, "\n")
end
"""


BASE_COMMIT = "8cb2554"
SOURCES = {
    "RodFishingSystem": "studio/rod-offers/RodFishingSystem.lua",
    "RodShopServer": "studio/rod-offers/RodShopServer.lua",
    "EconomyService": "src/server/EconomyService.luau",
    "EconomyClient": "src/client/EconomyClient.client.luau",
    "Config": "src/core/Config.luau",
    "Offers": "src/core/Offers.luau",
    "MoneyStore": "src/core/MoneyStore.luau",
    "Pricing": "src/core/Pricing.luau",
}


RELEASE_COMMIT = "a826d73"  # the rod-offers release installed in Studio (fresh InstallRodOffers)
SALES_RELEASE = "91121de"  # InstallSales / InstallUpgrades as released for Astra's install
EARNINGS_RELEASE = "0829fc9"  # InstallEarnings as installed by Astra
EARNINGS_FROZEN = ["InstallEarnings.lua", "RollbackEarnings.lua"]
RODS_RELEASE = "61a7bd4"  # InstallRods + InstallRodShopUI as installed by Astra
RODS_FROZEN = ["InstallRods.lua", "RollbackRods.lua", "InstallRodShopUI.lua", "RollbackRodShopUI.lua"]
# (InstallNetKg ... InstallFasterReels were never installed: superseded by InstallBoardUpgrades)
SALES_FROZEN = ["UpgradeAquariumV12.lua", "RollbackAquariumV12.lua", "InstallSales.lua", "RollbackSales.lua", "InstallUpgrades.lua", "RollbackUpgrades.lua"]
AQUARIUM_V1 = "2e320f9"
AQ_SHARED = ["Adapters", "Config", "CycleState", "Messages", "RiverRelease", "SharedTank", "TankPath", "Upgrades"]
SALES_LIVE = ["GrinderProcessor", "BotSystem", "CustomerSystem", "TruckSystem", "NetLiftScript", "HarpoonSystem"]


def git_show(rel: str, commit: str = BASE_COMMIT, prefix: str = "tools/economy/") -> str:
    return subprocess.run(
        ["git", "show", f"{commit}:{prefix}{rel}"], cwd=ROOT, capture_output=True, text=True, check=True
    ).stdout


def wrap(name: str, src: str) -> str:
    return f"local function {name}(game, workspace)\n{src}\nend\n"


TESTS = r"""
local function install(game, s) warnings = {} runInstall(game, s.Workspace) end
local function uninstall(game, s) warnings = {} runUninstall(game, s.Workspace) end
local function oldInstall(game, s) warnings = {} runOldInstall(game, s.Workspace) end
local function oldUninstall(game, s) warnings = {} runOldUninstall(game, s.Workspace) end
local function update(game, s) warnings = {} runUpdate(game, s.Workspace) end
local function rollback(game, s) warnings = {} runRollback(game, s.Workspace) end
local function refused(label) return #warnings > 0 and warnings[#warnings]:find("nothing changed", 1, true) ~= nil end

-- refusals change nothing
for _, case in ipairs({
	{ label = "mismatched RodFishingSystem", opts = { rfs = LIVE.RodFishingSystem .. "\n-- edited" } },
	{ label = "aquarium missing", opts = { noAquarium = true } },
	{ label = "another script creates leaderstats", opts = { otherMoney = true } },
}) do
	local game, s = scene(case.opts)
	local before = snapshot(game)
	install(game, s)
	check(case.label .. ": refused", #warnings > 0 and warnings[#warnings]:find("nothing changed", 1, true) ~= nil)
	check(case.label .. ": nothing changed", snapshot(game) == before)
end

-- clean install
local game, s, history, rfs, shop = scene()
install(game, s)
check("install committed one undo step", history.commits == 1)
check("RodFishingSystem patched", rfs.Source:find("[Economy patch v1]", 1, true) ~= nil and rfs.Source:find("Economy.runRodOffer", 1, true) ~= nil)
check("RodShopServer patched", shop.Source:find("Economy.tryDebit", 1, true) ~= nil)
local root = s.ReplicatedStorage:FindFirstChild("Economy")
check("Economy root tagged, offers on", root and root:GetAttribute("EconomyOwned") == true and root:GetAttribute("RodOffersEnabled") == true)
check("remotes + offers folder", root and root:FindFirstChild("Notice") and root:FindFirstChild("OfferAction") and root:FindFirstChild("Offers"))
local svc = s.ServerScriptService:FindFirstChild("EconomyService")
local names = {}
for _, c in ipairs(svc and svc:GetChildren() or {}) do names[c.Name] = c.ClassName == "ModuleScript" end
check("EconomyService + 7 core modules", svc and names.Config and names.Pricing and names.Ledger and names.MoneyStore and names.Offers and names.PieceTags and names.Sales)
check("EconomyBoot script", s.ServerScriptService:FindFirstChild("EconomyBoot") and s.ServerScriptService.EconomyBoot.ClassName == "Script")
check("EconomyClient local script", s.StarterPlayer.StarterPlayerScripts:FindFirstChild("EconomyClient") ~= nil)
local backup = s.ServerStorage:FindFirstChild("EconomyRodOffersBackup")
check("backup has 2 entries", backup and #backup:GetChildren() == 2)
local e1 = backup and backup:GetChildren()[1]
check("backup Before = live, After = patched, copies disabled", e1 and e1.Before.Source == LIVE.RodFishingSystem and e1.After.Source == rfs.Source and e1.Before.Enabled == false)

-- second install refuses
local afterInstall = snapshot(game)
install(game, s)
check("second install refused, nothing changed", snapshot(game) == afterInstall)

-- uninstall restores exactly
uninstall(game, s)
check("RodFishingSystem restored to the live source", rfs.Source == LIVE.RodFishingSystem)
check("RodShopServer restored to the live source", shop.Source == LIVE.RodShopServer)
check("all added objects removed", s.ReplicatedStorage:FindFirstChild("Economy") == nil and s.ServerScriptService:FindFirstChild("EconomyService") == nil
	and s.ServerScriptService:FindFirstChild("EconomyBoot") == nil and s.StarterPlayer.StarterPlayerScripts:FindFirstChild("EconomyClient") == nil
	and s.ServerStorage:FindFirstChild("EconomyRodOffersBackup") == nil)
check("aquarium untouched", s.ServerScriptService:FindFirstChild("AquariumCycleServer") ~= nil and s.ReplicatedStorage:FindFirstChild("AquariumCycle") ~= nil)

-- edited after install blocks uninstall
local g2, s2, _, rfs2 = scene()
install(g2, s2)
rfs2.Source = rfs2.Source .. "\n-- hand edit"
local beforeUn = snapshot(g2)
uninstall(g2, s2)
check("edited target blocks uninstall, nothing changed", snapshot(g2) == beforeUn)

-- Partial / earlier installs: ANY one of our objects blocks the install,
-- including when the Economy root is missing (no nil-hole skipping).
for _, slot in ipairs({
	{ "ServerScriptService", "EconomyService", "ModuleScript" },
	{ "ServerScriptService", "EconomyBoot", "Script" },
	{ "StarterPlayerScripts", "EconomyClient", "LocalScript" },
	{ "ServerStorage", "EconomyRodOffersBackup", "Folder" },
}) do
	local g, sv = scene()
	local parent = if slot[1] == "StarterPlayerScripts" then sv.StarterPlayer.StarterPlayerScripts else sv[slot[1]]
	local stray = new(slot[3], slot[2])
	stray.Parent = parent
	check("no Economy root, stray " .. slot[2] .. ": root really absent", sv.ReplicatedStorage:FindFirstChild("Economy") == nil)
	local before = snapshot(g)
	install(g, sv)
	check("stray " .. slot[2] .. " blocks the install", #warnings > 0 and warnings[#warnings]:find("already exists", 1, true) ~= nil)
	check("stray " .. slot[2] .. ": nothing overwritten or added", snapshot(g) == before and stray.Parent == parent)
end

-- Uninstall after the Economy root went missing: still restores the scripts
-- and removes the remaining TAGGED objects only.
do
	local g, sv, _, rfsX, shopX = scene()
	install(g, sv)
	sv.ReplicatedStorage.Economy:Destroy()
	uninstall(g, sv)
	check("root missing: scripts restored", rfsX.Source == LIVE.RodFishingSystem and shopX.Source == LIVE.RodShopServer)
	check("root missing: tagged objects removed", sv.ServerScriptService:FindFirstChild("EconomyService") == nil
		and sv.ServerScriptService:FindFirstChild("EconomyBoot") == nil
		and sv.StarterPlayer.StarterPlayerScripts:FindFirstChild("EconomyClient") == nil)
end

-- An untagged object with one of our names (someone else's) is never deleted
do
	local g, sv = scene()
	install(g, sv)
	sv.ServerScriptService.EconomyBoot:Destroy()
	local mine = new("Script", "EconomyBoot") -- not tagged
	mine.Source = "-- someone else's script"
	mine.Parent = sv.ServerScriptService
	local unrelated = new("Folder", "Unrelated")
	unrelated.Parent = sv.ReplicatedStorage
	uninstall(g, sv)
	check("untagged same-name object kept", mine.Parent == sv.ServerScriptService and mine.Source == "-- someone else's script")
	check("unrelated object kept", unrelated.Parent == sv.ReplicatedStorage)
	check("skipped object reported", table.concat(warnings, "\n"):find("not tagged EconomyOwned", 1, true) ~= nil)
	check("our tagged objects removed", sv.ServerScriptService:FindFirstChild("EconomyService") == nil and sv.ReplicatedStorage:FindFirstChild("Economy") == nil)
end

-- Uninstall with no backup (partial install): refuses, deletes nothing
do
	local g, sv = scene()
	local tagged = new("ModuleScript", "EconomyService")
	tagged:SetAttribute("EconomyOwned", true)
	tagged.Parent = sv.ServerScriptService
	local before = snapshot(g)
	uninstall(g, sv)
	check("no backup: uninstall refuses and deletes nothing", snapshot(g) == before and tagged.Parent ~= nil)
end

-- Fresh install refuses in Play mode and when the runtime stands folder exists
do
	local g, sv = scene()
	sv.RunService.running = true
	local before = snapshot(g)
	install(g, sv)
	check("fresh install: Play mode refused", refused() and snapshot(g) == before)
	sv.RunService.running = false
	local stray = new("Folder", "EconomyBuyStands")
	stray.Parent = sv.Workspace
	before = snapshot(g)
	install(g, sv)
	check("fresh install: existing Workspace.EconomyBuyStands refused", refused() and snapshot(g) == before)
end

------------------------------------------------------------ UpdateRodPrompt (from the installed 8cb2554)

local function subtree(inst)
	local out = {}
	for _, d in ipairs(inst:GetDescendants()) do
		table.insert(out, d:GetFullName() .. "|" .. tostring(d._props.Source) .. "|" .. tostring(d._props.Value))
	end
	table.sort(out)
	return table.concat(out, "\n")
end

-- the place as Astra has it: aquarium v1 + the REAL 8cb2554 installer
local function installed8cb()
	local g, sv, history, rfsX, shopX = scene()
	oldInstall(g, sv)
	assert(sv.ServerStorage:FindFirstChild("EconomyRodOffersBackup"), "8cb2554 installer did not install")
	return g, sv, history, rfsX, shopX
end

do
	local g, sv, history, rfsX, shopX = installed8cb()
	local baseline = snapshot(g)
	local baseBackup = subtree(sv.ServerStorage.EconomyRodOffersBackup)
	local commits = history.commits
	update(g, sv)
	check("update: one undo step", history.commits == commits + 1 and not refused())
	check("update: RodFishingSystem = new patch", rfsX.Source == NEW.RodFishingSystem)
	check("update: RodShopServer untouched", shopX.Source == OLD.RodShopServer)
	local svc = sv.ServerScriptService.EconomyService
	check("update: EconomyService = new", svc.Source == NEW.EconomyService)
	check("update: Config + Offers = new", svc.Config.Source == NEW.Config and svc.Offers.Source == NEW.Offers)
	check("update: other core modules untouched", svc.MoneyStore.Source == OLD.MoneyStore and svc.Pricing.Source == OLD.Pricing)
	check("update: EconomyClient = new", sv.StarterPlayer.StarterPlayerScripts.EconomyClient.Source == NEW.EconomyClient)
	local ub = sv.ServerStorage:FindFirstChild("EconomyRodPromptBackup")
	check("update: backup with 5 entries, tagged", ub and ub:GetAttribute("EconomyOwned") == true and #ub:GetChildren() == 5)
	local ok = true
	for _, e in ipairs(ub and ub:GetChildren() or {}) do
		if not (e.Target and e.Target.Value and e.Before and e.After and e.After.Source == e.Target.Value.Source and #e.Before:GetChildren() == 0) then ok = false end
		if e.Before.ClassName == "LocalScript" and e.Before.Enabled ~= false then ok = false end
	end
	check("update: every entry has Target + Before + After (childless, disabled)", ok)
	check("update: original uninstall backup untouched", subtree(sv.ServerStorage.EconomyRodOffersBackup) == baseBackup)
	check("update: Economy root untouched", sv.ReplicatedStorage.Economy:GetAttribute("RodOffersEnabled") == true)

	local afterUpdate = snapshot(g)
	update(g, sv)
	check("update twice: refused, nothing changed", refused() and snapshot(g) == afterUpdate)
	install(g, sv)
	check("fresh install over the update: refused", refused() and snapshot(g) == afterUpdate)
	uninstall(g, sv)
	check("uninstall while updated: refused (roll back first)", refused() and snapshot(g) == afterUpdate)
	oldUninstall(g, sv)
	check("the 8cb2554 uninstaller while updated: refused too", refused() and snapshot(g) == afterUpdate)

	rollback(g, sv)
	check("rollback: back to exactly the 8cb2554 install", not refused() and snapshot(g) == baseline)
	rollback(g, sv)
	check("rollback twice: refused", refused() and snapshot(g) == baseline)
	uninstall(g, sv)
	check("then uninstall: live sources restored", rfsX.Source == LIVE.RodFishingSystem and shopX.Source == LIVE.RodShopServer)
	check("then uninstall: all economy objects removed", sv.ServerScriptService:FindFirstChild("EconomyService") == nil
		and sv.ReplicatedStorage:FindFirstChild("Economy") == nil and sv.ServerStorage:FindFirstChild("EconomyRodOffersBackup") == nil)
end

-- update refusals change nothing
do
	local g, sv = scene()
	local before = snapshot(g)
	update(g, sv)
	check("update without the 8cb2554 install: refused", refused() and snapshot(g) == before)
end
do
	local g, sv = installed8cb()
	sv.RunService.running = true
	local before = snapshot(g)
	update(g, sv)
	check("update in Play: refused", refused() and snapshot(g) == before)
end
do
	local g, sv = installed8cb()
	sv.ServerScriptService.EconomyService.Config.Source ..= "\n-- tuned by hand"
	local before = snapshot(g)
	update(g, sv)
	check("update over an edited Config: refused, nothing changed", refused() and snapshot(g) == before)
end
do
	local g, sv = installed8cb()
	sv.ServerScriptService.EconomyService.MoneyStore.Source ..= "\n-- edited"
	local before = snapshot(g)
	update(g, sv)
	check("update over an edited unchanged module: refused", refused() and snapshot(g) == before)
end
do
	local g, sv = installed8cb()
	sv.ServerScriptService.EconomyService.Offers:SetAttribute("EconomyOwned", nil)
	local before = snapshot(g)
	update(g, sv)
	check("update when a target isn't ours (untagged): refused", refused() and snapshot(g) == before)
end
do
	local g, sv = installed8cb()
	new("Folder", "EconomyBuyStands").Parent = sv.Workspace
	local before = snapshot(g)
	update(g, sv)
	check("update with Workspace.EconomyBuyStands present: refused", refused() and snapshot(g) == before)
end
do
	local g, sv = installed8cb()
	new("Folder", "EconomySalesBackup").Parent = sv.ServerStorage
	local before = snapshot(g)
	update(g, sv)
	check("update with a later milestone present: refused", refused() and snapshot(g) == before)
end
do
	local g, sv = installed8cb()
	update(g, sv)
	sv.StarterPlayer.StarterPlayerScripts.EconomyClient.Source ..= "\n-- hand edit"
	local before = snapshot(g)
	rollback(g, sv)
	check("rollback over an edited script: refused, nothing changed", refused() and snapshot(g) == before)
end
do
	local g, sv = installed8cb()
	local before = snapshot(g)
	rollback(g, sv)
	check("rollback without the update: refused", refused() and snapshot(g) == before)
end

------------------------------------------------------------ aquarium v1.2 + sales (on the a826d73 release)

-- The place as Astra has it now: the aquarium v1 objects exactly as its
-- installer made them, the six live scripts, and the FRESH a826d73
-- InstallRodOffers (the file in this repo, frozen at that release).
local function aquariumV1(sv)
	local folder = new("Folder", "AquariumCycle")
	folder:SetAttribute("AquariumCycleOwned", true)
	folder:SetAttribute("Enabled", true)
	for name, src in pairs(AQV1.shared) do
		local m = new("ModuleScript", name) m.Source = src m.Parent = folder
	end
	new("Folder", "Bindings").Parent = folder
	folder.Parent = sv.ReplicatedStorage
	for _, name in ipairs({ "AquariumCycleServer", "AquariumEconomy" }) do
		local m = new("ModuleScript", name) m.Source = AQV1[name] m:SetAttribute("AquariumCycleOwned", true) m.Parent = sv.ServerScriptService
	end
	local c = new("LocalScript", "AquariumTankClient") c.Source = AQV1.AquariumTankClient c:SetAttribute("AquariumCycleOwned", true)
	c.Parent = sv.StarterPlayer.StarterPlayerScripts
	local b = new("Folder", "AquariumCycleBackup") b:SetAttribute("AquariumCycleOwned", true) b.Parent = sv.ServerStorage
end
-- the two live MoneyController copies (StarterGui), as Astra sent them
local function moneyHuds(sv)
	local function chain(parent, path)
		for _, step in ipairs(path) do
			local node = parent:FindFirstChild(step[1]) or new(step[2], step[1])
			node.Parent = parent
			parent = node
		end
		local mc = new("LocalScript", "MoneyController")
		mc.Source = MONEYHUD.Live
		mc.Parent = parent
		return mc
	end
	local a = chain(sv.StarterGui, { { "Money", "ScreenGui" }, { "MoneyFrame", "Frame" } })
	local b = chain(sv.StarterGui, { { "ScreenGui", "ScreenGui" }, { "Buttons", "Frame" }, { "Frames", "Frame" }, { "MoneyFrame", "Frame" } })
	return a, b
end
local function astraPlace(opts)
	opts = opts or {}
	local g, sv, history = makeGame()
	local rfs = new("Script", "RodFishingSystem") rfs.Source = LIVE.RodFishingSystem rfs.Parent = sv.ServerScriptService
	local shop = new("Script", "RodShopServer") shop.Source = LIVE.RodShopServer shop.Parent = sv.Workspace
	local scripts = { RodFishingSystem = rfs, RodShopServer = shop }
	for name, src in pairs(LIVE6) do
		local sc = new("Script", name) sc.Source = src sc.Parent = if name == "NetLiftScript" then sv.Workspace else sv.ServerScriptService
		scripts[name] = sc
	end
	local rodClient = new("LocalScript", "RodFishingClient") rodClient.Source = VIS.LiveRodFishingClient
	rodClient.Parent = sv.StarterPlayer.StarterPlayerScripts
	scripts.RodFishingClient = rodClient
	local spawner = new("Script", "FishSpawner") spawner.Source = VIS.LiveFishSpawner spawner.Parent = sv.ServerScriptService
	scripts.FishSpawner = spawner
	local swimClient = new("LocalScript", "FishSwimClient") swimClient.Source = VIS.LiveFishSwimClient
	swimClient.Parent = sv.StarterPlayer.StarterPlayerScripts
	scripts.FishSwimClient = swimClient
	scripts.MoneyHud, scripts.ButtonsMoneyHud = moneyHuds(sv)
	-- the live rod shop UI (StarterGui.ScreenGui.Buttons.Frames.RodShopFrame)
	local rsf = new("Frame", "RodShopFrame")
	rsf.Parent = scripts.ButtonsMoneyHud.Parent.Parent -- Frames
	local rsc = new("LocalScript", "RodShopController")
	rsc.Source = SHOPUI.Live
	rsc.Parent = rsf
	scripts.RodShopController = rsc
	aquariumV1(sv)
	if opts.chain8cb then
		oldInstall(g, sv)
		update(g, sv)
	else
		install(g, sv)
	end
	assert(sv.ServerStorage:FindFirstChild("EconomyRodOffersBackup"), "rod offers not installed")
	return g, sv, history, scripts
end
local function upgradeAq(g, s) warnings = {} runUpgradeAq(g, s.Workspace) end
local function rollbackAq(g, s) warnings = {} runRollbackAq(g, s.Workspace) end
local function installSales(g, s) warnings = {} runInstallSales(g, s.Workspace) end
local function rollbackSales(g, s) warnings = {} runRollbackSales(g, s.Workspace) end

do
	local g, sv, history, sc = astraPlace()
	check("baseline: fresh a826d73 install = the release sources", sc.RodFishingSystem.Source == NEW.RodFishingSystem
		and sv.ServerScriptService.EconomyService.Source == NEW.EconomyService)
	local base = snapshot(g)
	local rodBackup = subtree(sv.ServerStorage.EconomyRodOffersBackup)

	installSales(g, sv)
	check("sales before the aquarium upgrade: refused, nothing changed", refused() and snapshot(g) == base)

	local commits = history.commits
	upgradeAq(g, sv)
	check("aquarium upgrade: one undo step", not refused() and history.commits == commits + 1)
	local aq = sv.ReplicatedStorage.AquariumCycle
	check("aquarium upgrade: Config/SharedTank/server/client = v1.2", aq.Config.Source == AQV12.Config and aq.SharedTank.Source == AQV12.SharedTank
		and sv.ServerScriptService.AquariumCycleServer.Source == AQV12.AquariumCycleServer
		and sv.StarterPlayer.StarterPlayerScripts.AquariumTankClient.Source == AQV12.AquariumTankClient)
	check("aquarium upgrade: other modules untouched", aq.CycleState.Source == AQV1.shared.CycleState and sv.ServerScriptService.AquariumEconomy.Source == AQV1.AquariumEconomy)
	local ab = sv.ServerStorage:FindFirstChild("EconomyAquariumBackup")
	check("aquarium upgrade: backup with 4 entries", ab and ab:GetAttribute("EconomyOwned") == true and #ab:GetChildren() == 4)
	check("aquarium upgrade: rod scripts untouched", sc.RodFishingSystem.Source == NEW.RodFishingSystem)
	local afterAq = snapshot(g)
	upgradeAq(g, sv)
	check("aquarium upgrade twice: refused", refused() and snapshot(g) == afterAq)

	commits = history.commits
	installSales(g, sv)
	check("sales: one undo step", not refused() and history.commits == commits + 1)
	local ok = true
	for name, src in pairs(SALES) do
		if sc[name] and sc[name].Source ~= src then ok = false print_real("  mismatch " .. name) end
	end
	check("sales: the 6 live scripts + RodFishingSystem = sales patches", ok and sc.GrinderProcessor.Source == SALES.GrinderProcessor)
	local svc = sv.ServerScriptService.EconomyService
	check("sales: EconomyService, Ledger, PieceTags = current", svc.Source == CUR.EconomyService and svc.Ledger.Source == CUR.Ledger and svc.PieceTags.Source == CUR.PieceTags)
	check("sales: shop, client, other modules untouched", sc.RodShopServer.Source == NEW.RodShopServer and svc.Offers.Source == NEW.Offers
		and sv.StarterPlayer.StarterPlayerScripts.EconomyClient.Source == NEW.EconomyClient)
	local sb = sv.ServerStorage:FindFirstChild("EconomySalesBackup")
	check("sales: backup with 10 entries", sb and #sb:GetChildren() == 10)
	check("sales: original rod backup untouched", subtree(sv.ServerStorage.EconomyRodOffersBackup) == rodBackup)
	local afterSales = snapshot(g)
	installSales(g, sv)
	check("sales twice: refused", refused() and snapshot(g) == afterSales)
	rollbackAq(g, sv)
	check("aquarium rollback while sales installed: refused", refused() and snapshot(g) == afterSales)
	uninstall(g, sv)
	check("rod uninstall while sales installed: refused", refused() and snapshot(g) == afterSales)

	rollbackSales(g, sv)
	check("sales rollback: exactly the state before sales", not refused() and snapshot(g) == afterAq)
	rollbackAq(g, sv)
	check("aquarium rollback: exactly the a826d73 + aquarium v1 place", not refused() and snapshot(g) == base)
	uninstall(g, sv)
	check("then the rod uninstall restores the live scripts", not refused() and sc.RodFishingSystem.Source == LIVE.RodFishingSystem
		and sc.RodShopServer.Source == LIVE.RodShopServer and sv.ServerScriptService:FindFirstChild("EconomyService") == nil)
	check("live sale scripts never touched by the rod install", sc.GrinderProcessor.Source == LIVE6.GrinderProcessor)
end

-- the 8cb2554 + UpdateRodPrompt chain ends in the same sources: sales installs there too
do
	local g, sv, _, sc = astraPlace({ chain8cb = true })
	upgradeAq(g, sv)
	installSales(g, sv)
	check("8cb2554 + update chain: aquarium + sales install", not refused() and sc.TruckSystem.Source == SALES.TruckSystem)
	rollbackSales(g, sv)
	rollbackAq(g, sv)
	check("8cb2554 + update chain: both roll back", not refused() and sv.ServerStorage:FindFirstChild("EconomyRodPromptBackup") ~= nil
		and sc.RodFishingSystem.Source == NEW.RodFishingSystem)
end

-- paid upgrades on top of sales
local function installUpg(g, s) warnings = {} runInstallUpg(g, s.Workspace) end
local function rollbackUpg(g, s) warnings = {} runRollbackUpg(g, s.Workspace) end
do
	local g, sv = astraPlace()
	upgradeAq(g, sv)
	local beforeSales = snapshot(g)
	local studioToday, studioAgain
	installUpg(g, sv)
	check("upgrades before sales: refused", refused() and snapshot(g) == beforeSales)
	installSales(g, sv)
	local afterSales = snapshot(g)
	installUpg(g, sv)
	check("upgrades: installed", not refused() and sv.ServerScriptService.AquariumEconomy.Source == UPG.AquariumEconomy)
	check("upgrades: backup with 1 entry", #sv.ServerStorage.EconomyUpgradesBackup:GetChildren() == 1)
	local afterUpg = snapshot(g)
	rollbackSales(g, sv)
	check("sales rollback while upgrades installed: refused", refused() and snapshot(g) == afterUpg)
	installUpg(g, sv)
	check("upgrades twice: refused", refused() and snapshot(g) == afterUpg)
	rollbackUpg(g, sv)
	check("upgrades rollback: exactly the sales state", not refused() and snapshot(g) == afterSales
		and sv.ServerScriptService.AquariumEconomy.Source == AQV1.AquariumEconomy)
end

------------------------------------------------------------ visual features (rebased on live)

-- fish jumps: the live FishSwimClient (with its harpoon branch) -> patched; uninstall restores it
local function jumpInstall(g, s) warnings = {} runJumpInstall(g, s.Workspace) end
local function jumpUninstall(g, s) warnings = {} runJumpUninstall(g, s.Workspace) end
do
	local g, sv = makeGame()
	local client = new("LocalScript", "FishSwimClient") client.Source = VIS.LiveFishSwimClient
	client.Parent = sv.StarterPlayer.StarterPlayerScripts
	local base = snapshot(g)
	sv.RunService.running = true
	jumpInstall(g, sv)
	check("jump install in Play: refused", refused() and snapshot(g) == base)
	sv.RunService.running = false
	jumpInstall(g, sv)
	check("jump install on the live client", not refused() and client.Source == VIS.JumpPatched
		and sv.ReplicatedStorage:FindFirstChild("FishJump") ~= nil and sv.ServerStorage:FindFirstChild("FishJumpBackup") ~= nil)
	check("jump patch keeps the live harpoon branch", client.Source:find("HARPOONED", 1, true) ~= nil)
	jumpUninstall(g, sv)
	check("jump uninstall restores the live client exactly", not refused() and snapshot(g) == base)
	local g2, sv2 = makeGame()
	local old = new("LocalScript", "FishSwimClient") old.Source = VIS.LiveFishSwimClient .. "\n-- edited"
	old.Parent = sv2.StarterPlayer.StarterPlayerScripts
	local b2 = snapshot(g2)
	jumpInstall(g2, sv2)
	check("jump install over a different client: refused", refused() and snapshot(g2) == b2)
end

-- immediate rod cast, on top of sales
local function rodCast(g, s) warnings = {} runRodCast(g, s.Workspace) end
local function rodCastBack(g, s) warnings = {} runRodCastBack(g, s.Workspace) end
do
	local g, sv, _, sc = astraPlace()
	upgradeAq(g, sv)
	local before = snapshot(g)
	rodCast(g, sv)
	check("rod cast before sales: refused (needs the sales RodFishingSystem)", refused() and snapshot(g) == before)
	installSales(g, sv)
	local afterSales = snapshot(g)
	rodCast(g, sv)
	check("rod cast: installed", not refused() and sc.RodFishingSystem.Source == VIS.RodCastServer and sc.RodFishingClient.Source == VIS.RodCastClient)
	local afterCast = snapshot(g)
	rollbackSales(g, sv)
	check("sales rollback while rod cast installed: refused", refused() and snapshot(g) == afterCast)
	rodCastBack(g, sv)
	check("rod cast rollback: exactly the sales state", not refused() and snapshot(g) == afterSales)
end

-- grinder dwell: every combination of fish jumps / rod cast on top of sales
local function dwell(g, s) warnings = {} runDwell(g, s.Workspace) end
local function dwellBack(g, s) warnings = {} runDwellBack(g, s.Workspace) end
do
	local g, sv = astraPlace()
	upgradeAq(g, sv)
	local before = snapshot(g)
	dwell(g, sv)
	check("dwell before sales: refused", refused() and snapshot(g) == before)
end
for _, combo in ipairs({ { jump = false, cast = false }, { jump = true, cast = false }, { jump = false, cast = true }, { jump = true, cast = true } }) do
	local label = string.format("dwell (jump %s, rod cast %s)", tostring(combo.jump), tostring(combo.cast))
	local g, sv, _, sc = astraPlace()
	upgradeAq(g, sv)
	installSales(g, sv)
	if combo.jump then
		jumpInstall(g, sv)
	end
	if combo.cast then
		rodCast(g, sv)
	end
	assert(not refused(), label .. ": setup")
	local before = snapshot(g)
	dwell(g, sv)
	check(label .. ": installed", not refused())
	check(label .. ": the matching client patch", sc.FishSwimClient.Source == (if combo.jump then DWELL.ClientJump else DWELL.ClientLive))
	check(label .. ": the matching rod patch", sc.RodFishingSystem.Source == (if combo.cast then DWELL.RodCast else DWELL.RodSales))
	check(label .. ": net + harpoon patched", sc.NetLiftScript.Source == DWELL.Net and sc.HarpoonSystem.Source == DWELL.Harpoon)
	local mod = sv.ReplicatedStorage:FindFirstChild("GrinderDwell")
	check(label .. ": module added, tagged", mod and mod.Source == DWELL.Module and mod:GetAttribute("EconomyOwned") == true)
	local after = snapshot(g)
	if combo.cast then
		rodCastBack(g, sv)
		check(label .. ": rod cast rollback refused while dwell is in", refused() and snapshot(g) == after)
	end
	rollbackSales(g, sv)
	check(label .. ": sales rollback refused while dwell is in", refused() and snapshot(g) == after)
	dwellBack(g, sv)
	check(label .. ": rollback restores exactly (module removed)", not refused() and snapshot(g) == before)
end
do
	local g, sv = astraPlace()
	upgradeAq(g, sv)
	installSales(g, sv)
	local mine = new("ModuleScript", "GrinderDwell") mine.Source = "return {}" mine.Parent = sv.ReplicatedStorage
	local before = snapshot(g)
	dwell(g, sv)
	check("dwell with someone else's ReplicatedStorage.GrinderDwell: refused", refused() and snapshot(g) == before)
	mine:Destroy()
	dwell(g, sv)
	sv.ReplicatedStorage.GrinderDwell.Source ..= "\n-- tuned"
	before = snapshot(g)
	dwellBack(g, sv)
	check("dwell rollback over an edited module: refused", refused() and snapshot(g) == before)
end

-- rare variants: on every rod version (sales / rod cast / dwell / both)
local function variants(g, s) warnings = {} runVariants(g, s.Workspace) end
local function variantsBack(g, s) warnings = {} runVariantsBack(g, s.Workspace) end
do
	local g, sv = astraPlace()
	upgradeAq(g, sv)
	local before = snapshot(g)
	variants(g, sv)
	check("variants before sales: refused", refused() and snapshot(g) == before)
end
for _, combo in ipairs({ { cast = false, dwell = false, rod = "sales" }, { cast = true, dwell = false, rod = "rodcast" },
	{ cast = false, dwell = true, rod = "dwell-sales" }, { cast = true, dwell = true, rod = "dwell-rodcast" } }) do
	local label = "variants on " .. combo.rod
	local g, sv, _, sc = astraPlace()
	upgradeAq(g, sv)
	installSales(g, sv)
	if combo.cast then rodCast(g, sv) end
	if combo.dwell then dwell(g, sv) end
	assert(not refused(), label .. ": setup")
	local before = snapshot(g)
	variants(g, sv)
	check(label .. ": installed", not refused())
	check(label .. ": the matching rod patch", sc.RodFishingSystem.Source == VAR["Rod_" .. combo.rod])
	check(label .. ": spawner + grinder patched", sc.FishSpawner.Source == VAR.Spawner and sc.GrinderProcessor.Source == VAR.Grinder)
	check(label .. ": both modules added, tagged", sv.ReplicatedStorage:FindFirstChild("FishVariants") and sv.ReplicatedStorage.FishVariants:GetAttribute("EconomyOwned") == true
		and sv.ReplicatedStorage:FindFirstChild("FishVariantVisuals") ~= nil)
	local after = snapshot(g)
	if combo.dwell then
		dwellBack(g, sv)
		check(label .. ": dwell rollback refused while variants are in", refused() and snapshot(g) == after)
	end
	if combo.cast then
		rodCastBack(g, sv)
		check(label .. ": rod cast rollback refused while variants are in", refused() and snapshot(g) == after)
	end
	variantsBack(g, sv)
	check(label .. ": rollback restores exactly (modules removed)", not refused() and snapshot(g) == before)
end

-- refusals change nothing
do
	local g, sv, _, sc = astraPlace()
	sv.RunService.running = true
	local before = snapshot(g)
	upgradeAq(g, sv)
	check("aquarium upgrade in Play: refused", refused() and snapshot(g) == before)
	sv.RunService.running = false
	sv.ReplicatedStorage.AquariumCycle.SharedTank.Source ..= "\n-- tuned"
	before = snapshot(g)
	upgradeAq(g, sv)
	check("aquarium upgrade over an edited module: refused", refused() and snapshot(g) == before)
end
do
	local g, sv, _, sc = astraPlace()
	upgradeAq(g, sv)
	sc.GrinderProcessor.Source ..= "\n-- hand edit"
	local before = snapshot(g)
	installSales(g, sv)
	check("sales over an edited live script: refused", refused() and snapshot(g) == before)
end
do
	local g, sv, _, sc = astraPlace()
	upgradeAq(g, sv)
	local dup = new("Script", "TruckSystem") dup.Source = LIVE6.TruckSystem dup.Parent = sv.Workspace
	local before = snapshot(g)
	installSales(g, sv)
	check("sales with two TruckSystem scripts: refused", refused() and snapshot(g) == before)
end
do
	-- the CustomerSystem without CarSalesServer's line-cap / per-minute hooks
	-- (what refused Astra's first InstallSales run): refused, and says where
	local g, sv, _, sc = astraPlace()
	upgradeAq(g, sv)
	sc.CustomerSystem.Source = OLDCUSTOMER
	local before = snapshot(g)
	installSales(g, sv)
	check("sales over the pre-hook CustomerSystem: refused", refused() and snapshot(g) == before)
	check("refusal names the first differing line", (warnings[#warnings] or ""):find("first difference at line", 1, true) ~= nil)
end
-- the 58dcd56 baselines were rebuilt from descriptions and lacked one comment
-- line each: the exact guard must refuse them (it did in Studio)
for _, case in ipairs({ { name = "CustomerSystem", src = RECON.CustomerSystem }, { name = "TruckSystem", src = RECON.TruckSystem } }) do
	local g, sv, _, sc = astraPlace()
	upgradeAq(g, sv)
	sc[case.name].Source = case.src
	local before = snapshot(g)
	installSales(g, sv)
	check("sales over the comment-less " .. case.name .. " reconstruction: refused", refused() and snapshot(g) == before)
	check(case.name .. " refusal names the missing comment line", (warnings[#warnings] or ""):find("first difference at line", 1, true) ~= nil)
end
do
	local g, sv = astraPlace()
	upgradeAq(g, sv)
	sv.ServerScriptService.EconomyService.Ledger:SetAttribute("EconomyOwned", nil)
	local before = snapshot(g)
	installSales(g, sv)
	check("sales when an economy module isn't ours: refused", refused() and snapshot(g) == before)
end
do
	local g, sv, _, sc = astraPlace()
	upgradeAq(g, sv)
	installSales(g, sv)
	sc.CustomerSystem.Source ..= "\n-- hand edit"
	local before = snapshot(g)
	rollbackSales(g, sv)
	check("sales rollback over an edited script: refused", refused() and snapshot(g) == before)
end

------------------------------------------------------------ economy milestones after the sales release

-- earnings popup: on top of sales (and upgrades, if used, first)
local function earnings(g, s) warnings = {} runEarnings(g, s.Workspace) end
local function earningsBack(g, s) warnings = {} runEarningsBack(g, s.Workspace) end
do
	local g, sv, history, sc = astraPlace()
	upgradeAq(g, sv)
	local before = snapshot(g)
	earnings(g, sv)
	check("earnings before sales: refused", refused() and snapshot(g) == before)
	installSales(g, sv)
	local afterSales = snapshot(g)
	sv.RunService.running = true
	earnings(g, sv)
	check("earnings in Play: refused", refused() and snapshot(g) == afterSales)
	sv.RunService.running = false
	local commits = history.commits
	earnings(g, sv)
	local svc = sv.ServerScriptService.EconomyService
	local client = sv.StarterPlayer.StarterPlayerScripts.EconomyClient
	check("earnings: installed in one undo step", not refused() and history.commits == commits + 1)
	check("earnings: EconomyService + EconomyClient = the earnings sources", svc.Source == EARN.EconomyService and client.Source == EARN.EconomyClient)
	check("earnings: core modules and sale scripts untouched", svc.Ledger.Source == CUR.Ledger and sc.TruckSystem.Source == SALES.TruckSystem)
	local eb = sv.ServerStorage:FindFirstChild("EconomyEarningsBackup")
	check("earnings: backup with 2 entries", eb and eb:GetAttribute("EconomyOwned") == true and #eb:GetChildren() == 2)
	local afterEarn = snapshot(g)
	earnings(g, sv)
	check("earnings twice: refused", refused() and snapshot(g) == afterEarn)
	rollbackSales(g, sv)
	check("sales rollback while earnings is in: refused", refused() and snapshot(g) == afterEarn)
	installUpg(g, sv)
	check("upgrades after earnings: refused (install upgrades first)", refused() and snapshot(g) == afterEarn)
	earningsBack(g, sv)
	check("earnings rollback: exactly the sales state", not refused() and snapshot(g) == afterSales)
	installUpg(g, sv)
	earnings(g, sv)
	check("upgrades, then earnings: both in", not refused() and svc.Source == EARN.EconomyService
		and sv.ServerScriptService.AquariumEconomy.Source == UPG.AquariumEconomy)
	svc.Source ..= "\n-- hand edit"
	local edited = snapshot(g)
	earningsBack(g, sv)
	check("earnings rollback over an edited EconomyService: refused", refused() and snapshot(g) == edited)
end
-- with the whole visual chain in (rod cast, dwell, variants): earnings still installs
do
	local g, sv = astraPlace()
	upgradeAq(g, sv)
	installSales(g, sv)
	installUpg(g, sv)
	rodCast(g, sv)
	dwell(g, sv)
	variants(g, sv)
	assert(not refused(), "full chain setup")
	local before = snapshot(g)
	earnings(g, sv)
	check("earnings on the full chain: installed", not refused())
	earningsBack(g, sv)
	check("earnings on the full chain: rolls back exactly", not refused() and snapshot(g) == before)
end

-- Blender Bot recovery: on top of sales, independent of earnings
local function botFix(g, s) warnings = {} runBotFix(g, s.Workspace) end
local function botFixBack(g, s) warnings = {} runBotFixBack(g, s.Workspace) end
do
	local g, sv, history, sc = astraPlace()
	upgradeAq(g, sv)
	local before = snapshot(g)
	botFix(g, sv)
	check("bot fix before sales: refused", refused() and snapshot(g) == before)
	installSales(g, sv)
	local afterSales = snapshot(g)
	local commits = history.commits
	botFix(g, sv)
	check("bot fix: installed in one undo step", not refused() and history.commits == commits + 1 and sc.BotSystem.Source == BOTFIX)
	check("bot fix: only BotSystem changed", sc.TruckSystem.Source == SALES.TruckSystem and sc.GrinderProcessor.Source == SALES.GrinderProcessor
		and #sv.ServerStorage.EconomyBotBackup:GetChildren() == 1)
	local afterBot = snapshot(g)
	botFix(g, sv)
	check("bot fix twice: refused", refused() and snapshot(g) == afterBot)
	rollbackSales(g, sv)
	check("sales rollback while the bot fix is in: refused", refused() and snapshot(g) == afterBot)
	earnings(g, sv)
	check("earnings on top of the bot fix: installs", not refused())
	earningsBack(g, sv)
	botFixBack(g, sv)
	check("bot fix rollback: exactly the sales state", not refused() and snapshot(g) == afterSales)
	sc.BotSystem.Source = SALES.BotSystem .. "\n-- hand edit"
	local edited = snapshot(g)
	botFix(g, sv)
	check("bot fix over an edited BotSystem: refused, names the line", refused() and snapshot(g) == edited
		and (warnings[#warnings] or ""):find("first difference at line", 1, true) ~= nil)
end

-- variant glow on moved meat: on top of variants; BotSystem = sales or bot-recovery version
local function meatGlow(g, s) warnings = {} runMeatGlow(g, s.Workspace) end
local function meatGlowBack(g, s) warnings = {} runMeatGlowBack(g, s.Workspace) end
for _, withBotFix in ipairs({ false, true }) do
	local label = if withBotFix then "meat glow (bot fix in)" else "meat glow"
	local g, sv, history, sc = astraPlace()
	upgradeAq(g, sv)
	installSales(g, sv)
	if withBotFix then botFix(g, sv) end
	local before = snapshot(g)
	meatGlow(g, sv)
	check(label .. " before variants: refused", refused() and snapshot(g) == before)
	variants(g, sv)
	local afterVar = snapshot(g)
	local commits = history.commits
	meatGlow(g, sv)
	check(label .. ": installed in one undo step", not refused() and history.commits == commits + 1)
	check(label .. ": the matching BotSystem patch", sc.BotSystem.Source == (if withBotFix then GLOW.Bot_bot else GLOW.Bot_sales))
	check(label .. ": customer + truck patched", sc.CustomerSystem.Source == GLOW.Customer and sc.TruckSystem.Source == GLOW.Truck)
	check(label .. ": backup with 3 entries", #sv.ServerStorage.EconomyMeatGlowBackup:GetChildren() == 3)
	local afterGlow = snapshot(g)
	meatGlow(g, sv)
	check(label .. " twice: refused", refused() and snapshot(g) == afterGlow)
	variantsBack(g, sv)
	check(label .. ": variants rollback refused while it is in", refused() and snapshot(g) == afterGlow)
	if withBotFix then
		botFixBack(g, sv)
		check(label .. ": bot fix rollback refused while it is in", refused() and snapshot(g) == afterGlow)
	else
		botFix(g, sv)
		check(label .. ": bot fix after meat glow: refused (install it first)", refused() and snapshot(g) == afterGlow)
	end
	meatGlowBack(g, sv)
	check(label .. ": rollback restores exactly", not refused() and snapshot(g) == afterVar)
end
do
	local g, sv = astraPlace()
	upgradeAq(g, sv)
	installSales(g, sv)
	variants(g, sv)
	sv.ReplicatedStorage.FishVariantVisuals.Source ..= "\n-- tuned"
	local before = snapshot(g)
	meatGlow(g, sv)
	check("meat glow over an edited FishVariantVisuals: refused", refused() and snapshot(g) == before)
end

-- harpoon mid-jump fix: on the fish-jump client, or grinder dwell over it
local function blend(g, s) warnings = {} runBlend(g, s.Workspace) end
local function blendBack(g, s) warnings = {} runBlendBack(g, s.Workspace) end
do
	local g, sv, _, sc = astraPlace()
	local before = snapshot(g)
	blend(g, sv)
	check("harpoon blend without fish jumps: refused", refused() and snapshot(g) == before)
end
for _, withDwell in ipairs({ false, true }) do
	local label = if withDwell then "harpoon blend (dwell in)" else "harpoon blend"
	local g, sv, history, sc = astraPlace()
	jumpInstall(g, sv)
	if withDwell then
		upgradeAq(g, sv)
		installSales(g, sv)
		dwell(g, sv)
	end
	assert(not refused(), label .. ": setup")
	local before = snapshot(g)
	local commits = history.commits
	blend(g, sv)
	check(label .. ": installed in one undo step", not refused() and history.commits == commits + 1)
	check(label .. ": the matching client patch", sc.FishSwimClient.Source == (if withDwell then BLEND.Dwell else BLEND.Jump))
	check(label .. ": backup with 1 entry", #sv.ServerStorage.HarpoonBlendBackup:GetChildren() == 1)
	local after = snapshot(g)
	blend(g, sv)
	check(label .. " twice: refused", refused() and snapshot(g) == after)
	if withDwell then
		dwellBack(g, sv)
		check(label .. ": dwell rollback refused while it is in", refused() and snapshot(g) == after)
	else
		jumpUninstall(g, sv)
		check(label .. ": jump uninstall refused while it is in", refused() and snapshot(g) == after)
		upgradeAq(g, sv)
		installSales(g, sv)
		local mid = snapshot(g)
		dwell(g, sv)
		check(label .. ": dwell after it: refused (install dwell first)", refused() and snapshot(g) == mid)
		rollbackSales(g, sv)
		rollbackAq(g, sv)
	end
	blendBack(g, sv)
	check(label .. ": rollback restores exactly", not refused() and snapshot(g) == before)
end
do
	local g, sv = astraPlace()
	jumpInstall(g, sv)
	sv.ReplicatedStorage.FishJump.Source ..= "\n-- tuned"
	local before = snapshot(g)
	blend(g, sv)
	check("harpoon blend over an edited FishJump module: refused", refused() and snapshot(g) == before)
end

-- Money HUD: both live MoneyController copies -> leaderstats.Money; independent of the rest
local function moneyHud(g, s) warnings = {} runMoneyHud(g, s.Workspace) end
local function moneyHudBack(g, s) warnings = {} runMoneyHudBack(g, s.Workspace) end
do
	local g, sv = scene()
	local a = moneyHuds(sv)
	local before = snapshot(g)
	moneyHud(g, sv)
	check("money HUD without rod offers: refused", refused() and snapshot(g) == before and a.Source == MONEYHUD.Live)
end
do
	local g, sv, history, sc = astraPlace()
	upgradeAq(g, sv)
	installSales(g, sv) -- where Studio is now
	local afterSales = snapshot(g)
	sv.RunService.running = true
	moneyHud(g, sv)
	check("money HUD in Play: refused", refused() and snapshot(g) == afterSales)
	sv.RunService.running = false
	local commits = history.commits
	moneyHud(g, sv)
	check("money HUD: installed in one undo step", not refused() and history.commits == commits + 1)
	check("money HUD: both copies = the new controller", sc.MoneyHud.Source == MONEYHUD.New and sc.ButtonsMoneyHud.Source == MONEYHUD.New)
	local hb = sv.ServerStorage:FindFirstChild("EconomyMoneyHudBackup")
	check("money HUD: backup with 2 entries, Before = live", hb and #hb:GetChildren() == 2 and hb:GetChildren()[1].Before.Source == MONEYHUD.Live
		and hb:GetChildren()[2].Before.Source == MONEYHUD.Live)
	check("money HUD: nothing else changed", sv.ServerScriptService.EconomyService.Source == CUR.EconomyService and sc.TruckSystem.Source == SALES.TruckSystem)
	local afterHud = snapshot(g)
	moneyHud(g, sv)
	check("money HUD twice: refused", refused() and snapshot(g) == afterHud)
	earnings(g, sv)
	botFix(g, sv)
	check("other installs on top of the money HUD: fine", not refused())
	earningsBack(g, sv)
	botFixBack(g, sv)
	check("and back", snapshot(g) == afterHud)
	sc.ButtonsMoneyHud.Source ..= "\n-- hand edit"
	local edited = snapshot(g)
	moneyHudBack(g, sv)
	check("money HUD rollback over an edited copy: refused", refused() and snapshot(g) == edited)
	sc.ButtonsMoneyHud.Source = MONEYHUD.New
	moneyHudBack(g, sv)
	check("money HUD rollback: exactly the sales state", not refused() and snapshot(g) == afterSales)
end
for _, case in ipairs({
	{ label = "one copy edited", edit = function(sc) sc.ButtonsMoneyHud.Source = MONEYHUD.Live:gsub("VIPMulti", "VipMulti", 1) end, line = true },
	{ label = "one copy missing", edit = function(sc) sc.MoneyHud:Destroy() end },
	{ label = "a copy that is a Script", edit = function(sc)
		local p = sc.MoneyHud.Parent
		sc.MoneyHud:Destroy()
		local x = new("Script", "MoneyController") x.Source = MONEYHUD.Live x.Parent = p
	end },
}) do
	local g, sv, _, sc = astraPlace()
	case.edit(sc)
	local before = snapshot(g)
	moneyHud(g, sv)
	check("money HUD, " .. case.label .. ": refused, nothing changed", refused() and snapshot(g) == before)
	if case.line then
		check("money HUD refusal names the first differing line", (warnings[#warnings] or ""):find("first difference at line", 1, true) ~= nil)
	end
end
do
	local g, sv, _, sc = astraPlace()
	sc.MoneyHud.Source = MONEYHUD.Live:gsub("\n", "\r\n") .. "   \n"
	moneyHud(g, sv)
	check("money HUD: CRLF / trailing spaces in Studio still match", not refused() and sc.MoneyHud.Source == MONEYHUD.New)
end

-- Studio as Astra reported it (2026-09-29): everything but paid upgrades,
-- variants and meat glow. The live FishSpawner has the harpoon-safe despawn
-- guard; variants must install over it (and keep it), then meat glow.
do
	local g, sv, history, sc = astraPlace()
	check("live FishSpawner baseline has the harpoon despawn guard twice",
		select(2, sc.FishSpawner.Source:gsub('and not m:GetAttribute%\("HarpoonT"%\) then m:Destroy', "")) == 2)
	upgradeAq(g, sv)
	for _, step in ipairs({ installSales, moneyHud, earnings, botFix, jumpInstall, rodCast, dwell, blend }) do
		step(g, sv)
		assert(not refused(), "Astra's state: " .. tostring(warnings[#warnings]))
	end
	local studioNow = snapshot(g)
	local commits = history.commits
	variants(g, sv)
	check("Astra's state (no upgrades): variants installs in one undo step", not refused() and history.commits == commits + 1)
	check("variants: FishSpawner = the patch of the exact live source", sc.FishSpawner.Source == VAR.Spawner)
	check("variants: the harpoon despawn guard is kept",
		select(2, sc.FishSpawner.Source:gsub('and not m:GetAttribute%\("HarpoonT"%\) then m:Destroy', "")) == 2)
	check("variants: rod = the dwell + rod-cast version", sc.RodFishingSystem.Source == VAR["Rod_dwell-rodcast"])
	local afterVar = snapshot(g)
	meatGlow(g, sv)
	check("Astra's state: meat glow installs after variants (bot-recovery BotSystem)", not refused() and sc.BotSystem.Source == GLOW.Bot_bot)
	meatGlowBack(g, sv)
	check("meat glow rollback: exactly the variants state", not refused() and snapshot(g) == afterVar)
	variantsBack(g, sv)
	check("variants rollback: exactly Astra's state, live FishSpawner back", not refused() and snapshot(g) == studioNow
		and sc.FishSpawner.Source == VIS.LiveFishSpawner)
end
-- aquarium panel: one custom panel instead of three default prompts, on
-- Astra's current state (everything but paid upgrades, variants + glow in)
local function panel(g, s) warnings = {} runPanel(g, s.Workspace) end
local function panelBack(g, s) warnings = {} runPanelBack(g, s.Workspace) end
local function astraNow()
	local g, sv, history, sc = astraPlace()
	upgradeAq(g, sv)
	for _, step in ipairs({ installSales, moneyHud, earnings, botFix, jumpInstall, rodCast, dwell, blend, variants, meatGlow }) do
		step(g, sv)
		assert(not refused(), "Astra's state: " .. tostring(warnings[#warnings]))
	end
	return g, sv, history, sc
end
do
	local g, sv, history = astraNow()
	local acs = sv.ServerScriptService.AquariumCycleServer
	local sps = sv.StarterPlayer.StarterPlayerScripts
	local before = snapshot(g)
	sv.RunService.running = true
	panel(g, sv)
	check("panel in Play: refused", refused() and snapshot(g) == before)
	sv.RunService.running = false
	local commits = history.commits
	panel(g, sv)
	check("panel on Astra's state: installed in one undo step", not refused() and history.commits == commits + 1)
	check("panel: AquariumCycleServer = the panel version", acs.Source == PANEL.Server)
	local client = sps:FindFirstChild("AquariumPanelClient")
	check("panel: AquariumPanelClient added, tagged", client and client.ClassName == "LocalScript" and client.Source == PANEL.Client
		and client:GetAttribute("EconomyOwned") == true)
	local pb = sv.ServerStorage:FindFirstChild("AquariumPanelBackup")
	check("panel: backup = 1 change + 1 add", pb and #pb:GetChildren() == 2)
	check("panel: aquarium modules, tank client, bindings untouched", sv.ReplicatedStorage.AquariumCycle.Config.Source == AQV12.Config
		and sps.AquariumTankClient.Source == AQV12.AquariumTankClient)
	local after = snapshot(g)
	panel(g, sv)
	check("panel twice: refused", refused() and snapshot(g) == after)
	installUpg(g, sv)
	check("released InstallUpgrades refuses after the panel (needs a new installer anyway)", refused() and snapshot(g) == after)
	rollbackAq(g, sv)
	check("aquarium v1.2 rollback refused while the panel is in", refused() and snapshot(g) == after)
	acs.Source ..= "\n-- hand edit"
	local edited = snapshot(g)
	panelBack(g, sv)
	check("panel rollback over an edited server: refused", refused() and snapshot(g) == edited)
	acs.Source = PANEL.Server
	panelBack(g, sv)
	check("panel rollback: exactly Astra's state (client removed)", not refused() and snapshot(g) == before
		and sps:FindFirstChild("AquariumPanelClient") == nil)
end
do
	-- aquarium v1 only (no v1.2): refused
	local g, sv = astraPlace()
	local before = snapshot(g)
	panel(g, sv)
	check("panel without aquarium v1.2: refused", refused() and snapshot(g) == before)
end
do
	local g, sv = astraNow()
	sv.ServerScriptService.AquariumCycleServer.Source ..= "\n-- tuned"
	local before = snapshot(g)
	panel(g, sv)
	check("panel over an edited AquariumCycleServer: refused, names the line", refused() and snapshot(g) == before
		and (warnings[#warnings] or ""):find("first difference at line", 1, true) ~= nil)
end
do
	local g, sv = astraNow()
	local mine = new("LocalScript", "AquariumPanelClient")
	mine.Source = "-- someone else's"
	mine.Parent = sv.StarterPlayer.StarterPlayerScripts
	local before = snapshot(g)
	panel(g, sv)
	check("panel when an AquariumPanelClient already exists: refused, kept", refused() and snapshot(g) == before and mine.Source == "-- someone else's")
end
do
	local g, sv = astraNow()
	sv.ReplicatedStorage.AquariumCycle.Upgrades.Source ..= "\n-- retuned"
	local before = snapshot(g)
	panel(g, sv)
	check("panel over an edited Upgrades module: refused", refused() and snapshot(g) == before)
end

-- fish jump more often: only the FishJump module; FishJumpBackup untouched
local function jumpRate(g, s) warnings = {} runJumpRate(g, s.Workspace) end
local function jumpRateBack(g, s) warnings = {} runJumpRateBack(g, s.Workspace) end
do
	local g, sv, history, sc = astraNow()
	local module = sv.ReplicatedStorage.FishJump
	local client = sc.FishSwimClient.Source
	local jumpBackup = subtree(sv.ServerStorage.FishJumpBackup)
	local before = snapshot(g)
	local commits = history.commits
	jumpRate(g, sv)
	check("jump rate on Astra's state: one undo step", not refused() and history.commits == commits + 1)
	check("jump rate: FishJump = the more-often module", module.Source == RATE.Module)
	check("jump rate: FishSwimClient untouched (its protections stay)", sc.FishSwimClient.Source == client)
	check("jump rate: FishJumpBackup untouched; own backup with 1 entry", subtree(sv.ServerStorage.FishJumpBackup) == jumpBackup
		and #sv.ServerStorage.FishJumpRateBackup:GetChildren() == 1)
	local after = snapshot(g)
	jumpRate(g, sv)
	check("jump rate twice: refused", refused() and snapshot(g) == after)
	module.Source ..= "\n-- tuned"
	local edited = snapshot(g)
	jumpRateBack(g, sv)
	check("jump rate rollback over an edited module: refused", refused() and snapshot(g) == edited)
	module.Source = RATE.Module
	jumpRateBack(g, sv)
	check("jump rate rollback: exactly the state before", not refused() and snapshot(g) == before)
end
do
	local g, sv = astraPlace()
	local before = snapshot(g)
	jumpRate(g, sv)
	check("jump rate without fish jumps: refused", refused() and snapshot(g) == before)
	jumpInstall(g, sv)
	sv.ReplicatedStorage.FishJump.Source ..= "\n-- tuned"
	before = snapshot(g)
	jumpRate(g, sv)
	check("jump rate over an edited FishJump: refused, names the line", refused() and snapshot(g) == before
		and (warnings[#warnings] or ""):find("first difference at line", 1, true) ~= nil)
end
do
	local g, sv = astraPlace()
	jumpInstall(g, sv)
	jumpRate(g, sv)
	local mid = snapshot(g)
	jumpUninstall(g, sv)
	check("UninstallFishJump refuses while the jump rate is in", refused() and snapshot(g) == mid
		and (warnings[#warnings] or ""):find("RollbackJumpRate", 1, true) ~= nil)
	jumpRateBack(g, sv)
	jumpUninstall(g, sv)
	check("then it uninstalls", not refused() and sv.ReplicatedStorage:FindFirstChild("FishJump") == nil)
end

-- rods milestone 1: saved ownership + equip + faster bites, on Astra's state
local function rods(g, s) warnings = {} runRods(g, s.Workspace) end
local function rodsBack(g, s) warnings = {} runRodsBack(g, s.Workspace) end
do
	local g, sv, history, sc = astraNow()
	panel(g, sv) -- installed too (aquarium only)
	local svc = sv.ServerScriptService.EconomyService
	local backups = {}
	for _, name in ipairs({ "EconomyRodOffersBackup", "EconomySalesBackup", "EconomyEarningsBackup", "EconomyVariantsBackup", "EconomyMeatGlowBackup" }) do
		backups[name] = subtree(sv.ServerStorage[name])
	end
	local before = snapshot(g)
	sv.RunService.running = true
	rods(g, sv)
	check("rods in Play: refused", refused() and snapshot(g) == before)
	sv.RunService.running = false
	local commits = history.commits
	rods(g, sv)
	check("rods on Astra's state: installed in one undo step", not refused() and history.commits == commits + 1)
	check("rods: EconomyService / Config / MoneyStore = the rods sources", svc.Source == RODS.EconomyService
		and svc.Config.Source == RODS.Config and svc.MoneyStore.Source == RODS.MoneyStore)
	check("rods: RodShopServer + RodFishingSystem patched", sc.RodShopServer.Source == RODS.Shop and sc.RodFishingSystem.Source == RODS.Fishing)
	check("rods: EconomyService.Rods added, tagged", svc:FindFirstChild("Rods") and svc.Rods.Source == RODS.Rods and svc.Rods:GetAttribute("EconomyOwned") == true)
	check("rods: other core modules untouched", svc.Ledger.Source == CUR.Ledger and svc.Offers.Source == CUR.Offers)
	local rb = sv.ServerStorage:FindFirstChild("EconomyRodsBackup")
	check("rods: backup = 5 changes + 1 add", rb and #rb:GetChildren() == 6)
	local kept = true
	for name, tree in pairs(backups) do
		kept = kept and subtree(sv.ServerStorage[name]) == tree
	end
	check("rods: every earlier backup untouched", kept)
	local after = snapshot(g)
	rods(g, sv)
	check("rods twice: refused", refused() and snapshot(g) == after)
	earningsBack(g, sv)
	check("earnings rollback refused while rods are in", refused() and snapshot(g) == after)
	variantsBack(g, sv)
	check("variants rollback refused while rods are in", refused() and snapshot(g) == after)
	sc.RodShopServer.Source ..= "\n-- hand edit"
	local edited = snapshot(g)
	rodsBack(g, sv)
	check("rods rollback over an edited RodShopServer: refused", refused() and snapshot(g) == edited)
	sc.RodShopServer.Source = RODS.Shop
	rodsBack(g, sv)
	check("rods rollback: exactly the state before (Rods module removed)", not refused() and snapshot(g) == before and svc:FindFirstChild("Rods") == nil)
end
do
	-- without earnings (EconomyService still the sales version): refused
	local g, sv = astraPlace()
	upgradeAq(g, sv)
	installSales(g, sv)
	variants(g, sv)
	local before = snapshot(g)
	rods(g, sv)
	check("rods without earnings: refused", refused() and snapshot(g) == before)
end
do
	local g, sv = astraNow()
	sv.ServerScriptService.EconomyService.MoneyStore.Source ..= "\n-- tuned"
	local before = snapshot(g)
	rods(g, sv)
	check("rods over an edited MoneyStore: refused, names the line", refused() and snapshot(g) == before
		and (warnings[#warnings] or ""):find("first difference at line", 1, true) ~= nil)
end
do
	local g, sv = astraNow()
	local stray = new("ModuleScript", "Rods")
	stray.Source = "return {}"
	stray.Parent = sv.ServerScriptService.EconomyService
	local before = snapshot(g)
	rods(g, sv)
	check("rods when an EconomyService.Rods already exists: refused, kept", refused() and snapshot(g) == before and stray.Source == "return {}")
end
do
	-- the legacy (pre-offers) RodShopServer isn't what Studio has: refused
	local g, sv, _, sc = astraNow()
	sc.RodShopServer.Source = LIVE.RodShopServer
	local before = snapshot(g)
	rods(g, sv)
	check("rods over the legacy RodShopServer: refused", refused() and snapshot(g) == before)
end

-- rod shop UI: the exact live controller -> owned / equipped / truthful results; needs rods
local function shopUi(g, s) warnings = {} runShopUi(g, s.Workspace) end
local function shopUiBack(g, s) warnings = {} runShopUiBack(g, s.Workspace) end
do
	local g, sv, history, sc = astraNow()
	local before = snapshot(g)
	shopUi(g, sv)
	check("shop UI without rods: refused", refused() and snapshot(g) == before)
	rods(g, sv)
	local afterRods = snapshot(g)
	sv.RunService.running = true
	shopUi(g, sv)
	check("shop UI in Play: refused", refused() and snapshot(g) == afterRods)
	sv.RunService.running = false
	local commits = history.commits
	shopUi(g, sv)
	check("shop UI: installed in one undo step", not refused() and history.commits == commits + 1)
	check("shop UI: the controller is the patched one; nothing else changed", sc.RodShopController.Source == SHOPUI.New
		and sc.RodShopServer.Source == RODS.Shop and #sv.ServerStorage.EconomyRodShopUIBackup:GetChildren() == 1)
	local after = snapshot(g)
	shopUi(g, sv)
	check("shop UI twice: refused", refused() and snapshot(g) == after)
	rodsBack(g, sv)
	check("rods rollback refused while the shop UI is in", refused() and snapshot(g) == after)
	sc.RodShopController.Source ..= "\n-- hand edit"
	local edited = snapshot(g)
	shopUiBack(g, sv)
	check("shop UI rollback over an edited controller: refused", refused() and snapshot(g) == edited)
	sc.RodShopController.Source = SHOPUI.New
	shopUiBack(g, sv)
	check("shop UI rollback: exactly the rods state (live controller back)", not refused() and snapshot(g) == afterRods
		and sc.RodShopController.Source == SHOPUI.Live)
	rodsBack(g, sv)
	check("then rods roll back too", not refused() and snapshot(g) == before)
end
do
	local g, sv, _, sc = astraNow()
	rods(g, sv)
	sc.RodShopController.Source = SHOPUI.Live:gsub('"NO %$ YET"', '"NOPE"', 1)
	local before = snapshot(g)
	shopUi(g, sv)
	check("shop UI over a different controller: refused, names the line", refused() and snapshot(g) == before
		and (warnings[#warnings] or ""):find("first difference at line", 1, true) ~= nil)
end

-- the upgrade board + one net capacity: on Astra's LIVE state (2026-09-30):
-- panel, rods, shop UI, jump rate, and the GrinderUpgrades system Astra
-- installed (EconomyService with the blade multiplier, GrinderUpgradesServer /
-- Client / Config, backups GrinderUpgradesBackup + BillboardLockBackup)
local function suite(g, s) warnings = {} runSuite(g, s.Workspace) end
local function suiteBack(g, s) warnings = {} runSuiteBack(g, s.Workspace) end
local function astraCurrent()
	local g, sv, history, sc = astraNow()
	panel(g, sv)
	rods(g, sv)
	shopUi(g, sv)
	jumpRate(g, sv)
	assert(not refused(), "Astra's current state: " .. tostring(warnings[#warnings]))
	return g, sv, history, sc
end
local function astraLive()
	local g, sv, history, sc = astraCurrent()
	sv.ServerScriptService.EconomyService.Source = GLIVE.EconomyService -- the blade multiplier, as installed
	local gs = new("Script", "GrinderUpgradesServer")
	gs.Source = GLIVE.Server
	gs.Parent = sv.ServerScriptService
	local gc = new("LocalScript", "GrinderUpgradesClient")
	gc.Source = GLIVE.Client
	gc.Parent = sv.StarterPlayer.StarterPlayerScripts
	local cfg = new("ModuleScript", "GrinderUpgradesConfig")
	cfg.Source = GLIVE.Config
	cfg.Parent = sv.ReplicatedStorage
	-- the live NetLiftScript (per-player NetMaxWeight gate) in Workspace.NetLift
	local netLift = new("Model", "NetLift")
	netLift.Parent = sv.Workspace
	sc.NetLiftScript.Parent = netLift
	sc.NetLiftScript.Source = GLIVE.NetLift
	for _, name in ipairs({ "GrinderUpgradesBackup", "BillboardLockBackup" }) do
		local f = new("Folder", name)
		f.Parent = sv.ServerStorage
	end
	return g, sv, history, sc
end
do
	local g, sv, history, sc = astraLive()
	local svc = sv.ServerScriptService.EconomyService
	local sss = sv.ServerScriptService
	local sps = sv.StarterPlayer.StarterPlayerScripts
	local backups = {}
	for _, bk in ipairs(sv.ServerStorage:GetChildren()) do
		backups[bk.Name] = subtree(bk)
	end
	local before = snapshot(g)
	sv.RunService.running = true
	suite(g, sv)
	check("board upgrades in Play: refused", refused() and snapshot(g) == before)
	sv.RunService.running = false
	local commits = history.commits
	suite(g, sv)
	check("board upgrades on Astra's live state: one undo step", not refused() and history.commits == commits + 1)
	check("board upgrades: EconomyService (blade multiplier carried) and the core updated", svc.Source == SUITE.EconomyService
		and svc.Source:find("GrinderUpgrades: the owner's blade tier", 1, true) ~= nil and svc.Config.Source == SUITE.Config
		and svc.MoneyStore.Source == SUITE.MoneyStore and svc.Pricing.Source == SUITE.Pricing and svc.Ledger.Source == SUITE.Ledger
		and svc.Sales.Source == SUITE.Sales)
	check("board upgrades: RodFishingSystem, GrinderUpgradesServer / Client patched; GrinderUpgradesConfig untouched",
		sc.RodFishingSystem.Source == SUITE.Fishing and sss.GrinderUpgradesServer.Source == SUITE.GServer
		and sps.GrinderUpgradesClient.Source == SUITE.GClient and sv.ReplicatedStorage.GrinderUpgradesConfig.Source == GLIVE.Config)
	local addsOk = true
	for _, a in ipairs({
		{ svc, "NetKg", "NetKg" }, { svc, "BoardUpgrades", "BoardUpgrades" }, { sss, "NetCapacityServer", "NetCapacityServer" },
		{ sss, "UpgradeBoardServer", "UpgradeBoardServer" }, { sps, "KgSignClient", "KgSignClient" }, { sps, "UpgradeBoardClient", "UpgradeBoardClient" },
	}) do
		local inst = a[1]:FindFirstChild(a[2])
		addsOk = addsOk and inst ~= nil and inst.Source == SUITE[a[3]] and inst:GetAttribute("EconomyOwned") == true
	end
	check("board upgrades: 6 scripts added, tagged EconomyOwned", addsOk)
	check("board upgrades: Rods / shop / shop UI / NetLiftScript untouched", svc.Rods.Source == RODS.Rods and sc.RodShopServer.Source == RODS.Shop
		and sc.RodShopController.Source == SHOPUI.New and sc.NetLiftScript.Source == GLIVE.NetLift)
	check("board upgrades: the BillboardLock line carried into the installed EconomyService",
		svc.Source:find("gui.Size = UDim2.fromScale(6.25, 3) -- locked world size", 1, true) ~= nil
		and svc.Source:find("fromOffset(200, 96)", 1, true) == nil)
	check("board upgrades: backup = 10 changes + 6 adds", #sv.ServerStorage.EconomyBoardUpgradesBackup:GetChildren() == 16)
	check("board upgrades: the MeatGlow CustomerSystem patched (customers for every player)",
		sc.CustomerSystem.Source == SUITE.Customer and SUITE.Customer:find("pcall(Economy.customers)", 1, true) ~= nil)
	local kept = true
	for name, tree in pairs(backups) do
		kept = kept and sv.ServerStorage:FindFirstChild(name) ~= nil and subtree(sv.ServerStorage[name]) == tree
	end
	check("board upgrades: every earlier backup untouched (GrinderUpgradesBackup, BillboardLockBackup, rods, ...)", kept)
	local after = snapshot(g)
	suite(g, sv)
	check("board upgrades twice: refused", refused() and snapshot(g) == after)
	rodsBack(g, sv)
	check("rods rollback refused while the board upgrades are in", refused() and snapshot(g) == after)
	sss.GrinderUpgradesServer.Source ..= "\n-- hand edit"
	local edited = snapshot(g)
	suiteBack(g, sv)
	check("board upgrades rollback over an edited GrinderUpgradesServer: refused", refused() and snapshot(g) == edited)
	sss.GrinderUpgradesServer.Source = SUITE.GServer
	suiteBack(g, sv)
	check("board upgrades rollback: exactly Astra's live state (blade EconomyService, live grinder scripts; added scripts gone)",
		not refused() and snapshot(g) == before and svc.Source == GLIVE.EconomyService and sss.GrinderUpgradesServer.Source == GLIVE.Server
		and sps.GrinderUpgradesClient.Source == GLIVE.Client and sss:FindFirstChild("NetCapacityServer") == nil and svc:FindFirstChild("NetKg") == nil)
	check("board upgrades rollback: the MeatGlow CustomerSystem back exactly", sc.CustomerSystem.Source == GLOW.Customer)
	suite(g, sv)
	check("and installs again after the rollback", not refused())
end
do
	-- a CustomerSystem other than the MeatGlow one (e.g. the sales version without the glow)
	local g, sv, _, sc = astraLive()
	sc.CustomerSystem.Source = GLOW.Customer:gsub("WAIT_FOR_MEAT = 18", "WAIT_FOR_MEAT = 20", 1)
	local before = snapshot(g)
	suite(g, sv)
	check("board upgrades over a different CustomerSystem: refused, names the line", refused() and snapshot(g) == before
		and (warnings[#warnings] or ""):find("first difference at line", 1, true) ~= nil)
end
do
	local g, sv = astraLive()
	sv.ServerScriptService.EconomyService.Source = RODS.EconomyService -- the rods release WITHOUT the blade multiplier
	local before = snapshot(g)
	suite(g, sv)
	check("board upgrades on an EconomyService without the blade multiplier: refused, names the line", refused() and snapshot(g) == before
		and (warnings[#warnings] or ""):find("first difference at line", 1, true) ~= nil)
end
do
	local g, sv = astraLive()
	-- the baseline b97a01c assumed (without BillboardLock): not what Studio has
	sv.ServerScriptService.EconomyService.Source = GLIVE.EconomyService:gsub("gui.Size = UDim2.fromScale%(6.25, 3%) %-%- locked world size", "gui.Size = UDim2.fromOffset(200, 96)", 1)
	local before = snapshot(g)
	suite(g, sv)
	check("board upgrades on an EconomyService without the BillboardLock line: refused, names the line", refused() and snapshot(g) == before
		and (warnings[#warnings] or ""):find("first difference at line", 1, true) ~= nil)
end
do
	local g, sv, _, sc = astraLive()
	sc.NetLiftScript.Source = GLIVE.NetLift:gsub('player:GetAttribute%("NetMaxWeight"%) or ', "", 1) -- a shared-only gate
	local before = snapshot(g)
	suite(g, sv)
	check("board upgrades over a NetLiftScript that doesn't read NetMaxWeight: refused", refused() and snapshot(g) == before)
end
do
	local g, sv = astraCurrent() -- no GrinderUpgrades at all
	local before = snapshot(g)
	suite(g, sv)
	check("board upgrades without the GrinderUpgrades system: refused", refused() and snapshot(g) == before)
end
do
	local g, sv = astraLive()
	sv.ServerScriptService.GrinderUpgradesServer.Source = GLIVE.Server:gsub("d.MaxActivationDistance = 24", "d.MaxActivationDistance = 30", 1)
	local before = snapshot(g)
	suite(g, sv)
	check("board upgrades over a different GrinderUpgradesServer: refused (not overwritten)", refused() and snapshot(g) == before)
end
-- the board-art update (InstallBoardArt): on the INSTALLED board release
local function art(g, s) warnings = {} runArt(g, s.Workspace) end
local function artBack(g, s) warnings = {} runArtBack(g, s.Workspace) end
do
	local g, sv, history = astraLive()
	local before = snapshot(g)
	art(g, sv)
	check("board art without the board release installed: refused, nothing changed", refused() and snapshot(g) == before)
	suite(g, sv)
	assert(not refused(), "board release: " .. tostring(warnings[#warnings]))
	local sss, sps, svc = sv.ServerScriptService, sv.StarterPlayer.StarterPlayerScripts, sv.ServerScriptService.EconomyService
	local backups = {}
	for _, bk in ipairs(sv.ServerStorage:GetChildren()) do
		backups[bk.Name] = subtree(bk)
	end
	local installed = snapshot(g)
	sv.RunService.running = true
	art(g, sv)
	check("board art in Play: refused", refused() and snapshot(g) == installed)
	sv.RunService.running = false
	local commits = history.commits
	art(g, sv)
	check("board art on the installed board: one undo step", not refused() and history.commits == commits + 1)
	check("board art: UpgradeBoardServer / Client replaced, still tagged EconomyOwned", sss.UpgradeBoardServer.Source == ART.Server
		and sps.UpgradeBoardClient.Source == ART.Client and sss.UpgradeBoardServer:GetAttribute("EconomyOwned") == true
		and sps.UpgradeBoardClient:GetAttribute("EconomyOwned") == true)
	check("board art: nothing else changed (EconomyService, NetCapacityServer, KgSignClient, the rest)", svc.Source == SUITE.EconomyService
		and sss.NetCapacityServer.Source == SUITE.NetCapacityServer and sps.KgSignClient.Source == SUITE.KgSignClient
		and svc.Config.Source == SUITE.Config)
	check("board art: backup EconomyBoardArtBackup with its 2 changes; every earlier backup untouched", (function()
		local bk = sv.ServerStorage:FindFirstChild("EconomyBoardArtBackup")
		if not (bk and #bk:GetChildren() == 2) then
			return false
		end
		for name, tree in pairs(backups) do
			if not (sv.ServerStorage:FindFirstChild(name) and subtree(sv.ServerStorage[name]) == tree) then
				return false
			end
		end
		return true
	end)())
	local after = snapshot(g)
	art(g, sv)
	check("board art twice: refused", refused() and snapshot(g) == after)
	suiteBack(g, sv)
	check("the board release's rollback is refused while the art update is in", refused() and snapshot(g) == after)
	sps.UpgradeBoardClient.Source ..= "\n-- hand edit"
	local edited = snapshot(g)
	artBack(g, sv)
	check("board art rollback over an edited client: refused", refused() and snapshot(g) == edited)
	sps.UpgradeBoardClient.Source = ART.Client
	artBack(g, sv)
	check("board art rollback: exactly the installed board release again", not refused() and snapshot(g) == installed
		and sss.UpgradeBoardServer.Source == ART.OldServer and sps.UpgradeBoardClient.Source == ART.OldClient)
	suiteBack(g, sv)
	check("then the board release rolls back too", not refused())
end
do
	-- a board client edited after the board release: not the version the art update knows
	local g, sv = astraLive()
	suite(g, sv)
	local sps = sv.StarterPlayer.StarterPlayerScripts
	sps.UpgradeBoardClient.Source = ART.OldClient:gsub("FLASH_SECONDS = 1.6", "FLASH_SECONDS = 2", 1)
	local before = snapshot(g)
	art(g, sv)
	check("board art over a different UpgradeBoardClient: refused, names the line", refused() and snapshot(g) == before
		and (warnings[#warnings] or ""):find("first difference at line", 1, true) ~= nil)
	sps.UpgradeBoardClient.Source = ART.OldClient
	sv.ServerScriptService.EconomyService.Source ..= "\n-- changed"
	before = snapshot(g)
	art(g, sv)
	check("board art over a different EconomyService: refused", refused() and snapshot(g) == before)
end
do
	-- the board scripts without their EconomyOwned tag: not ours
	local g, sv = astraLive()
	suite(g, sv)
	sv.ServerScriptService.UpgradeBoardServer:SetAttribute("EconomyOwned", nil)
	local before = snapshot(g)
	art(g, sv)
	check("board art over an untagged UpgradeBoardServer: refused (not ours)", refused() and snapshot(g) == before)
end
do
	local g, sv = astraLive()
	sv.ReplicatedStorage.GrinderUpgradesConfig.Source ..= "\n-- tuned"
	local before = snapshot(g)
	suite(g, sv)
	check("board upgrades over a different GrinderUpgradesConfig: refused", refused() and snapshot(g) == before)
end
do
	local g, sv = astraLive()
	local f = new("Folder", "EconomyNetKgBackup") -- a superseded milestone somehow installed
	f.Parent = sv.ServerStorage
	local before = snapshot(g)
	suite(g, sv)
	check("board upgrades with a superseded milestone's backup present: refused", refused() and snapshot(g) == before)
end
do
	local g, sv = astraLive()
	local mine = new("Script", "NetCapacityServer")
	mine.Source = "-- someone else's"
	mine.Parent = sv.ServerScriptService
	local before = snapshot(g)
	suite(g, sv)
	check("board upgrades when a NetCapacityServer already exists: refused, kept", refused() and snapshot(g) == before and mine.Source == "-- someone else's")
end

-- the old baseline (no HarpoonT in the despawn guard) is not what Studio has: refused
do
	local g, sv, _, sc = astraPlace()
	upgradeAq(g, sv)
	installSales(g, sv)
	sc.FishSpawner.Source = VIS.LiveFishSpawner:gsub(' and not m:GetAttribute%\("HarpoonT"%\)', "")
	local before = snapshot(g)
	variants(g, sv)
	check("variants over a FishSpawner without the harpoon guard: refused, names the line", refused() and snapshot(g) == before
		and (warnings[#warnings] or ""):find("first difference at line 85", 1, true) ~= nil)
end

------------------------------------------------------------ the whole guide (tools/INSTALL_GUIDE.md), in order

do
	local g, sv, history = astraPlace() -- a826d73 rod offers
	upgradeAq(g, sv) -- aquarium v1.2: what Studio has today
	local beforeSales = snapshot(g)
	local studioToday, studioAgain
	local steps = {
		{ "InstallSales", installSales, rollbackSales },
		{ "InstallMoneyHud", moneyHud, moneyHudBack },
		{ "InstallUpgrades", installUpg, rollbackUpg },
		{ "InstallEarnings", earnings, earningsBack },
		{ "InstallBotRecovery", botFix, botFixBack },
		{ "InstallFishJump", jumpInstall, jumpUninstall },
		{ "InstallRodCast", rodCast, rodCastBack },
		{ "InstallGrinderDwell", dwell, dwellBack },
		{ "InstallFishVariants", variants, variantsBack },
		{ "InstallMeatGlow", meatGlow, meatGlowBack },
		{ "InstallHarpoonBlend", blend, blendBack },
		{ "InstallJumpRate", jumpRate, jumpRateBack },
	}
	local states, allOk = {}, true
	for i, step in ipairs(steps) do
		states[i] = snapshot(g)
		if i == 2 then
			studioToday = states[i] -- InstallSales (91121de): installed and verified by Astra
		end
		local commits = history.commits
		step[2](g, sv)
		if refused() or history.commits ~= commits + 1 then
			allOk = false
			print_real("  guide order: " .. step[1] .. " refused: " .. tostring(warnings[#warnings]))
		end
	end
	check("guide order: all 12 install, one undo step each", allOk)
	local backOk = true
	for i = #steps, 1, -1 do
		if i == 1 then
			studioAgain = snapshot(g)
		end
		steps[i][3](g, sv)
		if refused() or snapshot(g) ~= states[i] then
			backOk = false
			print_real("  guide rollback: " .. steps[i][1] .. " rollback failed: " .. tostring(warnings[#warnings]))
		end
	end
	check("guide rollback in reverse: each step restores exactly the state before it", backOk)
	check("guide: rolling back 12..2 leaves exactly today's Studio (sales in)", studioAgain == studioToday)
	check("guide rollback: back to exactly rod offers + aquarium v1.2 (before sales)", snapshot(g) == beforeSales)
end

print_real(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then error("installer simulation failed") end
"""


def lua_string(text: str) -> str:
    level = 0
    while f"]{'=' * level}]" in text or f"[{'=' * level}[" in text or text.endswith("]"):
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


def main() -> int:
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    live = ROOT / "studio" / "live"
    prelude = PRELUDE.replace("__RFS__", lua_string((live / "RodFishingSystem.lua").read_text())).replace(
        "__SHOP__", lua_string((live / "RodShopServer.lua").read_text())
    )
    prelude = "local print_real = print\n" + prelude
    installer = (ROOT / "InstallRodOffers.lua").read_text()
    # the fresh installer and the rod-prompt update are frozen at the release Astra installed
    for frozen in ("InstallRodOffers.lua", "UninstallRodOffers.lua", "UpdateRodPrompt.lua", "RollbackRodPrompt.lua"):
        if (ROOT / frozen).read_text() != git_show(frozen, RELEASE_COMMIT):
            print(f"FAIL: {frozen} differs from the {RELEASE_COMMIT} release installed in Studio")
            return 1
    # the sales chain is frozen at the release Astra is installing; later
    # economy milestones ship their own installers on top
    for frozen in SALES_FROZEN:
        if (ROOT / frozen).read_text() != git_show(frozen, SALES_RELEASE):
            print(f"FAIL: {frozen} differs from the {SALES_RELEASE} sales release")
            return 1
    for frozen in RODS_FROZEN:
        if (ROOT / frozen).read_text() != git_show(frozen, RODS_RELEASE):
            print(f"FAIL: {frozen} differs from the {RODS_RELEASE} rods release")
            return 1
    for frozen in ("InstallJumpRate.lua", "RollbackJumpRate.lua"):
        if (ROOT.parent / "fish-jump" / frozen).read_text() != git_show(frozen, "1a19061", "tools/fish-jump/"):
            print(f"FAIL: fish-jump/{frozen} differs from the 1a19061 release")
            return 1
    for frozen in EARNINGS_FROZEN:
        if (ROOT / frozen).read_text() != git_show(frozen, EARNINGS_RELEASE):
            print(f"FAIL: {frozen} differs from the {EARNINGS_RELEASE} earnings release")
            return 1
    uninstaller = (ROOT / "UninstallRodOffers.lua").read_text()
    # the rod-offers install Astra has in Studio: the REAL 8cb2554 scripts
    old_installer = git_show("InstallRodOffers.lua")
    old_uninstaller = git_show("UninstallRodOffers.lua")
    old = {k: git_show(v) for k, v in SOURCES.items()}
    new = {k: git_show(v, RELEASE_COMMIT) for k, v in SOURCES.items()}
    tables = "local OLD = {\n" + "".join(f"\t{k} = {lua_string(v)},\n" for k, v in old.items()) + "}\n"
    tables += "local NEW = {\n" + "".join(f"\t{k} = {lua_string(v)},\n" for k, v in new.items()) + "}\n"
    # what InstallSales writes (the 91121de release)
    cur = {k: git_show(v, SALES_RELEASE) for k, v in SOURCES.items()}
    cur["Ledger"] = git_show("src/core/Ledger.luau", SALES_RELEASE)
    cur["PieceTags"] = git_show("src/core/PieceTags.luau", SALES_RELEASE)
    tables += "local CUR = {\n" + "".join(f"\t{k} = {lua_string(v)},\n" for k, v in cur.items()) + "}\n"
    live6 = {k: (live / f"{k}.lua").read_text() for k in SALES_LIVE}
    tables += "local LIVE6 = {\n" + "".join(f"\t{k} = {lua_string(v)},\n" for k, v in live6.items()) + "}\n"
    sales = {p.stem: p.read_text() for p in sorted((ROOT / "studio" / "sales").glob("*.lua"))}
    tables += "local SALES = {\n" + "".join(f"\t{k} = {lua_string(v)},\n" for k, v in sales.items()) + "}\n"
    aq = "tools/aquarium-cycle/src/"
    aqv1 = {n: git_show(f"shared/{n}.luau", AQUARIUM_V1, aq) for n in AQ_SHARED}
    tables += "local AQV1 = { shared = {\n" + "".join(f"\t{k} = {lua_string(v)},\n" for k, v in aqv1.items()) + "},\n"
    for n in ("AquariumCycleServer", "AquariumEconomy"):
        tables += f"\t{n} = {lua_string(git_show(f'server/{n}.luau', AQUARIUM_V1, aq))},\n"
    tables += f"\tAquariumTankClient = {lua_string(git_show('client/AquariumTankClient.client.luau', AQUARIUM_V1, aq))},\n}}\n"
    # what InstallEarnings writes (the 0829fc9 release, installed)
    tables += "local EARN = {\n" + "".join(
        f"\t{k} = {lua_string(git_show(v, EARNINGS_RELEASE))},\n" for k, v in (("EconomyService", "src/server/EconomyService.luau"), ("EconomyClient", "src/client/EconomyClient.client.luau"))
    ) + "}\n"
    tables += "local MONEYHUD = {\n" + "".join(
        f"\t{k} = {lua_string(v.read_text())},\n" for k, v in (("Live", live / "MoneyController.lua"), ("New", ROOT / "src" / "client" / "MoneyController.client.luau"))
    ) + "}\n"
    pn = ROOT.parent / "aquarium-panel"
    tables += "local PANEL = {\n" + "".join(
        f"\t{k} = {lua_string(v.read_text())},\n" for k, v in (("Server", pn / "studio" / "AquariumCycleServer.patched.from-v12.lua"), ("Client", pn / "src" / "AquariumPanelClient.client.luau"))
    ) + "}\n"
    tables += f"local RATE = {{ Module = {lua_string((ROOT.parent / 'fish-jump' / 'studio' / 'jump-rate' / 'FishJump.luau').read_text())} }}\n"
    # what InstallRods writes (the 61a7bd4 release, installed pending validation)
    rods_files = {
        "EconomyService": "src/server/EconomyService.luau",
        "Config": "src/core/Config.luau",
        "MoneyStore": "src/core/MoneyStore.luau",
        "Rods": "src/core/Rods.luau",
        "Shop": "studio/rods/RodShopServer.lua",
        "Fishing": "studio/rods/RodFishingSystem.lua",
    }
    tables += "local RODS = {\n" + "".join(f"\t{k} = {lua_string(git_show(v, RODS_RELEASE))},\n" for k, v in rods_files.items()) + "}\n"
    tables += "local SHOPUI = {\n" + "".join(
        f"\t{k} = {lua_string(git_show(v, RODS_RELEASE))},\n" for k, v in (("Live", "studio/live/RodShopController.lua"), ("New", "studio/rods/RodShopController.lua"))
    ) + "}\n"
    # the board upgrades on Astra's live baseline (GrinderUpgrades installed)
    live = ROOT / "studio" / "live"
    grinder = ROOT / "studio" / "grinder"
    tables += "local GLIVE = {\n" + "".join(f"\t{k} = {lua_string(v.read_text())},\n" for k, v in (
        ("EconomyService", live / "EconomyService.grinder.lua"),
        ("Server", live / "GrinderUpgradesServer.lua"),
        ("Client", live / "GrinderUpgradesClient.lua"),
        ("Config", live / "GrinderUpgradesConfig.lua"),
        ("NetLift", live / "NetLiftScript.grinder.lua"),
    )) + "}\n"
    # the installed board release's own board scripts, and the board-art update's
    tables += "local ART = {\n" + "".join(f"\t{k} = {lua_string(v)},\n" for k, v in (
        ("OldServer", git_show("src/server/UpgradeBoardServer.server.luau", "fffdaa3")),
        ("OldClient", git_show("src/client/UpgradeBoardClient.client.luau", "fffdaa3")),
        ("Server", (ROOT / "src/server/UpgradeBoardServer.server.luau").read_text()),
        ("Client", (ROOT / "src/client/UpgradeBoardClient.client.luau").read_text()),
    )) + "}\n"
    tables += "local SUITE = {\n" + "".join(f"\t{k} = {lua_string(v.read_text())},\n" for k, v in (
        ("EconomyService", ROOT / "src/server/EconomyService.luau"),
        ("Config", ROOT / "src/core/Config.luau"),
        ("MoneyStore", ROOT / "src/core/MoneyStore.luau"),
        ("Pricing", ROOT / "src/core/Pricing.luau"),
        ("Ledger", ROOT / "src/core/Ledger.luau"),
        ("Sales", ROOT / "src/core/Sales.luau"),
        ("NetKg", ROOT / "src/core/NetKg.luau"),
        ("BoardUpgrades", ROOT / "src/core/BoardUpgrades.luau"),
        ("NetCapacityServer", ROOT / "src/server/NetCapacityServer.server.luau"),
        ("KgSignClient", ROOT / "src/client/KgSignClient.client.luau"),
        ("Fishing", ROOT / "studio/board/RodFishingSystem.lua"),
        ("GServer", grinder / "GrinderUpgradesServer.lua"),
        ("GClient", grinder / "GrinderUpgradesClient.lua"),
        ("Customer", ROOT / "studio" / "board" / "CustomerSystem.lua"),
    )) + "}\n"
    tables += "SUITE.UpgradeBoardServer = ART.OldServer\nSUITE.UpgradeBoardClient = ART.OldClient\n"
    tables += f"local BOTFIX = {lua_string((ROOT / 'studio' / 'bot' / 'BotSystem.lua').read_text())}\n"
    tables += f"local UPG = {{ AquariumEconomy = {lua_string((ROOT / 'src/server/AquariumEconomy.luau').read_text())} }}\n"
    tables += f"local OLDCUSTOMER = {lua_string(git_show('studio/live/CustomerSystem.lua', 'd39b00b'))}\n"
    tables += "local RECON = {\n" + "".join(
        f"\t{n} = {lua_string(git_show(f'studio/live/{n}.lua', '58dcd56'))},\n" for n in ("CustomerSystem", "TruckSystem")
    ) + "}\n"
    vis = {
        "LiveFishSwimClient": (live / "FishSwimClient.lua").read_text(),
        "JumpPatched": (ROOT.parent / "fish-jump" / "studio" / "FishSwimClient.patched.lua").read_text(),
        "LiveRodFishingClient": (live / "RodFishingClient.lua").read_text(),
        "LiveFishSpawner": (live / "FishSpawner.lua").read_text(),
        "RodCastServer": (ROOT.parent / "rod-cast" / "studio" / "RodFishingSystem.patched.from-sales.lua").read_text(),
        "RodCastClient": (ROOT.parent / "rod-cast" / "studio" / "RodFishingClient.patched.lua").read_text(),
    }
    dw = ROOT.parent / "grinder-dwell"
    dwell = {
        "ClientLive": (dw / "studio" / "FishSwimClient.patched.from-live.lua").read_text(),
        "ClientJump": (dw / "studio" / "FishSwimClient.patched.from-jump.lua").read_text(),
        "RodSales": (dw / "studio" / "RodFishingSystem.patched.from-sales.lua").read_text(),
        "RodCast": (dw / "studio" / "RodFishingSystem.patched.from-rodcast.lua").read_text(),
        "Net": (dw / "studio" / "NetLiftScript.patched.from-sales.lua").read_text(),
        "Harpoon": (dw / "studio" / "HarpoonSystem.patched.from-sales.lua").read_text(),
        "Module": (dw / "src" / "GrinderDwell.luau").read_text(),
    }
    tables += "local DWELL = {\n" + "".join(f"\t{k} = {lua_string(v)},\n" for k, v in dwell.items()) + "}\n"
    ve = ROOT.parent / "fish-variants" / "studio" / "economy"
    var = {
        "Spawner": (ve / "FishSpawner.patched.from-live.lua").read_text(),
        "Grinder": (ve / "GrinderProcessor.patched.from-sales.lua").read_text(),
        **{f'["Rod_{k}"]': (ve / f"RodFishingSystem.patched.from-{k}.lua").read_text() for k in ("sales", "rodcast", "dwell-sales", "dwell-rodcast")},
    }
    tables += "local VAR = {\n" + "".join(f"\t{k} = {lua_string(v)},\n" for k, v in var.items()) + "}\n"
    mg = ROOT.parent / "fish-variants" / "studio" / "meat-glow"
    glow = {
        "Bot_sales": (mg / "BotSystem.patched.from-sales.lua").read_text(),
        "Bot_bot": (mg / "BotSystem.patched.from-bot.lua").read_text(),
        "Customer": (mg / "CustomerSystem.patched.from-sales.lua").read_text(),
        "Truck": (mg / "TruckSystem.patched.from-sales.lua").read_text(),
    }
    tables += "local GLOW = {\n" + "".join(f"\t{k} = {lua_string(v)},\n" for k, v in glow.items()) + "}\n"
    hb = ROOT.parent / "fish-jump" / "studio" / "harpoon-blend"
    tables += "local BLEND = {\n" + "".join(
        f"\t{k} = {lua_string((hb / f'FishSwimClient.patched.from-{v}.lua').read_text())},\n" for k, v in (("Jump", "jump"), ("Dwell", "dwell-jump"))
    ) + "}\n"
    tables += "local VIS = {\n" + "".join(f"\t{k} = {lua_string(v)},\n" for k, v in vis.items()) + "}\n"
    aqroot = ROOT.parent / "aquarium-cycle" / "src"
    tables += "local AQV12 = {\n"
    for n in ("Config", "SharedTank"):
        tables += f"\t{n} = {lua_string((aqroot / 'shared' / f'{n}.luau').read_text())},\n"
    tables += f"\tAquariumCycleServer = {lua_string((aqroot / 'server' / 'AquariumCycleServer.luau').read_text())},\n"
    tables += f"\tAquariumTankClient = {lua_string((aqroot / 'client' / 'AquariumTankClient.client.luau').read_text())},\n}}\n"
    source = (
        prelude
        + tables
        + wrap("runInstall", installer)
        + wrap("runUninstall", uninstaller)
        + wrap("runOldInstall", old_installer)
        + wrap("runOldUninstall", old_uninstaller)
        + wrap("runUpdate", (ROOT / "UpdateRodPrompt.lua").read_text())
        + wrap("runRollback", (ROOT / "RollbackRodPrompt.lua").read_text())
        + wrap("runUpgradeAq", (ROOT / "UpgradeAquariumV12.lua").read_text())
        + wrap("runRollbackAq", (ROOT / "RollbackAquariumV12.lua").read_text())
        + wrap("runInstallSales", (ROOT / "InstallSales.lua").read_text())
        + wrap("runRollbackSales", (ROOT / "RollbackSales.lua").read_text())
        + wrap("runInstallUpg", (ROOT / "InstallUpgrades.lua").read_text())
        + wrap("runJumpInstall", (ROOT.parent / "fish-jump" / "InstallFishJump.lua").read_text())
        + wrap("runRodCast", (ROOT.parent / "rod-cast" / "InstallRodCast.lua").read_text())
        + wrap("runDwell", (ROOT.parent / "grinder-dwell" / "InstallGrinderDwell.lua").read_text())
        + wrap("runVariants", (ROOT.parent / "fish-variants" / "InstallFishVariants.lua").read_text())
        + wrap("runVariantsBack", (ROOT.parent / "fish-variants" / "RollbackFishVariants.lua").read_text())
        + wrap("runDwellBack", (ROOT.parent / "grinder-dwell" / "RollbackGrinderDwell.lua").read_text())
        + wrap("runRodCastBack", (ROOT.parent / "rod-cast" / "RollbackRodCast.lua").read_text())
        + wrap("runJumpUninstall", (ROOT.parent / "fish-jump" / "UninstallFishJump.lua").read_text())
        + wrap("runRollbackUpg", (ROOT / "RollbackUpgrades.lua").read_text())
        + wrap("runEarnings", (ROOT / "InstallEarnings.lua").read_text())
        + wrap("runEarningsBack", (ROOT / "RollbackEarnings.lua").read_text())
        + wrap("runBotFix", (ROOT / "InstallBotRecovery.lua").read_text())
        + wrap("runBotFixBack", (ROOT / "RollbackBotRecovery.lua").read_text())
        + wrap("runMeatGlow", (ROOT.parent / "fish-variants" / "InstallMeatGlow.lua").read_text())
        + wrap("runMeatGlowBack", (ROOT.parent / "fish-variants" / "RollbackMeatGlow.lua").read_text())
        + wrap("runBlend", (ROOT.parent / "fish-jump" / "InstallHarpoonBlend.lua").read_text())
        + wrap("runBlendBack", (ROOT.parent / "fish-jump" / "RollbackHarpoonBlend.lua").read_text())
        + wrap("runMoneyHud", (ROOT / "InstallMoneyHud.lua").read_text())
        + wrap("runMoneyHudBack", (ROOT / "RollbackMoneyHud.lua").read_text())
        + wrap("runPanel", (ROOT.parent / "aquarium-panel" / "InstallAquariumPanel.lua").read_text())
        + wrap("runPanelBack", (ROOT.parent / "aquarium-panel" / "RollbackAquariumPanel.lua").read_text())
        + wrap("runJumpRate", (ROOT.parent / "fish-jump" / "InstallJumpRate.lua").read_text())
        + wrap("runJumpRateBack", (ROOT.parent / "fish-jump" / "RollbackJumpRate.lua").read_text())
        + wrap("runRods", (ROOT / "InstallRods.lua").read_text())
        + wrap("runRodsBack", (ROOT / "RollbackRods.lua").read_text())
        + wrap("runShopUi", (ROOT / "InstallRodShopUI.lua").read_text())
        + wrap("runShopUiBack", (ROOT / "RollbackRodShopUI.lua").read_text())
        + wrap("runSuite", (ROOT / "InstallBoardUpgrades.lua").read_text())
        + wrap("runSuiteBack", (ROOT / "RollbackBoardUpgrades.lua").read_text())
        + wrap("runArt", (ROOT / "InstallBoardArt.lua").read_text())
        + wrap("runArtBack", (ROOT / "RollbackBoardArt.lua").read_text())
        + TESTS
    )
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "installer_sim.luau"
        path.write_text(source)
        return subprocess.run([luau, str(path)]).returncode


if __name__ == "__main__":
    sys.exit(main())
