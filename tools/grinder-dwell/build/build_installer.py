#!/usr/bin/env python3
"""Generates tools/grinder-dwell/InstallGrinderDwell.lua (run make_patches.py first).

Also asserts client/server timing stay in sync: every patched FishSwimClient
takes its launch timeline from GrinderDwell, and every patched NetLiftScript
fires/destroys at GrinderDwell.serverDelay().

Usage:  python3 tools/grinder-dwell/build/build_installer.py
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import make_patches as mp  # noqa: E402

ROOT = mp.ROOT


def long_string(text: str) -> str:
    level = 0
    while f"]{'=' * level}]" in text or f"[{'=' * level}[" in text or (level == 0 and text.endswith("]")):
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


LOCAL = {"FishSwimClient": True, "NetLiftScript": False, "RodFishingSystem": False}
SYNC = {
    "FishSwimClient": ["LAUNCH_RISE, LAUNCH_FLY, LAUNCH_DROP = Dwell.Rise, Dwell.Fly, Dwell.Drop", "Dwell.dwellOffset", "Dwell.dropOffset"],
    "NetLiftScript": ["Dwell.serverDelay()", "task.delay(CATCH_DELAY"],
    "RodFishingSystem": ["Dwell.dwellOffset", "Dwell.dropOffset", "Dwell.Dwell + Dwell.Drop"],
}


def main() -> None:
    rows = []
    for name, bases in mp.BASES.items():
        cands = []
        for label, base in bases.items():
            patched = (mp.OUT / f"{name}.patched.from-{label}.lua").read_text()
            for needle in SYNC[name]:
                assert needle in patched, f"{name} ({label}) missing sync point {needle!r}"
            cands.append(f'{{ label = "{label}", base = {long_string(base.read_text())}, patched = {long_string(patched)} }}')
        rows.append(
            f'\t{{ name = "{name}", localScript = {str(LOCAL[name]).lower()}, candidates = {{\n\t\t'
            + ",\n\t\t".join(cands)
            + "\n\t} },"
        )
    targets = "{\n" + "\n".join(rows) + "\n}"
    text = (ROOT / "build" / "InstallGrinderDwell.template.lua").read_text()
    for marker, value in {
        "--[[@TARGETS]]": targets,
        "--[[@MODULE]]": long_string((ROOT / "src" / "GrinderDwell.luau").read_text()),
    }.items():
        assert text.count(marker) == 1, marker
        text = text.replace(marker, value)
    out = ROOT / "InstallGrinderDwell.lua"
    out.write_text(text)
    print(f"wrote {out.relative_to(ROOT.parent.parent)} ({len(text)} chars); client/server timing sync verified")


if __name__ == "__main__":
    main()
