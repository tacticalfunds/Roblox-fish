# Aquarium panel

One compact panel at the aquarium's loader pad, replacing the three stacked
default prompts (E Release Fish, F Capacity, G Release Rate). Styled like the
rod Buy panel: dark box, bold FredokaOne white text with thick dark outlines,
lime outlined keycaps and buttons.

```
┌──────────────────────────────┐
│ [E]  Release Fish            │
│      2/3 fish in tank        │
├──────────────────────────────┤
│ <      Tank Capacity       > │
│          Now 3 fish          │
│ [ Not available yet        ] │
└──────────────────────────────┘
```

| What | Keyboard | Gamepad | Touch / mouse |
|---|---|---|---|
| Release Fish | E | X | tap the Release row |
| Switch card (Tank Capacity ↔ Release Amount) | ← / → | D-pad ← / → | tap `<` / `>` |
| Buy the shown upgrade (only when upgrades exist) | F | Y | tap the Upgrade button |

- **One panel at a time:** it only appears while you're in range of the pad
  and alive. It disappears when you walk away, die, or the aquarium stops.
  Its arrow-key / D-pad binding goes with it.
- **Paid upgrades are not installed** (levels aren't saved yet). The card
  shows the current level and says **Not available yet**; the button is
  grey. The server creates **no upgrade prompt** in this case, so nothing
  can be bought or charged. Release Fish works as before.
- **Server authority:** every action is a native ProximityPrompt trigger
  (`Style = Custom`, so Roblox draws nothing). The server checks the same
  things as before: alive, within range, cooldown, and (for upgrades) the
  charge through the currency binding. The client only draws the panel and
  switches which card's prompt is on for itself. A spoofed trigger from far
  away is refused.
- **Later, with a currency binding** (`ServerScriptService.AquariumEconomy`
  returning one): both upgrade prompts exist on F / gamepad Y. Each client
  turns on only the card it shows, so F buys exactly what the card says.
  The card shows `3 → 6 fish` and `Upgrade  $50`, then `Maxed`.
- **Placeholder:** the `CountPrompt` binding (`Workspace.Model.Road.ProximityPrompt.ProximityPrompt`)
  is untouched. That placeholder prompt and the BillboardGui beside it stay
  hidden while the aquarium runs, and go back to how they were when it stops.
  The count UI still can't bind to that billboard (it's a sibling, not a
  child), so the aquarium's own "Fish in tank" billboard above the tank stays,
  and the panel also shows the count.

## Install / rollback

- **Install:** `InstallAquariumPanel.lua` (Command Bar, Edit mode). It needs
  aquarium v1.2 (`EconomyAquariumBackup`) and checks exact sources:
  - `AquariumCycleServer` must be exactly v1.2 (the version
    `UpgradeAquariumV12` installed)
  - the `Config` and `Upgrades` modules must be exactly v1.2
  In one undo step it updates `AquariumCycleServer` and adds
  `StarterPlayerScripts.AquariumPanelClient`. The backup is
  `ServerStorage.AquariumPanelBackup`.
- **Rollback:** `RollbackAquariumPanel.lua` restores the v1.2 server and
  removes the client. The three default prompts come back.
- **Paid upgrades later:** the released `InstallUpgrades` checks the v1.2
  server and refuses once this is in. Once persistence is decided, paid
  upgrades need a new installer anyway, and the panel is ready for them.

## Studio checklist

| # | Do | Expect |
|---|---|---|
| A1 | Play, walk to the loader pad | One dark panel: `[E] Release Fish`, the tank count, one card `Tank Capacity`, `Now 3 fish`, grey `Not available yet`. No default prompt panels |
| A2 | Press → (or tap `>`, or D-pad →) | The card changes to `Release Amount`, `Now 1 per release`; ← goes back |
| A3 | Press F / tap the grey button | Nothing is bought, no charge; Money unchanged |
| A4 | Catch fish into the tank, press E (and tap Release once the cooldown ends) | Fish swim back to the river; the count drops |
| A5 | Walk away / die | The panel disappears; arrow keys turn the camera again |
| A6 | Gamepad | The keycap shows the X button image; D-pad switches cards |
| A7 | Look for the old car prompt / "Fish available" billboard at the pad | Still hidden |
| A8 | Edit mode: `RollbackAquariumPanel` | The v1.2 prompts are back; `AquariumPanelClient` is gone |

Tuning: `PANEL_W` / `PANEL_H` and `STUDS_UP` (the panel's height above the
pad) at the top of `src/AquariumPanelClient.client.luau`.

## Tests (offline, fake engine)

- `tools/economy/tests/run_runtime_sim.py ... panel_sim`: 47 checks. The
  real patched server and the real client, in the live pad layout (the
  prompt on an Attachment, with a disabled billboard beside it). It covers
  every row above, plus the future currency case: per-client card
  selection, charges, max level, can't pay, and spoofed triggers.
- `tools/economy/tests/run_installer_sim.py`: install over Astra's current
  state, refusals (Play, no v1.2, an edited server or Upgrades module, an
  existing client), rollback exactly, and the InstallUpgrades interaction.
