#!/usr/bin/env python3
"""Dry-runs the REAL InstallRodOffers.lua / UninstallRodOffers.lua under the
Luau CLI against a tiny fake Studio DataModel (Instances with Name, Parent,
Source, attributes, Clone/Destroy; a ChangeHistoryService stub).

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
function Inst:IsA(c) return self.ClassName == c or (CLASS_ISA[self.ClassName] or {})[c] == true end
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
	for _, n in ipairs({ "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer", "Workspace" }) do
		local s = new(n, n) s.Parent = game services[n] = s
	end
	new("StarterPlayerScripts", "StarterPlayerScripts").Parent = services.StarterPlayer
	local history = { commits = 0 }
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


def wrap(name: str, src: str) -> str:
    return f"local function {name}(game, workspace)\n{src}\nend\n"


TESTS = r"""
local function install(game, s) warnings = {} runInstall(game, s.Workspace) end
local function uninstall(game, s) warnings = {} runUninstall(game, s.Workspace) end

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
    uninstaller = (ROOT / "UninstallRodOffers.lua").read_text()
    source = prelude + wrap("runInstall", installer) + wrap("runUninstall", uninstaller) + TESTS
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "installer_sim.luau"
        path.write_text(source)
        return subprocess.run([luau, str(path)]).returncode


if __name__ == "__main__":
    sys.exit(main())
