#!/usr/bin/env python3
"""Generates the Blender Bot recovery patch -> tools/economy/studio/bot/BotSystem.lua.

Base = the sales-patched BotSystem (studio/sales/BotSystem.lua, as
InstallSales writes it). Every trip runs under pcall: if anything errors
while the bot has a piece in its hands, the loose clone is removed and the
piece is HELD in the ledger (the grinder brings it back out of the pipe,
same as a full stack), so it is never lost unpaid; the bot then carries on.
Before, one error stopped the script for good and stranded the piece.

Every edit is asserted to match exactly once.

Usage:  python3 tools/economy/build/make_bot.py
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import make_patches as mp  # noqa: E402

ROOT = mp.ROOT
BASE = ROOT / "studio" / "sales" / "BotSystem.lua"
OUT = ROOT / "studio" / "bot"


def bot(src: str) -> str:
    p = mp.Patch(src)
    p.rep(
        "-- variant, tier, value), so the customer sale pays the right owner once.\n",
        "-- variant, tier, value), so the customer sale pays the right owner once.\n"
        "--\n"
        "-- [Bot recovery patch] Each trip runs under pcall. If anything errors while\n"
        "-- the bot holds a piece (between the stack and the table), the loose clone is\n"
        "-- removed and the piece is held in the ledger: the grinder brings it back out\n"
        "-- of the pipe, so it is never lost unpaid. The bot then carries on (it used to\n"
        "-- stop for good). Changes are marked \"Recovery\".\n",
    )
    p.rep(
        "pose(0, 0)\nwhile true do\n\tlocal slot = freeSlot()\n",
        "-- Recovery: the piece in the bot's hands, from leaving the stack until it lies\n"
        "-- on the table ({ pieceId = id?, part = clone? })\n"
        "local inHand = nil\n"
        "\n"
        "local function trip()\n\tlocal slot = freeSlot()\n",
    )
    p.rep(
        "\t\tidle(0.6)\n\t\tcontinue\n\tend\n",
        "\t\tidle(0.6)\n\t\treturn\n\tend\n",
    )
    p.rep(
        "\tif not meat then continue end\n",
        "\tif not meat then return end\n",
    )
    p.rep(
        "\tlocal tags = Economy and Economy.readPiece(meat) -- Economy: keep the piece's identity\n"
        "\tmeat:Destroy()\n"
        "\tlocal c = meatTemplate:Clone()\n",
        "\tlocal tags = Economy and Economy.readPiece(meat) -- Economy: keep the piece's identity\n"
        "\tinHand = { pieceId = tags and tags.PieceId } -- Recovery\n"
        "\tmeat:Destroy()\n"
        "\tlocal c = meatTemplate:Clone()\n"
        "\tinHand.part = c -- Recovery\n",
    )
    p.rep(
        "\tc.Parent = saleMeat\n\tidle(0.25)\nend",
        "\tc.Parent = saleMeat\n"
        "\tinHand = nil -- Recovery: on the table, the customer sale takes it from here\n"
        "\tidle(0.25)\n"
        "end\n"
        "\n"
        "-- Recovery: whatever the bot was holding goes back to the ledger (held: the\n"
        "-- grinder re-emits it), never lost unpaid. (Once it lies on the table inHand\n"
        "-- is already nil: the customer sale takes it from there.)\n"
        "local function recover()\n"
        "\tcarried = nil\n"
        "\tlocal h = inHand\n"
        "\tinHand = nil\n"
        "\tif not h then return end\n"
        "\tif Economy and h.pieceId then\n"
        "\t\tpcall(Economy.hold, h.pieceId)\n"
        "\tend\n"
        "\tif h.part then pcall(function() h.part:Destroy() end) end\n"
        "end\n"
        "\n"
        "pose(0, 0)\n"
        "local fails = 0\n"
        "while true do\n"
        "\tlocal ok, err = pcall(trip)\n"
        "\tif ok then\n"
        "\t\tfails = 0\n"
        "\telse\n"
        "\t\tfails += 1\n"
        "\t\trecover()\n"
        "\t\tif fails == 1 or fails % 20 == 0 then\n"
        "\t\t\twarn(\"[BotSystem] trip failed (\" .. fails .. \"x), piece kept, retrying: \" .. tostring(err))\n"
        "\t\tend\n"
        "\t\ttask.wait(math.min(5, fails)) -- back off while something stays broken\n"
        "\tend\n"
        "end",
    )
    assert "continue" not in p.src.split("local function trip()")[1].split("local function recover()")[0]
    return p.src


def build() -> str:
    return bot(BASE.read_text())


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "BotSystem.lua").write_text(build())
    print(f"wrote {(OUT / 'BotSystem.lua').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
