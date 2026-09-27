#!/usr/bin/env python3
"""Generates tools/aquarium-cycle/InstallAquariumCycle.lua.

The installer is a single Studio Command Bar script. It embeds, verbatim:
  * studio/RodFishingSystem.original.lua  (to verify the live script first)
  * studio/RodFishingSystem.patched.lua   (the replacement source)
  * every module under src/shared, src/server and the client LocalScript
so what Astra pastes is exactly what was reviewed and tested.

Usage:  python3 tools/aquarium-cycle/build/build_installer.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "build" / "InstallAquariumCycle.template.lua"
OUT = ROOT / "InstallAquariumCycle.lua"


def long_string(text: str) -> str:
    level = 0
    # Also bump the level when the text ends in "]", which would otherwise
    # merge with the closing bracket.
    while f"]{'=' * level}]" in text or f"[{'=' * level}[" in text or (level == 0 and text.endswith("]")):
        level += 1
    eq = "=" * level
    # A leading newline after [[ is dropped by Lua, so add one to keep text exact.
    return f"[{eq}[\n{text}]{eq}]"


def module_table(paths) -> str:
    rows = []
    for path in paths:
        name = path.name.split(".")[0]
        rows.append(f'\t{{ name = "{name}", source = {long_string(path.read_text())} }},')
    return "{\n" + "\n".join(rows) + "\n}"


def main() -> None:
    shared = sorted((ROOT / "src" / "shared").glob("*.luau"))
    text = TEMPLATE.read_text()
    replacements = {
        "--[[@ORIGINAL]]": long_string((ROOT / "studio" / "RodFishingSystem.original.lua").read_text()),
        "--[[@PATCHED]]": long_string((ROOT / "studio" / "RodFishingSystem.patched.lua").read_text()),
        "--[[@SHARED]]": module_table(shared),
        "--[[@SERVER]]": long_string((ROOT / "src" / "server" / "AquariumCycleServer.luau").read_text()),
        "--[[@ECONOMY]]": long_string((ROOT / "src" / "server" / "AquariumEconomy.luau").read_text()),
        "--[[@CLIENT]]": long_string((ROOT / "src" / "client" / "AquariumTankClient.client.luau").read_text()),
    }
    for marker, value in replacements.items():
        assert text.count(marker) == 1, marker
        text = text.replace(marker, value)
    OUT.write_text(text)
    print(f"wrote {OUT.relative_to(ROOT.parent.parent)} ({len(text)} chars, {len(shared)} shared modules)")


if __name__ == "__main__":
    main()
