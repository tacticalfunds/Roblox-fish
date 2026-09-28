#!/usr/bin/env python3
"""Generates tools/economy/InstallRodOffers.lua (runs make_rod_offers.py first).

Usage:  python3 tools/economy/build/build_rod_offers_installer.py
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import make_rod_offers as mro  # noqa: E402

ROOT = mro.ROOT
CORE = ["Config", "Pricing", "Ledger", "MoneyStore", "Offers", "PieceTags", "Sales"]


def long_string(text: str) -> str:
    level = 0
    while f"]{'=' * level}]" in text or f"[{'=' * level}[" in text or (level == 0 and text.endswith("]")):
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


def main() -> None:
    if "--rebuild-release" not in sys.argv:
        sys.exit(
            "InstallRodOffers.lua / UpdateRodPrompt.lua are FROZEN at the a826d73 release installed in Studio;"
            " later milestones ship as update installers (build/build_updates.py)."
            " Pass --rebuild-release only when cutting a new fresh-install release."
        )
    mro.main()
    scripts = []
    for name in ("RodFishingSystem", "RodShopServer"):
        base = (mro.LIVE / f"{name}.lua").read_text()
        patched = (mro.OUT / f"{name}.lua").read_text()
        scripts.append(f'\t{{ name = "{name}", base = {long_string(base)}, patched = {long_string(patched)} }},')
    core = []
    for name in CORE:
        src = (ROOT / "src" / "core" / f"{name}.luau").read_text()
        core.append(f'\t{{ name = "{name}", source = {long_string(src)} }},')
    service = (ROOT / "src" / "server" / "EconomyService.luau").read_text()
    for name in CORE:
        assert f"require(script.{name})" in service, name
    store = re.search(r'Config\.DataStoreName = "([^"]+)"', (ROOT / "src" / "core" / "Config.luau").read_text()).group(1)
    text = (ROOT / "build" / "InstallRodOffers.template.lua").read_text()
    for marker, value in {
        "--[[@SCRIPTS]]": "{\n" + "\n".join(scripts) + "\n}",
        "--[[@SERVICE]]": long_string(service),
        "--[[@CORE]]": "{\n" + "\n".join(core) + "\n}",
        "--[[@BOOT]]": long_string((ROOT / "src" / "server" / "EconomyBoot.server.luau").read_text()),
        "--[[@CLIENT]]": long_string((ROOT / "src" / "client" / "EconomyClient.client.luau").read_text()),
        "--[[@STORE]]": store,
    }.items():
        assert text.count(marker) == 1, marker
        text = text.replace(marker, value)
    out = ROOT / "InstallRodOffers.lua"
    out.write_text(text)
    print(f"wrote {out.relative_to(ROOT.parent.parent)} ({len(text)} chars)")


if __name__ == "__main__":
    main()
