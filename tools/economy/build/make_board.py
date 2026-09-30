#!/usr/bin/env python3
"""Upgrade board, the RodFishingSystem side.

Patches the INSTALLED RodFishingSystem (the rods release, 61a7bd4:
studio/rods/RodFishingSystem.lua read from git) into
studio/board/RodFishingSystem.lua. Changes, marked "RodLuck":

  * each accepted press snapshots the PRESSER's committed Rod Luck
    (EconomyService.upgradeValue(player, "RodLuck"); 1 without the money
    service, on any error or for a value outside 1..5) for every rod it
    casts, next to the equipped rod: buying luck later never changes a cast
    already under way
  * the fish roll (pickFish) and the offer's chance label (rodChance) use
    the same weights: each fish's rod weight x BoardUpgrades.luckFactor
    (commonest tier x1, rarest x luck, geometric between), renormalised over
    the pool. At luck 1 both use the old weights (one math.random() per
    roll, as before)
  * the Silver / Gold roll (Variants.roll) is untouched

and (Faster Reels, board milestone 4), marked "FasterReels":

  * each accepted press also snapshots the PRESSER's committed reel speed
    (EconomyService.upgradeValue(player, "FasterReels"); 1 without the
    money service, on any error or outside 1..2)
  * the reel-in takes REEL / speed (3.4 s at 1x, ~2.83 s at 1.2x). The
    clients' fish-rising animation already follows the server's Dur
    attribute and the rod's Pulling flag, so it shortens with it; the
    silhouette flicks speed up by the same factor
  * the bite wait is untouched: that stays the equipped rod's benefit

Usage:  python3 tools/economy/build/make_board.py
"""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT.parent
RODS_RELEASE = "61a7bd4"
BASE_PATH = "tools/economy/studio/rods/RodFishingSystem.lua"
OUT = ROOT / "studio" / "board" / "RodFishingSystem.lua"


def base() -> str:
    return subprocess.run(["git", "show", f"{RODS_RELEASE}:{BASE_PATH}"], cwd=TOOLS.parent, capture_output=True, text=True, check=True).stdout


class Patch:
    def __init__(self, src: str):
        self.src = src

    def rep(self, old: str, new: str) -> None:
        n = self.src.count(old)
        assert n == 1, f"expected 1 match, got {n}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


def build() -> str:
    p = Patch(base())
    p.rep(
        "table.sort(pool, function(a, b) return a.tier < b.tier end)\n"
        "local function pickFish()\n"
        "\tlocal r = math.random() * total\n"
        "\tfor _, e in ipairs(pool) do r -= e.w if r <= 0 then return e.name end end\n"
        "\treturn pool[1].name\n"
        "end\n"
        "-- Economy: a fish's real roll chance on the rods (the same weights pickFish uses)\n"
        "local function rodChance(name)\n"
        "\tif total <= 0 then return nil end\n"
        "\tlocal w = 0\n"
        "\tfor _, e in ipairs(pool) do if e.name == name then w += e.w end end\n"
        "\treturn w / total\n"
        "end\n",
        "table.sort(pool, function(a, b) return a.tier < b.tier end)\n"
        "-- RodLuck: the caster's luck weights rarer tiers up (commonest x1, rarest\n"
        "-- x luck, EconomyService.BoardUpgrades.luckFactor), renormalised over the\n"
        "-- pool. luck nil / 1 (or no money service): exactly the old weights.\n"
        "local LuckMath = nil -- EconomyService.BoardUpgrades, set once the money service loads\n"
        "local loTier, hiTier = math.huge, -math.huge\n"
        "for _, e in ipairs(pool) do loTier = math.min(loTier, e.tier) hiTier = math.max(hiTier, e.tier) end\n"
        "local function luckWeight(e, luck)\n"
        "\tif not luck or luck <= 1 or not LuckMath then return e.w end\n"
        "\treturn e.w * LuckMath.luckFactor(e.tier, loTier, hiTier, luck)\n"
        "end\n"
        "local function pickFish(luck)\n"
        "\tlocal sum = 0\n"
        "\tfor _, e in ipairs(pool) do sum += luckWeight(e, luck) end\n"
        "\tlocal r = math.random() * sum\n"
        "\tfor _, e in ipairs(pool) do r -= luckWeight(e, luck) if r <= 0 then return e.name end end\n"
        "\treturn pool[1].name\n"
        "end\n"
        "-- Economy: a fish's real roll chance on the rods (the same weights pickFish uses)\n"
        "local function rodChance(name, luck)\n"
        "\tlocal sum, w = 0, 0\n"
        "\tfor _, e in ipairs(pool) do\n"
        "\t\tlocal x = luckWeight(e, luck)\n"
        "\t\tsum += x\n"
        "\t\tif e.name == name then w += x end\n"
        "\tend\n"
        "\tif sum <= 0 then return nil end\n"
        "\treturn w / sum\n"
        "end\n",
    )
    p.rep(
        "\t\t\t\tEconomy = api\n",
        "\t\t\t\tEconomy = api\n"
        "\t\t\t\tLuckMath = if type(api.BoardUpgrades) == \"table\" and type(api.BoardUpgrades.luckFactor) == \"function\" then api.BoardUpgrades else nil -- RodLuck\n",
    )
    p.rep(
        "\tlocal finalName = pickFish()\n",
        "\tlocal finalName = pickFish(rod.luck) -- RodLuck: the caster's luck, fixed at the press\n",
    )
    p.rep(
        "\t\t\t\tchance = rodChance(finalName) and rodChance(finalName) * (if variant then Variants.Defs[variant].Chance else 1),\n",
        "\t\t\t\t-- RodLuck: with the caster's luck (the odds this fish really had)\n"
        "\t\t\t\tchance = rodChance(finalName, rod.luck) and rodChance(finalName, rod.luck) * (if variant then Variants.Defs[variant].Chance else 1),\n",
    )
    p.rep(
        "\trod.biteWait, rod.castRodId = nil, nil\n",
        "\trod.biteWait, rod.castRodId = nil, nil\n"
        "\trod.luck = nil -- RodLuck\n",
    )
    p.rep(
        "\treturn BASIC_ROD\n"
        "end\n",
        "\treturn BASIC_ROD\n"
        "end\n"
        "-- RodLuck: the presser's committed Rod Luck, read once per accepted press\n"
        "-- (1 without the money service, on any error, or outside 1..5).\n"
        "local function luckFor(player)\n"
        "\tif Economy and type(Economy.upgradeValue) == \"function\" then\n"
        "\t\tlocal ok, v = pcall(Economy.upgradeValue, player, \"RodLuck\")\n"
        "\t\tif ok and type(v) == \"number\" and v >= 1 and v <= 5 then\n"
        "\t\t\treturn v\n"
        "\t\tend\n"
        "\tend\n"
        "\treturn 1\n"
        "end\n",
    )
    p.rep(
        "\tfor _, rod in ipairs(toCast) do rod.biteWait = castRod.BiteWait rod.castRodId = castRod.Id end\n",
        "\tfor _, rod in ipairs(toCast) do rod.biteWait = castRod.BiteWait rod.castRodId = castRod.Id end\n"
        "\t-- RodLuck: the presser's luck, fixed for this cast (buying later changes nothing)\n"
        "\tlocal luck = luckFor(player)\n"
        "\tfor _, rod in ipairs(toCast) do rod.luck = luck end\n",
    )
    src = p.src
    # every local is declared before the code that uses it (a later `local`
    # would make these nil globals inside the functions above it)
    for name in ("local LuckMath = nil", "local function luckWeight", "local function pickFish", "local function rodChance", "local Economy = nil", "local function luckFor"):
        assert src.count(name) == 1, name
    assert src.index("local LuckMath = nil") < src.index("local function luckWeight") < src.index("local function pickFish")
    assert src.index("local LuckMath = nil") < src.index("LuckMath = if type(api.BoardUpgrades)")
    assert src.index("local function luckFor") < src.index("local luck = luckFor(player)")
    assert "Variants.roll(math.random())" in src  # the Silver / Gold roll is untouched
    return reels(Patch(src))


def reels(p: Patch) -> str:
    p.rep(
        "\tlocal REEL = 3.4\n",
        "\tlocal REEL = 3.4 / (rod.reelSpeed or 1) -- FasterReels: the caster's reel speed, fixed at the press (clients follow Dur)\n",
    )
    p.rep(
        "\tlocal delay = 0.05\n",
        "\tlocal delay = 0.05 / (rod.reelSpeed or 1) -- FasterReels: the silhouette flicks keep pace\n",
    )
    p.rep(
        "\trod.luck = nil -- RodLuck\n",
        "\trod.luck = nil -- RodLuck\n"
        "\trod.reelSpeed = nil -- FasterReels\n",
    )
    p.rep(
        "\treturn 1\n"
        "end\n"
        "\n"
        "------------------------------------------------------------ pressing the button\n",
        "\treturn 1\n"
        "end\n"
        "-- FasterReels: the presser's committed reel speed, read once per accepted\n"
        "-- press (1 without the money service, on any error, or outside 1..2).\n"
        "local function reelFor(player)\n"
        "\tif Economy and type(Economy.upgradeValue) == \"function\" then\n"
        "\t\tlocal ok, v = pcall(Economy.upgradeValue, player, \"FasterReels\")\n"
        "\t\tif ok and type(v) == \"number\" and v >= 1 and v <= 2 then\n"
        "\t\t\treturn v\n"
        "\t\tend\n"
        "\tend\n"
        "\treturn 1\n"
        "end\n"
        "\n"
        "------------------------------------------------------------ pressing the button\n",
    )
    p.rep(
        "\tfor _, rod in ipairs(toCast) do rod.luck = luck end\n",
        "\tfor _, rod in ipairs(toCast) do rod.luck = luck end\n"
        "\t-- FasterReels: the presser's reel speed, fixed for this cast (the bite wait stays the rod's)\n"
        "\tlocal reelSpeed = reelFor(player)\n"
        "\tfor _, rod in ipairs(toCast) do rod.reelSpeed = reelSpeed end\n",
    )
    src = p.src
    assert src.index("local function reelFor") < src.index("local reelSpeed = reelFor(player)")
    # the bite wait is the rod's alone
    assert "(rod.biteWait or 1)))" in src and "reelSpeed" not in src[src.index("-- 2) wait for a bite"):src.index("-- 3) reel it up")]
    return src


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(build())
    print(f"wrote {OUT.relative_to(TOOLS.parent)}")


if __name__ == "__main__":
    main()
