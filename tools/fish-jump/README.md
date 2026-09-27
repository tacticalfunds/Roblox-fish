# River fish jumps (visual only)

River fish occasionally jump out of the water: a short, size-aware arc with
the nose following it and the body wiggle kept, plus a small splash disc on
takeoff and landing. This patches the live `FishSwimClient` minimally and adds
one pure module. It is independent of the aquarium install, so either can go
in first.

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
