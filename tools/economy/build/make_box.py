#!/usr/bin/env python3
"""The live TruckSystem's BoxMeat pickup, RECONSTRUCTED from Astra's
description (2026-10-04) - not the exact live text.

Astra found the live TruckSystem at 15573 chars (the inventory's 15071 is the
MeatGlow version without it): players can also pick meat up from the meat
box (Workspace.BoxMeat), not only from the conveyor's stack. Astra merged the
Sell stall (f2c3933) over it by hand, keeping every box edit
(EconomySellStallBackup holds the exact Before / After).

This writes, so later patches can be built on what Studio really runs:
  studio/live/TruckSystem.box.reconstructed.lua   MeatGlow + box pickup (≈ live Before)
  studio/stall/TruckSystem.box.reconstructed.lua  the stall version + box pickup (≈ installed After)
Both are RECONSTRUCTIONS: no installer targets them. They are replaced by the
exact sources once Astra sends them.

The box edits, as described:
  * after STACK_HALF: BOX_CENTER (-37, 10.05, 148.7), BOX_HALF (6, 0, 5),
    boxMeat = workspace:FindFirstChild("BoxMeat") or workspace:WaitForChild("BoxMeat")
  * topOfStack(folder) loops over (folder or meatStack)
  * pickup: the source is the stack if you stand within its bounds, else the
    box if within its bounds (|dY| < 8); then, if there is a source and you
    carry fewer than MAX_CARRY, the top piece of THAT source
  (the Sell stall stays before the truck branch)

Usage:  python3 tools/economy/build/make_box.py
"""
import pathlib

import make_stall

ROOT = pathlib.Path(__file__).resolve().parent.parent
LIVE_OUT = ROOT / "studio" / "live" / "TruckSystem.box.reconstructed.lua"
STALL_OUT = ROOT / "studio" / "stall" / "TruckSystem.box.reconstructed.lua"
HEADER = (
    "-- RECONSTRUCTED (tools/economy/build/make_box.py): the live BoxMeat pickup as\n"
    "-- described, not the exact live text. No installer targets this file.\n"
)


def with_box(src: str) -> str:
    p = make_stall.Patch(src)
    p.rep(
        "local STACK_HALF = Vector3.new(6.3, 0, 5.5)   -- pickup area around the end box\n",
        "local STACK_HALF = Vector3.new(6.3, 0, 5.5)   -- pickup area around the end box\n"
        "local BOX_CENTER = Vector3.new(-37, 10.05, 148.7)\n"
        "local BOX_HALF = Vector3.new(6, 0, 5)\n"
        "local boxMeat = workspace:FindFirstChild(\"BoxMeat\") or workspace:WaitForChild(\"BoxMeat\")\n",
    )
    p.rep(
        "local function topOfStack()\n"
        "\tlocal best, bi = nil, -1\n"
        "\tfor _, m in ipairs(meatStack:GetChildren()) do\n",
        "local function topOfStack(folder)\n"
        "\tlocal best, bi = nil, -1\n"
        "\tfor _, m in ipairs((folder or meatStack):GetChildren()) do\n",
    )
    p.rep(
        "\t\t\t-- pick up from the stack\n"
        "\t\t\tif math.abs(rel.X) <= STACK_HALF.X and math.abs(rel.Z) <= STACK_HALF.Z and math.abs(rel.Y) < 8 and c.count < MAX_CARRY then\n"
        "\t\t\t\tlocal meat = topOfStack()\n",
        "\t\t\t-- pick up from the stack, or from the meat box\n"
        "\t\t\tlocal src = nil\n"
        "\t\t\tif math.abs(rel.X) <= STACK_HALF.X and math.abs(rel.Z) <= STACK_HALF.Z and math.abs(rel.Y) < 8 then\n"
        "\t\t\t\tsrc = meatStack\n"
        "\t\t\telse\n"
        "\t\t\t\tlocal relBox = pos - BOX_CENTER\n"
        "\t\t\t\tif math.abs(relBox.X) <= BOX_HALF.X and math.abs(relBox.Z) <= BOX_HALF.Z and math.abs(relBox.Y) < 8 then\n"
        "\t\t\t\t\tsrc = boxMeat\n"
        "\t\t\t\tend\n"
        "\t\t\tend\n"
        "\t\t\tif src and c.count < MAX_CARRY then\n"
        "\t\t\t\tlocal meat = topOfStack(src)\n",
    )
    return HEADER + p.src


def main() -> None:
    LIVE_OUT.write_text(with_box(make_stall.BASE.read_text()))
    STALL_OUT.write_text(with_box(make_stall.truck()))
    print(f"wrote {LIVE_OUT.relative_to(ROOT.parent.parent)} + {STALL_OUT.relative_to(ROOT.parent.parent)}")


if __name__ == "__main__":
    main()
