# Economy

A single soft currency, `leaderstats.Money`, and buying rod fish. Astra
reviews and installs. Nothing here touches Studio on its own.

| Milestone | State | Installable? |
|---|---|---|
| Core (`6081e33`): Config, Pricing, Ledger, MoneyStore, Offers | done | review only |
| Sale-settlement patches (`dcf9c44`): grinder/bot/customer/truck/net/harpoon | parked WIP | **no** (no installer) |
| Rod Buy/Pass (`8cb2554`): Money service + offers + RodShop compatibility | **installed** (Astra) | `InstallRodOffers.lua` at `8cb2554` |
| **Rod-stand buy prompt** (this commit): proximity prompt instead of the panel | done | **yes**: `UpdateRodPrompt.lua` (on `8cb2554`), or the current `InstallRodOffers.lua` on a fresh place |
| Sale settlement (finish `dcf9c44`, buyer identity through the aquarium) | next | - |
| Paid aquarium upgrades | later | - |
| Rebased visual features (jump, dwell, immediate cast, variants) | later | - |

`studio/live/` holds the live sources Astra supplied on 2026-09-28. Every
patch and installer guard is built against these copies.

## Buying a rod fish: what it does

1. **Press.** The button casts every idle rod that can get an aquarium spot,
   as before. Each spot is reserved at the press. If the aquarium is
   closed, nothing is cast and the presser is told why.
2. **Reveal.** The fish is revealed as before. It then **waits on the
   line**. A label above it, which everyone sees, shows:
   - a clover and the fish's **real roll chance on the rods**, e.g.
     `🍀 3.4%`. This is the rod pool weight (`SpawnWeight^0.85`) divided by
     the pool total, exactly what `pickFish` uses. It is information only,
     not a bonus. It is hidden if the chance can't be computed.
   - the species, e.g. `Salmon`
   - the server's price, e.g. `$17`
3. **Buy at the rod stand.** Only the caster gets a prompt. It sits at the
   **stand of the rod that caught the fish**. When the caster walks within
   10 studs, a small panel appears there: a lime `E` keycap, the fish name
   and `Buy`.
   - Keyboard: `E`.
   - Controller: the ButtonX icon.
   - Touch: tap the panel (the keycap reads `TAP`).
   - Mouse: clicking the panel also works.

   With several of your catches nearby, only the nearest shows. The panel
   hides as soon as you walk away or the offer ends. Other players see the
   label but never a prompt.
4. **The server decides.** The server runs one step with no yields in
   between:
   1. The offer is still open and the requester is the caster.
   2. The offer hasn't expired.
   3. The caster is alive and **within 14 studs of the rod stand** (the
      10-stud prompt plus 4 studs of slack). Range is measured from the
      stand, never from the fish, because clients animate the fish.
   4. The aquarium is still running; if not, the offer is cancelled and
      **nothing is charged**.
   5. Money is taken; if there isn't enough, the offer **stays open** and
      the prompt comes back.
   6. The fish is landed in the aquarium; if that fails, the price is
      **refunded in full**.

   The fish then flies into the tank. Repeated presses, taps or requests
   never charge or deliver twice.
5. **Not bought.** The fish slips back into the water and is gone, the
   reserved tank spot is freed, and nothing is charged. This happens when:
   - the 20 s timeout passes
   - the caster dies or leaves
   - the feature is turned off
   - the rod errors

   There is no Pass key; the fish just times out. The server still accepts
   `pass`. **An unpaid rod fish never reaches the aquarium or the grinder.**

Prices come from `Pricing.offerPrice`:

- Tiers 1–5 cost 1–3 Money; examples: tier 10 costs 17, tier 14 costs 48,
  tier 19 costs 180.
- Silver/Gold prices are ×1.25 / ×1.75. Variants aren't rolled for rod fish
  in this slice.

A new player gets **100 Money once**. Tank 6 (50) still leaves money for
fish.

**In this slice Money only goes down.** Nothing pays out yet; that is the
sale-settlement milestone. Balances are saved in DataStore `FishEconomy_v1`,
so Money spent while testing stays spent.

### Where the prompt sits

The server creates an invisible, anchored, non-colliding part per open
offer. It goes in `Workspace.EconomyBuyStands`, a folder created during Play
and never saved, and is placed 2.5 studs above the rod's lowest corner (its
stand). The caster's client adds the `ProximityPrompt` to that part, with
`Style = Custom`, `RequiresLineOfSight = false` and `Exclusivity =
OnePerButton`. The distances are in `Config.Offer`:

- `PromptDistance` (10): the prompt's range
- `ReachSlack` (4): extra distance the server accepts
- `StandHeight` (2.5): how high above the stand the prompt sits

### Money safety

- Money is shown in leaderstats only after it loads successfully.
- A load error or a corrupt record never grants Money and never writes, and
  that player is never saved. They get a notice and background retries.
- Saves use a session lock and report success only if the write happened.
- Outside writes to `leaderstats.Money` are reverted.

### Why RodShopServer is patched too

The live shop charges whatever `leaderstats.Money` it finds by writing the
value directly. Once Money exists, that write would be reverted and the rod
given anyway, so rods would be free. The patch charges through
EconomyService instead. The shop stays **closed** ("Rod shop opens soon")
until owning a rod does something and is saved (`Config.RodShopOpen`).
Stock and restock are unchanged.

### Switches and failure behaviour

Offers count as *configured* while `ReplicatedStorage.Economy` exists and
its `RodOffersEnabled` attribute isn't false.

- **Configured, but EconomyService is missing or failed to start:** rods
  **fail closed**. Nothing is cast, and the presser sees "Fish buying is
  unavailable right now". There is no silent fallback to free fish.
- **Configured, but the aquarium is closed:** nothing is cast either.
- **`RodOffersEnabled = false` during Play:** open offers are cancelled with
  no charge, and rods go back to the pre-install behaviour (free rod →
  aquarium).
- **Uninstalled:** the pre-install behaviour, as above.

### Not in this slice: buyer identity

The installed aquarium is v1 (commit `2e320f9`, which Astra confirmed).
Its `hook(rodKey, fishName)` and `land` carry no metadata. So this slice
**does not** pass or claim the buyer's id through the tank or river. It
doesn't need to, because nothing pays out yet. The sale-payout milestone
will ship a guarded aquarium upgrade that carries the buyer, and it will
refuse to install without it.

### Studio sessions and test clients

- `game.JobId` is empty in Studio, so each Studio server locks saves under
  a fresh GUID instead. Two parallel Studio sessions can't both own one
  record.
- Studio test clients have negative UserIds (Player1 = -1, ...). In Studio
  they can open and buy offers. Their Money lives in memory only and is
  never written to the DataStore.
- Live servers accept only real, positive UserIds.

## Install / update / rollback (Astra)

**Studio has 8cb2554 installed → use the update:**

1. Edit mode (not Play). Paste `tools/economy/UpdateRodPrompt.lua` into the
   Command Bar and press Enter.
2. First, it checks the following, and changes nothing if any check fails:
   - the 8cb2554 install is present (`ServerStorage.EconomyRodOffersBackup`)
   - this update isn't already installed
   - no later milestone is installed
   - `Workspace.EconomyBuyStands` doesn't exist
   - all 11 economy scripts are exactly the 8cb2554 version: the 5 it
     changes and the 6 it only reads
3. It then rewrites 5 scripts in **one undo step**: RodFishingSystem,
   EconomyService, EconomyService.Config, EconomyService.Offers and
   EconomyClient. It backs them up to `ServerStorage.EconomyRodPromptBackup`
   and doesn't touch the original `EconomyRodOffersBackup`.

**Roll back the update** (back to exactly 8cb2554, bottom panel): Edit mode
→ paste `tools/economy/RollbackRodPrompt.lua`. It refuses if one of those 5
scripts was edited after the update; set `FORCE_RESTORE = true` to override.

**Uninstall everything** (the pre-economy game): run `RollbackRodPrompt.lua`
first, then `UninstallRodOffers.lua`. Both uninstallers refuse while the
update is in place: the current one checks for it, and the 8cb2554 one sees
RodFishingSystem changed. Saved Money is kept.

**Fresh place (no economy yet):** paste the current
`tools/economy/InstallRodOffers.lua`. It installs this version directly
with the 2-script `EconomyRodOffersBackup`. `UninstallRodOffers.lua`
reverses it.

**Dependencies (fresh install):**

- The aquarium must be installed and enabled.
- RodFishingSystem and RodShopServer must equal `studio/live/`.
- Nothing else may create `leaderstats`.

**Persistence in Studio:** enable *Game Settings → Security → Enable Studio
Access to API Services*. Without it, a temporary in-memory store is used and
Output says so.

## Studio acceptance checklist

Run Play with the aquarium enabled. Two players (Test → Clients and Servers)
are needed for items 4 and 12. Rows marked **new** are what the update
changes; the rest re-check behaviour that already worked.

| # | Do | Expect |
|---|---|---|
| 1 | Join as a new player | Toast "Welcome! 100 Money to start"; leaderboard Money = 100 (a returning player keeps their saved Money) |
| 2 | Press the button | Up to 3 rods cast (tank capacity 3); same reel/reveal as before |
| 3 **new** | Wait for a reveal | Above the fish: `🍀 N%`, species, lime `$price`, chunky outlined text; no bottom-screen panel |
| 4 **new** | Second player walks up to the same rod stand | Sees the label, **never** a prompt |
| 5 **new** | Stay near the button (> 10 studs from the stand) | No panel; E does nothing |
| 6 **new** | Walk up to the stand of the rod holding your fish | Small panel at the stand: lime `E` keycap, fish name, lime `Buy`. **Check it sits at the rod stand and is reachable from the dock** |
| 7 **new** | Walk away | Panel disappears straight away |
| 8 | Press E | Money drops by exactly the shown price; fish flies into the tank; toast "Bought!" |
| 9 | Spam E / tap on one fish | Charged once; one fish in the tank |
| 10 **new** | Two of your catches on neighbouring rods, stand between them | Only one panel (the nearer stand); after buying it, the other one shows |
| 11 | Leave one alone for 20 s | Fish drops into the water; no charge; toast "... slipped off the hook"; spot freed |
| 12 | Caster leaves mid-offer | Fish drops; nothing charged; other player sees no leftover prompt |
| 13 **new** | Caster dies (reset) mid-offer | Fish drops; no charge; no prompt after respawn |
| 14 **new** | Controller | Keycap shows the controller button icon; that button buys |
| 15 **new** | Touch (device emulator) | Keycap reads TAP; tapping the panel buys |
| 16 | Spend down under a price, press E | "Not enough Money"; panel comes back; offer stays until timeout |
| 17 | Set `ReplicatedStorage.Economy.RodOffersEnabled` false mid-offer | Offer ends, no charge; next press behaves like before the install |
| 18 | Fill the tank, press again | No cast; no charge |
| 19 | Try the rod shop | "Rod shop opens soon"; Money unchanged |
| 20 | Rename `ServerScriptService.EconomyService`, Play, press | No cast; toast "Fish buying is unavailable right now"; no free fish. Rename it back afterwards |
| 21 | Stop, Play again (API access on) | Money is what you left with, no second grant |
| 22 | Edit mode: `RollbackRodPrompt.lua`, Play | The old bottom Buy/Pass panel is back (8cb2554) |

## Tests (offline, not Roblox runtime)

```
python3 tools/economy/tests/run_tests.py path/to/luau          # 260 checks
python3 tools/economy/tests/run_runtime_sim.py path/to/luau    # 80 checks
python3 tools/economy/tests/run_installer_sim.py path/to/luau  # 71 checks
```

- **Core:** pricing, ledger, MoneyStore against a fake DataStore that fails
  on purpose, and Offers. The Offers tests include buy reach from the stand
  and chance formatting.
- **Rod-offer integration:** the aquarium core **exactly as installed (v1,
  read from git at `2e320f9`)**, MoneyStore and Offers, wired as the patch
  wires them. Range uses the stand-reach rule.
- **Runtime simulation:** the **real** EconomyService and EconomyClient on a
  fake engine: signals, a virtual clock, remotes that know the calling
  player, and a ProximityPrompt model. It checks:
  - only the caster gets a prompt, with the right settings
  - the panel content and the input type (keyboard / controller / touch)
  - hide/show with range, and nearest-only
  - buy once under spam; server reach from the stand
  - not enough Money
  - cleanup on buy, timeout, pass, death, leave and switch-off
- **Installer dry run:** the real fresh installer and uninstaller, plus
  `UpdateRodPrompt` / `RollbackRodPrompt`, against a place set up by the
  **real 8cb2554 installer** (from git). It checks:
  - every refusal
  - rollback to exactly 8cb2554
  - the original uninstall chain afterwards
- **Build-time guards:** the offer path never fires the grinder event, and
  its only aquarium delivery is the paid `deliver` callback. It also passes
  the rod's stand and real chance.
