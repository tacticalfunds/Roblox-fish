# Economy

A single soft currency, `leaderstats.Money`, and rod-fish Buy/Pass. Astra
reviews and installs. Nothing here touches Studio on its own.

| Milestone | State | Installable? |
|---|---|---|
| Core (`6081e33`): Config, Pricing, Ledger, MoneyStore, Offers | done | review only |
| Sale-settlement patches (`dcf9c44`): grinder/bot/customer/truck/net/harpoon | parked WIP | **no** (no installer) |
| **Rod Buy/Pass** (this commit): Money service + offers + RodShop compatibility | done | **yes**: `InstallRodOffers.lua` |
| Paid aquarium upgrades | next | - |
| Sale settlement (finish `dcf9c44`) | later | - |
| Rebased visual features (jump, dwell, immediate cast, variants) | later | - |

`studio/live/` holds the live sources Astra supplied on 2026-09-28. Every
patch and installer guard is built against these copies.

## Rod Buy/Pass: what it does

1. **Press.** The button casts every idle rod that can get an aquarium spot,
   as before. Each spot is reserved at the press. If the aquarium is
   closed, nothing is cast and the presser is told why.
2. **Reveal.** The fish is revealed as before. It then **waits on the
   line**:
   - A label above it shows the species and the server's price, e.g.
     `Salmon - 17 Money`, plus `<caster>'s catch: Buy or Pass`.
   - The caster gets a panel at the bottom of the screen: `Buy` / `Pass`
     with a 20 s countdown.
3. **Buy.** Only the caster can buy. The server runs one step with no yields
   in between:
   1. The offer is still open and the requester is the caster.
   2. The offer hasn't expired.
   3. The caster is within 100 studs of the fish.
   4. The aquarium is still running; if not, the offer is cancelled and
      **nothing is charged**.
   5. Money is taken; if there isn't enough, the offer **stays open**.
   6. The fish is landed in the aquarium; if that fails, the price is
      **refunded in full**.

   The fish then flies into the tank. Repeated clicks never charge or
   deliver twice.
4. **Pass, timeout, caster leaving, feature off, rod error.** The fish slips
   back into the water and is gone. The reserved tank spot is freed and
   nothing is charged. **An unpaid rod fish never reaches the aquarium or
   the grinder.**

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

## Install / rollback (Astra)

**Dependencies:**

- The aquarium must be installed and enabled.
- RodFishingSystem and RodShopServer must equal `studio/live/`. If they
  differ, the installer changes nothing and asks for the current source.
- Nothing else may create `leaderstats`.

**Install:** Edit mode (not Play) → paste `tools/economy/InstallRodOffers.lua`
into the Command Bar → Enter.

- It checks everything first and changes nothing if any check fails.
- It is one undo step.
- It backs up both scripts to `ServerStorage.EconomyRodOffersBackup`.

**Rollback:** Edit mode → paste `tools/economy/UninstallRodOffers.lua`.

- It restores both scripts' original sources and removes only objects
  tagged `EconomyOwned`.
- It refuses if a patched script was edited afterwards (set
  `FORCE_RESTORE = true` to override).
- Saved Money is kept.

**Persistence in Studio:** enable *Game Settings → Security → Enable Studio
Access to API Services*. Without it, a temporary in-memory store is used and
Output says so.

## Studio acceptance checklist

Run Play with the aquarium enabled. Two players (Test → Clients and Servers)
are needed for items 4 and 11.

| # | Do | Expect |
|---|---|---|
| 1 | Join as a new player | Toast "Welcome! 100 Money to start"; leaderboard Money = 100; Output `[Economy] running (DataStore store)` (or `Memory` with a warning) |
| 2 | Press the button | Up to 3 rods cast (tank capacity 3); same reel/reveal as before |
| 3 | Wait for a reveal | Label above the fish `Name - N Money`; your panel shows the row with Buy/Pass and a countdown; the fish stays on the line |
| 4 | Second player looks (Studio multi-client test users are fine) | Sees the label, **no** panel row; cannot buy |
| 5 | Click Buy | Money drops by exactly N; fish flies into the tank; tank count +1; toast "Bought!" |
| 6 | Spam-click Buy on one fish | Charged once; one fish in the tank |
| 7 | Click Pass on another | Fish drops into the water and disappears; no charge; tank spot freed (count unchanged, next press can cast) |
| 8 | Let one time out (20 s) | Same as Pass; toast "... slipped off the hook" |
| 9 | Fill the tank, press again | No cast; "tank full" notice; no charge |
| 10 | Spend down to under a price, click Buy | "Not enough Money"; offer stays until it times out |
| 11 | Caster leaves mid-offer | The other player sees the fish drop; no fish added to the tank |
| 12 | Set `ReplicatedStorage.Economy.RodOffersEnabled` false mid-offer | Offers vanish, no charge; next press behaves like before the install |
| 13 | Walk >100 studs away, click Buy | "Get closer to the rods to buy"; offer stays |
| 14 | Try the rod shop | "Rod shop opens soon"; Money unchanged; no rod added |
| 15 | Stop, Play again (API access on) | Money is what you left with, no second grant |
| 16 | Any rod fish going to the grinder in offer mode | Must never happen |
| 17 | Rename `ServerScriptService.EconomyService` (so it can't load), Play, press | No cast; toast "Fish buying is unavailable right now"; no free fish. Rename it back afterwards |

## Tests (offline, not Roblox runtime)

```
python3 tools/economy/tests/run_tests.py path/to/luau          # 240 checks
python3 tools/economy/tests/run_installer_sim.py path/to/luau  # 41 checks
```

- **Core:** pricing, ledger, MoneyStore against a fake DataStore that fails
  on purpose, and Offers.
- **Rod-offer integration:** the aquarium core **exactly as installed (v1,
  read from git at `2e320f9`)**, MoneyStore and Offers, wired as the patch
  wires them.
- **Installer dry run:** the real installer and uninstaller against a fake
  DataModel, including partial installs, a missing Economy root, and
  untagged objects with our names.
- **Build-time guards:** the offer path never fires the grinder event, and
  its only aquarium delivery is the paid `deliver` callback.
