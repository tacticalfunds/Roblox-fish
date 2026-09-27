# Aquarium cycle (dock rods → aquarium → river)

Opt-in, self-contained module for the recycling loop: dock rods lift single
fish into an upgradeable aquarium, and the aquarium releases them back into
the river to be caught again. It is separate from the net/grinder/conveyor
bulk route and from the paused `src/` prototype.

## Status

| Part | State |
|---|---|
| `src/Config.luau` | Done. `Enabled = false` by default. |
| `src/Upgrades.luau` | Done. Explicit per-level tables, clamped levels. |
| `src/CycleState.luau` | Done. Pure, server-authoritative state machine. |
| `src/Adapters.luau` | Contracts only. All adapters default to off. |
| `tests/cycle.test.luau` | Done. Offline pure-logic tests plus a randomized fuzz. |
| Roblox controller, prompts, visuals | **Not started, on purpose.** Waiting for the real source. |
| Installer and uninstaller | **Not started.** Waiting for the scene/source inventory. |

The live place already has `RodFishingClient`, `FishSwimClient`,
`TruckClient`, `NetLiftClient`, `Workspace.SwimmingFish`, `RodCatches`,
`FishTank`, `FishLoader`, `TankPipe`, `FishStockingTruck`, five
`FishingRod1` models, and `ReplicatedStorage.FishModels`, `SwimTemplates`,
`Rods` and `PressFishButton`. The Roblox side of this module must extend that
code, not duplicate or replace it. Nothing is wired until its server source
has been read.

## Core rules (what the tests enforce)

- Every tracked fish is in exactly one place: `River`, `Hooked` (on one rod),
  `Tank` (one owner) or `Releasing` (swimming back). Fish are never
  duplicated or lost; the fuzz test checks the fish count and every
  invariant after each random operation.
- A cast reserves a tank slot up front. When `tank + reserved` would exceed
  capacity, the cast is refused with `tankFull` before any fish is taken.
- Rods and tanks belong to one owner, and every call checks ownership.
- The server picks which river fish gets hooked. Timings (`BiteSeconds`,
  `LiftSeconds`, cast timeout, release swim time and cooldown) are enforced
  in the core, never supplied by the client.
- Upgrade levels are clamped to `[1, max]`. Malformed saved levels fall back
  to level 1.
- Removing an owner or shutting the system down cancels casts and returns
  every fish they hold to the river.
- **No currency is ever created.** Release and return events go to an
  optional payout adapter that decides whether anything is paid. Upgrades
  can't be bought until an economy adapter is installed, and the price
  always comes from the core state, never from the caller.

## Upgrades (tentative numbers)

| Upgrade | Levels 1→4 | Cost to next level |
|---|---|---|
| Tank Capacity | 3 / 6 / 10 / 15 fish | 50 / 150 / 400 |
| Release Rate | 1 / 2 / 4 / 6 fish per release | 40 / 120 / 350 |

The release cooldown is fixed (4 s), so batch size is the one throughput
lever. There's no luck or value upgrade; one can be added later if wanted.

## Proposed controls (no handheld minigame)

- **Rod** (ProximityPrompt on each bound rod): `Cast Rod`. While busy, show
  `Reeling…` with the prompt disabled. When the tank is full, show `Tank Full`
  (disabled) instead of casting.
- **Tank counter** (billboard): `Fish in tank: 2/3`. This replaces the
  placeholder `NEW CAR / PLACE CAR` prompt.
- **Tank prompt**: `Release Fish`, disabled while the tank is empty or on
  cooldown.
- **Upgrade prompts**: `Upgrade Capacity (3 → 6)` and
  `Upgrade Release Rate (1 → 2)`. These appear only once an economy adapter
  exists.

## Proposed bindings (to confirm against the inventory)

No scene names are guessed in code. The installer will create one folder
owned by this module containing `ObjectValue`s that Astra points at existing
objects: each rod model, the tank's swim bounds, the river swim bounds, and
the fish template source. The controller reads only those bindings and
refuses to start if any is missing or has the wrong class. Uninstall removes
only that folder and any runtime objects this module created.

## Running the tests

```sh
luau tools/aquarium-cycle/tests/cycle.test.luau
```

These are offline pure-logic tests. No Roblox runtime test has been run.

The modules use string requires (`require("./Upgrades")`) so the same files
run under the Luau CLI. Before installing, check that Studio accepts these
require-by-string paths for the chosen module layout, or switch them to
`script.Parent` requires.
