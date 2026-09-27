#!/usr/bin/env python3
"""Generates tools/rod-cast/InstallRodCast.lua (run build/make_patches.py first).

Usage:  python3 tools/rod-cast/build/build_installer.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT.parent


def long_string(text: str) -> str:
    level = 0
    while f"]{'=' * level}]" in text or f"[{'=' * level}[" in text or (level == 0 and text.endswith("]")):
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


def candidate(label: str, base: pathlib.Path, patched: pathlib.Path) -> str:
    return f'{{ label = "{label}", base = {long_string(base.read_text())}, patched = {long_string(patched.read_text())} }}'


def main() -> None:
    studio = ROOT / "studio"
    targets = (
        "{\n"
        '\t{ name = "RodFishingSystem", localScript = false, candidates = {\n\t\t'
        + candidate(
            "variants+aquarium",
            TOOLS / "fish-variants" / "studio" / "RodFishingSystem.patched.lua",
            studio / "RodFishingSystem.patched.from-variants.lua",
        )
        + ",\n\t\t"
        + candidate(
            "aquarium only",
            TOOLS / "aquarium-cycle" / "studio" / "RodFishingSystem.patched.lua",
            studio / "RodFishingSystem.patched.from-aquarium.lua",
        )
        + "\n\t} },\n"
        '\t{ name = "RodFishingClient", localScript = true, candidates = {\n\t\t'
        + candidate("original", studio / "RodFishingClient.original.lua", studio / "RodFishingClient.patched.lua")
        + "\n\t} },\n}"
    )
    text = (ROOT / "build" / "InstallRodCast.template.lua").read_text()
    assert text.count("--[[@TARGETS]]") == 1
    text = text.replace("--[[@TARGETS]]", targets)
    out = ROOT / "InstallRodCast.lua"
    out.write_text(text)
    print(f"wrote {out.relative_to(TOOLS.parent)} ({len(text)} chars)")


if __name__ == "__main__":
    main()
