#!/usr/bin/env python3
"""Harpoon mid-jump fix -> tools/fish-jump/studio/harpoon-blend/.

Jumps are client-only (deterministic from the fish's Seed and the server
time); the server aims the harpoon at the fish's swim line. A fish struck
mid-jump used to snap straight down to the water on the first pulled frame.
Now the pull starts from the fish's height in the air at HarpoonT and eases
down onto the rope over the pull (the rest of the harpoon path is
unchanged, and so is its timing: the server's reel/toss/suck match it).

Bases (FishSwimClient): the fish-jump version, or grinder dwell on top of it.
Every edit is asserted to match exactly once.

Usage:  python3 tools/fish-jump/build/make_harpoon_blend.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT.parent
OUT = ROOT / "studio" / "harpoon-blend"
BASES = {
    "jump": ROOT / "studio" / "FishSwimClient.patched.lua",
    "dwell-jump": TOOLS / "grinder-dwell" / "studio" / "FishSwimClient.patched.from-jump.lua",
}

HEADER = """--
-- [HarpoonBlend patch] A fish harpooned mid-jump starts its pull from where it
-- is in the air and eases down onto the rope, instead of snapping to the
-- water. Changes marked "HarpoonBlend".
"""


class Patch:
    def __init__(self, base: str):
        self.src = base

    def rep(self, old: str, new: str) -> None:
        n = self.src.count(old)
        assert n == 1, f"expected 1 match, got {n}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


def blend(base: str) -> str:
    p = Patch(base)
    first = base.split("\n", 1)[0] + "\n"
    p.rep(first, first + HEADER)
    p.rep(
        "local function addFish(m)\n",
        "-- HarpoonBlend: the server aims at the swim line; if the fish was mid-jump at\n"
        "-- the hit, its height above that line (cached per hit). Zero without jumps.\n"
        "local function harpoonLift(f)\n"
        "\tif not Jump then return Vector3.zero end\n"
        "\tif f.hLiftT ~= f.harpoonT then\n"
        "\t\tf.hLiftT = f.harpoonT\n"
        "\t\tlocal sp, sd = swimPos(f, f.harpoonT)\n"
        "\t\tlocal jp = jumpAt(f, f.harpoonT, sp, sd)\n"
        "\t\tf.hLift = Vector3.new(0, math.max(0, jp.Y - sp.Y), 0)\n"
        "\tend\n"
        "\treturn f.hLift\n"
        "end\n"
        "\n"
        "local function addFish(m)\n",
    )
    p.rep(
        "\t\t\t\tpos = f.hHit:Lerp(f.hBack, u) + Vector3.new(0, math.sin(u * math.pi) * 2, 0)\n",
        "\t\t\t\tpos = f.hHit:Lerp(f.hBack, u) + Vector3.new(0, math.sin(u * math.pi) * 2, 0)\n"
        "\t\t\t\t\t+ harpoonLift(f) * (1 - u) -- HarpoonBlend: from the air down onto the rope\n",
    )
    return p.src


def build() -> dict:
    """{label: (base, patched)}"""
    return {label: (path.read_text(), blend(path.read_text())) for label, path in BASES.items()}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.lua"):
        old.unlink()
    for label, (_, src) in build().items():
        path = OUT / f"FishSwimClient.patched.from-{label}.lua"
        path.write_text(src)
        print(f"wrote {path.relative_to(TOOLS.parent)}")


if __name__ == "__main__":
    main()
