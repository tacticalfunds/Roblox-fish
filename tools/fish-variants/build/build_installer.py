#!/usr/bin/env python3
"""Generates tools/fish-variants/InstallFishVariants.lua and
RollbackFishVariants.lua (economy chain, 2026-09-28) from the economy's
guarded update template v2. Runs make_patches.py first.

Adds ReplicatedStorage.FishVariants (rules) and .FishVariantVisuals
(effects); patches FishSpawner, RodFishingSystem (one of 4 known versions)
and GrinderProcessor.

Usage:  python3 tools/fish-variants/build/build_installer.py
"""
import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "economy" / "build"))
import build_updates as bu  # noqa: E402

_spec = importlib.util.spec_from_file_location("variants_make_patches", ROOT / "build" / "make_patches.py")
make_patches = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(make_patches)
_spec = importlib.util.spec_from_file_location("variants_make_meat_glow", ROOT / "build" / "make_meat_glow.py")
make_meat_glow = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(make_meat_glow)

MEAT_GLOW_BACKUP = "EconomyMeatGlowBackup"
assert MEAT_GLOW_BACKUP in bu.LATER_THAN_BOT, "the bot recovery rollback must wait for the meat glow rollback"


def check_names() -> None:
    """The economy prices exactly the variants this rolls."""
    rules = (ROOT / "src" / "FishVariants.luau").read_text()
    econ = (ROOT.parent / "economy" / "src" / "core" / "Config.luau").read_text()
    rolled = set(re.findall(r"^\t(\w+) = \{ Chance", rules, re.M))
    priced = set(re.findall(r"^\t(\w+) = \{ Sale =", econ, re.M))
    assert rolled == priced == {"Silver", "Gold"}, (rolled, priced)


def main() -> None:
    check_names()
    make_patches.main()
    changes = []
    where = {"FishSpawner": "script:FishSpawner", "RodFishingSystem": "script:RodFishingSystem", "GrinderProcessor": "script:GrinderProcessor"}
    for name, bases in make_patches.BASES.items():
        variants = [
            (label, path.read_text(), (make_patches.OUT / f"{name}.patched.from-{label}.lua").read_text())
            for label, path in bases.items()
        ]
        changes.append(({"key": name, "where": where[name], "class": "Script"}, variants))
    adds = [
        {"where": "ReplicatedStorage", "name": "FishVariants", "class": "ModuleScript", "source": (ROOT / "src" / "FishVariants.luau").read_text()},
        {"where": "ReplicatedStorage", "name": "FishVariantVisuals", "class": "ModuleScript", "source": (ROOT / "src" / "FishVariantVisuals.luau").read_text()},
    ]
    bu.write_pair_v2(
        "InstallFishVariants.lua",
        "RollbackFishVariants.lua",
        """
Rare Silver / Gold fish. A variant is rolled ONCE when a fish is created
(FishSpawner for river fish: Gold 0.5%, Silver 2%; the rod's final pick,
same odds) and only copied after that: net / harpoon payloads, aquarium v1.2
(tank and release), every meat piece. The extra value is applied once, when
a piece sells, by the economy ledger (Silver x2, Gold x5 of the fish value,
split over its meat pieces). A rod offer for a variant costs x1.25 / x1.75
and its label shows the variant and the chance of exactly that catch.
Effects: a soft outline, sparkles, a small light and a label on the fish; a
small glow on its meat. Species colours are never changed.
Requires: sale payouts (GrinderProcessor = the InstallSales version).
Works with or without rod cast / grinder dwell (install those first).
""",
        "EconomyVariantsBackup",
        [["EconomyRodOffersBackup"]],
        ["EconomyVariantsBackup"],
        [MEAT_GLOW_BACKUP],
        changes,
        [],
        adds,
        ROOT,
    )
    meat_glow(adds)


def meat_glow(variant_adds: list) -> None:
    """InstallMeatGlow.lua: Silver / Gold meat keeps its glow when carried,
    laid out or loaded. On top of the variants install."""
    make_meat_glow.main()
    where = {"BotSystem": "script:BotSystem", "CustomerSystem": "script:CustomerSystem", "TruckSystem": "script:TruckSystem"}
    changes = [
        ({"key": name, "where": where[name], "class": "Script"}, [(label, base, new) for label, (base, new) in versions.items()])
        for name, versions in make_meat_glow.build().items()
    ]
    visuals = next(a for a in variant_adds if a["name"] == "FishVariantVisuals")
    unchanged = [(
        {"key": "FishVariantVisuals", "where": "ReplicatedStorage/FishVariantVisuals", "class": "ModuleScript", "tag": "EconomyOwned"},
        visuals["source"],
    )]
    bu.write_pair_v2(
        "InstallMeatGlow.lua",
        "RollbackMeatGlow.lua",
        """
Variant glow on MOVED meat. Silver / Gold meat glows in the blender, on the
belt and on the stack (InstallFishVariants); every later hop is a fresh
MeatTemplate clone that used to lose the glow. Now it keeps it:
  * BotSystem: the piece the Blender Bot carries, and on the sale table
  * CustomerSystem: the piece in the customer's hand
  * TruckSystem: the stack a player carries, the pieces flying to the
    truck, and the meat loaded in the truck
Display only: it reads the Variant the ledger stamped on the piece; value
and payment are unchanged. Without ReplicatedStorage.FishVariantVisuals the
scripts behave exactly like before.
BotSystem may be the sales version or the Blender Bot recovery version:
install InstallBotRecovery.lua FIRST if you want it (it refuses after this).
Requires: InstallFishVariants.lua (the visuals module, checked by source).
""",
        MEAT_GLOW_BACKUP,
        [["EconomyVariantsBackup"]],
        [MEAT_GLOW_BACKUP],
        [],
        changes,
        unchanged,
        [],
        ROOT,
    )


if __name__ == "__main__":
    main()
