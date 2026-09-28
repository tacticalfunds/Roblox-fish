# Grinder roller dwell

Fish arriving at the grinder now land on top of the rollers, tumble and
shudder there for about a second, then spiral in and shrink, as before. No
gore. Everything happens at the same `GrinderPos`, and aquarium routing is
unchanged.

## Timeline

`ReplicatedStorage.GrinderDwell` is the single source for every path:

| Phase | Seconds | Notes |
|---|---|---|
| rise | 0.12 | original |
| fly | 0.95 | original, ends exactly at `GrinderPos` |
| **dwell** | **1.0** | new |
| drop | 0.55 | original spiral and shrink |

- **Server timing:** the server destroys the fish and fires `FishCaught`
  once, at `serverDelay()` = 2.65 s. That's the client's 2.62 s plus the
  original 0.03 s slack; before the patch it was 1.65 s.
- **Dwell motion:** the fish settles from `GrinderPos` to `OffsetY` (−0.8)
  over 0.15 s. It then shudders upward only (≤0.12 studs, fading in and out)
  and tumbles at 4 rad/s. It drifts to exactly where the spiral starts, so
  the drop no longer snaps 1.2 studs sideways as the original did.
- **Per-fish:** everything is a pure function of the fish's own time and
  seed, so overlapping catches share no visual state.

**Tuning:** edit `Dwell` or `OffsetY` in the module. Raise `OffsetY` if fish
clip into the housing, lower it if they hover. It's placed relative to
`GrinderPos` because I haven't seen the roller geometry.

## Rebased 2026-09-28 (economy chain)

The patches are regenerated for the scripts that can be live now. The
installer picks the right one by exact source.

| Script | Accepted versions | Change |
|---|---|---|
| FishSwimClient | live, or fish-jump (rebased on live) | Adds the dwell phase to the `CaughtT` launch (the jump start point is kept). **New:** the live **harpoon** branch also rests on the rollers before its suck. |
| NetLiftScript | sale-payout version | `task.delay(1.65)` becomes `task.delay(Dwell.serverDelay())`. It fires once, with the owner payload unchanged. |
| HarpoonSystem | sale-payout version | **New:** `FishCaught` fires after `TOSS + Dwell + SUCK`. It fires once, with the owner payload unchanged. |
| RodFishingSystem | sale-payout, or rod-cast | The grinder fallback (offers off, and the aquarium not taking the fish) plays the same dwell and drop server-side before `FishCaught` fires once. |

Without the module, all of them behave exactly like their base versions.

## Install and rollback

- **Install:** `tools/grinder-dwell/InstallGrinderDwell.lua`, built from the
  economy's guarded update template (v2). It:
  - checks exact sources, with alternatives per script; a refusal names the
    first differing line
  - records one undo step
  - backs up the 4 scripts to `ServerStorage.GrinderDwellBackup`
  - adds `ReplicatedStorage.GrinderDwell`, tagged `EconomyOwned`
- **Order:** install after InstallSales. Fish jumps and rod cast are
  optional, but install them first.
- **Rollback:** `tools/grinder-dwell/RollbackGrinderDwell.lua` restores all 4
  scripts exactly and removes the module, only if it wasn't edited. Roll it
  back before rod cast, jumps or sales: those rollbacks refuse while it's in.
- **Build-time sync check:** every client path must take its timeline from
  the module, and the net and harpoon servers must fire after the client
  animation.

**Studio checklist:**

| # | Do | Expect |
|---|---|---|
| D1 | Net some fish | They land on top of the rollers, tumble about 1 s, then spiral in; meat appears once per fish |
| D2 | Let the harpoon catch one | Same rest on the rollers, then sucked in; meat once |
| D3 | Look at the rest height | Fish sit on the rollers: raise `OffsetY` in the module if they clip, lower it if they hover |
| D4 | Sale payouts | Unchanged: each piece still pays its owner once when sold |

## Checks run

- `luau tools/grinder-dwell/tests/dwell.test.luau`: 20/20 pass (timeline,
  continuity, frame steps, independence).
- **`tools/economy/tests/sim/dwell_sim.luau`** (17 checks) runs the **real**
  patched FishSwimClient (jump version) and RodFishingSystem (rod-cast
  version) with the module on the fake engine:
  - net and harpooned fish land on the rollers, rest there tumbling, then
    spiral in and shrink
  - the rod grinder fallback rests server-side and fires `FishCaught` exactly
    once, after the rest
  - mutations caught: no client dwell, no rod dwell, no harpoon dwell
- **Installer dry run** (tools/economy): it refuses before sales, installs in
  all 4 combinations of jumps and rod cast with the matching variants, adds
  and removes the module, blocks earlier rollbacks, and rolls back exactly.
- **Not Roblox runtime tested:** see the checklist above.
