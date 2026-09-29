#!/usr/bin/env python3
"""Variant glow on MOVED meat -> tools/fish-variants/studio/meat-glow/.

The variants install makes Silver / Gold meat glow in the blender, on the
belt and on the stack. Every later hop makes a fresh MeatTemplate clone,
which lost the glow (the value was never affected). This carries the glow
through those clones too:
  BotSystem:      the carried piece and the sale-table piece (bases: the
                  sales version, or the Blender Bot recovery version)
  CustomerSystem: the piece in the customer's hand
  TruckSystem:    the stack a player carries, the piece flying to the
                  truck, and the meat loaded in the truck

Display only: it reads the Variant attribute the ledger already stamped and
calls ReplicatedStorage.FishVariantVisuals.applyToPart. Without that module
every patched script behaves exactly like its base.

Every edit is asserted to match exactly once.

Usage:  python3 tools/fish-variants/build/make_meat_glow.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT.parent
OUT = ROOT / "studio" / "meat-glow"
SALES = TOOLS / "economy" / "studio" / "sales"

BASES = {
    "BotSystem": {"sales": SALES / "BotSystem.lua", "bot": TOOLS / "economy" / "studio" / "bot" / "BotSystem.lua"},
    "CustomerSystem": {"sales": SALES / "CustomerSystem.lua"},
    "TruckSystem": {"sales": SALES / "TruckSystem.lua"},
}

HEADER = """--
-- [MeatGlow patch] Changes marked "MeatGlow": Silver / Gold meat keeps its
-- glow when it is carried, laid out or loaded (display only; the value is in
-- the ledger). Needs ReplicatedStorage.FishVariantVisuals; without it this
-- script behaves exactly like its base version.
"""

LOAD = """-- MeatGlow: optional effects module (missing -> no glow, base behaviour)
local VariantFx = nil
do
	local mod = game:GetService("ReplicatedStorage"):FindFirstChild("FishVariantVisuals")
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			VariantFx = result
		else
			warn("[MeatGlow] FishVariantVisuals failed to load: " .. tostring(result))
		end
	end
end
local function glow(part, variant)
	if VariantFx and variant then pcall(VariantFx.applyToPart, part, variant) end
end

"""


class Patch:
    def __init__(self, base: str):
        self.src = base

    def rep(self, old: str, new: str) -> None:
        n = self.src.count(old)
        assert n == 1, f"expected 1 match, got {n}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


def bot(base: str) -> str:
    p = Patch(base)
    p.rep(
        "-- variant, tier, value), so the customer sale pays the right owner once.\n",
        "-- variant, tier, value), so the customer sale pays the right owner once.\n" + HEADER,
    )
    p.rep("\nlocal SPEED = 7\n", "\n" + LOAD + "local SPEED = 7\n")
    p.rep(
        "\tif tags then Economy.writePiece(c, tags) end\n",
        "\tif tags then Economy.writePiece(c, tags) end\n"
        "\tglow(c, c:GetAttribute(\"Variant\")) -- MeatGlow: carried, then on the table\n",
    )
    return p.src


def customer(base: str) -> str:
    p = Patch(base)
    p.rep(
        "-- (if there is any), and walk back into the city.\n",
        "-- (if there is any), and walk back into the city.\n" + HEADER,
    )
    p.rep("-- tuning\nlocal SPAWN_DELAY", LOAD + "-- tuning\nlocal SPAWN_DELAY")
    p.rep(
        "\tlocal from = meat.Position\n\tmeat:Destroy()\n",
        "\tlocal from = meat.Position\n"
        "\tlocal variant = meat:GetAttribute(\"Variant\") -- MeatGlow: read before it goes\n"
        "\tmeat:Destroy()\n",
    )
    p.rep(
        "\tlocal p = meatTemplate:Clone()\n",
        "\tlocal p = meatTemplate:Clone()\n\tglow(p, variant) -- MeatGlow: in the customer's hand\n",
    )
    return p.src


def truck(base: str) -> str:
    p = Patch(base)
    p.rep(
        "-- the grinder pipe instead of vanishing unpaid. Truck UI is unchanged.\n",
        "-- the grinder pipe instead of vanishing unpaid. Truck UI is unchanged.\n" + HEADER,
    )
    p.rep("\n-- tuning\n", "\n" + LOAD + "-- tuning\n")
    # the carried stack: c.glow[i] = variant of the i-th carried piece (parallel to c.ids)
    p.rep(
        "\t\tlocal i = #c.parts\n",
        "\t\tlocal i = #c.parts\n\t\tglow(p, c.glow and c.glow[i + 1]) -- MeatGlow\n",
    )
    p.rep(
        "local function flyPart(from, to, height, dur)\n\tlocal p = meatTemplate:Clone()\n",
        "local function flyPart(from, to, height, dur, variant) -- MeatGlow: variant\n"
        "\tlocal p = meatTemplate:Clone()\n\tglow(p, variant) -- MeatGlow\n",
    )
    p.rep(
        "local function addMeatToTruck(t, n) -- n = 0-based slot\n",
        "local function addMeatToTruck(t, n, variant) -- n = 0-based slot; MeatGlow: variant\n",
    )
    p.rep(
        "\tp.Name = \"LoadedMeat\"\n",
        "\tp.Name = \"LoadedMeat\"\n\tglow(p, variant) -- MeatGlow\n",
    )
    p.rep(
        "\t\t\t\t\tlocal pieceId = meat:GetAttribute(\"PieceId\") -- Economy\n",
        "\t\t\t\t\tlocal pieceId = meat:GetAttribute(\"PieceId\") -- Economy\n"
        "\t\t\t\t\tlocal variant = meat:GetAttribute(\"Variant\") -- MeatGlow\n",
    )
    p.rep(
        "\t\t\t\t\tflyPart(from, pos + Vector3.new(0, 0.5 + c.count * 0.3, 0), 2, 0.2)\n\t\t\t\t\tc.count += 1\n",
        "\t\t\t\t\tflyPart(from, pos + Vector3.new(0, 0.5 + c.count * 0.3, 0), 2, 0.2, variant)\n"
        "\t\t\t\t\tc.count += 1\n"
        "\t\t\t\t\tc.glow = c.glow or {} -- MeatGlow\n"
        "\t\t\t\t\tc.glow[c.count] = variant or false\n",
    )
    p.rep(
        "\t\t\t\t\tc.count -= 1\n",
        "\t\t\t\t\tc.count -= 1\n"
        "\t\t\t\t\tlocal variant = c.glow and c.glow[c.count + 1] -- MeatGlow: the top piece\n",
    )
    p.rep(
        "bucketPos + Vector3.new(0, 0.5, 0), 4, 0.35)\n",
        "bucketPos + Vector3.new(0, 0.5, 0), 4, 0.35, variant)\n",
    )
    p.rep(
        "addMeatToTruck(truck, slotLoaded) end\n",
        "addMeatToTruck(truck, slotLoaded, variant) end\n",
    )
    return p.src


BUILDERS = {"BotSystem": bot, "CustomerSystem": customer, "TruckSystem": truck}


def build() -> dict:
    """{name: {label: (base, patched)}}"""
    out = {}
    for name, bases in BASES.items():
        out[name] = {}
        for label, path in bases.items():
            base = path.read_text()
            out[name][label] = (base, BUILDERS[name](base))
    return out


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.lua"):
        old.unlink()
    for name, versions in build().items():
        for label, (_, src) in versions.items():
            path = OUT / f"{name}.patched.from-{label}.lua"
            path.write_text(src)
            print(f"wrote {path.relative_to(TOOLS.parent)}")


if __name__ == "__main__":
    main()
