# Aquarium cycle (dock rods → aquarium → river)

Rod catches from the five shared dock rods go into the one `FishTank`
instead of the grinder. Players release them back into
`Workspace.SwimmingFish`, where they swim, can be netted, and go through the
grinder as usual. The net → grinder → conveyor → customer/truck route is
unchanged. Releasing pays nothing.

## Install and uninstall (Studio, Edit mode, Command Bar)

| Step | File |
|---|---|
| Install | `tools/aquarium-cycle/InstallAquariumCycle.lua` (generated; paste the whole file) |
| Uninstall | `tools/aquarium-cycle/UninstallAquariumCycle.lua` |
| Kill switch | Untick `Enabled` on `ReplicatedStorage.AquariumCycle`. Rod catches go back to the grinder, and mid-play any tank fish are put back in the river. |

The installer changes nothing unless every check passes. It requires exactly
one `RodFishingSystem` Script in ServerScriptService whose source matches
`studio/RodFishingSystem.original.lua` (whitespace-normalized), exactly one
BasePart named `BaseWater` anywhere under `Workspace.FishTank` (live:
`FishTank.Base5.BaseWater`), `SwimmingFish` with numeric bounds,
`SwimTemplates` and `FishModels`. The install is one undo step.

**What it changes:**
- **Patched:** `ServerScriptService…RodFishingSystem`. The original and
  patched copies are saved, disabled, in `ServerStorage.AquariumCycleBackup`.
- **Added:** `ReplicatedStorage.AquariumCycle`, holding 8 pure ModuleScripts,
  a `Bindings` folder of ObjectValues, and the `Enabled` attribute.
- **Added:** `ServerScriptService.AquariumCycleServer` (ModuleScript) and
  `ServerScriptService.AquariumEconomy` (ModuleScript; returns nil, so no
  currency).
- **Added:** `StarterPlayer.StarterPlayerScripts.AquariumTankClient`
  (LocalScript).

Every added object is tagged `AquariumCycleOwned`, and the uninstaller removes
only tagged objects. It restores the original source unless the patched script
was edited after install; in that case it stops and says so.

**Bindings the installer writes** (the runtime reads only these, never
guessing names):

| Binding | Points at | Required |
|---|---|---|
| `TankWater` | `FishTank.Base5.BaseWater` (the one `BaseWater` under `FishTank`) | yes |
| `River` | `SwimmingFish` | yes |
| `SwimTemplates`, `FishModels` | the ReplicatedStorage folders | yes |
| `Loader` | `FishLoader` | optional |
| `CountPrompt` | `Model.Road.ProximityPrompt` | optional; only if exactly one match with `BillboardGui.TextLabel` = "Fish available" and an `Amount` label |

## RodFishingSystem changes

Every change is marked `AquariumCycle` in `studio/RodFishingSystem.patched.lua`.
Diff it against the `.original.lua` beside it.

- **Before casting:** `press()` reserves one tank spot per idle rod before any
  rod task starts. Rods beyond the free spots stay idle.
- **Tank full:** the button handler tells the presser and doesn't cast, and
  the `PressedAt` press animation doesn't play.
- **At the bite:** the picked fish is attached to the reserved spot.
- **Step 6:** the fish arcs into the tank instead of the grinder. If the
  aquarium is missing, disabled, stopped mid-catch, or refuses, the fish goes
  to the grinder exactly as before (`FishCaught:Fire` with the same
  arguments), so no catch is lost.
- **Error safety:** each rod task runs in `xpcall`. On error it destroys its
  bobber and fish, clears `Pulling`, frees its tank spot and goes idle.
  Previously an error left the rod busy forever.

The weighted pick, silhouette cycling, reveal, button lock and all client
visuals (`RodFishingClient`) are unchanged.

## Runtime behavior

- **One tank for the server.** Capacity is shared, not per player. It starts
  at 3; Release Rate starts at 1 fish per release, with a 4 s cooldown.
- **Count display:** the bound "Fish available" label reads "Fish in tank"
  with `count/capacity`, and turns red when no spot is free.
- **Placeholder prompt:** the "NEW CAR / PLACE CAR" prompt is hidden while
  running (`Config.Scene.HidePlaceholderPrompt`).
- **Prompts at the same spot:** `E` Release Fish, `F` Upgrade Tank Capacity,
  `G` Upgrade Release Rate. The server re-checks distance, a live character
  and a per-player cooldown on every trigger.
- **Returning to the river:** released fish swim to the fish loader and fade
  out on clients. After 3 s the server clones the fish's `SwimTemplate` into
  `SwimmingFish` with FishSpawner's attributes (`SpawnT`, `StartZ`, `Speed`,
  `LaneX`, `Seed`), set before parenting, plus the end-of-river despawn.
- **Tank visuals:** client-side clones of `FishModels`, scaled and swimming a
  smooth path bounded inside the bound `BaseWater` (derived at runtime).

## Known limitations (please review)

1. **Upgrades are unavailable.** The place has no currency consumer, so the
   upgrade prompts say so and nothing is granted. To connect one, make
   `AquariumEconomy` return `{ tryCharge = function(player, amount, reason) }`.
   Prices come from the aquarium's own tables.
2. **Nothing persists.** Levels and tank contents reset each server, and the
   one shared tank has no owner.
3. **Released fish ignore FishSpawner's rare-fish caps.** Released rare fish
   count toward those caps but can push the river above them.
4. **The placeholder prompt is disabled, not reused.** If its count
   BillboardGui turns out to depend on the prompt being enabled, set
   `HidePlaceholderPrompt = false`.
5. **Switching `Enabled` on mid-play does nothing** until the server restarts;
   switching off works immediately.

## Checks run

- `python3 tools/aquarium-cycle/tests/run_tests.py <luau>`: 850 offline
  checks pass (core 477, integration 373). The randomized fuzz tests assert
  every invariant, and that each hooked fish ends in exactly one outcome.
- Every source, the patched RodFishingSystem and both installer scripts
  compile, and type-check clean with luau-lsp (Roblox definitions plus a Rojo
  sourcemap). The only lints are same-line-statement style warnings in lines
  that are unchanged from the original RodFishingSystem.
- The generated installer contains every source verbatim.
- **No Roblox runtime test has been run.** Everything below needs the Studio
  playtest.

## Studio playtest checklist

1. Install. The output lists the bindings; check that CountPrompt and Loader
   are bound.
2. Play. Output shows `[AquariumCycle] running; upgrades unavailable …`.
3. Press the button. Three rods cast and two stay idle (capacity 3), the
   label shows `0/3`, and the fish arc into the tank. They should not go to
   the grinder, and no meat should appear.
4. The tank shows swimming fish and `3/3` in red. Pressing again shows the
   full-tank notice and no rods cast.
5. `E` releases one fish, which swims to the loader. About 3 s later it
   appears at the upstream end of the river and swims normally.
6. Net that fish. It launches into the grinder and meat comes out as usual.
7. `F`/`G` show the upgrades-unavailable notice, and levels don't change.
8. Untick `Enabled` mid-play. Tank fish reappear in the river, rods in flight
   go to the grinder, and the "Fish available" label is restored.
9. Stop, run the uninstaller, and confirm RodFishingSystem matches the
   original with no AquariumCycle objects left.

## Source layout

- `src/shared/`: pure modules (Config, Upgrades, CycleState, Adapters,
  SharedTank, RiverRelease, TankPath, Messages). Studio requires use
  `script.Parent`; `tests/run_tests.py` rewrites them for the Luau CLI.
- `src/server/`, `src/client/`: the Roblox side.
- `studio/`: the reviewed original and patched RodFishingSystem.
- `build/`: the installer generator and template. Rebuild with
  `python3 tools/aquarium-cycle/build/build_installer.py`.
- `default.project.json`: used only to generate a sourcemap for type
  checking. Don't Rojo-sync it into the live place.
