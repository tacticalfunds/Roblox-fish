#!/usr/bin/env python3
"""Fish jump more often: about twice the jumps, same everything else.

Patches the INSTALLED FishJump module (src/FishJump.luau, embedded in
InstallFishJump.lua and checked by InstallHarpoonBlend) into
studio/jump-rate/FishJump.luau. Only the two period numbers change:

  PeriodMin     16 -> 8   seconds
  PeriodSpread  12 -> 6   seconds  (each fish's period: [16, 28) -> [8, 14))

Each fish still gets its own period and time offset from its Seed, and still
jumps in a period with Chance 0.35, so jumps stay staggered and random; the
mean period halves (22 s -> 11 s), so each fish jumps about twice as often
(about once every 63 s -> about once every 31 s). Unchanged: Chance,
Duration (0.9 s in the air), heights, EdgeMargin, SkipSnakes, the splash
pool (10) and every client-side protection (caught / harpooned fish never
jump: FishSwimClient isn't touched). The river attribute JumpChance still
overrides Chance.

Usage:  python3 tools/fish-jump/build/make_jump_rate.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = ROOT / "src" / "FishJump.luau"
OUT = ROOT / "studio" / "jump-rate" / "FishJump.luau"

BEFORE = {"PeriodMin": 16, "PeriodSpread": 12}
AFTER = {"PeriodMin": 8, "PeriodSpread": 6}


def build() -> str:
    src = BASE.read_text()
    for key in BEFORE:
        old = f"\t{key} = {BEFORE[key]},\n"
        assert src.count(old) == 1, old
        src = src.replace(old, f"\t{key} = {AFTER[key]}, -- JumpRate: was {BEFORE[key]} (jumps about twice as often)\n")
    header = "-- (Seed, cycle number). Everything is a pure function of server time and\n"
    assert src.count(header) == 1
    src = src.replace(
        "local FishJump = {}\n",
        "-- [JumpRate v1] Periods halved (16-28 s -> 8-14 s): about twice the jumps,\n"
        "-- still one period and offset per fish, so they stay staggered.\n"
        "local FishJump = {}\n",
        1,
    )
    # nothing else may differ from the installed module
    base_lines = [l for l in BASE.read_text().split("\n")]
    new_lines = src.split("\n")
    changed = [l for l in new_lines if l not in base_lines]
    assert len(changed) == 4, changed  # 2 header lines + 2 settings
    return src


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(build())
    print(f"wrote {OUT.relative_to(ROOT.parent.parent)}")


if __name__ == "__main__":
    main()
