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
--   * reads are AUTHORITATIVE: the fake DataStore caches GetAsync like Roblox
--     (a write that landed but errored leaves the old record in the cache);
--     the read-back and the settling reader bypass it (UseCache = false)
--   * a purchase delivered later is OWNED here once settled (BladeTier, the
--     next price), and a later purchase never writes a stale copy back
--     (compare-and-set on the stored record); conveyor too

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
local CPAD = Vector3.new(-70, 8, 170)
local cpad = new("Model", "ConveyorPad")
local ctouch = part("TouchPart", CPAD, cpad, Vector3.new(4, 1, 4))
cpad.Parent = ws
addTag(cpad, "ConveyorPad")
current = nil

local G = {}
dsOther.GrinderUpgrades_v1 = G
for id = 1, 9 do
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
local function buyConveyor(p)
	moveTo(p, CPAD + Vector3.new(0, 2, 0))
	asServer(function()
		ctouch.Touched:Fire(p.Character.HumanoidRootPart)
	end)
end
local function rec(id)
	return dsData[KEY .. id]
end
-- a plain (cached) GetAsync of the grinder store, like any script on this server
local grinderStore = services.DataStoreService:GetDataStore("GrinderUpgrades_v1")
local function cachedBlade(id)
	local r = grinderStore:GetAsync("player_" .. id)
	return type(r) == "table" and r.blade or nil
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
check("(the cache holds the record from before: blade 1)", cachedBlade(4) == 1)
mode["player_4"] = { failAfter = true }
buyBlade(P4)
advance(1)
mode["player_4"] = nil
check("a plain cached read right after still says blade 1 (the write landed, its answer was lost)",
	cachedBlade(4) == 1 and G["player_4"].blade == 2)
advance(1)
check("write landed but errored: read back AUTHORITATIVELY -> kept, not refunded", Economy.balance(P4) == 16000 and G["player_4"].blade == 2
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
check("... and the grinder's own copy follows: BladeTier 2 (owned here, not just in the store)",
	P5:GetAttribute("BladeTier") == 2)
advance(2)
buyBlade(P5)
advance(2)
check("next blade press: Rare for 15000 (not Uncommon again for 4000)", Economy.balance(P5) == 1000
	and G["player_5"].blade == 3 and P5:GetAttribute("BladeTier") == 3 and lastNotice(P5) == "Bought Rare Blade!")
runAs("server", function()
	Economy.credit(P5, 5000, "test")
end)
advance(2)
buyConveyor(P5)
advance(2)
check("then the conveyor: bought, and the stored blade is kept (3, never a stale 1 or 2)",
	G["player_5"].conveyor == true and G["player_5"].blade == 3 and P5:GetAttribute("OwnsConveyor") == true
	and P5:GetAttribute("BladeTier") == 3 and Economy.balance(P5) == 2000)

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

------------------------------------------------------------ 7) conveyor: outcome unknown, delivered -> owned once settled

local P7 = join(7, "ConvUnknown", AWAY)
advance(2)
mode["player_7"] = { failAfter = true }
readFails["player_7"] = true
buyConveyor(P7)
advance(2)
mode["player_7"] = nil
check("conveyor, can't tell: charged, entry open, not owned here yet", Economy.balance(P7) == 16000 and openCount(7) == 1
	and P7:GetAttribute("OwnsConveyor") == false)
buyConveyor(P7)
advance(2)
check("pressing again meanwhile: refused (last purchase unsettled), not charged twice", Economy.balance(P7) == 16000
	and lastNotice(P7) == "Finishing your last purchase - try again in a moment")
readFails["player_7"] = nil
advance(SETTLE + 5)
check("settled from the store: kept, OwnsConveyor true, blade untouched", Economy.balance(P7) == 16000 and openCount(7) == 0
	and P7:GetAttribute("OwnsConveyor") == true and G["player_7"].conveyor == true and G["player_7"].blade == 1)
local notices7 = lastNotice(P7)
buyConveyor(P7)
advance(2)
check("the conveyor pad now does nothing (owned): not charged again", Economy.balance(P7) == 16000 and lastNotice(P7) == notices7)
buyBlade(P7)
advance(2)
check("a blade after it keeps the conveyor in the store", G["player_7"].conveyor == true and G["player_7"].blade == 2
	and Economy.balance(P7) == 12000)

------------------------------------------------------------ 8) the store moved on (another server): nothing written, refunded, refreshed

local P8 = join(8, "Stale", AWAY)
advance(2)
G["player_8"] = { blade = 3, conveyor = true, kg = 2, other = "kept" } -- written elsewhere since this server loaded
buyBlade(P8) -- this server still thinks blade 1: priced as Uncommon
advance(2)
check("stale copy: compare-and-set refuses, nothing written (blade 3, conveyor, kg, unknown field kept)",
	G["player_8"].blade == 3 and G["player_8"].conveyor == true and G["player_8"].kg == 2 and G["player_8"].other == "kept"
	and G["player_8"].applied == nil)
check("... refunded (20000), entry closed, told why", Economy.balance(P8) == 20000 and openCount(8) == 0
	and lastNotice(P8) == "Your upgrades had already changed - refreshed, you were refunded")
check("... and this server's copy follows the store: BladeTier 3, OwnsConveyor", P8:GetAttribute("BladeTier") == 3
	and P8:GetAttribute("OwnsConveyor") == true)
advance(2)
buyBlade(P8)
advance(2)
check("the next press buys the real next tier (Epic, 50000 > 20000: not enough money, not charged)",
	Economy.balance(P8) == 20000 and lastNotice(P8) == "Not enough Money!")

------------------------------------------------------------ 9) a refresh that fails keeps the entry open (buying stays blocked)

local P9 = join(9, "RefreshFails", AWAY)
advance(2)
mode["player_9"] = { failAfter = true }
readFails["player_9"] = true
buyBlade(P9)
advance(2)
mode["player_9"], readFails["player_9"] = nil, nil
G["player_9"].blade = "broken" -- the record is unreadable when it is settled
advance(SETTLE + 5)
check("unreadable record at settling: the token is there -> kept; buying off for that player (never overwritten)",
	Economy.balance(P9) == 16000 and openCount(9) == 0 and G["player_9"].blade == "broken")
buyBlade(P9)
advance(2)
check("... the pad refuses (read-only), nothing charged, the record untouched", Economy.balance(P9) == 16000
	and G["player_9"].blade == "broken")

------------------------------------------------------------ 10) a source whose refresh fails: the entry stays open until it works

dsData[KEY .. 10] = { v = 2, money = 100 }
local P10 = join(10, "RefreshErr", AWAY)
advance(2)
local held = {}
local refreshOk = false
local refreshed = 0
runAs("server", function()
	Economy.registerPurchaseSource("TestSource", function()
		return held, { note = "record" }
	end, function(_, record)
		refreshed += 1
		if not refreshOk then
			error("refresh broke (fake)")
		end
		return record.note == "record"
	end)
end)
local token10
runAs("server", function()
	token10 = Economy.beginPurchase(P10, "TestSource", 40, "Test Thing")
end)
advance(1)
check("test source: charged 40, entry open", token10 ~= nil and Economy.balance(P10) == 60 and openCount(10) == 1)
if token10 then held[token10] = true end -- delivered in its store
runAs("server", function()
	Economy.finishPurchase(P10, token10, nil) -- can't tell yet
end)
advance(SETTLE + 5)
check("its refresh errors: NOT settled (entry open, buying stays blocked), tried", openCount(10) == 1 and refreshed >= 1
	and Economy.balance(P10) == 60)
local blocked
runAs("server", function()
	local t, why = Economy.beginPurchase(P10, "TestSource", 10, "Other")
	blocked = t == nil and why == "unsettled"
end)
check("... a new purchase meanwhile: refused as unsettled", blocked)
refreshOk = true
advance(40)
check("refresh works again: settled as delivered (60 kept), entry gone", openCount(10) == 0 and Economy.balance(P10) == 60)

finish("journal sim")
