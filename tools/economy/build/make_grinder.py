#!/usr/bin/env python3
"""The GrinderUpgrades side of the upgrade-board integration.

Patches the LIVE GrinderUpgradesServer / GrinderUpgradesClient (exactly as
Astra sent them: studio/live/GrinderUpgrades*.lua) into studio/grinder/.
Changes, marked "Economy board":

GrinderUpgradesServer
  * the KG signs are no longer sold here: their ClickDetectors (and the
    PricePlate one it used to create) belong to NetCapacityServer, which
    sells the ONE saved net capacity (EconomyService netKg, money + kg in
    one write) that the upgrade board's Net Strength card sells too. No
    second handler, no second charge, no second progression.
  * its saved `kg` count (earlier KG buys) is REPORTED once per join to
    EconomyService.adoptLegacyNetKg, which adopts it as netKg = max(netKg,
    15 + 5 x kg): idempotent, never compounded. The count itself stays in
    GrinderUpgrades_v1 untouched (rollback keeps working).
  * NetKgBuys / NetMaxWeight are published by EconomyService now (from
    netKg, never from the live NetLift.MaxWeight): no compounding when
    NetCapacityServer raises that attribute.
  * conveyor / blade purchases (unchanged prices and effects):
      - fail closed in a LIVE server whose DataStore is unavailable: no
        memory store outside Studio (purchases would vanish on leave)
      - a record it can't read is never overwritten: buying is off for that
        player this session
      - JOURNALED (EconomyService.beginPurchase / finishPurchase): the debit
        and an open entry are saved in the Money record in one write before
        this store is touched; the upgrade is written HERE together with the
        purchase token (a short `applied` list); then the entry is settled
        (kept / refunded). An entry a shutdown, a slow write or a crash
        leaves open is settled at the player's next load by reading this
        store's tokens (the registered reader): delivered -> kept, else
        refunded. No purchase is paid-for-and-lost or delivered-for-free.
GrinderUpgradesClient
  * no longer writes the KG signs' PricePlate.PriceGui.Pill (KgSignClient
    is its only writer); conveyor / blade labels, ghost and blades are
    unchanged.

Usage:  python3 tools/economy/build/make_grinder.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIVE = ROOT / "studio" / "live"
OUT = ROOT / "studio" / "grinder"
SERVER_BASE = LIVE / "GrinderUpgradesServer.lua"
CLIENT_BASE = LIVE / "GrinderUpgradesClient.lua"
SERVER_OUT = OUT / "GrinderUpgradesServer.lua"
CLIENT_OUT = OUT / "GrinderUpgradesClient.lua"


class Patch:
    def __init__(self, src: str):
        self.src = src

    def rep(self, old: str, new: str) -> None:
        n = self.src.count(old)
        assert n == 1, f"expected 1 match, got {n}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


def server() -> str:
    p = Patch(SERVER_BASE.read_text())
    p.rep(
        "-- saved in DataStore \"GrinderUpgrades_v1\". Per player attributes:\n"
        "--   UpgradesLoaded (bool), OwnsConveyor (bool), BladeTier (1..9)\n",
        "-- saved in DataStore \"GrinderUpgrades_v1\". Per player attributes:\n"
        "--   UpgradesLoaded (bool), OwnsConveyor (bool), BladeTier (1..9)\n"
        "-- [Economy board] The KG signs are sold by NetCapacityServer now (the one\n"
        "-- saved net capacity, shared with the upgrade board): this script only\n"
        "-- reports its saved kg count once per join (EconomyService.adoptLegacyNetKg).\n"
        "-- Purchases are journaled in the Money record (EconomyService.beginPurchase):\n"
        "-- the upgrade is saved here WITH its purchase token, and a purchase left\n"
        "-- open by a shutdown / slow write / crash is settled at the next load from\n"
        "-- these tokens. No memory store outside Studio; records it can't read are\n"
        "-- never overwritten.\n",
    )
    p.rep(
        "\tif ok then ds = store else warn(\"[GrinderUpgrades] DataStore unavailable - using memory (Studio only)\") end\n",
        "\tif ok then\n"
        "\t\tds = store\n"
        "\telseif RunService:IsStudio() then\n"
        "\t\twarn(\"[GrinderUpgrades] DataStore unavailable - using memory (Studio only)\")\n"
        "\telse\n"
        "\t\t-- Economy board: never a memory store in a live server (purchases would vanish on leave)\n"
        "\t\tstoreOff = true\n"
        "\t\twarn(\"[GrinderUpgrades] DataStore unavailable - upgrades can't be loaded or bought on this server\")\n"
        "\tend\n",
    )
    p.rep("local ds\n", "local ds\nlocal storeOff = false -- Economy board: live server without its DataStore\n")
    p.rep(
        "local netLift = workspace:WaitForChild(\"NetLift\")\n"
        "local function baseKg()\n"
        "\treturn tonumber(netLift:GetAttribute(\"MaxWeight\")) or 15\n"
        "end\n",
        "",
    )
    p.rep(
        "\tp:SetAttribute(\"NetKgBuys\", d.kg)\n"
        "\tp:SetAttribute(\"NetMaxWeight\", Cfg.netMax(baseKg(), d.kg))\n",
        "\t-- Economy board: NetKgBuys / NetMaxWeight come from EconomyService (the saved netKg)\n",
    )
    p.rep(
        "local function clean(v)\n",
        "-- Economy board: a record whose fields this script can't read is kept as it\n"
        "-- is (never overwritten): buying is off for that player this session.\n"
        "local function whole(x, lo)\n"
        "\treturn type(x) == \"number\" and x == x and x == math.floor(x) and x >= lo\n"
        "end\n"
        "local function readable(v)\n"
        "\tif v == nil then return true end\n"
        "\treturn type(v) == \"table\" and (v.conveyor == nil or type(v.conveyor) == \"boolean\")\n"
        "\t\tand (v.blade == nil or whole(v.blade, 1)) and (v.kg == nil or whole(v.kg, 0))\n"
        "end\n"
        "\n"
        "local function clean(v)\n",
    )
    p.rep(
        "local function load(p)\n"
        "\tfor attempt = 1, 4 do\n",
        "local function load(p)\n"
        "\tif storeOff then return end -- Economy board: nothing to load from (and nothing is sold)\n"
        "\tfor attempt = 1, 4 do\n",
    )
    p.rep(
        "\t\tif ok then\n"
        "\t\t\tdata[p] = clean(res)\n"
        "\t\t\tpublish(p)\n"
        "\t\t\treturn\n"
        "\t\tend\n",
        "\t\tif ok then\n"
        "\t\t\tdata[p] = clean(res)\n"
        "\t\t\tif not readable(res) then\n"
        "\t\t\t\tdata[p].readOnly = true\n"
        "\t\t\t\twarn(\"[GrinderUpgrades] \" .. p.Name .. \"'s saved upgrades can't be read; kept as they are, buying is off\")\n"
        "\t\t\tend\n"
        "\t\t\tpublish(p)\n"
        "\t\t\t-- Economy board: earlier KG-sign buys become the saved net capacity (idempotent)\n"
        "\t\t\tif Economy and type(Economy.adoptLegacyNetKg) == \"function\" and readable(res) then\n"
        "\t\t\t\tEconomy.adoptLegacyNetKg(p, data[p].kg)\n"
        "\t\t\tend\n"
        "\t\t\treturn\n"
        "\t\tend\n",
    )
    p.rep(
        "-- Writes the new state; returns true only if it was saved.\n"
        "local function save(p, newState)\n"
        "\tlocal ok, err = pcall(update, p, function(old)\n"
        "\t\tlocal out = type(old) == \"table\" and table.clone(old) or {}\n"
        "\t\tout.conveyor = newState.conveyor\n"
        "\t\tout.blade = newState.blade\n"
        "\t\tout.kg = newState.kg\n"
        "\t\treturn out\n"
        "\tend)\n",
        "-- Writes the new state; returns true only if it was saved.\n"
        "-- Economy board: with `token`, the purchase token is written in the SAME\n"
        "-- update (the last APPLIED_KEEP of them, in `applied`): proof of delivery\n"
        "-- for a purchase whose Money entry is settled later.\n"
        "local APPLIED_KEEP = 20\n"
        "local function save(p, newState, token)\n"
        "\tlocal ok, err = pcall(update, p, function(old)\n"
        "\t\tlocal out = type(old) == \"table\" and table.clone(old) or {}\n"
        "\t\tout.conveyor = newState.conveyor\n"
        "\t\tout.blade = newState.blade\n"
        "\t\tout.kg = newState.kg\n"
        "\t\tif token then\n"
        "\t\t\tlocal applied = type(out.applied) == \"table\" and table.clone(out.applied) or {}\n"
        "\t\t\ttable.insert(applied, token)\n"
        "\t\t\twhile #applied > APPLIED_KEEP do table.remove(applied, 1) end\n"
        "\t\t\tout.applied = applied\n"
        "\t\tend\n"
        "\t\treturn out\n"
        "\tend)\n",
    )
    p.rep(
        "local function buy(p, price, what, apply)\n"
        "\tlocal d = data[p]\n"
        "\tif not Economy then return end\n"
        "\tif not d then Economy.notify(p, \"Loading your upgrades...\", \"error\") return end\n"
        "\tlocal paid, why = Economy.tryDebit(p, price, \"GrinderUpgrade:\" .. what)\n"
        "\tif not paid then\n"
        "\t\tEconomy.notify(p, REASON[why] or tostring(why), \"error\")\n"
        "\t\treturn\n"
        "\tend\n"
        "\tlocal nextState = table.clone(d)\n"
        "\tapply(nextState)\n"
        "\tlocal saved = save(p, nextState)\n"
        "\tif not p.Parent then return end\n"
        "\tif saved then\n"
        "\t\tdata[p] = nextState\n"
        "\t\tpublish(p)\n"
        "\t\tEconomy.notify(p, \"Bought \" .. what .. \"!\", \"success\")\n"
        "\telse\n"
        "\t\tEconomy.refund(p, price, \"GrinderUpgrade:\" .. what)\n"
        "\t\tEconomy.notify(p, \"Purchase failed, refunded\", \"error\")\n"
        "\tend\n"
        "end\n",
        "local function buy(p, price, what, apply)\n"
        "\tlocal d = data[p]\n"
        "\tif not Economy then return end\n"
        "\tif storeOff then Economy.notify(p, \"Grinder upgrades are unavailable on this server\", \"error\") return end\n"
        "\tif not d then Economy.notify(p, \"Loading your upgrades...\", \"error\") return end\n"
        "\tif d.readOnly then Economy.notify(p, \"Your saved grinder upgrades couldn't be read - buying is off this session\", \"error\") return end\n"
        "\tif type(Economy.beginPurchase) ~= \"function\" then Economy.notify(p, \"Grinder upgrades are unavailable right now\", \"error\") return end\n"
        "\t-- Economy board: debit + open entry saved in the Money record first (one write)\n"
        "\tlocal token, why = Economy.beginPurchase(p, SOURCE, price, what)\n"
        "\tif not token then\n"
        "\t\tEconomy.notify(p, REASON[why] or \"Couldn't buy that right now - you were not charged\", \"error\")\n"
        "\t\treturn\n"
        "\tend\n"
        "\tlocal nextState = table.clone(d)\n"
        "\tapply(nextState)\n"
        "\tlocal delivered = save(p, nextState, token) -- the upgrade and its token, one write\n"
        "\tif not delivered then\n"
        "\t\t-- a write can error after it landed: read back whether the token is here\n"
        "\t\tlocal ok, rec = pcall(function()\n"
        "\t\t\tif ds and p.UserId > 0 then return ds:GetAsync(key(p)) end\n"
        "\t\t\treturn mem[key(p)]\n"
        "\t\tend)\n"
        "\t\tif ok then\n"
        "\t\t\tdelivered = type(rec) == \"table\" and type(rec.applied) == \"table\" and table.find(rec.applied, token) ~= nil\n"
        "\t\telse\n"
        "\t\t\tdelivered = nil -- can't tell: the open entry is settled from this store later\n"
        "\t\tend\n"
        "\tend\n"
        "\tEconomy.finishPurchase(p, token, delivered) -- kept / refunded / settled later\n"
        "\tif delivered == true then\n"
        "\t\tif p.Parent then\n"
        "\t\t\tdata[p] = nextState\n"
        "\t\t\tpublish(p)\n"
        "\t\t\tEconomy.notify(p, \"Bought \" .. what .. \"!\", \"success\")\n"
        "\t\tend\n"
        "\telseif delivered == false then\n"
        "\t\tif p.Parent then Economy.notify(p, \"Purchase failed, refunded\", \"error\") end\n"
        "\telseif p.Parent then\n"
        "\t\tEconomy.notify(p, \"Checking your purchase - it will be kept or refunded shortly\", \"info\")\n"
        "\tend\n"
        "end\n",
    )
    p.rep(
        "local function onKgSign(p)\n"
        "\tlocal d = data[p]\n"
        "\tif not d then return end\n"
        "\tlocal price = Cfg.kgPrice(d.kg)\n"
        "\tbuy(p, price, \"+\" .. Cfg.Kg.Step .. \" KG\", function(s) s.kg = d.kg + 1 end)\n"
        "end\n"
        "\n",
        "",
    )
    p.rep(
        "-- KG signs: click / tap the board (ClickDetector) or its price plate\n"
        "local lastKg = {}\n"
        "local function kgClicked(p)\n"
        "\tif busy[p] then return end\n"
        "\tlocal now = os.clock()\n"
        "\tif lastKg[p] and now - lastKg[p] < 0.4 then return end\n"
        "\tlastKg[p] = now\n"
        "\tbusy[p] = true\n"
        "\tlocal ok, err = pcall(onKgSign, p)\n"
        "\tbusy[p] = nil\n"
        "\tif not ok then warn(\"[GrinderUpgrades] \" .. tostring(err)) end\n"
        "end\n"
        "for _, sign in ipairs(CollectionService:GetTagged(\"KgSign\")) do\n"
        "\tfor _, d in ipairs(sign:GetDescendants()) do\n"
        "\t\tif d:IsA(\"ClickDetector\") then\n"
        "\t\t\td.MaxActivationDistance = 24\n"
        "\t\t\td.MouseClick:Connect(kgClicked)\n"
        "\t\tend\n"
        "\tend\n"
        "\tlocal plate = sign:FindFirstChild(\"PricePlate\")\n"
        "\tif plate and not plate:FindFirstChildOfClass(\"ClickDetector\") then\n"
        "\t\tlocal cd = Instance.new(\"ClickDetector\")\n"
        "\t\tcd.MaxActivationDistance = 24\n"
        "\t\tcd.Parent = plate\n"
        "\t\tcd.MouseClick:Connect(kgClicked)\n"
        "\tend\n"
        "end\n"
        "netLift:GetAttributeChangedSignal(\"MaxWeight\"):Connect(function()\n"
        "\tfor p in pairs(data) do publish(p) end\n"
        "end)\n",
        "-- Economy board: the KG signs (board + price plate) are NetCapacityServer's\n",
    )
    p.rep("\tlastKg[p] = nil\n", "")
    # the purchase journal: this store's tokens, for settling open entries
    p.rep(
        "------------------------------------------------------------ players\n",
        "-- Economy board: how EconomyService reads this store's purchase tokens\n"
        "-- (to settle a Money entry left open by a shutdown / slow write / crash)\n"
        "if Economy and type(Economy.registerPurchaseSource) == \"function\" and not storeOff then\n"
        "\tEconomy.registerPurchaseSource(SOURCE, function(userId)\n"
        "\t\tlocal ok, rec = pcall(function()\n"
        "\t\t\tif ds and userId > 0 then return ds:GetAsync(\"player_\" .. userId) end\n"
        "\t\t\treturn mem[\"player_\" .. userId]\n"
        "\t\tend)\n"
        "\t\tif not ok then return nil end\n"
        "\t\tlocal set = {}\n"
        "\t\tif type(rec) == \"table\" and type(rec.applied) == \"table\" then\n"
        "\t\t\tfor _, t in ipairs(rec.applied) do\n"
        "\t\t\t\tif type(t) == \"string\" then set[t] = true end\n"
        "\t\t\tend\n"
        "\t\tend\n"
        "\t\treturn set\n"
        "\tend)\n"
        "end\n"
        "\n"
        "------------------------------------------------------------ players\n",
    )
    p.rep(
        "local REASON = { funds = \"Not enough Money!\", notLoaded = \"Money still loading...\" }\n",
        "local REASON = { funds = \"Not enough Money!\", notLoaded = \"Money still loading...\" }\n"
        "-- Economy board: the journal's name for this store's purchases\n"
        "local SOURCE = \"GrinderUpgrades\"\n"
        "REASON.unsettled = \"Finishing your last purchase - try again in a moment\"\n"
        "REASON.busy = \"One moment - still saving\"\n"
        "REASON.notSaved = \"Couldn't save the purchase - you were not charged. Try again.\"\n",
    )
    src = p.src
    # nothing of the old KG path is left, nothing reads the live MaxWeight
    for gone in ("onKgSign", "kgClicked", "kgPrice", "baseKg", "NetMaxWeight\", Cfg", "netLift", "MouseClick"):
        assert gone not in src, gone
    # the conveyor / blade paths are still there
    for kept in ("onConveyorPad", "onBladePad", "hookPad(pad, onConveyorPad)", "hookPad(pad, onBladePad)", "out.kg = newState.kg"):
        assert kept in src, kept
    # every purchase goes through the journal; no direct debit / refund is left
    assert "Economy.tryDebit" not in src and "Economy.refund" not in src and "holdSave" not in src
    assert src.index("local SOURCE = ") < src.index("local function buy(") < src.index("registerPurchaseSource")
    return src


def client() -> str:
    p = Patch(CLIENT_BASE.read_text())
    start = p.src.index("\t-- KG signs: price + your net before/after\n")
    end = p.src.index("\tlocal _, tier = Cfg.blade(player:GetAttribute(\"BladeTier\") or 1)\n\tlabel(\"BladePad\"")
    block = p.src[start:end]
    assert "pill.Info.Text" in block and block.count("\tend\n") >= 3
    p.rep(block, "\t-- Economy board: the KG signs' price plates are KgSignClient's (the one saved net capacity)\n")
    src = p.src
    assert "Pill" not in src and "NetKgBuys" not in src and "kgPrice" not in src
    for kept in ("refreshConveyor", "refreshBlade", "label(\"ConveyorPad\"", "label(\"BladePad\"", "task.wait(0.25)"):
        assert kept in src, kept
    return src


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    SERVER_OUT.write_text(server())
    CLIENT_OUT.write_text(client())
    print(f"wrote {SERVER_OUT.relative_to(ROOT.parent.parent)} + {CLIENT_OUT.name}")


if __name__ == "__main__":
    main()
