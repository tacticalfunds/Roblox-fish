-- Journaled grinder purchases (EconomyService.beginPurchase / finishPurchase,
-- the Money record's pendingPurchases, the grinder store's `applied` tokens)
-- through the REAL EconomyService and the PATCHED GrinderUpgradesServer:
--   * shutdown (BindToClose) while a slow grinder write FAILS: the Money is
--     saved with the debit AND the open entry (never "debited, entry gone");
--     at the next load the entry is settled from the grinder store: token
--     absent -> refunded exactly once (Astra's case: 20000 -4000 -> 20000)
--   * shutdown while a slow write SUCCEEDS: kept at the next load, no refund
--   * a write slower than the leave wait (>20 s) that fails: the final save
--     keeps the entry; refunded at the next load
--   * a write that LANDS then errors: read back, kept (not refunded)
--   * a write whose outcome can't be read back: left open, settled from the
--     store once readable
--   * a young entry (maybe still being written by another server) waits for
--     PurchaseSettleSeconds before it is settled

local Economy, root = installEconomy()
Economy.Config.NetKgLegacy = false -- not what this sim is about
local RS = services.ReplicatedStorage
local SSS = services.ServerScriptService
local ws = workspaceInst
local KEY = Economy.Config.KeyPrefix
local PAD = Vector3.new(-60, 8, 170)
local AWAY = Vector3.new(300, 8, 300)
local SETTLE = Economy.Config.PurchaseSettleSeconds

current = "server"
script("ModuleScript", "GrinderUpgradesConfig", SOURCES.Grinder_Config, RS)
local netLift = new("Model", "NetLift")
netLift:SetAttribute("MaxWeight", 15)
netLift.Parent = ws
local pad = new("Model", "BladePad")
local touch = part("TouchPart", PAD, pad, Vector3.new(4, 1, 4))
pad.Parent = ws
addTag(pad, "BladePad")
current = nil

local G = {}
dsOther.GrinderUpgrades_v1 = G
for id = 1, 6 do
	dsData[KEY .. id] = { v = 2, money = 20000 }
	G["player_" .. id] = { blade = 1 }
end
-- per player: how their grinder writes behave
local mode = {} -- key -> { delay, fail = bool, failAfter = bool }
dsHooks.before = function(key, store)
	local m = store == "GrinderUpgrades_v1" and mode[key]
	if m then
		if m.delay then
			task.wait(m.delay)
		end
		if m.fail then
			error("DataStore request failed (fake)")
		end
	end
end
dsHooks.after = function(key, store)
	local m = store == "GrinderUpgrades_v1" and mode[key]
	if m and m.failAfter then
		error("DataStore answer lost (fake): the write landed")
	end
end
local readFails = {}
dsHooks.get = function(key, store)
	if store == "GrinderUpgrades_v1" and readFails[key] then
		error("DataStore read failed (fake)")
	end
end

runScript(script("Script", "GrinderUpgradesServer", SOURCES.Grinder_Server, SSS))
local function buyBlade(p)
	moveTo(p, PAD + Vector3.new(0, 2, 0))
	asServer(function()
		touch.Touched:Fire(p.Character.HumanoidRootPart)
	end)
end
local function rec(id)
	return dsData[KEY .. id]
end
local function openCount(id)
	local n = 0
	for _ in pairs(rec(id).pendingPurchases or {}) do
		n += 1
	end
	return n
end

------------------------------------------------------------ 1+2) shutdown during slow writes (one fails, one succeeds)

local P1 = join(1, "ShutFail", AWAY)
local P2 = join(2, "ShutOk", AWAY + Vector3.new(5, 0, 0))
advance(2)
mode["player_1"] = { delay = 40, fail = true }
mode["player_2"] = { delay = 40 }
buyBlade(P1)
buyBlade(P2)
advance(1)
check("both purchases journaled first: debit + open entry saved in one write", rec(1).money == 16000 and openCount(1) == 1
	and rec(2).money == 16000 and openCount(2) == 1)
-- the server shuts down now (BindToClose), long before the writes answer
for _, fn in ipairs(closers) do
	runAs("server", fn)
end
advance(25)
check("shutdown: the Money is saved with the debit AND the open entry (nothing silently lost)",
	rec(1).money == 16000 and openCount(1) == 1 and rec(1).lock == nil and rec(2).money == 16000 and openCount(2) == 1)
leave(P1)
leave(P2)
advance(20) -- the writes answer now: P1's failed, P2's landed
mode["player_1"], mode["player_2"] = nil, nil
check("after the shutdown the entries are still there (nobody to settle them now)", openCount(1) == 1 and openCount(2) == 1
	and G["player_2"].blade == 2 and G["player_1"].blade == 1)
-- next session (a new server): the entries are settled from the grinder store
P1 = join(1, "ShutFail", AWAY)
P2 = join(2, "ShutOk", AWAY + Vector3.new(5, 0, 0))
advance(2)
check("a young entry waits (another server's write could still land)", Economy.balance(P1) == 16000 and openCount(1) == 1)
advance(SETTLE)
check("failed write: refunded at the next load (20000 again), entry gone, saved", Economy.balance(P1) == 20000 and rec(1).money == 20000
	and openCount(1) == 0)
check("the refund says so", lastNotice(P1) and lastNotice(P1):find("refunded 4000", 1, true) ~= nil)
check("landed write: kept (16000, Uncommon), entry gone", Economy.balance(P2) == 16000 and rec(2).money == 16000 and openCount(2) == 0
	and P2:GetAttribute("BladeTier") == 2)
leave(P1)
advance(2)
P1 = join(1, "ShutFail", AWAY)
advance(SETTLE + 5)
check("settled exactly once: another join changes nothing", Economy.balance(P1) == 20000 and rec(1).money == 20000)

------------------------------------------------------------ 3) leaving during a >20 s failing write (no shutdown)

local P3 = join(3, "SlowFail", AWAY)
advance(2)
mode["player_3"] = { delay = 40, fail = true }
buyBlade(P3)
advance(1)
leave(P3)
advance(25) -- the leave waits 20 s, then saves the Money with the entry
check("final save after the wait: debit + open entry, never debit alone", rec(3).money == 16000 and openCount(3) == 1)
advance(20)
mode["player_3"] = nil
P3 = join(3, "SlowFail", AWAY)
advance(SETTLE + 2)
check("next load: refunded (20000), entry gone", Economy.balance(P3) == 20000 and rec(3).money == 20000 and openCount(3) == 0)

------------------------------------------------------------ 4) a write that lands, then errors

local P4 = join(4, "Landed", AWAY)
advance(2)
mode["player_4"] = { failAfter = true }
buyBlade(P4)
advance(2)
mode["player_4"] = nil
check("write landed but errored: read back -> kept, not refunded", Economy.balance(P4) == 16000 and G["player_4"].blade == 2
	and P4:GetAttribute("BladeTier") == 2 and lastNotice(P4) == "Bought Uncommon Blade!")
advance(2)
check("... and the entry is settled and saved", openCount(4) == 0 and rec(4).money == 16000)

------------------------------------------------------------ 5) outcome unknown (write errored, read-back fails too)

local P5 = join(5, "Unknown", AWAY)
advance(2)
mode["player_5"] = { failAfter = true }
readFails["player_5"] = true
buyBlade(P5)
advance(2)
mode["player_5"] = nil
check("can't tell: neither refunded nor kept yet, the entry stays open", Economy.balance(P5) == 16000 and openCount(5) == 1
	and lastNotice(P5) == "Checking your purchase - it will be kept or refunded shortly")
readFails["player_5"] = nil
advance(SETTLE + 5)
check("once readable: the token is there -> kept, entry gone", Economy.balance(P5) == 16000 and openCount(5) == 0
	and G["player_5"].blade == 2)

------------------------------------------------------------ 6) a normal failing write still refunds at once

local P6 = join(6, "Normal", AWAY)
advance(2)
mode["player_6"] = { fail = true }
buyBlade(P6)
advance(2)
mode["player_6"] = nil
check("ordinary failed write: refunded at once, entry gone", Economy.balance(P6) == 20000 and lastNotice(P6) == "Purchase failed, refunded")
advance(2)
check("... saved: 20000, no entry", rec(6).money == 20000 and openCount(6) == 0)

finish("journal sim")
