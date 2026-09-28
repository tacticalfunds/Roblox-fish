#!/usr/bin/env python3
"""Generates tools/rod-cast/InstallRodCast.lua and RollbackRodCast.lua from
the economy's guarded update template (exact-source checks, one undo step,
Target/Before/After backup, rollback that refuses over later edits).

Base: RodFishingSystem = the sale-payout version (tools/economy/studio/sales),
RodFishingClient = the live source. Runs make_patches.py first.

Usage:  python3 tools/rod-cast/build/build_installer.py
"""
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "economy" / "build"))
import build_updates as bu  # noqa: E402

# this tool's own make_patches.py (the economy build dir has one of the same name)
_spec = importlib.util.spec_from_file_location("rodcast_make_patches", ROOT / "build" / "make_patches.py")
make_patches = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(make_patches)

LATER = ["GrinderDwellBackup", "EconomyVariantsBackup"]


def main() -> None:
    make_patches.main()
    studio = ROOT / "studio"
    changes = [
        (
            {"key": "RodFishingSystem", "where": "script:RodFishingSystem", "class": "Script"},
            [("sales", (ROOT.parent / "economy" / "studio" / "sales" / "RodFishingSystem.lua").read_text(),
              (studio / "RodFishingSystem.patched.from-sales.lua").read_text())],
        ),
        (
            {"key": "RodFishingClient", "where": "localscript:RodFishingClient", "class": "LocalScript"},
            [("live", (studio / "RodFishingClient.original.lua").read_text(), (studio / "RodFishingClient.patched.lua").read_text())],
        ),
    ]
    keys = bu.write_pair_v2(
        "InstallRodCast.lua",
        "RollbackRodCast.lua",
        """
Immediate rod cast: an accepted button press casts every eligible rod at
once, right away (no press delay, no per-rod stagger), and the rods dip
toward the water the moment they cast (RodFishingClient, CastT0). A refused
press (cooldown, busy, tank full, buying unavailable) starts nothing and
doesn't animate the button. Rod offers, sale payouts and the aquarium work
exactly as before.
Requires: sale payouts (RodFishingSystem = the InstallSales version).
""",
        "RodCastBackup",
        [["EconomyRodOffersBackup"]],
        ["RodCastBackup", *LATER],
        LATER,
        changes,
        [],
        [],
        ROOT,
    )
    assert keys == ["RodFishingSystem", "RodFishingClient"], keys


if __name__ == "__main__":
    main()
