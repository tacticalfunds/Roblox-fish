#!/usr/bin/env python3
"""Generates tools/economy/UpdateRodPrompt.lua: the guarded update from the
installed rod-offers commit 8cb2554 to the rod-stand buy prompt. The 8cb2554
sources are read from git, so the update's checks match exactly what that
installer wrote. Runs build_rod_offers_installer.py first (fresh installer).

Usage:  python3 tools/economy/build/build_rod_prompt_update.py
"""
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import build_rod_offers_installer as bi  # noqa: E402

ROOT = bi.ROOT
BASE_COMMIT = "8cb2554"
# key -> path of its source (relative to tools/economy), as the installer writes it
PATHS = {
    "RodFishingSystem": "studio/rod-offers/RodFishingSystem.lua",
    "RodShopServer": "studio/rod-offers/RodShopServer.lua",
    "EconomyService": "src/server/EconomyService.luau",
    "EconomyClient": "src/client/EconomyClient.client.luau",
    **{name: f"src/core/{name}.luau" for name in bi.CORE},
}


def at_base(rel: str) -> str:
    return subprocess.run(
        ["git", "show", f"{BASE_COMMIT}:tools/economy/{rel}"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout


def main() -> None:
    if "--rebuild-release" not in sys.argv:
        sys.exit(
            "InstallRodOffers.lua / UpdateRodPrompt.lua are FROZEN at the a826d73 release installed in Studio;"
            " later milestones ship as update installers (build/build_updates.py)."
            " Pass --rebuild-release only when cutting a new fresh-install release."
        )
    bi.main()
    changes, unchanged = [], []
    for key, rel in PATHS.items():
        old = at_base(rel)
        new = (ROOT / rel).read_text()
        if old == new:
            unchanged.append(f'\t{{ key = "{key}", source = {bi.long_string(old)} }},')
        else:
            changes.append(f'\t{{ key = "{key}", old = {bi.long_string(old)}, new = {bi.long_string(new)} }},')
    names = [c.split('"')[1] for c in changes]
    assert names == ["RodFishingSystem", "EconomyService", "EconomyClient", "Config", "Offers"], names
    text = (ROOT / "build" / "UpdateRodPrompt.template.lua").read_text()
    for marker, value in {
        "--[[@CHANGES]]": "{\n" + "\n".join(changes) + "\n}",
        "--[[@UNCHANGED]]": "{\n" + "\n".join(unchanged) + "\n}",
    }.items():
        assert text.count(marker) == 1, marker
        text = text.replace(marker, value)
    out = ROOT / "UpdateRodPrompt.lua"
    out.write_text(text)
    print(f"wrote {out.relative_to(ROOT.parent.parent)} ({len(text)} chars; changes {', '.join(names)})")


if __name__ == "__main__":
    main()
