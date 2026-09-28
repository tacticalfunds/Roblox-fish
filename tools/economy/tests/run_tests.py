#!/usr/bin/env python3
"""Offline test runner for tools/economy.

The shared modules use Studio Instance requires (`require(script.Parent.X)`),
which the standalone Luau CLI can't resolve. This copies src/core into a
temporary directory, rewrites those requires to CLI paths (`require("./X")`),
copies the tests next to it and runs each *.test.luau with `luau`.

Usage:  python3 tools/economy/tests/run_tests.py [path/to/luau]
These are pure-logic tests only; they are not Roblox runtime tests.
"""
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
REQUIRE = re.compile(r"require\(script\.Parent\.(\w+)\)")
AQUARIUM_V1_COMMIT = "2e320f9"
AQUARIUM_V1 = ["Adapters", "Config", "CycleState", "Messages", "RiverRelease", "SharedTank", "TankPath", "Upgrades"]


def main() -> int:
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        (tmp / "src").mkdir()
        (tmp / "tests").mkdir()
        for module in sorted((ROOT / "src" / "core").glob("*.luau")):
            text = REQUIRE.sub(r'require("./\1")', module.read_text())
            if "script." in text:
                print(f"{module.name}: unexpected Instance access left after rewrite", file=sys.stderr)
                return 1
            (tmp / "src" / module.name).write_text(text)
        # The aquarium core AS INSTALLED IN STUDIO (v1, commit 2e320f9 - Astra
        # confirmed the live AquariumCycleServer is that version), for the
        # rod-offer integration tests. Read from git so it can't drift.
        (tmp / "src" / "aquarium").mkdir()
        for name in AQUARIUM_V1:
            text = subprocess.run(
                ["git", "show", f"{AQUARIUM_V1_COMMIT}:tools/aquarium-cycle/src/shared/{name}.luau"],
                cwd=ROOT, capture_output=True, text=True, check=True,
            ).stdout
            (tmp / "src" / "aquarium" / f"{name}.luau").write_text(REQUIRE.sub(r'require("./\1")', text))
        tests = sorted((ROOT / "tests").glob("*.test.luau"))
        for test in tests:
            shutil.copy(test, tmp / "tests" / test.name)
        failed = 0
        for test in tests:
            print(f"== {test.name}")
            result = subprocess.run([luau, str(tmp / "tests" / test.name)])
            if result.returncode != 0:
                failed += 1
        print(f"{len(tests) - failed}/{len(tests)} test files passed")
        return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
