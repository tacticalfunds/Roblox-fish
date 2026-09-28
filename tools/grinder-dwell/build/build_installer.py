#!/usr/bin/env python3
"""Generates tools/grinder-dwell/InstallGrinderDwell.lua and
RollbackGrinderDwell.lua from the economy's guarded update template (v2:
several known base versions per script; adds the GrinderDwell module).
Runs make_patches.py first.

Usage:  python3 tools/grinder-dwell/build/build_installer.py
"""
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "economy" / "build"))
import build_updates as bu  # noqa: E402

_spec = importlib.util.spec_from_file_location("dwell_make_patches", ROOT / "build" / "make_patches.py")
make_patches = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(make_patches)

LATER = ["EconomyVariantsBackup"]
WHERE = {
    "FishSwimClient": ("localscript:FishSwimClient", "LocalScript"),
    "NetLiftScript": ("script:NetLiftScript", "Script"),
    "HarpoonSystem": ("script:HarpoonSystem", "Script"),
    "RodFishingSystem": ("script:RodFishingSystem", "Script"),
}


def main() -> None:
    make_patches.main()
    # timing sync: every client path takes its timeline from the module, and
    # the servers act once, after the client animation
    out = make_patches.OUT
    for label in make_patches.BASES["FishSwimClient"]:
        c = (out / f"FishSwimClient.patched.from-{label}.lua").read_text()
        assert "if Dwell then LAUNCH_RISE, LAUNCH_FLY, LAUNCH_DROP = Dwell.Rise, Dwell.Fly, Dwell.Drop end" in c
        assert "elseif lt < PULL + TOSS + DWELL then" in c, "harpooned fish dwell too"
    assert "task.delay(CATCH_DELAY, function() -- GrinderDwell" in (out / "NetLiftScript.patched.from-sales.lua").read_text()
    assert "local CATCH_DELAY = if Dwell then Dwell.serverDelay() else 1.65" in (out / "NetLiftScript.patched.from-sales.lua").read_text()
    assert "task.delay(TOSS + HARPOON_DWELL + SUCK, function()" in (out / "HarpoonSystem.patched.from-sales.lua").read_text()
    changes = []
    for name, bases in make_patches.BASES.items():
        where, cls = WHERE[name]
        variants = [
            (label, path.read_text(), (make_patches.OUT / f"{name}.patched.from-{label}.lua").read_text())
            for label, path in bases.items()
        ]
        changes.append(({"key": name, "where": where, "class": cls}, variants))
    adds = [{
        "where": "ReplicatedStorage",
        "name": "GrinderDwell",
        "class": "ModuleScript",
        "source": (ROOT / "src" / "GrinderDwell.luau").read_text(),
    }]
    bu.write_pair_v2(
        "InstallGrinderDwell.lua",
        "RollbackGrinderDwell.lua",
        """
Grinder dwell: every fish arriving at the grinder (net catch, harpoon, and a
rod catch sent to the grinder with offers off) lands on the rollers, tumbles
and shudders there for about a second, then spirals in and shrinks. The
server fires FishCaught (meat, payouts) once, after the client animation, so
nothing is paid or ground twice. Timeline: ReplicatedStorage.GrinderDwell.
Works with or without fish jumps, and with or without the immediate rod cast
(the matching patch is picked by exact source). Install it after those, and
roll it back before them.
Requires: sale payouts (NetLiftScript / HarpoonSystem = the InstallSales versions).
""",
        "GrinderDwellBackup",
        [["EconomyRodOffersBackup"]],
        ["GrinderDwellBackup", *LATER],
        LATER,
        changes,
        [],
        adds,
        ROOT,
    )


if __name__ == "__main__":
    main()
