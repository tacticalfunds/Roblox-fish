#!/usr/bin/env python3
"""Generates tools/fish-jump/InstallJumpRate.lua and RollbackJumpRate.lua
(the economy's guarded update template, v2). Runs make_jump_rate.py first.

Changes one ModuleScript, ReplicatedStorage.FishJump (installed by
InstallFishJump, tagged FishJumpOwned), from the installed version to the
more-often version. Its own backup, ServerStorage.FishJumpRateBackup;
ServerStorage.FishJumpBackup (the original install's) is never touched.

Usage:  python3 tools/fish-jump/build/build_jump_rate.py
"""
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "economy" / "build"))
import build_updates as bu  # noqa: E402

_spec = importlib.util.spec_from_file_location("jump_make_jump_rate", ROOT / "build" / "make_jump_rate.py")
make_jump_rate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(make_jump_rate)

BACKUP = "FishJumpRateBackup"


def main() -> None:
    make_jump_rate.main()
    bu.write_pair_v2(
        "InstallJumpRate.lua",
        "RollbackJumpRate.lua",
        """
Fish jump more often (about twice as often). Changes only the two period
numbers in ReplicatedStorage.FishJump:
  PeriodMin     16 -> 8   seconds
  PeriodSpread  12 -> 6   seconds   (each fish's period: 16-28 s -> 8-14 s)
Unchanged: Chance 0.35 per period, 0.9 s in the air, heights, the river-end
margin, snakes don't jump, splash pool 10, and the client's protections
(a netted or harpooned fish never jumps; FishSwimClient isn't touched).
Each fish keeps its own period and offset, so jumps stay staggered. Per
fish: about once every 63 s -> about once every 31 s.
Its own backup (FishJumpRateBackup); FishJumpBackup is never touched.
Requires: fish jumps (InstallFishJump.lua). Roll this back BEFORE
UninstallFishJump (which refuses while it is in).
""",
        BACKUP,
        [["FishJumpBackup"]],
        [BACKUP],
        [],
        [(
            {"key": "FishJump", "where": "ReplicatedStorage/FishJump", "class": "ModuleScript", "tag": "FishJumpOwned"},
            [("installed", make_jump_rate.BASE.read_text(), make_jump_rate.OUT.read_text())],
        )],
        [],
        [],
        ROOT,
    )


if __name__ == "__main__":
    main()
