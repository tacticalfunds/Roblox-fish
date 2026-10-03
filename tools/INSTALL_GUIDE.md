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

As reported by Astra, 2026-09-29 (user authorised the remaining installs):

- rod offers `a826d73` (`EconomyRodOffersBackup`), aquarium v1.2
  (`EconomyAquariumBackup`)
- **installed:** rows 1, 2, 4, 5, 6, 7, 8, 11: sales `91121de`, Money HUD
  `b1c0f59`, earnings `0829fc9`, bot recovery, fish jumps, rod cast, grinder
  dwell, harpoon blend (each with its backup folder)
- **deliberately not installed:** row 3, paid aquarium upgrades (levels
  aren't saved; see open decisions)
- **installed since:** row 9, variants (`28a9b3f`), and row 10, meat glow
- **installed since:** row 12, the aquarium panel (`0e64dd2`); rows 13-15
  (jump rate, rods, rod shop UI) were installed **pending validation**: Play
  couldn't be run yet, so runtime, visuals and persistence are unverified.
  The paid shop is still closed.
- **installed by Astra since** (not from this repo): the GrinderUpgrades
  system (`GrinderUpgradesBackup`: conveyor, blades, the KG signs with their
  own store, the blade multiplier in EconomyService) and `BillboardLockBackup`
- **installed by Astra (2026-10-03):** row 16, `InstallBoardUpgrades.lua` at
  `fffdaa3` (all 16 targets verified, `EconomyBoardUpgradesBackup`); paid
  upgrades closed
- **next:** row 17, `InstallBoardArt.lua`: the board on the place's own
  four-card art (`StarterGui.UpgradeBoardGui`)

**Not production-ready as a whole:** paid upgrades (row 3) and the live Car
Sales upgrades reset every server while the Money spent stays saved. See
[Open decisions](#open-decisions-nothing-coded).

## Install order

Install top to bottom. Skip any row you don't want: the "Needs" column says
what each one relies on. The installer sim runs this exact sequence (all 11,
from before sales) and rolls it all back, checking the state after each
rollback.

| # | File | What it does | Needs | Backup folder |
|---|---|---|---|---|
| 1 | ~~[`economy/InstallSales.lua`](economy/README.md#sale-payouts-installsaleslua)~~ **installed** | Meat pays its owner once, when it sells | rod offers + aquarium v1.2 | `EconomySalesBackup` |
| 2 | [`economy/InstallMoneyHud.lua`](economy/README.md#money-hud-installmoneyhudlua) | Both money labels show `leaderstats.Money` (they were stuck) | rod offers; independent of the rest | `EconomyMoneyHudBackup` |
| 3 | [`economy/InstallUpgrades.lua`](economy/README.md#paid-aquarium-upgrades-installupgradeslua) | Aquarium upgrades cost Money. **Levels not saved: see open decisions** | 1 | `EconomyUpgradesBackup` |
| 4 | [`economy/InstallEarnings.lua`](economy/README.md#earnings-popup-installearningslua) | "+$N" popup for the owner on each sale (real amount; "pending" while Money loads) | 1; **after 3** if you use 3 | `EconomyEarningsBackup` |
| 5 | [`economy/InstallBotRecovery.lua`](economy/README.md#blender-bot-recovery-installbotrecoverylua) | Blender Bot survives errors without losing meat | 1; **before 10** | `EconomyBotBackup` |
| 6 | [`fish-jump/InstallFishJump.lua`](fish-jump/README.md) | Fish jump out of the water now and then | the live FishSwimClient | `FishJumpBackup` |
| 7 | [`rod-cast/InstallRodCast.lua`](rod-cast/README.md) | Rods cast the moment the button is pressed | 1 | `RodCastBackup` |
| 8 | [`grinder-dwell/InstallGrinderDwell.lua`](grinder-dwell/README.md) | Fish tumble ~1 s on the grinder rollers | 1; **after 6 and 7** if used | `GrinderDwellBackup` |
| 9 | [`fish-variants/InstallFishVariants.lua`](fish-variants/README.md) | Rare Silver / Gold fish | 1; **after 3, 7, 8** if used | `EconomyVariantsBackup` |
| 10 | [`fish-variants/InstallMeatGlow.lua`](fish-variants/README.md#glow-on-moved-meat-installmeatglowlua) | Variant meat keeps its glow when moved | 9; **after 5** if used | `EconomyMeatGlowBackup` |
| 11 | [`fish-jump/InstallHarpoonBlend.lua`](fish-jump/README.md#harpoon-mid-jump-fix-installharpoonblendlua) | No snap when a jumping fish is harpooned | 6; **after 8** if used | `HarpoonBlendBackup` |
| 12 | [`aquarium-panel/InstallAquariumPanel.lua`](aquarium-panel/README.md) | One custom aquarium panel at the loader pad (Release Fish + one upgrade card) instead of three default prompts; upgrades shown as not available | aquarium v1.2; **the released row 3 refuses after it** | `AquariumPanelBackup` |
| 13 | [`fish-jump/InstallJumpRate.lua`](fish-jump/README.md#jump-more-often-installjumpratelua) | Fish jump about twice as often (periods 16–28 s → 8–14 s) | 6 | `FishJumpRateBackup` |
| 14 | [`economy/InstallRods.lua`](economy/README.md#rods-milestone-1-installrodslua) | Rods owned for good (saved with Money), equipped, faster bites; paid shop stays closed | 4 and 9 | `EconomyRodsBackup` |
| 15 | [`economy/InstallRodShopUI.lua`](economy/README.md#rod-shop-ui-installrodshopuilua) | Shop cards show price / OWNED / benefit / EQUIPPED and the server's real answers | 14 | `EconomyRodShopUIBackup` |
| 17 | [`economy/InstallBoardArt.lua`](economy/README.md#board-art-installboardartlua) | The board on the place's own four-card art: binds each player's `PlayerGui.UpgradeBoardGui` (Desc / Btn.Price texts only), reach measured to `Workspace["Upgrade board"].Screen`; the generated board on the old Workspace.Board is gone (that board is left as it is) | 16 (exact installed sources) | `EconomyBoardArtBackup` |
| 16 | [`economy/InstallBoardUpgrades.lua`](economy/README.md#upgrade-board-on-the-live-baseline-installboardupgradeslua) | The four-card upgrade board (Net Strength, Rod Luck, Meat Price, Faster Reels) and ONE saved net capacity sold by the KG posts and the board; earlier GrinderUpgrades KG buys adopted (idempotent); GrinderUpgrades conveyor / blades kept, hardened; customers for every player (CustomerSystem) and fast-start prices; paid upgrades closed | 14 and the GrinderUpgrades system (exact live sources) | `EconomyBoardUpgradesBackup` |

"After X" matters because both change the same script. The later installer
knows X's version; the earlier one doesn't, so running them the other way
round is refused, with nothing changed.

## Rollback order

Exactly the reverse: **17 → 1**, then, if you ever need to go further,
`economy/RollbackAquariumV12.lua` and `economy/UninstallRodOffers.lua`.
Row 2 (Money HUD) touches nothing else, so its rollback works at any time.

| # | Rollback file |
|---|---|
| 17 | `economy/RollbackBoardArt.lua` (before 16; restores the board release's two board scripts) |
| 16 | `economy/RollbackBoardUpgrades.lua` (before 14; restores the live GrinderUpgrades scripts; refused while 17 is in) |
| 15 | `economy/RollbackRodShopUI.lua` (before 14) |
| 14 | `economy/RollbackRods.lua` (before 4 and 9) |
| 13 | `fish-jump/RollbackJumpRate.lua` (before 6) |
| 12 | `aquarium-panel/RollbackAquariumPanel.lua` (independent of 4–11) |
| 11 | `fish-jump/RollbackHarpoonBlend.lua` |
| 10 | `fish-variants/RollbackMeatGlow.lua` |
| 9 | `fish-variants/RollbackFishVariants.lua` |
| 8 | `grinder-dwell/RollbackGrinderDwell.lua` |
| 7 | `rod-cast/RollbackRodCast.lua` |
| 6 | `fish-jump/UninstallFishJump.lua` |
| 5 | `economy/RollbackBotRecovery.lua` |
| 4 | `economy/RollbackEarnings.lua` |
| 3 | `economy/RollbackUpgrades.lua` |
| 2 | `economy/RollbackMoneyHud.lua` |
| 1 | `economy/RollbackSales.lua` |

A rollback run too early refuses, with nothing changed. It names the backup
folder of the install you have to roll back first, or the script that still
carries a later install.

## Studio checklists

Each README has a short table for its install: aquarium panel `A#`, sales `S#`, Money HUD `M#`,
upgrades `U#`, earnings `E#`, bot recovery `B#`, variants `V#`, meat glow
`G#`, harpoon blend `H#`, rods `R#`, net capacity `K#`, upgrade board `N#`,
Rod Luck `L#`, Meat Price `P#`, Faster Reels `F#`, live-baseline integration `G#`.
Fish jumps, rod cast and dwell have theirs in their READMEs.

## Client input audit (2026-09-29)

Every way a client can reach the server, in the scripts in this repo:

| Input | Guard |
|---|---|
| `PressFishButton` (RodFishingSystem) | 0.6 s per-player cooldown, within 80 studs, only when rods are ready, only with a free aquarium spot. Rod fish must be bought; nothing is free |
| `Economy.OfferAction` (buy a rod fish) | rate-limited per player; the server checks the offer, the caster, the expiry, alive, within reach of the stand, and Money, all in one step with no yields between |
| Aquarium Release / upgrade prompts | the server checks alive and in range (prompt distance + slack) before acting or charging. With the panel (row 12) they are Custom-style prompts; upgrade prompts exist only with a currency binding |
| `RodShopServer` buy | charged through EconomyService only (row 14: fail closed, alive, loaded, near the shop, in stock, one at a time, saved before it counts); paid shop closed until validated |
| Net pad (`Touched`) | one shared lift cycle (~2.6 s), per-player weight limit (`NetMaxWeight`, else the unchanged `MaxWeight`), refuses while the grinder is backed up |
| +5 KG sign clicks (row 16) | NetCapacityServer only (board and price plate ClickDetectors; GrinderUpgradesServer no longer sells KG): alive, loaded, earlier buys adopted, near the clicked part, one purchase at a time, cooldown, re-checked before the debit, saved with the money in one write; paid signs closed until validated |
| GrinderUpgrades pads (conveyor, blades) | touch on the server, alive, 1.5 s per pad; charged through EconomyService, saved in its own store; journaled: debit + open entry saved first, settled against the pad store's token (kept or refunded; after a shutdown or a slow write, at the next load); no memory store outside Studio; unreadable records never overwritten |
| `Economy.UpgradeAction` (row 16, the upgrade board) | known card ids only (strings), 0.25 s between presses; Net Strength goes through the same net purchase as the posts with "near the board" as the place check; Rod Luck, Meat Price and Faster Reels through `upgradeAction` with the same checks (alive, loaded, near the board, one at a time, cooldown, re-checked before the debit, saved before it counts) |
| Truck carry / delivery | server-side, from the player's position; carriers are never paid, and each piece pays its owner once |
| `Economy.Notice`, `Economy.Earned` | server → client only; the client ignores malformed values |
| Money HUD | reads `leaderstats.Money` only; sends nothing |

**Not audited, source needed:** CarSalesServer (the truck unlock, Max Line,
Car Speed and customer upgrades), TruckClient and any UI scripts. Please
paste them if you want those checked.

**Inherent limit:** player position comes from the client, so an exploiter
can teleport between the stack, the net pad and the trucks. That only
speeds up hauling. It creates no Money: every piece's value is fixed when
the fish is ground, and only its owner is paid, once.

## Open decisions (nothing coded)

- **Upgrade levels reset each server while Money is saved (unresolved).**
  - Paid aquarium upgrades (row 3): Tank Capacity / Release Rate levels
    live only in the server session.
  - The live Car Sales upgrades already do the same: CarSalesServer charges
    through `EconomyService.tryDebit` (the one Money), but the truck unlock,
    Max Line, Car Speed and customer levels live only in player attributes.
  - Options: save the levels, or sell them as a per-session boost and say so
    in the prompt. Nothing here picks a policy; until one is chosen, these
    upgrades are **not production-ready**.
- **Rod shop (row 14 coded):** rods are saved, equipped and speed up bites;
  the paid shop stays closed until it's validated in Studio with API
  access, with row 15 (the shop UI) in. Still open: swapping the dock rod
  visuals. **Don't install / enable rods until the review of rows 14-15 is
  done.**
- **HUD multiplier labels** (Rebirth, Robux, Friends, VIP): the Money HUD
  hides them because their inputs don't exist, and no payout applies any
  multiplier. If those systems come, their payouts need a design first.
- **Robux items** (e.g. the harpoon, as HarpoonSystem's comment suggests):
  which items, and prices.
