# Immediate rod cast

Pressing the big button now casts every eligible rod together, right away,
and the rods visibly dip toward the water. After that everything is as
before: the bite wait, silhouettes, reveal, the buy offer at the rod stand,
and delivery to the tank.

## Rebased 2026-09-28 (economy chain)

- **Server base:** the sale-payout RodFishingSystem
  (`tools/economy/studio/sales/RodFishingSystem.lua`). That is the live rod
  script with the aquarium, rod offers and buyer identity added.
- **Client base:** the live RodFishingClient, unchanged since Astra supplied
  it.
- **Install order:** InstallRodOffers → UpgradeAquariumV12 → InstallSales →
  **InstallRodCast**.
- **Earlier bases dropped:** the from-aquarium / from-variants bases were
  pre-live originals that are no longer in Studio.

## What changes

**RodFishingSystem:**

- **No delays:** Astra's 0.05 s `PRESS_DELAY` and the 0.12 s per-rod stagger
  are removed.
- **One synchronous press:** `press()` doesn't yield and returns whether the
  press was accepted. It claims the button lock and every rod's busy state
  before anything else can run, so rapid presses can't double-cast.
- **Button animation:** the button animates for other players (`PressedAt`)
  only when the press was accepted. These start nothing and don't animate:
  - a full tank or a lost reservation
  - busy rods or the cooldown
  - fish buying being unavailable (fail closed)
- **Rod dip:** each rod gets `CastT0` when its cast starts. It's cleared when
  the reel starts, and on the error path.
- **Unchanged:** offers, the fail-closed checks, the buyer carried as
  `OwnerId`, the cooldown, the 80-stud check and reservations.

**RodFishingClient:** while `CastT0` is set, the rod dips by `CAST_DIP_DEG`
(−14°) over 0.18 s and rests low with a gentle sway. The existing reel tug
takes over when `Pulling` starts. In the test, a negative angle lowers the
tip toward +X (the river). **If rods tilt up instead of down in Studio, flip
the sign of `CAST_DIP_DEG`**; the real pivot may differ from the test model.

## Install / rollback (Studio, Edit mode, Command Bar)

- **Install:** `tools/rod-cast/InstallRodCast.lua`. It's built from the
  economy's guarded update template:
  - it checks both scripts' exact sources first, and a refusal names the
    first differing line
  - it records one undo step
  - it backs up both scripts to `ServerStorage.RodCastBackup`
- **Rollback:** `tools/rod-cast/RollbackRodCast.lua` restores the sale-payout
  versions exactly. `RollbackSales` refuses while this is installed.

## Tests

- **`tests/sim/rod_sim.luau`** in tools/economy (23 checks). It runs the
  **real** patched RodFishingSystem and RodFishingClient with the real
  EconomyService/EconomyClient and a recording stub aquarium, and checks:
  - all rods cast in the same frame with the same `CastT0`
  - spam and a second player don't double-cast
  - the rod tip dips toward the river on the client
  - each hooked fish carries its caster as `OwnerId`
  - buying at the rod stand charges once and lands the fish
  - unbought fish are aborted with no charge
  - a full tank or a lost reservation neither casts nor animates
  - with offers switched off, the free fish path works and no owner is
    claimed

  Mutations caught: the unpatched base, a flipped dip sign, a dropped buyer,
  and animating on refused presses.
- **Installer dry run:** it refuses before sales, installs on sales, blocks
  `RollbackSales`, and rolls back exactly.

**Studio checklist:**

| # | Do | Expect |
|---|---|---|
| C1 | Press the button | Every eligible rod dips **down toward the water** the instant you press |
| C2 | Watch the rest | Bite, reveal, buy prompt at the stand and tank delivery as before |
| C3 | Press with a full tank | Nothing casts; the button doesn't animate for others |
| C4 | Spam the button | Only one cast per rod |
