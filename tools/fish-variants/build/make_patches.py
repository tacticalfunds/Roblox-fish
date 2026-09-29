#!/usr/bin/env python3
"""Rare Silver / Gold fish, rebased (2026-09-28) on the economy chain.

The variant is rolled ONCE when a logical fish is created, and everything
downstream only copies it. The economy already carries it and applies the
extra value once per sale:
  * net / harpoon catch payloads send the fish's Variant (sale patches)
  * aquarium v1.2 carries Variant rod -> tank -> river (and shows effects)
  * the grinder's ledger prices each piece with the variant's sale
    multiplier (Silver x2, Gold x5 of the fish value, split over its pieces)
    and every piece pays its owner once
This feature adds only the rolls and the visuals:
  FishSpawner:      live source -> roll + effects before parenting
  RodFishingSystem: sale-payout | rod-cast | dwell(sales) | dwell(rod-cast)
                    -> roll at the final pick; offer priced/labelled with the
                    variant (Pricing: x1.25 / x1.75); the variant rides into
                    the tank; the grinder fallback sends it; glow on the reveal
  GrinderProcessor: sale-payout version -> a glow on variant meat pieces

Usage:  python3 tools/fish-variants/build/make_patches.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT.parent
OUT = ROOT / "studio" / "economy"
LIVE = TOOLS / "economy" / "studio" / "live"
SALES = TOOLS / "economy" / "studio" / "sales"
DWELL = TOOLS / "grinder-dwell" / "studio"

BASES = {
    "FishSpawner": {"live": LIVE / "FishSpawner.lua"},
    "RodFishingSystem": {
        "sales": SALES / "RodFishingSystem.lua",
        "rodcast": TOOLS / "rod-cast" / "studio" / "RodFishingSystem.patched.from-sales.lua",
        "dwell-sales": DWELL / "RodFishingSystem.patched.from-sales.lua",
        "dwell-rodcast": DWELL / "RodFishingSystem.patched.from-rodcast.lua",
    },
    "GrinderProcessor": {"sales": SALES / "GrinderProcessor.lua"},
}

HEADER = """--
-- [FishVariants patch v2] Changes marked "FishVariants": rare Silver/Gold fish.
-- The variant is rolled once when a fish is created and only copied after
-- that; the economy applies its extra value once, when the meat sells.
-- Needs ReplicatedStorage.FishVariants (+ FishVariantVisuals for effects);
-- without them this script behaves exactly like its base version.
"""

LOAD = """
-- FishVariants: optional modules (missing -> base behaviour)
local Variants, VariantFx = nil, nil
do
	local rs = game:GetService("ReplicatedStorage")
	local function load(name)
		local mod = rs:FindFirstChild(name)
		if not (mod and mod:IsA("ModuleScript")) then return nil end
		local ok, result = pcall(require, mod)
		if not ok then
			warn("[FishVariants] " .. name .. " failed to load: " .. tostring(result))
			return nil
		end
		return result
	end
	Variants = load("FishVariants")
	if Variants then VariantFx = load("FishVariantVisuals") end
end
"""


class Patch:
    def __init__(self, base: str):
        self.src = base

    def rep(self, old: str, new: str, count: int = 1) -> None:
        n = self.src.count(old)
        assert n == count, f"expected {count} match(es), got {n}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


# The live despawn timers (both: new fish and the pre-filled river) leave a
# fish the harpoon has hit (HarpoonT) to the harpoon. The patch must keep that.
HARPOON_GUARD = 'not m:GetAttribute("CaughtT") and not m:GetAttribute("HarpoonT") then m:Destroy() end'


def fish_spawner(base: str) -> str:
    assert base.count(HARPOON_GUARD) == 2, "live FishSpawner: expected the harpoon-safe despawn guard twice"
    p = Patch(base)
    p.rep(
        "--   SpawnT, StartZ, Speed, LaneX, Seed   -> z = StartZ + Speed * (serverTime - SpawnT)\n",
        "--   SpawnT, StartZ, Speed, LaneX, Seed   -> z = StartZ + Speed * (serverTime - SpawnT)\n" + HEADER,
    )
    p.rep("local rng = Random.new()\n", "local rng = Random.new()\n" + LOAD)
    p.rep(
        "\tm:PivotTo(CFrame.lookAt(Vector3.new(laneX, surfaceY - 0.6, startZ), Vector3.new(laneX, surfaceY - 0.6, startZ + 1)))\n\tm.Parent = folder\n",
        "\tm:PivotTo(CFrame.lookAt(Vector3.new(laneX, surfaceY - 0.6, startZ), Vector3.new(laneX, surfaceY - 0.6, startZ + 1)))\n"
        "\t-- FishVariants: roll once for this new fish, before parenting\n"
        "\tif Variants then\n"
        "\t\tlocal variant = Variants.roll(rng:NextNumber())\n"
        "\t\tif variant then\n"
        '\t\t\tm:SetAttribute("Variant", variant)\n'
        "\t\t\tif VariantFx then pcall(VariantFx.applyToFish, m, variant) end\n"
        "\t\tend\n"
        "\tend\n"
        "\tm.Parent = folder\n",
    )
    assert p.src.count(HARPOON_GUARD) == 2, "variant FishSpawner lost the harpoon-safe despawn guard"
    return p.src


def rod_system(base: str) -> str:
    p = Patch(base)
    p.rep("-- ServerStorage.AquariumCycleBackup by the installer.\n", "-- ServerStorage.AquariumCycleBackup by the installer.\n" + HEADER)
    p.rep(
        "------------------------------------------------------------ button look / lock\n",
        LOAD.lstrip("\n") + "\n------------------------------------------------------------ button look / lock\n",
    )
    p.rep(
        "\tlocal finalName = pickFish()\n",
        "\tlocal finalName = pickFish()\n"
        "\tlocal variant = Variants and Variants.roll(math.random()) or nil -- FishVariants: rolled once, here\n",
    )
    p.rep(
        "\t\ttoTank = Aquarium.hook(rod.key, finalName, if rod.offerMode and player then { OwnerId = player.UserId } else nil)\n",
        "\t\t-- FishVariants: the variant rides into the tank with the buyer\n"
        "\t\ttoTank = Aquarium.hook(rod.key, finalName, {\n"
        "\t\t\tOwnerId = if rod.offerMode and player then player.UserId else nil,\n"
        "\t\t\tVariant = variant,\n"
        "\t\t})\n",
    )
    p.rep(
        "\tshow(finalName, false)\n",
        "\tshow(finalName, false)\n"
        "\t-- FishVariants: the glow appears only on the full-colour reveal, not the silhouettes\n"
        "\tif variant and VariantFx then pcall(VariantFx.applyToFish, shown, variant) end\n",
    )
    p.rep(
        "\t\t\t\tvariant = nil,\n\t\t\t\tchance = rodChance(finalName),\n",
        "\t\t\t\tvariant = variant, -- FishVariants: priced and labelled with it\n"
        "\t\t\t\t-- FishVariants: the chance of exactly this catch (species x variant)\n"
        "\t\t\t\tchance = rodChance(finalName) and rodChance(finalName) * (if variant then Variants.Defs[variant].Chance else 1),\n",
    )
    p.rep(
        "fishCaught:Fire(player, finalName, tpl and tpl:GetAttribute(\"Tier\") or 1)\n",
        "fishCaught:Fire(player, finalName, tpl and tpl:GetAttribute(\"Tier\") or 1, { Variant = variant, Source = \"Rod\" }) -- FishVariants\n",
        count=2,
    )
    return p.src


def grinder(base: str) -> str:
    p = Patch(base)
    p.rep("--    and stacks up neatly in the box at the end.\n", "--    and stacks up neatly in the box at the end.\n" + HEADER)
    p.rep('local pit = workspace:WaitForChild("Pit")\n', 'local pit = workspace:WaitForChild("Pit")\n' + LOAD)
    p.rep(
        "\tif Economy and pieceId then Economy.stamp(meat, pieceId) end -- Economy: PieceId, owner, value, variant\n",
        "\tif Economy and pieceId then Economy.stamp(meat, pieceId) end -- Economy: PieceId, owner, value, variant\n"
        "\t-- FishVariants: a small glow on rare meat (its value is in the ledger)\n"
        "\tif VariantFx and meat:GetAttribute(\"Variant\") then pcall(VariantFx.applyToPart, meat, meat:GetAttribute(\"Variant\")) end\n",
    )
    return p.src


BUILDERS = {"FishSpawner": fish_spawner, "RodFishingSystem": rod_system, "GrinderProcessor": grinder}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.lua"):
        old.unlink()
    for name, bases in BASES.items():
        for label, path in bases.items():
            out = OUT / f"{name}.patched.from-{label}.lua"
            src = BUILDERS[name](path.read_text())
            if name == "RodFishingSystem":
                assert "Economy.runRodOffer" in src and "variant = variant," in src
                assert src.count("Aquarium.hook(") == 1 and "Variant = variant," in src
            out.write_text(src)
            print(f"wrote {out.relative_to(TOOLS.parent)}")


if __name__ == "__main__":
    main()
