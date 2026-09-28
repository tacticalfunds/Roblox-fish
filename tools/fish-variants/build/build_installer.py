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
        [],
        changes,
        [],
        adds,
        ROOT,
    )


if __name__ == "__main__":
    main()
