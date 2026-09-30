#!/usr/bin/env python3
"""Generates the guarded update installers (and their rollbacks) that build
on what is installed in Studio, from build/SourceUpdate.template.lua and
build/Rollback.template.lua:

  UpgradeAquariumV12.lua / RollbackAquariumV12.lua
      aquarium v1 (commit 2e320f9, installed) -> v1.2: carries OwnerId (and
      Variant) rod -> tank -> river; the river-release despawn leaves
      harpooned fish alone.
  InstallSales.lua / RollbackSales.lua
      sale payouts: the grinder issues ledger pieces, bots / customers /
      trucks settle them once, net / harpoon send the owner, a bought rod
      fish carries its buyer. Needs rod offers (a826d73: fresh install, or
      8cb2554 + UpdateRodPrompt - both leave the same sources) and aquarium
      v1.2.
  InstallEarnings.lua / RollbackEarnings.lua, InstallBotRecovery.lua /
  RollbackBotRecovery.lua, InstallMoneyHud.lua / RollbackMoneyHud.lua
      later economy milestones, each on top of what is installed.

Every "old" source comes from git at the installed commit, so the checks
match exactly what the earlier installers wrote.

Usage:  python3 tools/economy/build/build_updates.py
"""
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import build_rod_offers_installer as bi  # noqa: E402
import make_bot  # noqa: E402
import make_sales  # noqa: E402

ROOT = bi.ROOT
REPO = ROOT.parent.parent
AQUARIUM_V1 = "2e320f9"
ROD_OFFERS = "a826d73"
# InstallSales / InstallUpgrades as released for Astra's install (91121de):
# the economy sources they write are read from that commit, so later
# economy milestones (built on top, with their own installers) don't change
# them.
SALES_RELEASE = "91121de"
AQ_SHARED = ["Adapters", "Config", "CycleState", "Messages", "RiverRelease", "SharedTank", "TankPath", "Upgrades"]
# (InstallSales.lua is released as of d39b00b: its lists stay as they are;
# later installs still can't be skipped - they change scripts it checks.)
LATER_THAN_SALES = ["EconomyUpgradesBackup"]
LATER_THAN_UPGRADES = ["EconomyVariantsBackup"]
# InstallEarnings as installed by Astra (0829fc9): its sources are read from
# that commit, so later milestones (rods, ...) don't change the release.
EARNINGS_RELEASE = "0829fc9"
# economy milestones after the sales release (each its own installer)
LATER_THAN_EARNINGS: list[str] = []
LATER_THAN_BOT = ["EconomyMeatGlowBackup"]
LATER_THAN_RODS = ["EconomyRodShopUIBackup"]  # the shop UI reads what InstallRods publishes
# InstallRods + InstallRodShopUI as installed by Astra (pending validation)
RODS_RELEASE = "61a7bd4"  # tools/fish-variants InstallMeatGlow patches BotSystem too
# InstallNetKg as released for Astra (187fe39): frozen; the upgrade board
# builds on the sources it writes, read from that commit.
NETKG_RELEASE = "187fe39"


def git_show(commit: str, path: str) -> str:
    return subprocess.run(["git", "show", f"{commit}:{path}"], cwd=REPO, capture_output=True, text=True, check=True).stdout


def lua(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"' + v + '"'
    if isinstance(v, list):
        return "{ " + ", ".join(lua(x) for x in v) + " }"
    raise TypeError(v)


def target(t: dict, old: str, new: str) -> tuple[str, bool]:
    """Returns (lua table text, changed?)."""
    fields = [f'key = "{t["key"]}"', f'where = "{t["where"]}"', f'class = "{t["class"]}"']
    if t.get("tag"):
        fields.append(f'tag = "{t["tag"]}"')
    if t.get("tagOnParent"):
        fields.append("tagOnParent = true")
    if old == new:
        return "\t{ " + ", ".join(fields) + f", source = {bi.long_string(old)} }},", False
    return "\t{ " + ", ".join(fields) + f", old = {bi.long_string(old)}, new = {bi.long_string(new)} }},", True


def fill(template: str, values: dict) -> str:
    for marker, value in values.items():
        assert marker in template, marker
        template = template.replace(marker, value)
    assert "--[[@" not in template, "unfilled marker"
    return template


def write_pair(file: str, rollback: str, about: str, backup: str, requires, forbids, later, targets, out_dir: pathlib.Path | None = None) -> list[str]:
    out_dir = out_dir or ROOT
    changes, unchanged, changed_keys = [], [], []
    for t, old, new in targets:
        text, changed = target(t, old, new)
        (changes if changed else unchanged).append(text)
        if changed:
            changed_keys.append(t["key"])
    name = file.removesuffix(".lua")
    rb_name = rollback.removesuffix(".lua")
    install = fill(
        (ROOT / "build" / "SourceUpdate.template.lua").read_text(),
        {
            "--[[@FILE]]": file,
            "--[[@ABOUT]]": "\n".join("\t" + line if line else "" for line in about.strip("\n").split("\n")),
            "--[[@BACKUP]]": backup,
            "--[[@ROLLBACK]]": rollback,
            "--[[@NAME]]": name,
            "--[[@REQUIRES]]": "{ " + ", ".join(lua(r) for r in requires) + " }",
            "--[[@FORBIDS]]": lua(forbids),
            "--[[@CHANGES]]": "{\n" + "\n".join(changes) + "\n}",
            "--[[@UNCHANGED]]": "{\n" + "\n".join(unchanged) + "\n}",
        },
    )
    (out_dir / file).write_text(install)
    rb = fill(
        (ROOT / "build" / "Rollback.template.lua").read_text(),
        {
            "--[[@FILE]]": rollback,
            "--[[@INSTALLER]]": file,
            "--[[@BACKUP]]": backup,
            "--[[@NAME]]": rb_name,
            "--[[@LATER]]": lua(later),
        },
    )
    (out_dir / rollback).write_text(rb)
    print(f"wrote {out_dir.relative_to(REPO)}/{file} ({len(install)} chars; changes {', '.join(changed_keys)}) + {rollback}")
    return changed_keys


def write_pair_v2(file: str, rollback: str, about: str, backup: str, requires, forbids, later, changes, unchanged, adds, out_dir: pathlib.Path) -> list[str]:
    """v2 template: a change may list several known versions ("variants": the
    one that matches Studio is used), and new objects can be added.
      changes:   [(target spec, [(label, old, new), ...])]
      unchanged: [(target spec, source)]
      adds:      [{"where", "name", "class", "source"}]"""

    def fields(t: dict) -> list[str]:
        out = [f'key = "{t["key"]}"', f'where = "{t["where"]}"', f'class = "{t["class"]}"']
        if t.get("tag"):
            out.append(f'tag = "{t["tag"]}"')
        if t.get("tagOnParent"):
            out.append("tagOnParent = true")
        return out

    change_rows, keys = [], []
    for t, variants in changes:
        assert variants and all(old != new for _, old, new in variants), t["key"]
        assert len({old for _, old, _ in variants}) == len(variants), "variants must have distinct bases"
        vs = ", ".join(
            f'{{ label = "{label}", old = {bi.long_string(old)}, new = {bi.long_string(new)} }}' for label, old, new in variants
        )
        change_rows.append("\t{ " + ", ".join(fields(t)) + f", variants = {{ {vs} }} }},")
        keys.append(t["key"])
    unchanged_rows = ["\t{ " + ", ".join(fields(t)) + f", source = {bi.long_string(src)} }}," for t, src in unchanged]
    add_rows = [
        f'\t{{ where = "{a["where"]}", name = "{a["name"]}", class = "{a["class"]}", source = {bi.long_string(a["source"])} }},'
        for a in adds
    ]
    name = file.removesuffix(".lua")
    install = fill(
        (ROOT / "build" / "SourceUpdateV2.template.lua").read_text(),
        {
            "--[[@FILE]]": file,
            "--[[@ABOUT]]": "\n".join("\t" + line if line else "" for line in about.strip("\n").split("\n")),
            "--[[@BACKUP]]": backup,
            "--[[@ROLLBACK]]": rollback,
            "--[[@NAME]]": name,
            "--[[@REQUIRES]]": "{ " + ", ".join(lua(r) for r in requires) + " }",
            "--[[@FORBIDS]]": lua(forbids),
            "--[[@CHANGES]]": "{\n" + "\n".join(change_rows) + "\n}",
            "--[[@UNCHANGED]]": "{\n" + "\n".join(unchanged_rows) + "\n}",
            "--[[@ADDS]]": "{\n" + "\n".join(add_rows) + "\n}",
        },
    )
    (out_dir / file).write_text(install)
    rb = fill(
        (ROOT / "build" / "RollbackV2.template.lua").read_text(),
        {
            "--[[@FILE]]": rollback,
            "--[[@INSTALLER]]": file,
            "--[[@BACKUP]]": backup,
            "--[[@NAME]]": rollback.removesuffix(".lua"),
            "--[[@LATER]]": lua(later),
        },
    )
    (out_dir / rollback).write_text(rb)
    print(f"wrote {out_dir.relative_to(REPO)}/{file} ({len(install)} chars; changes {', '.join(keys)}; adds {', '.join(a['name'] for a in adds) or '-'}) + {rollback}")
    return keys


def aquarium() -> list[str]:
    aq = REPO / "tools" / "aquarium-cycle" / "src"
    targets = []
    for name in AQ_SHARED:
        targets.append((
            {"key": name, "where": f"ReplicatedStorage/AquariumCycle/{name}", "class": "ModuleScript", "tag": "AquariumCycleOwned", "tagOnParent": True},
            git_show(AQUARIUM_V1, f"tools/aquarium-cycle/src/shared/{name}.luau"),
            (aq / "shared" / f"{name}.luau").read_text(),
        ))
    for name in ("AquariumCycleServer", "AquariumEconomy"):
        targets.append((
            {"key": name, "where": f"ServerScriptService/{name}", "class": "ModuleScript", "tag": "AquariumCycleOwned"},
            git_show(AQUARIUM_V1, f"tools/aquarium-cycle/src/server/{name}.luau"),
            (aq / "server" / f"{name}.luau").read_text(),
        ))
    targets.append((
        {"key": "AquariumTankClient", "where": "StarterPlayer/StarterPlayerScripts/AquariumTankClient", "class": "LocalScript", "tag": "AquariumCycleOwned"},
        git_show(AQUARIUM_V1, "tools/aquarium-cycle/src/client/AquariumTankClient.client.luau"),
        (aq / "client" / "AquariumTankClient.client.luau").read_text(),
    ))
    keys = write_pair(
        "UpgradeAquariumV12.lua",
        "RollbackAquariumV12.lua",
        """
Aquarium v1 -> v1.2 (the aquarium installed from commit 2e320f9).
  * A fish can carry OwnerId (the player who bought it) and Variant
    rod -> tank -> river, unchanged; nothing is rerolled or invented.
  * The river-release despawn timer leaves a fish the harpoon has hit
    (HarpoonT) to the harpoon.
  * The tank client shows variant effects only if
    ReplicatedStorage.FishVariantVisuals exists (it doesn't yet).
Behaves like v1 until something passes metadata (InstallSales.lua does).
Requires: the aquarium (ServerStorage.AquariumCycleBackup).
""",
        "EconomyAquariumBackup",
        [["AquariumCycleBackup"]],
        ["EconomyAquariumBackup", "EconomySalesBackup", *LATER_THAN_SALES],
        ["EconomySalesBackup", *LATER_THAN_SALES],
        targets,
    )
    assert keys == ["Config", "SharedTank", "AquariumCycleServer", "AquariumTankClient"], keys
    return keys


def sales() -> list[str]:
    outputs = make_sales.build()
    make_sales.main()
    targets = []
    for name in make_sales.LIVE_SCRIPTS:
        targets.append(({"key": name, "where": f"script:{name}", "class": "Script"}, (bi.mro.LIVE / f"{name}.lua").read_text(), outputs[name]))
    targets.append((
        {"key": "RodFishingSystem", "where": "script:RodFishingSystem", "class": "Script"},
        make_sales.rod_base(),
        outputs["RodFishingSystem"],
    ))
    rod_shop = git_show(ROD_OFFERS, "tools/economy/studio/rod-offers/RodShopServer.lua")
    targets.append(({"key": "RodShopServer", "where": "script:RodShopServer", "class": "Script"}, rod_shop, rod_shop))
    targets.append((
        {"key": "EconomyService", "where": "ServerScriptService/EconomyService", "class": "ModuleScript", "tag": "EconomyOwned"},
        git_show(ROD_OFFERS, "tools/economy/src/server/EconomyService.luau"),
        git_show(SALES_RELEASE, "tools/economy/src/server/EconomyService.luau"),
    ))
    for name in bi.CORE:
        targets.append((
            {"key": name, "where": f"ServerScriptService/EconomyService/{name}", "class": "ModuleScript", "tag": "EconomyOwned"},
            git_show(ROD_OFFERS, f"tools/economy/src/core/{name}.luau"),
            git_show(SALES_RELEASE, f"tools/economy/src/core/{name}.luau"),
        ))
    targets.append((
        {"key": "EconomyClient", "where": "StarterPlayer/StarterPlayerScripts/EconomyClient", "class": "LocalScript", "tag": "EconomyOwned"},
        git_show(ROD_OFFERS, "tools/economy/src/client/EconomyClient.client.luau"),
        git_show(SALES_RELEASE, "tools/economy/src/client/EconomyClient.client.luau"),
    ))
    # aquarium v1.2 must be in place (it carries the buyer through the tank)
    aq = REPO / "tools" / "aquarium-cycle" / "src"
    for name in ("Config", "SharedTank"):
        src = (aq / "shared" / f"{name}.luau").read_text()
        targets.append(({"key": "aquarium " + name, "where": f"ReplicatedStorage/AquariumCycle/{name}", "class": "ModuleScript", "tag": "AquariumCycleOwned", "tagOnParent": True}, src, src))
    src = (aq / "server" / "AquariumCycleServer.luau").read_text()
    targets.append(({"key": "aquarium AquariumCycleServer", "where": "ServerScriptService/AquariumCycleServer", "class": "ModuleScript", "tag": "AquariumCycleOwned"}, src, src))
    keys = write_pair(
        "InstallSales.lua",
        "RollbackSales.lua",
        """
Sale payouts: Money is paid once per meat piece, when it SELLS (customer at
the sale table, or dropped in a truck), to the piece's owner:
  * a bought rod fish: its buyer, wherever it is caught later
  * a net catch: the player on the pad
  * a harpoon catch: the fish's buyer, else the player set in HarpoonGun's
    OwnerUserId attribute, else nobody (it sells, nobody is paid)
The carrier is never paid for carrying. A fish's value is split across its
meat pieces. Full pit/stack: pieces wait (held as data) instead of being
destroyed; a carrier who leaves or respawns gives their pieces back.
Requires: rod offers a826d73 (fresh InstallRodOffers, or 8cb2554 +
UpdateRodPrompt) and aquarium v1.2 (UpgradeAquariumV12.lua).
""",
        "EconomySalesBackup",
        [["EconomyRodOffersBackup"]],  # aquarium v1.2 is checked by source (upgrade, or a fresh v1.2 install)
        ["EconomySalesBackup", *LATER_THAN_SALES],
        LATER_THAN_SALES,
        targets,
    )
    assert set(keys) >= set(make_sales.LIVE_SCRIPTS) | {"RodFishingSystem", "EconomyService"}, keys
    return keys


def upgrades() -> list[str]:
    targets = [(
        {"key": "AquariumEconomy", "where": "ServerScriptService/AquariumEconomy", "class": "ModuleScript", "tag": "AquariumCycleOwned"},
        git_show(AQUARIUM_V1, "tools/aquarium-cycle/src/server/AquariumEconomy.luau"),
        git_show(SALES_RELEASE, "tools/economy/src/server/AquariumEconomy.luau"),
    )]
    # needs sale payouts (Money comes in) and aquarium v1.2: checked by source
    for name in ("GrinderProcessor", "TruckSystem"):
        src = (ROOT / "studio" / "sales" / f"{name}.lua").read_text()
        targets.append(({"key": name + " (sales)", "where": f"script:{name}", "class": "Script"}, src, src))
    svc = git_show(SALES_RELEASE, "tools/economy/src/server/EconomyService.luau")
    targets.append(({"key": "EconomyService", "where": "ServerScriptService/EconomyService", "class": "ModuleScript", "tag": "EconomyOwned"}, svc, svc))
    src = (REPO / "tools" / "aquarium-cycle" / "src" / "server" / "AquariumCycleServer.luau").read_text()
    targets.append(({"key": "aquarium AquariumCycleServer", "where": "ServerScriptService/AquariumCycleServer", "class": "ModuleScript", "tag": "AquariumCycleOwned"}, src, src))
    keys = write_pair(
        "InstallUpgrades.lua",
        "RollbackUpgrades.lua",
        """
Paid aquarium upgrades: Tank Capacity and Release Rate are bought with Money
at the aquarium's upgrade prompts, at the aquarium's own prices
(capacity 50 / 150 / 400, release rate 40 / 120 / 350). The player who
triggers the prompt pays; the level applies to the one shared tank for this
server session (not saved, never per player). Not enough Money or money not
loaded: nothing charged, nothing applied. Nothing is ever free.
Changes one module (ServerScriptService.AquariumEconomy: it used to return
nil = "upgrades unavailable").
Requires: sale payouts (InstallSales.lua) and aquarium v1.2.
""",
        "EconomyUpgradesBackup",
        [["EconomyRodOffersBackup"]],
        ["EconomyUpgradesBackup", *LATER_THAN_UPGRADES],
        LATER_THAN_UPGRADES,
        targets,
    )
    assert keys == ["AquariumEconomy"], keys
    return keys


def earnings() -> list[str]:
    """Earnings popup: EconomyService tells a piece's owner when it sells,
    EconomyClient shows "+$N". On top of the sales release (91121de)."""
    changes = []
    for key, where, path in (
        ("EconomyService", "ServerScriptService/EconomyService", "src/server/EconomyService.luau"),
        ("EconomyClient", "StarterPlayer/StarterPlayerScripts/EconomyClient", "src/client/EconomyClient.client.luau"),
    ):
        changes.append((
            {"key": key, "where": where, "class": "LocalScript" if key == "EconomyClient" else "ModuleScript", "tag": "EconomyOwned"},
            [("sales", git_show(SALES_RELEASE, f"tools/economy/{path}"), git_show(EARNINGS_RELEASE, f"tools/economy/{path}"))],
        ))
    # the core modules it relies on, exactly as the sales release left them
    unchanged = [
        (
            {"key": name, "where": f"ServerScriptService/EconomyService/{name}", "class": "ModuleScript", "tag": "EconomyOwned"},
            git_show(SALES_RELEASE, f"tools/economy/src/core/{name}.luau"),
        )
        for name in ("Sales", "Ledger", "PieceTags")
    ]
    for name, path in (("Sales", "Sales"), ("Ledger", "Ledger"), ("PieceTags", "PieceTags")):
        assert (ROOT / "src" / "core" / f"{path}.luau").read_text() == git_show(SALES_RELEASE, f"tools/economy/src/core/{path}.luau"), name
    keys = write_pair_v2(
        "InstallEarnings.lua",
        "RollbackEarnings.lua",
        """
Earnings popup: when a piece of your meat SELLS (a customer at the sale
table, or a truck), you see "+$N" on the right of your screen, whoever
carried it. Quick sales add up into one popup ("+$54 / 3 pieces sold");
Gold / Silver meat tints it. N is what really reached your Money: while
your Money is still loading it says "+$N pending" (grey, not spendable
yet), and at the balance limit it shows the real increase ("Money is at
the maximum"), never the price. Display only: the payment is the same
ledger settlement as before (paid once, to the owner). Unowned meat shows
nothing.
Switch off with ReplicatedStorage.Economy attribute EarningsPopup = false.
Changes EconomyService (adds the Economy.Earned remote at start) and
EconomyClient (the popup).
Requires: sale payouts (InstallSales.lua). If you use paid aquarium
upgrades, install InstallUpgrades.lua FIRST: it checks the sales-release
EconomyService and refuses after this.
""",
        "EconomyEarningsBackup",
        [["EconomySalesBackup"]],
        ["EconomyEarningsBackup", *LATER_THAN_EARNINGS],
        LATER_THAN_EARNINGS,
        changes,
        unchanged,
        [],
        ROOT,
    )
    assert keys == ["EconomyService", "EconomyClient"], keys
    return keys


def bot_recovery() -> list[str]:
    """Blender Bot recovery: an error mid-trip holds the piece instead of
    losing it, and the bot carries on. On top of the sales release."""
    base = git_show(SALES_RELEASE, "tools/economy/studio/sales/BotSystem.lua")
    assert base == make_bot.BASE.read_text(), "studio/sales/BotSystem.lua must be the sales release"
    make_bot.main()
    keys = write_pair_v2(
        "InstallBotRecovery.lua",
        "RollbackBotRecovery.lua",
        """
Blender Bot recovery: each trip of the bot runs under pcall. If anything
errors while the bot holds a piece (between the stack and the table), the
loose clone is removed and the piece is HELD in the ledger - the grinder
brings it back out of the pipe with the same owner and value, so it is
never lost unpaid - and the bot carries on after a short back-off (it used
to stop for good, stranding the piece). One warning, then one per 20
failures while something stays broken.
Changes one script: BotSystem (the sales-patched version).
Requires: sale payouts (InstallSales.lua). Independent of the earnings
popup and the visual features.
""",
        "EconomyBotBackup",
        [["EconomySalesBackup"]],
        ["EconomyBotBackup", *LATER_THAN_BOT],
        LATER_THAN_BOT,
        [({"key": "BotSystem", "where": "script:BotSystem", "class": "Script"}, [("sales", base, make_bot.build())])],
        [],
        [],
        ROOT,
    )
    assert keys == ["BotSystem"], keys
    return keys


# the two HUD copies of the live MoneyController (identical sources)
MONEY_HUDS = [
    ("MoneyHud", "StarterGui/Money/MoneyFrame/MoneyController"),
    ("ButtonsMoneyHud", "StarterGui/ScreenGui/Buttons/Frames/MoneyFrame/MoneyController"),
]


def money_hud() -> list[str]:
    """Money HUD: both MoneyController LocalScripts show leaderstats.Money
    (EconomyService's balance) instead of waiting forever on the missing
    FormatModule / LocalPlayer.Money."""
    live = (ROOT / "studio" / "live" / "MoneyController.lua").read_text()
    new = (ROOT / "src" / "client" / "MoneyController.client.luau").read_text()
    keys = write_pair_v2(
        "InstallMoneyHud.lua",
        "RollbackMoneyHud.lua",
        """
Money HUD: both MoneyController LocalScripts (StarterGui.Money.MoneyFrame
and StarterGui.ScreenGui.Buttons.Frames.MoneyFrame) show leaderstats.Money,
the balance EconomyService keeps. They used to wait forever on the missing
ReplicatedStorage.FormatModule and LocalPlayer.Money, so the labels never
updated.
  * "Loading..." until the player's Money has loaded, then the balance,
    following every change ($1.23K style, never rounded up; FormatModule is
    used if it exists and works)
  * the multiplier labels keep their old formulas WHEN their inputs exist
    (Rebirths + Modules.RebirthDefinitions, Upgrades.RobuxMultiplier,
    FriendsMultiplier, VIP); a label whose inputs are missing is hidden.
    Display only: no payout applies any multiplier.
Changes only those two LocalScripts. Nothing server side.
Requires: rod offers (EconomyService makes leaderstats.Money). Independent
of every other install here.
""",
        "EconomyMoneyHudBackup",
        [["EconomyRodOffersBackup"]],
        ["EconomyMoneyHudBackup"],
        [],
        [({"key": key, "where": where, "class": "LocalScript"}, [("live", live, new)]) for key, where in MONEY_HUDS],
        [],
        [],
        ROOT,
    )
    assert keys == [k for k, _ in MONEY_HUDS], keys
    return keys


def rods() -> list[str]:
    """Rods milestone 1: saved rod ownership + equip + faster bites. On top of
    what Astra installed: earnings (EconomyService 0829fc9), the sales-release
    core, rod offers' RodShopServer and the variants RodFishingSystem."""
    import make_rods

    make_rods.main()
    core = lambda name: f"tools/economy/src/core/{name}.luau"  # noqa: E731
    changes = [
        (
            {"key": "EconomyService", "where": "ServerScriptService/EconomyService", "class": "ModuleScript", "tag": "EconomyOwned"},
            [("earnings", git_show(EARNINGS_RELEASE, "tools/economy/src/server/EconomyService.luau"), (ROOT / "src/server/EconomyService.luau").read_text())],
        ),
        (
            {"key": "Config", "where": "ServerScriptService/EconomyService/Config", "class": "ModuleScript", "tag": "EconomyOwned"},
            [("sales", git_show(SALES_RELEASE, core("Config")), (ROOT / "src/core/Config.luau").read_text())],
        ),
        (
            {"key": "MoneyStore", "where": "ServerScriptService/EconomyService/MoneyStore", "class": "ModuleScript", "tag": "EconomyOwned"},
            [("sales", git_show(SALES_RELEASE, core("MoneyStore")), (ROOT / "src/core/MoneyStore.luau").read_text())],
        ),
        (
            {"key": "RodShopServer", "where": "script:RodShopServer", "class": "Script"},
            [("rodoffers", git_show(ROD_OFFERS, "tools/economy/studio/rod-offers/RodShopServer.lua"), (ROOT / "studio/rods/RodShopServer.lua").read_text())],
        ),
        (
            {"key": "RodFishingSystem", "where": "script:RodFishingSystem", "class": "Script"},
            [("variants", make_rods.BASE.read_text(), make_rods.OUT.read_text())],
        ),
    ]
    # the other core modules EconomyService requires, exactly as installed
    unchanged = []
    for name in ("Pricing", "Ledger", "Offers", "PieceTags", "Sales"):
        src = git_show(SALES_RELEASE, core(name))
        assert src == (ROOT / "src" / "core" / f"{name}.luau").read_text(), name
        unchanged.append(({"key": name, "where": f"ServerScriptService/EconomyService/{name}", "class": "ModuleScript", "tag": "EconomyOwned"}, src))
    adds = [{"where": "ServerScriptService/EconomyService", "name": "Rods", "class": "ModuleScript", "source": (ROOT / "src/core/Rods.luau").read_text()}]
    keys = write_pair_v2(
        "InstallRods.lua",
        "RollbackRods.lua",
        """
Rods, milestone 1: rods are OWNED for good, EQUIPPED, and make bites faster.
  * five rods (ReplicatedStorage.Rods): Basic FishingRod1 (free, always
    owned), Tiger FishingRod4 150, Coral FishingRod3 600, Tide FishingRod2
    2000, Magma FishingRod5 7500. Bite wait x1 / .85 / .75 / .65 / .55
    (initial tuning, not measured pacing). Legacy Price/Tier/Title ignored.
  * saved in the player's Money record (schema v2: v1 records load with
    their money untouched; unknown fields and newer versions are kept; a
    record that failed to load is never written). A purchase saves the new
    balance AND the rod in ONE write before it counts; if that write fails
    nothing is charged.
  * RodShopServer: an owned rod is equipped (never charged again); buying
    needs the shop open, the player alive, loaded, near the Pet Shop, the rod
    in stock (Basic / Tiger always). FAIL CLOSED: no EconomyService, no sale;
    the old direct money-writing fallback is gone.
  * RodFishingSystem: each accepted press uses the PRESSER's equipped rod for
    every rod it casts (bite wait x BiteWait, never below 2 s so the aquarium
    timing holds). Another player's equip never changes a cast in progress.
  * PAID SHOP STAYS CLOSED (Config.RodShopOpen = false). For a Studio
    validation with real DataStore access, set the RodShopOpen attribute on
    ReplicatedStorage.Economy. Equipping owned rods always works.
Changes EconomyService, its Config and MoneyStore, RodShopServer and
RodFishingSystem; adds EconomyService.Rods.
Requires: earnings (EconomyEarningsBackup) and fish variants
(EconomyVariantsBackup), each checked by exact source.
""",
        "EconomyRodsBackup",
        [["EconomyEarningsBackup"], ["EconomyVariantsBackup"]],
        ["EconomyRodsBackup", *LATER_THAN_RODS],
        LATER_THAN_RODS,
        changes,
        unchanged,
        adds,
        ROOT,
    )
    assert keys == ["EconomyService", "Config", "MoneyStore", "RodShopServer", "RodFishingSystem"], keys
    return keys


def rod_shop_ui() -> list[str]:
    """The rod shop UI for rods milestone 1: the exact live
    RodShopController -> owned / equipped / benefit / truthful results."""
    import make_shop_ui

    make_shop_ui.main()
    keys = write_pair_v2(
        "InstallRodShopUI.lua",
        "RollbackRodShopUI.lua",
        """
Rod shop UI (StarterGui.ScreenGui.Buttons.Frames.RodShopFrame.RodShopController):
  * each card shows the real price (or OWNED), the benefit ("Bites 15%
    faster"), and a button that says what pressing does: BUY / EQUIP /
    EQUIPPED / SOON (paid shop not open) / SOLD OUT - live from the
    server's attributes, nothing captured once
  * pressing: "..." while the server answers (one request per rod; the
    equipped rod sends nothing), then the server's real result (BOUGHT! /
    EQUIPPED / NEED $ / TOO FAR / NOT SAVED / ...) with the full message on
    a status line under the cards (it used to show "NO $ YET" for most
    refusals)
  * the picture, restock countdown, open / close and scrolling are
    unchanged; the client decides nothing (the server checks and charges)
Changes one LocalScript (checked by its exact source and path).
Requires: rods (InstallRods.lua, EconomyRodsBackup).
""",
        "EconomyRodShopUIBackup",
        [["EconomyRodsBackup"]],
        ["EconomyRodShopUIBackup"],
        [],
        [(
            {"key": "RodShopController", "where": "StarterGui/ScreenGui/Buttons/Frames/RodShopFrame/RodShopController", "class": "LocalScript"},
            [("live", make_shop_ui.BASE.read_text(), make_shop_ui.OUT.read_text())],
        )],
        [],
        [],
        ROOT,
    )
    assert keys == ["RodShopController"], keys
    return keys


def net_kg() -> list[str]:
    """+5 KG signs: per-player net capacity saved with the Money, shared
    NetLift.MaxWeight = the highest loaded player's. On top of the rods
    release as installed (61a7bd4, pending validation)."""
    core = lambda name: f"tools/economy/src/core/{name}.luau"  # noqa: E731
    changes = [
        (
            {"key": "EconomyService", "where": "ServerScriptService/EconomyService", "class": "ModuleScript", "tag": "EconomyOwned"},
            [("rods", git_show(RODS_RELEASE, "tools/economy/src/server/EconomyService.luau"), (ROOT / "src/server/EconomyService.luau").read_text())],
        ),
        (
            {"key": "Config", "where": "ServerScriptService/EconomyService/Config", "class": "ModuleScript", "tag": "EconomyOwned"},
            [("rods", git_show(RODS_RELEASE, core("Config")), (ROOT / "src/core/Config.luau").read_text())],
        ),
        (
            {"key": "MoneyStore", "where": "ServerScriptService/EconomyService/MoneyStore", "class": "ModuleScript", "tag": "EconomyOwned"},
            [("rods", git_show(RODS_RELEASE, core("MoneyStore")), (ROOT / "src/core/MoneyStore.luau").read_text())],
        ),
    ]
    unchanged = []
    for name in ("Rods", "Pricing", "Ledger", "Offers", "PieceTags", "Sales"):
        src = git_show(RODS_RELEASE, core(name))
        assert src == (ROOT / "src" / "core" / f"{name}.luau").read_text(), name
        unchanged.append(({"key": name, "where": f"ServerScriptService/EconomyService/{name}", "class": "ModuleScript", "tag": "EconomyOwned"}, src))
    adds = [
        {"where": "ServerScriptService/EconomyService", "name": "NetKg", "class": "ModuleScript", "source": (ROOT / "src/core/NetKg.luau").read_text()},
        {"where": "ServerScriptService", "name": "NetCapacityServer", "class": "Script", "source": (ROOT / "src/server/NetCapacityServer.server.luau").read_text()},
        {"where": "StarterPlayer/StarterPlayerScripts", "name": "KgSignClient", "class": "LocalScript", "source": (ROOT / "src/client/KgSignClient.client.luau").read_text()},
    ]
    keys = write_pair_v2(
        "InstallNetKg.lua",
        "RollbackNetKg.lua",
        """
+5 KG signs: each player OWNS a net capacity (15 kg to start), saved with
their Money. Clicking either Workspace.KGsign (both same-named signs are
bound) buys the clicker's next +5 kg: 25, 50, 100, then x1.5 rounded to 5,
up to 60 kg (initial tuning). The purchase saves the new balance AND the
new capacity in ONE write before it counts; if the write fails nothing is
charged. Checks: alive, money loaded, near the clicked sign, one purchase
at a time, cooldown, re-checked right before the debit.
The net lift is shared: Workspace.NetLift.MaxWeight (weight gate, gauge,
themes) = the highest capacity among loaded players in the server, never
below the place's own value; it follows joins, purchases and leaves. No
fish are touched.
A panel above each sign shows YOUR capacity -> next and the price (SOON
while closed, MAX at the cap) and the shared net's capacity.
PAID SIGNS STAY CLOSED (Config.NetKgOpen = false). For a Studio validation
with real DataStore access, set the NetKgOpen attribute on
ReplicatedStorage.Economy.
Changes EconomyService, Config, MoneyStore (record field netKg); adds
EconomyService.NetKg, ServerScriptService.NetCapacityServer and
StarterPlayerScripts.KgSignClient.
Requires: rods (EconomyRodsBackup; its sources exactly as installed).
""",
        "EconomyNetKgBackup",
        [["EconomyRodsBackup"]],
        ["EconomyNetKgBackup"],
        [],
        changes,
        unchanged,
        adds,
        ROOT,
    )
    assert keys == ["EconomyService", "Config", "MoneyStore"], keys
    return keys


def upgrade_board() -> list[str]:
    """Upgrade board milestone 1: the four-card board on Workspace.Board;
    Net Strength sells the same saved net capacity as the KGsign posts
    (first step now $10); the posts' PricePlate shows each player's own
    values. On top of the net kg release (187fe39)."""
    core = lambda name: f"tools/economy/src/core/{name}.luau"  # noqa: E731
    at_netkg = lambda path: git_show(NETKG_RELEASE, f"tools/economy/{path}")  # noqa: E731
    changes = [
        (
            {"key": "Config", "where": "ServerScriptService/EconomyService/Config", "class": "ModuleScript", "tag": "EconomyOwned"},
            [("netkg", at_netkg("src/core/Config.luau"), (ROOT / "src/core/Config.luau").read_text())],
        ),
        (
            {"key": "KgSignClient", "where": "StarterPlayer/StarterPlayerScripts/KgSignClient", "class": "LocalScript", "tag": "EconomyOwned"},
            [("netkg", at_netkg("src/client/KgSignClient.client.luau"), (ROOT / "src/client/KgSignClient.client.luau").read_text())],
        ),
    ]
    unchanged = []
    svc = at_netkg("src/server/EconomyService.luau")
    assert svc == (ROOT / "src/server/EconomyService.luau").read_text(), "EconomyService"
    unchanged.append(({"key": "EconomyService", "where": "ServerScriptService/EconomyService", "class": "ModuleScript", "tag": "EconomyOwned"}, svc))
    for name in ("MoneyStore", "NetKg", "Rods", "Pricing", "Ledger", "Offers", "PieceTags", "Sales"):
        src = git_show(NETKG_RELEASE, core(name))
        assert src == (ROOT / "src" / "core" / f"{name}.luau").read_text(), name
        unchanged.append(({"key": name, "where": f"ServerScriptService/EconomyService/{name}", "class": "ModuleScript", "tag": "EconomyOwned"}, src))
    server = at_netkg("src/server/NetCapacityServer.server.luau")
    assert server == (ROOT / "src/server/NetCapacityServer.server.luau").read_text(), "NetCapacityServer"
    unchanged.append(({"key": "NetCapacityServer", "where": "ServerScriptService/NetCapacityServer", "class": "Script", "tag": "EconomyOwned"}, server))
    adds = [
        {"where": "ServerScriptService", "name": "UpgradeBoardServer", "class": "Script", "source": (ROOT / "src/server/UpgradeBoardServer.server.luau").read_text()},
        {"where": "StarterPlayer/StarterPlayerScripts", "name": "UpgradeBoardClient", "class": "LocalScript", "source": (ROOT / "src/client/UpgradeBoardClient.client.luau").read_text()},
    ]
    keys = write_pair_v2(
        "InstallUpgradeBoard.lua",
        "RollbackUpgradeBoard.lua",
        """
Upgrade board, milestone 1 (Net Strength): the board on Workspace.Board
(Main.SurfaceGui.bord3) shows four cards to each player - Net Strength
(pink), Rod Luck (lime), Meat Price (cyan), Faster Reels (amber) - drawn
on a per-player copy (the place's board is only hidden on each client,
never changed). Found by exact path (one Board, one Main, one SurfaceGui,
one bord3); the two old "Frame" cards are never looked up by name.
  * Net Strength sells the SAME saved net capacity as both KGsign posts
    (one progression): 15 -> 20 kg first, now $10 for everyone's first
    step (10, 25, 50, 100, then x1.5 rounded to 5, up to 60 kg). Saved with
    the money in one write before it counts; alive, loaded, near the board,
    one purchase at a time, re-checked right before the debit.
  * Rod Luck / Meat Price / Faster Reels show SOON and sell nothing yet.
  * The posts' PricePlate.PriceGui ("$100", "NET15KG->20KG" in the place)
    shows each player's own price and step (on that client only).
  * PAID UPGRADES STAY CLOSED (Config.NetKgOpen = false): SOON on the card
    and plates. For a Studio validation set the NetKgOpen attribute on
    ReplicatedStorage.Economy.
Changes Config and KgSignClient; adds ServerScriptService.UpgradeBoardServer
and StarterPlayerScripts.UpgradeBoardClient.
Requires: net kg (EconomyNetKgBackup; its sources exactly as installed).
""",
        "EconomyUpgradeBoardBackup",
        [["EconomyNetKgBackup"]],
        ["EconomyUpgradeBoardBackup"],
        [],
        changes,
        unchanged,
        adds,
        ROOT,
    )
    assert keys == ["Config", "KgSignClient"], keys
    return keys


def main() -> None:
    # InstallRodOffers.lua / UpdateRodPrompt.lua are FROZEN at the a826d73
    # release Astra installed; they are not rebuilt here.
    aquarium()
    sales()
    upgrades()
    earnings()
    bot_recovery()
    money_hud()
    # InstallRods / InstallRodShopUI are FROZEN at the 61a7bd4 release Astra
    # installed (pending validation): rods() / rod_shop_ui() are not rerun;
    # later milestones read their sources from git at RODS_RELEASE.
    # InstallNetKg is FROZEN at the 187fe39 release: net_kg() is not rerun.
    upgrade_board()


if __name__ == "__main__":
    main()
