#!/usr/bin/env python3
"""Regenerates tools/fish-variants/studio/*.patched.lua from the reviewed
live sources with small, asserted edits (every edit must match exactly once).

Bases:
  * FishSpawner, NetLiftScript, GrinderProcessor, TruckSystem, CustomerSystem:
    studio/<Name>.original.lua (live source as supplied)
  * RodFishingSystem: the aquarium-patched source currently installed in
    Studio (tools/aquarium-cycle/studio/RodFishingSystem.patched.lua)

Usage:  python3 tools/fish-variants/build/make_patches.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
STUDIO = ROOT / "studio"
AQUARIUM_ROD = ROOT.parent / "aquarium-cycle" / "studio" / "RodFishingSystem.patched.lua"

HEADER = """
--
-- [FishVariants patch v1] Changes vs. the base are marked "FishVariants".
-- Rare Silver/Gold fish: the variant is rolled once when a fish is created
-- and carried unchanged to every meat piece and sale. Needs
-- ReplicatedStorage.FishVariants (and optionally FishVariantVisuals and
-- ServerScriptService.FishPayout); without them this script behaves exactly
-- like the base version. Nothing is paid unless FishPayout is connected.
"""

LOAD_MODULES_SELL = """
-- FishVariants: optional modules (missing -> base behaviour)
local Variants, VariantFx, Payout = nil, nil, nil
do
	local rs = game:GetService("ReplicatedStorage")
	local function load(parent, name)
		local mod = parent:FindFirstChild(name)
		if not (mod and mod:IsA("ModuleScript")) then return nil end
		local ok, result = pcall(require, mod)
		if not ok then
			warn("[FishVariants] " .. name .. " failed to load: " .. tostring(result))
			return nil
		end
		return result
	end
	Variants = load(rs, "FishVariants")
	if Variants then
		VariantFx = load(rs, "FishVariantVisuals")
		local p = load(game:GetService("ServerScriptService"), "FishPayout")
		if type(p) == "table" and type(p.onSale) == "function" then Payout = p end
	end
end
"""

# Scripts that don't sell meat don't need the payout adapter.
LOAD_MODULES = LOAD_MODULES_SELL.replace(
    "local Variants, VariantFx, Payout = nil, nil, nil", "local Variants, VariantFx = nil, nil"
).replace(
    '''		local p = load(game:GetService("ServerScriptService"), "FishPayout")
		if type(p) == "table" and type(p.onSale) == "function" then Payout = p end
''',
    "",
)
assert "Payout" not in LOAD_MODULES

PAY_SALE = """
-- FishVariants: hand one sale to the payout adapter (exactly once per piece)
local function paySale(info)
	if not Payout then return end
	local ok, err = pcall(Payout.onSale, info)
	if not ok then warn("[FishVariants] FishPayout.onSale failed: " .. tostring(err)) end
end
-- sale metadata read from a meat part BEFORE it is destroyed
local function saleInfoOf(meat, kind)
	if Variants then
		return Variants.saleInfo(function(k) return meat:GetAttribute(k) end, kind)
	end
	return { kind = kind, tier = meat:GetAttribute("Tier"), multiplier = 1 }
end
"""


class Patch:
    def __init__(self, base: str):
        self.src = base

    def rep(self, old: str, new: str) -> None:
        count = self.src.count(old)
        assert count == 1, f"expected 1 match, got {count}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


def fish_spawner() -> str:
    p = Patch((STUDIO / "FishSpawner.original.lua").read_text())
    p.rep(
        "--   SpawnT, StartZ, Speed, LaneX, Seed   -> z = StartZ + Speed * (serverTime - SpawnT)\n",
        "--   SpawnT, StartZ, Speed, LaneX, Seed   -> z = StartZ + Speed * (serverTime - SpawnT)\n" + HEADER,
    )
    p.rep('local rng = Random.new()\n', 'local rng = Random.new()\n' + LOAD_MODULES)
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
    return p.src


def net_lift() -> str:
    p = Patch((STUDIO / "NetLiftScript.original.lua").read_text())
    p.rep(
        "-- Server: handles the step pad. The net animation + splash runs on each client (NetLiftClient).\n",
        "-- Server: handles the step pad. The net animation + splash runs on each client (NetLiftClient).\n"
        "--\n"
        "-- [FishVariants patch v1] FishCaught now fires (player, fishName, tier, payload)\n"
        "-- where payload = { Variant = <the fish's Variant attribute>, Source = \"Net\" }.\n"
        "-- Listeners that take three arguments are unaffected.\n",
    )
    p.rep(
        'caughtEvent.Name = "FishCaught" -- fires (player, fishName, tier) for each fish that lands in the grinder\n',
        'caughtEvent.Name = "FishCaught" -- fires (player, fishName, tier, payload) for each fish that lands in the grinder\n',
    )
    p.rep(
        '\t\t\t\t\tcaughtEvent:Fire(player, m.Name, m:GetAttribute("Tier"))\n',
        '\t\t\t\t\t-- FishVariants: optional 4th argument carries the variant to the grinder\n'
        '\t\t\t\t\tcaughtEvent:Fire(player, m.Name, m:GetAttribute("Tier"), { Variant = m:GetAttribute("Variant"), Source = "Net" })\n',
    )
    return p.src


def rod_system() -> str:
    p = Patch(AQUARIUM_ROD.read_text())
    p.rep(
        "-- ServerStorage.AquariumCycleBackup by the installer.\n",
        "-- ServerStorage.AquariumCycleBackup by the installer.\n" + HEADER,
    )
    p.rep(
        "------------------------------------------------------------ aquarium (AquariumCycle)\n",
        LOAD_MODULES.lstrip("\n") + "\n------------------------------------------------------------ aquarium (AquariumCycle)\n",
    )
    p.rep(
        "\tlocal finalName = pickFish()\n",
        "\tlocal finalName = pickFish()\n"
        "\t-- FishVariants: roll once for this newly caught fish\n"
        "\tlocal variant = Variants and Variants.roll(math.random()) or nil\n",
    )
    p.rep(
        "\t\ttoTank = Aquarium.hook(rod.key, finalName)\n",
        "\t\ttoTank = Aquarium.hook(rod.key, finalName, { Variant = variant }) -- FishVariants: variant rides along\n",
    )
    p.rep(
        "\t-- 5) reveal in full color with a little pop\n\tshow(finalName, false)\n",
        "\t-- 5) reveal in full color with a little pop\n\tshow(finalName, false)\n"
        "\t-- FishVariants: the glow appears only on the full-colour reveal, not the silhouettes\n"
        "\tif variant and VariantFx then pcall(VariantFx.applyToFish, shown, variant) end\n",
    )
    old = '\t\t\tfishCaught:Fire(player, finalName, tpl and tpl:GetAttribute("Tier") or 1)\n'
    p.rep(
        old,
        '\t\t\tfishCaught:Fire(player, finalName, tpl and tpl:GetAttribute("Tier") or 1, { Variant = variant, Source = "Rod" })\n',
    )
    p.rep(
        '\t\tfishCaught:Fire(player, finalName, tpl and tpl:GetAttribute("Tier") or 1)\n',
        '\t\tfishCaught:Fire(player, finalName, tpl and tpl:GetAttribute("Tier") or 1, { Variant = variant, Source = "Rod" })\n',
    )
    return p.src


def grinder() -> str:
    p = Patch((STUDIO / "GrinderProcessor.original.lua").read_text())
    p.rep(
        "--    and stacks up neatly in the box at the end.\n",
        "--    and stacks up neatly in the box at the end.\n" + HEADER,
    )
    p.rep("local rng = Random.new()\n", "local rng = Random.new()\n" + LOAD_MODULES)
    p.rep(
        '\tif info.player then meat:SetAttribute("OwnerId", info.player.UserId) end\n',
        '\tif info.player then meat:SetAttribute("OwnerId", info.player.UserId) end\n'
        "\t-- FishVariants: every meat piece of a variant fish carries the variant and its multiplier\n"
        "\tif info.variant then\n"
        '\t\tmeat:SetAttribute("Variant", info.variant)\n'
        '\t\tmeat:SetAttribute("ValueMultiplier", Variants.multiplier(info.variant))\n'
        "\t\tif VariantFx then pcall(VariantFx.applyToPart, meat, info.variant) end\n"
        "\tend\n",
    )
    p.rep(
        "caught.Event:Connect(function(player, fishName, tier)\n"
        "\ttable.insert(pending, { player = player, fishName = fishName, tier = tier })\n",
        "caught.Event:Connect(function(player, fishName, tier, extra)\n"
        "\t-- FishVariants: optional 4th argument { Variant, Source } (sanitized)\n"
        "\tlocal variant = Variants and Variants.fromPayload(extra) or nil\n"
        "\ttable.insert(pending, { player = player, fishName = fishName, tier = tier, variant = variant })\n",
    )
    return p.src


def trucks() -> str:
    p = Patch((STUDIO / "TruckSystem.original.lua").read_text())
    p.rep(
        "-- (Trucks are drawn/moved on each client by TruckClient using the \"S\" attribute; server keeps the logic.)\n",
        "-- (Trucks are drawn/moved on each client by TruckClient using the \"S\" attribute; server keeps the logic.)\n"
        + HEADER
        + "-- Carried meat now keeps each piece's identity (items list alongside count),\n"
        + "-- so a delivery knows its tier/owner/variant. MeatDelivered gains an optional\n"
        + "-- 3rd argument with that sale info.\n",
    )
    p.rep("local rng = Random.new()\n", "local rng = Random.new()\n" + LOAD_MODULES_SELL + PAY_SALE)
    p.rep(
        "local carry = {} -- player -> {count, parts}\n",
        "local carry = {} -- player -> {count, parts, items} (FishVariants: items[i] = sale info of piece i)\n",
    )
    p.rep(
        "\t\tp.Parent = folder\n\t\ttable.insert(c.parts, p)\n",
        "\t\tp.Parent = folder\n"
        "\t\tlocal item = c.items and c.items[#c.parts + 1] -- FishVariants: glow for variant pieces\n"
        "\t\tif item and item.variant and VariantFx then pcall(VariantFx.applyToPart, p, item.variant) end\n"
        "\t\ttable.insert(c.parts, p)\n",
    )
    p.rep(
        "local function addMeatToTruck(t, n) -- n = 0-based slot\n",
        "local function addMeatToTruck(t, n, item) -- n = 0-based slot; item = FishVariants sale info\n",
    )
    p.rep(
        "\tp.CFrame = Path.truckCF(0) * CFrame.new(off) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0)\n\tp.Parent = t.model\n",
        "\tp.CFrame = Path.truckCF(0) * CFrame.new(off) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0)\n"
        "\tif item and item.variant then\n"
        '\t\tp:SetAttribute("Variant", item.variant)\n'
        "\t\tif VariantFx then pcall(VariantFx.applyToPart, p, item.variant) end\n"
        "\tend\n"
        "\tp.Parent = t.model\n",
    )
    p.rep(
        "\t\t\tcarry[player] = carry[player] or { count = 0, parts = {} }\n\t\t\tlocal c = carry[player]\n",
        "\t\t\tcarry[player] = carry[player] or { count = 0, parts = {}, items = {} }\n"
        "\t\t\tlocal c = carry[player]\n"
        "\t\t\tc.items = c.items or {}\n",
    )
    p.rep(
        "\t\t\t\t\tlocal from = meat.Position\n\t\t\t\t\tmeat:Destroy()\n",
        "\t\t\t\t\tlocal from = meat.Position\n"
        "\t\t\t\t\ttable.insert(c.items, saleInfoOf(meat, \"Truck\")) -- FishVariants: capture before destroy\n"
        "\t\t\t\t\tmeat:Destroy()\n",
    )
    p.rep(
        "\t\t\t\t\tc.count -= 1\n\t\t\t\t\tcarryVisual(player)\n\t\t\t\t\tlocal truck = front\n",
        "\t\t\t\t\tc.count -= 1\n"
        "\t\t\t\t\t-- FishVariants: the piece on top of the carried stack is the one delivered\n"
        "\t\t\t\t\tlocal item = table.remove(c.items) or { kind = \"Truck\", multiplier = 1 }\n"
        "\t\t\t\t\titem.sellerId = player.UserId\n"
        "\t\t\t\t\tcarryVisual(player)\n"
        "\t\t\t\t\tlocal truck = front\n",
    )
    p.rep(
        "\t\t\t\t\tevents.MeatDelivered:Fire(player, truck.model)\n",
        "\t\t\t\t\tevents.MeatDelivered:Fire(player, truck.model, item)\n"
        "\t\t\t\t\tpaySale(item)\n",
    )
    p.rep(
        "\t\t\t\t\t\tif truck.model.Parent then addMeatToTruck(truck, slotLoaded) end\n",
        "\t\t\t\t\t\tif truck.model.Parent then addMeatToTruck(truck, slotLoaded, item) end\n",
    )
    p.rep(
        "\t\tcarry[p] = { count = 0, parts = {} }\n",
        "\t\tcarry[p] = { count = 0, parts = {}, items = {} }\n",
    )
    return p.src


def customers() -> str:
    p = Patch((STUDIO / "CustomerSystem.original.lua").read_text())
    p.rep(
        "-- (if there is any), and walk back into the city.\n",
        "-- (if there is any), and walk back into the city.\n"
        + HEADER
        + "-- The sold piece's tier/owner/variant are now read BEFORE giveMeat destroys\n"
        + "-- it; CustomerBought gains an optional 3rd argument with that sale info.\n",
    )
    p.rep(
        'local bought = SS:WaitForChild("CustomerEvents"):WaitForChild("CustomerBought")\n',
        'local bought = SS:WaitForChild("CustomerEvents"):WaitForChild("CustomerBought")\n' + LOAD_MODULES_SELL + PAY_SALE,
    )
    p.rep(
        "local function giveMeat(c, meat)\n",
        "local function giveMeat(c, meat, variant) -- FishVariants: variant keeps the held piece glowing\n",
    )
    p.rep(
        "\tlocal p = meatTemplate:Clone()\n\tp.Anchored = true\n\tp.Parent = workspace\n",
        "\tlocal p = meatTemplate:Clone()\n"
        "\tp.Anchored = true\n"
        "\tif variant and VariantFx then pcall(VariantFx.applyToPart, p, variant) end\n"
        "\tp.Parent = workspace\n",
    )
    p.rep(
        "\t\tif meat then\n"
        "\t\t\tgiveMeat(c, meat)\n"
        "\t\t\tbought:Fire(c.model.Name, meat:GetAttribute(\"Tier\"))\n",
        "\t\tif meat then\n"
        "\t\t\t-- FishVariants: capture the sale BEFORE giveMeat destroys the meat. topOfStack\n"
        "\t\t\t-- already marked it Sold, so this sale happens exactly once.\n"
        "\t\t\tlocal info = saleInfoOf(meat, \"Customer\")\n"
        "\t\t\tinfo.customer = c.model.Name\n"
        "\t\t\tgiveMeat(c, meat, info.variant)\n"
        "\t\t\tbought:Fire(c.model.Name, info.tier, info)\n"
        "\t\t\tpaySale(info)\n",
    )
    return p.src


def main() -> None:
    outputs = {
        "FishSpawner": fish_spawner(),
        "NetLiftScript": net_lift(),
        "RodFishingSystem": rod_system(),
        "GrinderProcessor": grinder(),
        "TruckSystem": trucks(),
        "CustomerSystem": customers(),
    }
    for name, text in outputs.items():
        (STUDIO / f"{name}.patched.lua").write_text(text)
        print(f"wrote studio/{name}.patched.lua")


if __name__ == "__main__":
    main()
