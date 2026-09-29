#!/usr/bin/env python3
"""Generates tools/fish-jump/InstallHarpoonBlend.lua and
RollbackHarpoonBlend.lua from the economy's guarded update template (v2).
Runs make_harpoon_blend.py first.

Usage:  python3 tools/fish-jump/build/build_harpoon_blend.py
"""
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT.parent / "economy" / "build"))
import build_updates as bu  # noqa: E402

_spec = importlib.util.spec_from_file_location("jump_make_harpoon_blend", ROOT / "build" / "make_harpoon_blend.py")
make_harpoon_blend = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(make_harpoon_blend)

BACKUP = "HarpoonBlendBackup"


def main() -> None:
    make_harpoon_blend.main()
    versions = make_harpoon_blend.build()
    for label, (_, src) in versions.items():
        assert "+ harpoonLift(f) * (1 - u) -- HarpoonBlend" in src, label
    jump_module = (ROOT / "src" / "FishJump.luau").read_text()
    bu.write_pair_v2(
        "InstallHarpoonBlend.lua",
        "RollbackHarpoonBlend.lua",
        """
Harpoon mid-jump fix. Fish jumps are drawn on each client; the harpoon aims
at the fish's swim line. A fish struck in the air used to snap straight down
to the water on the first frame of the pull. Now the pull starts from its
height in the air and eases down onto the rope; the rest of the harpoon path
and its timing are unchanged (the server's reel, toss and suck still match).
Changes one LocalScript: FishSwimClient (the fish-jump version, or grinder
dwell on top of it: the matching patch is picked by exact source).
Requires: fish jumps (InstallFishJump.lua). If you use grinder dwell,
install it FIRST (it refuses after this). Roll this back before either.
""",
        BACKUP,
        [["FishJumpBackup"]],
        [BACKUP],
        [],
        [(
            {"key": "FishSwimClient", "where": "localscript:FishSwimClient", "class": "LocalScript"},
            [(label, base, new) for label, (base, new) in versions.items()],
        )],
        [(
            {"key": "FishJump", "where": "ReplicatedStorage/FishJump", "class": "ModuleScript"},
            jump_module,
        )],
        [],
        ROOT,
    )


if __name__ == "__main__":
    main()
