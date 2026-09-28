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
    uninstaller = (ROOT / "UninstallRodOffers.lua").read_text()
    # the rod-offers install Astra has in Studio: the REAL 8cb2554 scripts
    old_installer = git_show("InstallRodOffers.lua")
    old_uninstaller = git_show("UninstallRodOffers.lua")
    old = {k: git_show(v) for k, v in SOURCES.items()}
    new = {k: git_show(v, RELEASE_COMMIT) for k, v in SOURCES.items()}
    tables = "local OLD = {\n" + "".join(f"\t{k} = {lua_string(v)},\n" for k, v in old.items()) + "}\n"
    tables += "local NEW = {\n" + "".join(f"\t{k} = {lua_string(v)},\n" for k, v in new.items()) + "}\n"
    cur = {k: (ROOT / v).read_text() for k, v in SOURCES.items()}
    cur["Ledger"] = (ROOT / "src/core/Ledger.luau").read_text()
    cur["PieceTags"] = (ROOT / "src/core/PieceTags.luau").read_text()
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
        + TESTS
    )
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "installer_sim.luau"
        path.write_text(source)
        return subprocess.run([luau, str(path)]).returncode


if __name__ == "__main__":
    sys.exit(main())
