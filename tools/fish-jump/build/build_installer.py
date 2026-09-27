#!/usr/bin/env python3
"""Generates tools/fish-jump/InstallFishJump.lua, embedding the reviewed
original FishSwimClient (for the source guard), the patched client and the
FishJump module verbatim.

Usage:  python3 tools/fish-jump/build/build_installer.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent


def long_string(text: str) -> str:
    level = 0
    while f"]{'=' * level}]" in text or f"[{'=' * level}[" in text or (level == 0 and text.endswith("]")):
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


def main() -> None:
    text = (ROOT / "build" / "InstallFishJump.template.lua").read_text()
    for marker, path in {
        "--[[@ORIGINAL]]": ROOT / "studio" / "FishSwimClient.original.lua",
        "--[[@PATCHED]]": ROOT / "studio" / "FishSwimClient.patched.lua",
        "--[[@MODULE]]": ROOT / "src" / "FishJump.luau",
    }.items():
        assert text.count(marker) == 1, marker
        text = text.replace(marker, long_string(path.read_text()))
    out = ROOT / "InstallFishJump.lua"
    out.write_text(text)
    print(f"wrote {out.relative_to(ROOT.parent.parent)} ({len(text)} chars)")


if __name__ == "__main__":
    main()
