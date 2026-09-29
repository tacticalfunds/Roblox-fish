# River fish jumps (visual only)

River fish occasionally jump out of the water: a short, size-aware arc with
the nose following it and the body wiggle kept, plus a small splash disc on
takeoff and landing. This patches the live `FishSwimClient` minimally and adds
one pure module. It is independent of the aquarium install, so either can go
in first.

## Rebased on the live client (2026-09-28)

- **Base:** `studio/FishSwimClient.original.lua` is now the **live**
  `FishSwimClient` that Astra supplied, including its harpoon branch. The
  patch was re-applied with a clean three-way merge.
- **Harpoon order:** the harpoon branch still runs first. A harpooned fish
  never jumps.
- **Harpooned mid-jump:** the pull starts from the harpoon's hit point, which
  is at water level, because the server doesn't know about the client-only
  jump. That fish drops to the water as the rope pulls. It's rare and
  cosmetic.
- **Independent install:** this feature doesn't depend on the economy or the
  aquarium, and none of their installers change `FishSwimClient`.
- **Edit mode:** the installer and uninstaller now refuse to run in Play.

**Studio checklist:**

| # | Do | Expect |
|---|---|---|
| J1 | Play and watch the river for a minute | Fish jump now and then, not in sync, with a splash on takeoff and landing |
| J2 | Net a fish while it's in the air | It launches from the air into the grinder (no snap down) |
| J3 | Let the harpoon fire | Harpooned fish are pulled in exactly as before |
| J4 | Set `Workspace.SwimmingFish.JumpEnabled = false` during Play | Jumps stop within a few seconds |
| J5 | Uninstall | The client source is back to the live version |

## Install and uninstall (Studio, Edit mode, Command Bar)

- Install: `tools/fish-jump/InstallFishJump.lua` (generated). One undo step.
  It requires exactly one LocalScript `FishSwimClient` whose source matches
  `studio/FishSwimClient.original.lua`, backs it up to
  `ServerStorage.FishJumpBackup`, patches it, and adds
  `ReplicatedStorage.FishJump`.
- Uninstall: `tools/fish-jump/UninstallFishJump.lua`. It restores the original
  source and removes only objects tagged `FishJumpOwned`. It refuses if the
  client was edited after install.
- Tuning and kill switch, applied live: set attributes on
  `Workspace.SwimmingFish`:
  - `JumpEnabled` (bool)
  - `JumpChance` (0–1 per period; default 0.35)
  - `JumpHeightScale` (multiplier)

  Other defaults are in `src/FishJump.luau`.

## How it works

- **Schedule:** each fish has a period of 16–28 s and a time offset, both
  from its `Seed`. Each period it jumps with probability `Chance`, decided by
  an exact 32-bit integer hash of (Seed, cycle). Everything is a pure
  function of server time, so all clients agree, jumps are staggered, and a
  player joining mid-jump sees the same arc.
- **Frequency:** on average about 1.4% of fish are airborne at any moment.
  Very rarely a handful coincide.
- **Path:** only height and pitch change. x/z stay on the original lane path,
  and jumps are skipped within 6 studs of the river's ends so the whole arc
  stays in bounds. Height is `SwimLen × 0.45`, clamped to 1.2–3.2 studs.
  `CrystalSerpent` doesn't jump.
- **Net catches take priority immediately.** The `CaughtT` branch runs before
  any jump logic, and the launch starts from the fish's current jump height,
  so there's no snap. Catch eligibility (NetLiftScript uses only x/z from the
  spawn attributes) and rewards are unchanged.
- **Splashes:** discs come from a fixed pool of 10 parts that are reused, and
  fade out over 0.5 s. A splash only fires for jumps the client saw take off,
  so a late joiner doesn't get a burst of splashes.
- **Fallback:** without the module (uninstalled, or it fails to load), the
  client behaves exactly like the original.

## Checks run

- `luau tools/fish-jump/tests/jump.test.luau`: 28 offline checks pass. They
  use realistic server times (~1.7e9) and the live seed ranges (spawner 1..N,
  aquarium 1e6+N), and cover:
  - the airborne fraction is near expected
  - every fish jumps within 10 minutes
  - arc shape and bounds
  - the end margin
  - attribute overrides
- The patched client and both installer scripts compile. luau-lsp reports only
  same-line style lints, all on lines unchanged from the original.
- **No Roblox runtime test yet.** In a Studio playtest:
  - fish jump now and then, not in sync
  - a splash on takeoff and landing
  - netting a mid-air fish launches it smoothly into the grinder
  - setting `JumpEnabled = false` stops jumps immediately
  - frame rate holds with 60 fish on mobile emulation

## Harpoon mid-jump fix (`InstallHarpoonBlend.lua`)

**The bug:** jumps are drawn on each client, and the harpoon aims at the
fish's swim line. A fish struck in the air snapped straight down to the water
on the first frame of the pull.

**The fix** (FishSwimClient only): the pull starts from the fish's height in
the air at `HarpoonT`, worked out from the same jump the client drew, and
eases down onto the rope over the 0.6 s pull. After that the harpoon path is
unchanged: toss, grinder dwell if installed, then suck. Timing is unchanged
too, so the server's reel/toss/suck still match. A fish that wasn't jumping
is pulled exactly as before.

- **Bases:** the fish-jump client, or grinder dwell on top of it. The
  installer picks the matching patch by exact source.
- **Install:** after `InstallFishJump.lua` (the `FishJump` module is checked
  by source). If you use grinder dwell, install it **first**: it refuses once
  this has changed the client. Backup: `ServerStorage.HarpoonBlendBackup`.
- **Rollback:** `RollbackHarpoonBlend.lua`, before `UninstallFishJump` and
  `RollbackGrinderDwell` (both refuse while it's in).
- **Tested:** `tools/economy/tests/sim/harpoonblend_sim.luau` (15 checks) runs
  the real patched client on both bases. A fish struck mid-jump starts in the
  air, is exactly halfway down at mid-pull and on the rope end by the end,
  then reaches the grinder. A swimming fish is unchanged. The unpatched
  client is shown snapping.

| # | Do | Expect |
|---|---|---|
| H1 | Set `SwimmingFish.JumpChance` high for a test; watch the harpoon hit a jumping fish | The fish is dragged down from the air onto the rope, no jump cut |
| H2 | Harpoon hits a swimming fish | Same as before |
