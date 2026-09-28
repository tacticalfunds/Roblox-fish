#!/usr/bin/env python3
"""Runs the simulations in tests/sim/*_sim.luau on the fake engine
(tests/sim/engine.luau): the REAL EconomyService (+ core modules), the REAL
EconomyClient and, for the sale routes, the REAL patched live scripts.

  prompt_sim: the rod-stand buy prompt (caster only, range, custom panel,
              buy once, cleanup on buy / timeout / pass / death / leave / off)
  sales_sim:  sale payouts through the real patched grinder and truck

Usage:  python3 tools/economy/tests/run_runtime_sim.py [path/to/luau]
Fake-engine simulation only; not a Roblox runtime test.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORE = ["Config", "Pricing", "Ledger", "MoneyStore", "Offers", "PieceTags", "Sales"]


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
    for patched in sorted((ROOT / "studio" / "sales").glob("*.lua")):
        out["Sales_" + patched.stem] = patched.read_text()
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


def main() -> int:
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    only = sys.argv[2] if len(sys.argv) > 2 else None
    return run(luau, sources(), only)


if __name__ == "__main__":
    sys.exit(main())
