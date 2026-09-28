#!/usr/bin/env python3
"""Runs tests/runtime_sim.luau: the REAL EconomyService (+ core modules) and
the REAL EconomyClient against a small fake engine (signals, virtual clock,
remotes, a ProximityPrompt model). Covers the rod-stand buy prompt: caster
only, range, the custom panel, buy once, and cleanup on buy / timeout / pass /
death / leave / switch-off.

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


def sources() -> dict:
    out = {name: (ROOT / "src" / "core" / f"{name}.luau").read_text() for name in CORE}
    out["EconomyService"] = (ROOT / "src" / "server" / "EconomyService.luau").read_text()
    out["EconomyClient"] = (ROOT / "src" / "client" / "EconomyClient.client.luau").read_text()
    return out


def run(luau: str, srcs: dict) -> int:
    prelude = "SOURCES = {\n" + "".join(f"\t{k} = {long_string(v)},\n" for k, v in srcs.items()) + "}\n"
    body = (ROOT / "tests" / "runtime_sim.luau").read_text()
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "runtime_sim.luau"
        path.write_text(prelude + body)
        return subprocess.run([luau, str(path)]).returncode


def main() -> int:
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    return run(luau, sources())


if __name__ == "__main__":
    sys.exit(main())
