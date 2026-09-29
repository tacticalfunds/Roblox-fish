# Install guide (Astra)

One page for every guarded installer in `tools/`, in the order to run them,
and how to undo them. The details and the Studio checklists stay in each
package's README (linked below).

**Rules for every script here**

- Run it in **Edit mode** (stop Play): paste the whole file into the Command
  Bar and press Enter. Each one refuses in Play.
- It checks everything first (backup folders, and the **exact source** of
  every script it changes or relies on) and changes **nothing** if anything
  differs. The warning names the first differing line.
- It makes **one undo step**. It backs up each changed script to its
  `ServerStorage` backup folder (Target + Before/After copies).
- Its rollback restores the Before sources exactly, and removes anything it
  added. It refuses if a script was edited since the install.
- Nothing here touches `Workspace.FishGrinder`, uses HTTP or
  `require(assetId)`, or grants Money.

## Where Studio is now

As reported by Astra, 2026-09-28:

- rod offers `a826d73` (`EconomyRodOffersBackup`)
- aquarium v1.2 (`EconomyAquariumBackup`)

Nothing below is installed yet.

## Install order

Install top to bottom. Skip any row you don't want: the "Needs" column says
what each one relies on. The installer sim runs this exact sequence (all 10)
and rolls it all back.

| # | File | What it does | Needs | Backup folder |
|---|---|---|---|---|
| 1 | [`economy/InstallSales.lua`](economy/README.md#sale-payouts-installsaleslua) | Meat pays its owner once, when it sells | rod offers + aquarium v1.2 | `EconomySalesBackup` |
| 2 | [`economy/InstallUpgrades.lua`](economy/README.md#paid-aquarium-upgrades-installupgradeslua) | Aquarium upgrades cost Money | 1 | `EconomyUpgradesBackup` |
| 3 | [`economy/InstallEarnings.lua`](economy/README.md#earnings-popup-installearningslua) | "+$N" popup for the owner on each sale | 1; **after 2** if you use 2 | `EconomyEarningsBackup` |
| 4 | [`economy/InstallBotRecovery.lua`](economy/README.md#blender-bot-recovery-installbotrecoverylua) | Blender Bot survives errors without losing meat | 1; **before 9** | `EconomyBotBackup` |
| 5 | [`fish-jump/InstallFishJump.lua`](fish-jump/README.md) | Fish jump out of the water now and then | the live FishSwimClient | `FishJumpBackup` |
| 6 | [`rod-cast/InstallRodCast.lua`](rod-cast/README.md) | Rods cast the moment the button is pressed | 1 | `RodCastBackup` |
| 7 | [`grinder-dwell/InstallGrinderDwell.lua`](grinder-dwell/README.md) | Fish tumble ~1 s on the grinder rollers | 1; **after 5 and 6** if used | `GrinderDwellBackup` |
| 8 | [`fish-variants/InstallFishVariants.lua`](fish-variants/README.md) | Rare Silver / Gold fish | 1; **after 2, 6, 7** if used | `EconomyVariantsBackup` |
| 9 | [`fish-variants/InstallMeatGlow.lua`](fish-variants/README.md#glow-on-moved-meat-installmeatglowlua) | Variant meat keeps its glow when moved | 8; **after 4** if used | `EconomyMeatGlowBackup` |
| 10 | [`fish-jump/InstallHarpoonBlend.lua`](fish-jump/README.md#harpoon-mid-jump-fix-installharpoonblendlua) | No snap when a jumping fish is harpooned | 5; **after 7** if used | `HarpoonBlendBackup` |

"After X" matters because both change the same script. The later installer
knows X's version; the earlier one doesn't, so running them the other way
round is refused, with nothing changed.

## Rollback order

Exactly the reverse: **10 → 1**, then, if you ever need to go further,
`economy/RollbackAquariumV12.lua` and `economy/UninstallRodOffers.lua`.

| # | Rollback file |
|---|---|
| 10 | `fish-jump/RollbackHarpoonBlend.lua` |
| 9 | `fish-variants/RollbackMeatGlow.lua` |
| 8 | `fish-variants/RollbackFishVariants.lua` |
| 7 | `grinder-dwell/RollbackGrinderDwell.lua` |
| 6 | `rod-cast/RollbackRodCast.lua` |
| 5 | `fish-jump/UninstallFishJump.lua` |
| 4 | `economy/RollbackBotRecovery.lua` |
| 3 | `economy/RollbackEarnings.lua` |
| 2 | `economy/RollbackUpgrades.lua` |
| 1 | `economy/RollbackSales.lua` |

A rollback run too early refuses, with nothing changed. It names the backup
folder of the install you have to roll back first, or the script that still
carries a later install.

## Studio checklists

Each README has a short table for its install: sales `S#`, upgrades `U#`,
earnings `E#`, bot recovery `B#`, variants `V#`, meat glow `G#`, harpoon
blend `H#`. Fish jumps, rod cast and dwell have theirs in their READMEs.

## Client input audit (2026-09-29)

Every way a client can reach the server, in the scripts in this repo:

| Input | Guard |
|---|---|
| `PressFishButton` (RodFishingSystem) | 0.6 s per-player cooldown, within 80 studs, only when rods are ready, only with a free aquarium spot. Rod fish must be bought; nothing is free |
| `Economy.OfferAction` (buy a rod fish) | rate-limited per player; the server checks the offer, the caster, the expiry, alive, within reach of the stand, and Money, all in one step with no yields between |
| Aquarium Release / upgrade prompts | the server checks alive and in range (prompt distance + slack) before acting or charging |
| `RodShopServer` buy | charged through EconomyService; shop closed until rods do something |
| Net pad (`Touched`) | one shared lift cycle (~2.6 s), weight limit, refuses while the grinder is backed up |
| Truck carry / delivery | server-side, from the player's position; carriers are never paid, and each piece pays its owner once |
| `Economy.Notice`, `Economy.Earned` | server → client only; the client ignores malformed values |

**Not audited, source needed:** CarSalesServer (the truck unlock, Max Line,
Car Speed and customer upgrades), TruckClient and any UI scripts. Please
paste them if you want those checked.

**Inherent limit:** player position comes from the client, so an exploiter
can teleport between the stack, the net pad and the trucks. That only
speeds up hauling. It creates no Money: every piece's value is fixed when
the fish is ground, and only its owner is paid, once.

## Open decisions (nothing coded)

- **Aquarium upgrades reset each server while Money is saved.** Options: save
  tank levels, or sell them as a per-session boost.
- **Rod shop:** what owning a rod does, and whether it's saved (it stays
  closed until then).
- **Robux items** (e.g. the harpoon, as HarpoonSystem's comment suggests):
  which items, and prices.
