#!/usr/bin/env python3
"""Generates tools/fish-variants/InstallFishVariants.lua.

Embeds verbatim: each live script's reviewed base and patched source, the
installed aquarium v1 module sources (guards) and their v1.1 replacements,
and the three new modules.

Usage:  python3 tools/fish-variants/build/build_installer.py
(run build/make_patches.py first if the patches changed)
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
AQ = ROOT.parent / "aquarium-cycle"


def long_string(text: str) -> str:
    level = 0
    while f"]{'=' * level}]" in text or f"[{'=' * level}[" in text or (level == 0 and text.endswith("]")):
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


SCRIPT_BASES = {
    "FishSpawner": ROOT / "studio" / "FishSpawner.original.lua",
    "RodFishingSystem": AQ / "studio" / "RodFishingSystem.patched.lua",
    "NetLiftScript": ROOT / "studio" / "NetLiftScript.original.lua",
    "GrinderProcessor": ROOT / "studio" / "GrinderProcessor.original.lua",
    "TruckSystem": ROOT / "studio" / "TruckSystem.original.lua",
    "CustomerSystem": ROOT / "studio" / "CustomerSystem.original.lua",
}

AQUARIUM_MODULES = {
    "Config": ("Config.luau", AQ / "src" / "shared" / "Config.luau"),
    "SharedTank": ("SharedTank.luau", AQ / "src" / "shared" / "SharedTank.luau"),
    "AquariumCycleServer": ("AquariumCycleServer.luau", AQ / "src" / "server" / "AquariumCycleServer.luau"),
    "AquariumTankClient": ("AquariumTankClient.client.luau", AQ / "src" / "client" / "AquariumTankClient.client.luau"),
}


def main() -> None:
    rows = []
    for name, base in SCRIPT_BASES.items():
        patched = ROOT / "studio" / f"{name}.patched.lua"
        rows.append(
            f'\t{{ name = "{name}", base = {long_string(base.read_text())}, patched = {long_string(patched.read_text())} }},'
        )
    scripts = "{\n" + "\n".join(rows) + "\n}"

    rows = []
    for key, (v1_name, v11_path) in AQUARIUM_MODULES.items():
        v1 = (ROOT / "studio" / "aquarium-v1" / v1_name).read_text()
        rows.append(f'\t{{ key = "{key}", v1 = {long_string(v1)}, v11 = {long_string(v11_path.read_text())} }},')
    aquarium = "{\n" + "\n".join(rows) + "\n}"

    text = (ROOT / "build" / "InstallFishVariants.template.lua").read_text()
    for marker, value in {
        "--[[@SCRIPTS]]": scripts,
        "--[[@AQUARIUM]]": aquarium,
        "--[[@VARIANTS]]": long_string((ROOT / "src" / "FishVariants.luau").read_text()),
        "--[[@VISUALS]]": long_string((ROOT / "src" / "FishVariantVisuals.luau").read_text()),
        "--[[@PAYOUT]]": long_string((ROOT / "src" / "FishPayout.luau").read_text()),
    }.items():
        assert text.count(marker) == 1, marker
        text = text.replace(marker, value)
    out = ROOT / "InstallFishVariants.lua"
    out.write_text(text)
    print(f"wrote {out.relative_to(ROOT.parent.parent)} ({len(text)} chars)")


if __name__ == "__main__":
    main()
