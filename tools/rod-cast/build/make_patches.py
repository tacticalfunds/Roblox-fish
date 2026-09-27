#!/usr/bin/env python3
"""Regenerates the immediate-cast patches with asserted edits.

Server (RodFishingSystem), two supported bases:
  * variants-installed: tools/fish-variants/studio/RodFishingSystem.patched.lua
  * aquarium-only:      tools/aquarium-cycle/studio/RodFishingSystem.patched.lua
The same edits apply to both; the installer picks whichever base is live.

Client (RodFishingClient): studio/RodFishingClient.original.lua (supplied live source).

Usage:  python3 tools/rod-cast/build/make_patches.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT.parent
SERVER_BASES = {
    "variants": TOOLS / "fish-variants" / "studio" / "RodFishingSystem.patched.lua",
    "aquarium": TOOLS / "aquarium-cycle" / "studio" / "RodFishingSystem.patched.lua",
}


class Patch:
    def __init__(self, base: str):
        self.src = base

    def rep(self, old: str, new: str) -> None:
        count = self.src.count(old)
        assert count == 1, f"expected 1 match, got {count}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


def server(base: str) -> str:
    p = Patch(base)
    p.rep(
        "-- ServerStorage.AquariumCycleBackup by the installer.\n",
        "-- ServerStorage.AquariumCycleBackup by the installer.\n"
        "--\n"
        "-- [RodCast patch v1] Changes marked \"RodCast\": an accepted press casts every\n"
        "-- eligible rod at once, right away (no 0.45 s press delay, no 0.12 s stagger),\n"
        "-- and each rod gets a CastT0 attribute so clients dip it toward the water\n"
        "-- immediately. Cooldown, busy checks and the aquarium slot reservation are\n"
        "-- unchanged; a rejected press starts nothing and doesn't animate the button.\n",
    )
    # rod visibly lowers from the moment its cast starts
    p.rep(
        "local function runRod(rod, player)\n\trod.state = \"busy\"\n",
        "local function runRod(rod, player)\n"
        "\trod.state = \"busy\"\n"
        "\trod.model:SetAttribute(\"CastT0\", workspace:GetServerTimeNow()) -- RodCast: clients dip the rod now\n",
    )
    # hand over to the existing reel animation
    p.rep(
        "\tlocal t0 = workspace:GetServerTimeNow()\n\trod.model:SetAttribute(\"PullT0\", t0)\n",
        "\tlocal t0 = workspace:GetServerTimeNow()\n"
        "\trod.model:SetAttribute(\"CastT0\", nil) -- RodCast: the reel animation takes over\n"
        "\trod.model:SetAttribute(\"PullT0\", t0)\n",
    )
    # error path: never leave a rod stuck lowered
    p.rep(
        "\t\trod.model:SetAttribute(\"Pulling\", false)\n\tend\n\trod.temp = nil\n",
        "\t\trod.model:SetAttribute(\"Pulling\", false)\n"
        "\tend\n"
        "\trod.model:SetAttribute(\"CastT0\", nil) -- RodCast\n"
        "\trod.temp = nil\n",
    )
    # press(): synchronous, returns whether it was accepted, no stagger
    p.rep(
        "local function press(player)\n\tif not ready then return end\n\tif not anyIdle() then return end\n",
        "-- RodCast: returns true when the press was accepted. Runs without yielding,\n"
        "-- so ready/busy are claimed before any other press can be handled.\n"
        "local function press(player)\n\tif not ready then return false end\n\tif not anyIdle() then return false end\n",
    )
    p.rep(
        "\t\ttoCast = Aquarium.reserve(toCast, player)\n\t\tif #toCast == 0 then return end\n",
        "\t\ttoCast = Aquarium.reserve(toCast, player)\n\t\tif #toCast == 0 then return false end\n",
    )
    p.rep(
        "\t\t\tif not ready then setReady(true) end\n\t\tend)\n\t\ttask.wait(0.12)\n\tend\nend\n",
        "\t\t\tif not ready then setReady(true) end\n\t\tend)\n"
        "\t\t-- RodCast: no per-rod stagger; every eligible rod casts together\n"
        "\tend\n\treturn true\nend\n",
    )
    p.rep(
        "local PRESS_DELAY = 0.45   -- small pause after the click before the rods cast\n",
        "-- RodCast: PRESS_DELAY (0.45 s) removed; accepted presses cast immediately\n",
    )
    p.rep(
        "\tbutton:SetAttribute(\"PressedAt\", workspace:GetServerTimeNow())\n"
        "\ttask.delay(PRESS_DELAY, function() press(player) end)\n",
        "\t-- RodCast: cast right away; the button only animates for others if accepted\n"
        "\tif press(player) then\n"
        "\t\tbutton:SetAttribute(\"PressedAt\", workspace:GetServerTimeNow())\n"
        "\tend\n",
    )
    return p.src


def client() -> str:
    p = Patch((ROOT / "studio" / "RodFishingClient.original.lua").read_text())
    p.rep(
        "--  * rods bend back and tug while reeling\n",
        "--  * rods bend back and tug while reeling\n"
        "--  * [RodCast patch v1] rods dip toward the water the moment they cast (server\n"
        "--    sets CastT0) and stay low until the reel starts\n",
    )
    p.rep(
        "local rodAng = {}\n",
        "-- RodCast: signed dip in degrees while the line is out (negative lowers the tip\n"
        "-- toward the river at +X). If rods tilt UP on cast in Studio, flip the sign.\n"
        "local CAST_DIP_DEG = -14\n"
        "local CAST_DOWN_SECONDS = 0.18\n"
        "\n"
        "local rodAng = {}\n",
    )
    p.rep(
        "\t\t\t\tang = math.rad(9) * math.min(1, e * 3) + math.rad(4) * math.sin(e * 11) + math.rad(2) * math.sin(e * 23)\n"
        "\t\t\tend\n",
        "\t\t\t\tang = math.rad(9) * math.min(1, e * 3) + math.rad(4) * math.sin(e * 11) + math.rad(2) * math.sin(e * 23)\n"
        "\t\t\telseif m:GetAttribute(\"CastT0\") then\n"
        "\t\t\t\t-- RodCast: dip right away, then rest low with a gentle sway while waiting for a bite\n"
        "\t\t\t\tlocal e = math.max(0, now - m:GetAttribute(\"CastT0\"))\n"
        "\t\t\t\tang = math.rad(CAST_DIP_DEG) * math.min(1, e / CAST_DOWN_SECONDS)\n"
        "\t\t\t\t\t+ math.rad(1.2) * math.sin(e * 2.2) * math.min(1, e)\n"
        "\t\t\tend\n",
    )
    return p.src


def main() -> None:
    for name, path in SERVER_BASES.items():
        out = ROOT / "studio" / f"RodFishingSystem.patched.from-{name}.lua"
        out.write_text(server(path.read_text()))
        print(f"wrote {out.relative_to(TOOLS.parent)}")
    out = ROOT / "studio" / "RodFishingClient.patched.lua"
    out.write_text(client())
    print(f"wrote {out.relative_to(TOOLS.parent)}")


if __name__ == "__main__":
    main()
