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

Every "old" source comes from git at the installed commit, so the checks
match exactly what the earlier installers wrote.

Usage:  python3 tools/economy/build/build_updates.py
"""
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import build_rod_offers_installer as bi  # noqa: E402
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
# economy milestones after the sales release (each its own installer)
LATER_THAN_EARNINGS: list[str] = []


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
            [("sales", git_show(SALES_RELEASE, f"tools/economy/{path}"), (ROOT / path).read_text())],
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
Gold / Silver meat tints it. Display only: the payment is the same ledger
settlement as before (paid once, to the owner). Unowned meat shows nothing.
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


def main() -> None:
    # InstallRodOffers.lua / UpdateRodPrompt.lua are FROZEN at the a826d73
    # release Astra installed; they are not rebuilt here.
    aquarium()
    sales()
    upgrades()
    earnings()


if __name__ == "__main__":
    main()
