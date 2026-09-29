#!/usr/bin/env python3
"""Generates tools/aquarium-panel/InstallAquariumPanel.lua and
RollbackAquariumPanel.lua (the economy's v2 guarded template).

  changes  ServerScriptService.AquariumCycleServer: aquarium v1.2 (as
           UpgradeAquariumV12 installed it) -> the panel version
  adds     StarterPlayer.StarterPlayerScripts.AquariumPanelClient
  checks   ReplicatedStorage.AquariumCycle.Config / Upgrades are exactly
           v1.2 (the client reads their upgrade tables)

Usage:  python3 tools/aquarium-panel/build/build_installer.py
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = ROOT.parent.parent
sys.path.insert(0, str(ROOT / "build"))
sys.path.insert(0, str(REPO / "tools" / "economy" / "build"))
import build_updates as bu  # noqa: E402
import make_panel  # noqa: E402


def git_show(path: str) -> str:
    return subprocess.run(
        ["git", "show", f"{make_panel.SALES_RELEASE}:{path}"], cwd=REPO, capture_output=True, text=True, check=True
    ).stdout


def main() -> None:
    make_panel.main()
    base = make_panel.v12_server()
    new = make_panel.OUT.read_text()
    client = (ROOT / "src" / "AquariumPanelClient.client.luau").read_text()
    unchanged = [
        (
            {"key": name, "where": f"ReplicatedStorage/AquariumCycle/{name}", "class": "ModuleScript", "tag": "AquariumCycleOwned", "tagOnParent": True},
            git_show(f"tools/aquarium-cycle/src/shared/{name}.luau"),
        )
        for name in ("Config", "Upgrades")
    ]
    keys = bu.write_pair_v2(
        "InstallAquariumPanel.lua",
        "RollbackAquariumPanel.lua",
        """
Aquarium panel: ONE compact panel at the loader pad instead of the three
stacked default prompts (E Release Fish, F Capacity, G Release Rate).
  * Release Fish on top ([E] / gamepad X / tap) with the tank count
  * one upgrade card at a time (Tank Capacity or Release Amount), switched
    with < > / Left-Right arrows / D-pad; its button is [F] / gamepad Y / tap
  * paid upgrades are NOT installed (levels aren't saved): the card says
    "Not available yet" and no upgrade prompt exists, so nothing can be
    bought. Release works as before.
The server's prompts stay native ProximityPrompts (Style = Custom: no
default UI) with the same server checks; the client only draws the panel
and picks which card's prompt is on. The CountPrompt binding is untouched;
the old placeholder prompt and its billboard stay hidden while the aquarium
runs. Changes ServerScriptService.AquariumCycleServer (v1.2 -> panel) and
adds StarterPlayerScripts.AquariumPanelClient.
Requires: aquarium v1.2 (EconomyAquariumBackup). Note: the paid-upgrades
installer as released (InstallUpgrades) checks the v1.2 server and refuses
after this; paid upgrades need a new installer once persistence is decided.
""",
        "AquariumPanelBackup",
        [["EconomyAquariumBackup"]],
        ["AquariumPanelBackup"],
        [],
        [({"key": "AquariumCycleServer", "where": "ServerScriptService/AquariumCycleServer", "class": "ModuleScript", "tag": "AquariumCycleOwned"}, [("v12", base, new)])],
        unchanged,
        [{"where": "StarterPlayer/StarterPlayerScripts", "name": "AquariumPanelClient", "class": "LocalScript", "source": client}],
        ROOT,
    )
    assert keys == ["AquariumCycleServer"], keys


if __name__ == "__main__":
    main()
