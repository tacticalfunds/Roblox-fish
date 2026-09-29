#!/usr/bin/env python3
"""Rods milestone 1: the RodFishingSystem side.

Patches the INSTALLED RodFishingSystem (fish variants over grinder dwell over
rod cast over sale payouts: tools/fish-variants/studio/economy/
RodFishingSystem.patched.from-dwell-rodcast.lua) into studio/rods/
RodFishingSystem.lua. Changes, marked "Rods":

  * each accepted press snapshots the PRESSER's equipped rod
    (EconomyService.rodStats) for every rod it casts: another player
    equipping later never changes a cast already under way
  * the bite wait is the old random 3-9 s times the rod's BiteWait, never
    below MIN_BITE_WAIT (2 s): the aquarium only hooks a fish 2.5 s after
    the press (cast 0.2 s + wait + bite 0.6 s)
  * the rod model carries CastRod = the rod id while casting (a hook for
    visuals; nothing reads it yet)
  * no EconomyService / an error: Basic (x1), the old timing

Everything else (immediate cast, aquarium reservations, offers, variants,
dwell, grinder fallback) is untouched.

Usage:  python3 tools/economy/build/make_rods.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT.parent
BASE = TOOLS / "fish-variants" / "studio" / "economy" / "RodFishingSystem.patched.from-dwell-rodcast.lua"
OUT = ROOT / "studio" / "rods" / "RodFishingSystem.lua"


class Patch:
    def __init__(self, base: str):
        self.src = base

    def rep(self, old: str, new: str) -> None:
        n = self.src.count(old)
        assert n == 1, f"expected 1 match, got {n}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


def build() -> str:
    p = Patch(BASE.read_text())
    p.rep(
        "------------------------------------------------------------ pressing the button\n",
        "------------------------------------------------------------ rods (Economy rods v1)\n"
        "-- Rods: the presser's equipped rod, read once per accepted press (Basic\n"
        "-- without the money service or on any error). Its BiteWait scales the wait.\n"
        "local BASIC_ROD = { Id = \"FishingRod1\", BiteWait = 1 }\n"
        "local function rodFor(player)\n"
        "\tif Economy and type(Economy.rodStats) == \"function\" then\n"
        "\t\tlocal ok, rod = pcall(Economy.rodStats, player)\n"
        "\t\tif ok and type(rod) == \"table\" and type(rod.Id) == \"string\" and type(rod.BiteWait) == \"number\"\n"
        "\t\t\tand rod.BiteWait > 0 and rod.BiteWait <= 1 then\n"
        "\t\t\treturn rod\n"
        "\t\tend\n"
        "\tend\n"
        "\treturn BASIC_ROD\n"
        "end\n"
        "\n"
        "------------------------------------------------------------ pressing the button\n",
    )
    p.rep(
        "local WAIT_RANGE = { 3, 9 }   -- seconds a line sits in the water\n",
        "local WAIT_RANGE = { 3, 9 }   -- seconds a line sits in the water\n"
        "local MIN_BITE_WAIT = 2       -- Rods: floor for the rod-shortened wait (the aquarium hooks no earlier than 2.5 s after the press)\n",
    )
    p.rep(
        "\tfor _, rod in ipairs(toCast) do rod.state = \"busy\" rod.offerMode = offerMode end -- Economy: mode fixed per cast\n",
        "\tfor _, rod in ipairs(toCast) do rod.state = \"busy\" rod.offerMode = offerMode end -- Economy: mode fixed per cast\n"
        "\t-- Rods: the presser's rod, fixed for this cast (someone equipping later changes nothing)\n"
        "\tlocal castRod = rodFor(player)\n"
        "\tfor _, rod in ipairs(toCast) do rod.biteWait = castRod.BiteWait rod.castRodId = castRod.Id end\n",
    )
    p.rep(
        "\ttask.wait(math.random(WAIT_RANGE[1] * 10, WAIT_RANGE[2] * 10) / 10)\n",
        "\t-- Rods: the equipped rod shortens the wait (never below MIN_BITE_WAIT)\n"
        "\ttask.wait(math.max(MIN_BITE_WAIT, math.random(WAIT_RANGE[1] * 10, WAIT_RANGE[2] * 10) / 10 * (rod.biteWait or 1)))\n",
    )
    p.rep(
        '\trod.model:SetAttribute("CastT0", workspace:GetServerTimeNow()) -- RodCast: clients dip the rod now\n',
        '\trod.model:SetAttribute("CastT0", workspace:GetServerTimeNow()) -- RodCast: clients dip the rod now\n'
        '\trod.model:SetAttribute("CastRod", rod.castRodId) -- Rods: which rod this cast uses (visual hook)\n',
    )
    p.rep(
        '\trod.model:SetAttribute("CastT0", nil) -- RodCast\n\trod.temp = nil\n',
        '\trod.model:SetAttribute("CastT0", nil) -- RodCast\n'
        '\trod.model:SetAttribute("CastRod", nil) -- Rods\n'
        "\trod.biteWait, rod.castRodId = nil, nil\n"
        "\trod.temp = nil\n",
    )
    src = p.src
    # locals runRod uses must be declared before it (else they're nil globals there)
    run_at = src.index("local function runRod(")
    for name in ("local MIN_BITE_WAIT", "local WAIT_RANGE"):
        assert src.index(name) < run_at, name
    # the protections this must keep
    for needed in ("Aquarium.reserve(toCast, player)", "Variants.roll(math.random())", "Economy.cancelRodOffer(rod.key)",
                   "OwnerId = if rod.offerMode and player then player.UserId else nil", "if press(player) then"):
        assert needed in src, needed
    return src


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(build())
    print(f"wrote {OUT.relative_to(TOOLS.parent)}")


if __name__ == "__main__":
    main()
