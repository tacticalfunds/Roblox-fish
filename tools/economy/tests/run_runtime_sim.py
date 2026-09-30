#!/usr/bin/env python3
"""Runs the simulations in tests/sim/*_sim.luau on the fake engine
(tests/sim/engine.luau): the REAL EconomyService (+ core modules), the REAL
EconomyClient and, for the sale routes, the REAL patched live scripts.

  prompt_sim: the rod-stand buy prompt (caster only, range, custom panel,
              buy once, cleanup on buy / timeout / pass / death / leave / off)
  sales_sim:  sale payouts through the real patched grinder and truck
  panel_sim:  the aquarium panel (patched AquariumCycleServer + AquariumPanelClient)
  moneyhud_sim: the new MoneyController on leaderstats.Money (and the live
              one stuck on the missing FormatModule)

Usage:  python3 tools/economy/tests/run_runtime_sim.py [path/to/luau]
Fake-engine simulation only; not a Roblox runtime test.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORE = ["Config", "Pricing", "Ledger", "MoneyStore", "Offers", "PieceTags", "Sales", "Rods", "NetKg", "BoardUpgrades"]


def long_string(text: str) -> str:
    level = 0
    while f"]{'=' * level}]" in text or f"[{'=' * level}[" in text or text.endswith("]"):
        level += 1
    eq = "=" * level
    return f"[{eq}[\n{text}]{eq}]"


SIM = ROOT / "tests" / "sim"


def sources() -> dict:
    out = {name: (ROOT / "src" / "core" / f"{name}.luau").read_text() for name in CORE}
    out["EconomyService"] = (ROOT / "src" / "server" / "EconomyService.luau").read_text()
    out["EconomyClient"] = (ROOT / "src" / "client" / "EconomyClient.client.luau").read_text()
    out["MoneyController"] = (ROOT / "src" / "client" / "MoneyController.client.luau").read_text()
    out["Live_MoneyController"] = (ROOT / "studio" / "live" / "MoneyController.lua").read_text()
    for patched in sorted((ROOT / "studio" / "sales").glob("*.lua")):
        out["Sales_" + patched.stem] = patched.read_text()
    out["Bot_Recovery"] = (ROOT / "studio" / "bot" / "BotSystem.lua").read_text()
    # aquarium v1.2 pure modules + the economy's AquariumEconomy binding
    for module in sorted((ROOT.parent / "aquarium-cycle" / "src" / "shared").glob("*.luau")):
        out["Aq_" + module.stem] = module.read_text()
    out["AquariumEconomy"] = (ROOT / "src" / "server" / "AquariumEconomy.luau").read_text()
    # visual features (rebased on the live scripts)
    jump = ROOT.parent / "fish-jump"
    out["Jump_Module"] = (jump / "src" / "FishJump.luau").read_text()
    out["Jump_Client"] = (jump / "studio" / "FishSwimClient.patched.lua").read_text()
    out["Live_FishSwimClient"] = (ROOT / "studio" / "live" / "FishSwimClient.lua").read_text()
    rodcast = ROOT.parent / "rod-cast" / "studio"
    out["RodCast_Server"] = (rodcast / "RodFishingSystem.patched.from-sales.lua").read_text()
    out["RodCast_Client"] = (rodcast / "RodFishingClient.patched.lua").read_text()
    dwell = ROOT.parent / "grinder-dwell"
    out["Dwell_Module"] = (dwell / "src" / "GrinderDwell.luau").read_text()
    out["Dwell_Client"] = (dwell / "studio" / "FishSwimClient.patched.from-jump.lua").read_text()
    out["Dwell_Rod"] = (dwell / "studio" / "RodFishingSystem.patched.from-rodcast.lua").read_text()
    var = ROOT.parent / "fish-variants"
    out["Var_Rules"] = (var / "src" / "FishVariants.luau").read_text()
    out["Var_Visuals"] = (var / "src" / "FishVariantVisuals.luau").read_text()
    out["Var_Spawner"] = (var / "studio" / "economy" / "FishSpawner.patched.from-live.lua").read_text()
    out["Var_Rod"] = (var / "studio" / "economy" / "RodFishingSystem.patched.from-sales.lua").read_text()
    out["Var_Grinder"] = (var / "studio" / "economy" / "GrinderProcessor.patched.from-sales.lua").read_text()
    blend = jump / "studio" / "harpoon-blend"
    out["Blend_Jump"] = (blend / "FishSwimClient.patched.from-jump.lua").read_text()
    out["Blend_Dwell"] = (blend / "FishSwimClient.patched.from-dwell-jump.lua").read_text()
    out["Rods_Shop"] = (ROOT / "studio" / "rods" / "RodShopServer.lua").read_text()
    out["Rods_Fishing"] = (ROOT / "studio" / "rods" / "RodFishingSystem.lua").read_text()
    out["Board_Fishing"] = (ROOT / "studio" / "board" / "RodFishingSystem.lua").read_text()
    out["Kg_Server"] = (ROOT / "src" / "server" / "NetCapacityServer.server.luau").read_text()
    out["Kg_Client"] = (ROOT / "src" / "client" / "KgSignClient.client.luau").read_text()
    out["Board_Server"] = (ROOT / "src" / "server" / "UpgradeBoardServer.server.luau").read_text()
    out["NetLift_Live"] = (ROOT / "studio" / "live" / "NetLiftScript.grinder.lua").read_text()
    out["Grinder_Config"] = (ROOT / "studio" / "live" / "GrinderUpgradesConfig.lua").read_text()
    out["Grinder_Server"] = (ROOT / "studio" / "grinder" / "GrinderUpgradesServer.lua").read_text()
    out["Grinder_Client"] = (ROOT / "studio" / "grinder" / "GrinderUpgradesClient.lua").read_text()
    out["Board_Client"] = (ROOT / "src" / "client" / "UpgradeBoardClient.client.luau").read_text()
    out["Rods_ShopUI"] = (ROOT / "studio" / "rods" / "RodShopController.lua").read_text()
    out["Live_RodShopController"] = (ROOT / "studio" / "live" / "RodShopController.lua").read_text()
    panel = ROOT.parent / "aquarium-panel"
    out["Panel_Server"] = (panel / "studio" / "AquariumCycleServer.patched.from-v12.lua").read_text()
    out["AquariumPanelClient"] = (panel / "src" / "AquariumPanelClient.client.luau").read_text()
    glow = var / "studio" / "meat-glow"
    out["MG_Bot_sales"] = (glow / "BotSystem.patched.from-sales.lua").read_text()
    out["MG_Bot_bot"] = (glow / "BotSystem.patched.from-bot.lua").read_text()
    out["MG_Customer"] = (glow / "CustomerSystem.patched.from-sales.lua").read_text()
    out["MG_Truck"] = (glow / "TruckSystem.patched.from-sales.lua").read_text()
    return out


def run(luau: str, srcs: dict, only: str | None = None) -> int:
    prelude = "SOURCES = {\n" + "".join(f"\t{k} = {long_string(v)},\n" for k, v in srcs.items()) + "}\n"
    engine = (SIM / "engine.luau").read_text()
    failed = 0
    for scenario in sorted(SIM.glob("*_sim.luau")):
        if only and scenario.stem != only:
            continue
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / scenario.name
            path.write_text(prelude + engine + "\ndo\n" + scenario.read_text() + "\nend\n")
            print(f"== {scenario.name}")
            if subprocess.run([luau, str(path)]).returncode != 0:
                failed += 1
    return 1 if failed else 0


# sims that load ReplicatedStorage.FishJump: also run with the JumpRate
# version (tools/fish-jump InstallJumpRate), which only changes its periods
JUMP_SIMS = ["jump_sim", "harpoonblend_sim", "dwell_sim"]
BOARD_FISHING_SIMS = ["rods_sim"]


def main() -> int:
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    only = sys.argv[2] if len(sys.argv) > 2 else None
    srcs = sources()
    failed = run(luau, srcs, only)
    rate = dict(srcs, Jump_Module=(ROOT.parent / "fish-jump" / "studio" / "jump-rate" / "FishJump.luau").read_text())
    for name in JUMP_SIMS:
        if only in (None, name):
            print("-- with the JumpRate FishJump module:")
            failed |= run(luau, rate, name)
    # the rods sims again on the upgrade board's RodFishingSystem (Rod Luck
    # 1x everywhere there): nothing about rods may change
    board = dict(srcs, Rods_Fishing=srcs["Board_Fishing"])
    for name in BOARD_FISHING_SIMS:
        if only in (None, name):
            print("-- with the upgrade board's RodFishingSystem:")
            failed |= run(luau, board, name)
    return failed


if __name__ == "__main__":
    sys.exit(main())
