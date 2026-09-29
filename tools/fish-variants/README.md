# Rare fish variants (Silver / Gold)

Rare Silver and Gold fish have a soft outline, a few sparkles, a small light
and a label. Species colours and details are left alone.

- **Rolled once:** a variant is rolled **once**, when a logical fish is
  created.
- **Only copied after that:** river, rod reveal and offer, aquarium tank and
  release, net or harpoon catch, and every meat piece. Nothing rerolls.
- **Extra value applied once:** when a piece sells, through the economy's
  meat ledger.

## Rebased 2026-09-28 on the economy chain

The economy already carries the variant and pays for it:

- The sale patches send the fish's `Variant` in net and harpoon payloads.
- Aquarium v1.2 carries it from rod to tank to river.
- The ledger prices each piece with the variant's sale multiplier. The
  multipliers are in `tools/economy/src/core/Config.luau`, which must use the
  same variant names (a build check enforces this).

This package adds only the rolls and the visuals. The old pre-economy patches
(FishPayout adapter, truck/customer changes) are superseded by the sale
payouts and have been removed. Git history keeps them.

| Variant | Chance per new fish | Sale value (fish value, split over its meat) | Rod offer price |
|---|---|---|---|
| Gold | 0.5% | ×5 | ×1.75 |
| Silver | 2% | ×2 | ×1.25 |

Example, a tier 10 Salmon (fish value 42):

- **Normal:** sells for 42 in total, and its rod offer costs 17.
- **Gold:** sells for 210 in total, and its rod offer costs 29.
- **What the buyer earns:** the buyer gets that money only if the fish is
  caught again later and its meat sold. It isn't guaranteed.

## What changes

| Script | Accepted versions | Change |
|---|---|---|
| FishSpawner | live | Rolls the variant for each new fish, and sets `Variant` and the effects **before parenting**. |
| RodFishingSystem | sale-payout, rod-cast, grinder-dwell (on either) | Rolls at the final pick. The glow shows only on the full-colour reveal. The **offer** is priced and labelled with the variant (e.g. `GOLD Salmon`, `$29`), and its 🍀 chance is the chance of exactly that catch (species × variant). The variant rides into the tank with the buyer. The grinder fallback sends it on. |
| GrinderProcessor | sale-payout | A small glow on variant meat pieces (the value is already in the ledger). |

**Added**, tagged `EconomyOwned`:

- `ReplicatedStorage.FishVariants`: the rules (`Defs`, `roll`)
- `ReplicatedStorage.FishVariantVisuals`: the effects

Without these modules, every patched script behaves like its base. The
aquarium v1.2 tank and river release already show the effects once the
visuals module exists.

**Moved meat:** the meat the Blender Bot carries, meat on the sale table, and
meat carried to or loaded in trucks is a fresh clone that doesn't glow with
this install alone. `InstallMeatGlow.lua` (below) fixes that. Their value is
unaffected either way.

## Glow on moved meat (`InstallMeatGlow.lua`)

Silver / Gold meat now keeps its glow after it leaves the stack:

| Script | Where the glow now shows |
|---|---|
| BotSystem (sales or Blender Bot recovery version) | the piece the bot carries, and on the sale table |
| CustomerSystem (sales version) | the piece in the customer's hand |
| TruckSystem (sales version) | the stack a player carries, the pieces flying to the truck, the meat loaded in the truck |

It's display only: it reads the `Variant` attribute the ledger already
stamped on each piece and calls `FishVariantVisuals.applyToPart`. The truck
carry keeps one variant per carried piece, in step with the ledger ids, so
the right piece glows as pieces go in and out from the top. Without
`ReplicatedStorage.FishVariantVisuals`, every patched script behaves exactly
like its base.

- **Install:** after `InstallFishVariants.lua` (checked by the
  `FishVariantVisuals` source). If you want the Blender Bot recovery, install
  `tools/economy/InstallBotRecovery.lua` **first**: it refuses once this has
  changed BotSystem. Backup: `ServerStorage.EconomyMeatGlowBackup`.
- **Rollback:** `RollbackMeatGlow.lua`, before `RollbackFishVariants` and
  `RollbackBotRecovery` (both refuse while it's in).

| # | Do | Expect |
|---|---|---|
| G1 | With V1's test chance, net Gold fish; watch the bot | The carried piece and the table piece glow gold; a customer holds a glowing piece |
| G2 | Carry a mix of Gold and plain pieces to a truck | Only the Gold pieces glow in your carried stack, in flight and in the truck |
| G3 | Sell them | Same payment as before (×5 for Gold) |

## Install / rollback (Studio, Edit mode, Command Bar)

- **Install:** `tools/fish-variants/InstallFishVariants.lua`, **last in the
  chain**: after InstallSales, and after rod cast or grinder dwell if you use
  them. It's built from the economy's guarded update template (v2). It:
  - checks exact sources, and picks the matching rod version out of 4
  - records one undo step
  - backs up the 3 scripts to `ServerStorage.EconomyVariantsBackup`
  - adds the 2 modules
- **Rollback:** `tools/fish-variants/RollbackFishVariants.lua` restores the 3
  scripts exactly and removes the modules, only if they weren't edited. Roll
  it back before dwell, rod cast or sales: those rollbacks refuse while it's
  in.

## Checks run

- `luau tools/fish-variants/tests/variants.test.luau`: 31 checks. They cover
  roll boundaries and measured rates over 400k rolls, and sanitisation.
- **`tools/economy/tests/sim/variants_sim.luau`** (21 checks) runs the **real**
  patched FishSpawner, RodFishingSystem and GrinderProcessor with the real
  modules and EconomyService, with Gold forced:
  - every new river fish is Gold, with effects, before it appears
  - the rod offer carries `Gold`, costs ×1.75 and says `GOLD`
  - the revealed fish glows, and the variant goes into the tank with the
    buyer
  - Gold meat totals ×5 of the fish value and glows
  - it's paid once; a second sale pays nothing

  Mutations caught: no spawner roll, offer without the variant, tank without
  the variant, no meat glow, sale multiplier off.
- **Installer dry run** (tools/economy): it refuses before sales, installs on
  all 4 rod versions with the right patch, blocks the dwell and rod-cast
  rollbacks, and rolls back exactly.

**Studio checklist:**

| # | Do | Expect |
|---|---|---|
| V1 | For a test, set `FishVariants.Defs.Gold.Chance` to 0.5 (put it back after) | About half the new river fish glow gold with a GOLD label; species colours unchanged |
| V2 | Rod catch that's Gold | Label `GOLD <fish>` with a higher `$price`; the glow only after the reveal; buying costs that price once |
| V3 | Release it from the tank and net it | It's still Gold in the river; its meat glows; selling pays the buyer ×5 in total |
| V4 | Net an ordinary fish | Normal value, no glow |
| V5 | Many gold fish on screen | Outlines may drop past 31 (a Roblox Highlight limit); sparkles and lights still show |
