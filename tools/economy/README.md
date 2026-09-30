# Economy

A single soft currency, `leaderstats.Money`, and buying rod fish. Astra
reviews and installs. Nothing here touches Studio on its own.

| Milestone | State | Installable? |
|---|---|---|
| Core (`6081e33`): Config, Pricing, Ledger, MoneyStore, Offers | done | review only |
| Rod Buy/Pass (`8cb2554`): Money service + offers + RodShop compatibility | superseded | - |
| Rod-stand buy prompt (`a826d73`) | **installed** (Astra, fresh `InstallRodOffers.lua`) | frozen release: `InstallRodOffers.lua`, or `UpdateRodPrompt.lua` on `8cb2554` |
| Aquarium v1.2 (`d39b00b`): buyer (`OwnerId`) through tank → river | **installed** (Astra, 2026-09-28) | `UpgradeAquariumV12.lua` |
| Sale payouts (`91121de` release): grinder / bot / customer / truck / net / harpoon | **installed** (Astra, 2026-09-29) | `InstallSales.lua` |
| Money HUD: both MoneyController copies show `leaderstats.Money` | done | **yes**: `InstallMoneyHud.lua` (independent) |
| Paid aquarium upgrades (`de507bf`) | done, **not production-ready** (levels not saved, see below) | **yes**: `InstallUpgrades.lua` (after sales) |
| Fish jumps, rebased on live (`d5fec9b`) | done | **yes**: `tools/fish-jump/InstallFishJump.lua` (independent) |
| Immediate rod cast, rebased on sales (`e08e824`; installer regenerated with v2) | done | **yes**: `tools/rod-cast/InstallRodCast.lua` (after sales) |
| Grinder dwell (`d64a180`; ~1 s on the rollers: net, harpoon, rod fallback) | done | **yes**: `tools/grinder-dwell/InstallGrinderDwell.lua` (after sales; after jumps / rod cast if used) |
| Rare Silver / Gold variants (`a92a678`) | done | **yes**: `tools/fish-variants/InstallFishVariants.lua` |
| Earnings popup (`561c4d1`; pending / balance-limit amounts fixed later): "+$N" for the owner when their meat sells | done | **yes**: `InstallEarnings.lua` (after sales; after upgrades if used) |
| Blender Bot recovery (`e933db6`): an error mid-trip keeps the piece | done | **yes**: `InstallBotRecovery.lua` (after sales; before meat glow) |
| Rods milestone 1: saved ownership + equip + faster bites (paid shop still closed) | **installed** (Astra, pending validation), frozen at `61a7bd4` | `InstallRods.lua` + `InstallRodShopUI.lua` |
| Upgrade board + one saved net capacity (KG posts and board), on the live GrinderUpgrades baseline (paid upgrades closed) | done, needs Studio validation | **yes**: `InstallBoardUpgrades.lua` (after rods and the GrinderUpgrades system) |

**All installers in one place, in order, with rollbacks: [`tools/INSTALL_GUIDE.md`](../INSTALL_GUIDE.md).**

**The sales release is frozen at `91121de`.** `UpgradeAquariumV12`,
`InstallSales`, `InstallUpgrades` and their rollbacks are built from that
commit's economy sources and pinned byte-for-byte by the installer test.
Later economy milestones change `src/` and ship their own installers on top.

**Studio now (Astra, 2026-09-29):** fresh `a826d73` rod install + aquarium
v1.2 + `InstallSales` (`91121de`): `EconomyRodOffersBackup`,
`EconomyAquariumBackup`, `EconomySalesBackup`. Astra checked that every
exact guard matched, that the 10 changes persist after a playtest, and ran
an installed-module test (buyer ownership, Gold tier-1 payout 20, duplicate
settlement refused, held/re-emitted settlement) on isolated in-memory money.
Nothing after sales is installed yet.

`InstallSales` refused the first time because two live scripts carry
existing paid-upgrade hooks that weren't in the baseline:

- **CustomerSystem** (CarSalesServer's customer upgrades): 3 more line
  slots, `CustomersLineCap` and `CustomersPerMin`.
- **TruckSystem** (Car Sales unlock, Max Line and Car Speed):
  - trucks come only while `workspace.CarsUnlocked` is set
  - `CarsMaxQueue` caps the line
  - `CarsGapSeconds` sets the spacing

`studio/live/` holds Astra's **exact pasted live sources** (2026-09-28, and
the two MoneyController copies on 2026-09-29). Every patch and installer
guard is built against these copies. The sales patch keeps the Car Sales
hooks; the installer dry run checks that the comment-less rebuilds of those
two scripts are still refused.

**Install order and rollbacks:** see [`tools/INSTALL_GUIDE.md`](../INSTALL_GUIDE.md).
Each installer identifies what is installed by exact source, so it works on
either rod-offers chain: a fresh `a826d73` install, or `8cb2554` +
`UpdateRodPrompt`.

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

**With only rod offers installed, Money only goes down.** Payouts come with
`InstallSales` (below). Balances are saved in DataStore `FishEconomy_v1`, so
Money spent while testing stays spent.

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

### Buyer identity

With rod offers alone, the installed aquarium is v1: its `hook` and `land`
carry no metadata, and nothing claims the buyer. `UpgradeAquariumV12` +
`InstallSales` carry the buyer (`OwnerId`) with a bought fish from rod to
tank to river to meat. `InstallSales` refuses to install on aquarium v1.

### Studio sessions and test clients

- `game.JobId` is empty in Studio, so each Studio server locks saves under
  a fresh GUID instead. Two parallel Studio sessions can't both own one
  record.
- Studio test clients have negative UserIds (Player1 = -1, ...). In Studio
  they can open and buy offers. Their Money lives in memory only and is
  never written to the DataStore.
- Live servers accept only real, positive UserIds.

## Sale payouts (`InstallSales.lua`)

Money comes in **only when meat sells**: a customer buys it at the sale
table, or a player drops it in a truck. Each meat piece pays **once**, its
ledger value, to the piece's **owner**:

| Fish came from | Owner (who is paid) |
|---|---|
| Net pad | the player on the pad |
| A bought rod fish, caught again later by the net or harpoon | **its buyer** (carried rod → tank → river) |
| Harpoon, fish nobody bought | the player set in `HarpoonGun`'s `OwnerUserId` attribute; otherwise **nobody**. The meat still sells, but no one is paid |

- **Owner not in the server:** nobody is paid.
- **Carrying:** carrying meat to a truck never pays the carrier.
- **Value:** a fish's value (`4 × 1.3^(tier−1)`, e.g. tier 10 = 42) is
  **split** across its meat pieces, not multiplied by them.

**Nothing unpaid is destroyed:**

- **The stack is full:** the belt waits.
- **The blender pit is full (24 pieces):** new pieces are held as data and
  come back out of the pipe later.
- **A carrier respawns or leaves:** their carried pieces are held the same
  way.
- **Too much meat is held (150):** the net pad refuses to lift and the
  harpoon skips shots until the meat clears.

What each patched script does:

- **GrinderProcessor:** creates the ledger pieces and stamps each meat part
  (`PieceId`, `OwnerId`, `Value`, `Tier`).
- **BotSystem:** copies that identity onto the piece it carries to the
  table.
- **CustomerSystem:** settles the piece before it's destroyed.
- **TruckSystem:** settles when a piece is dropped in a truck. The truck UI
  is unchanged. Every player is bound to respawn cleanup exactly once,
  including players already in the server when the script starts, because
  loading EconomyService can yield.
- **CustomerSystem:** Astra's live version, with CarSalesServer's line-cap
  and customers-per-minute hooks kept as they are.
- **NetLiftScript and HarpoonSystem:** send the owner payload.
- **RodFishingSystem:** a hooked fish in offer mode carries its caster as
  `OwnerId`. Only the caster can buy it, and an unbought fish's data is
  discarded.

### Aquarium v1.2 (`UpgradeAquariumV12.lua`)

It changes 4 of the aquarium v1 scripts (Config, SharedTank,
AquariumCycleServer, AquariumTankClient) and checks the rest are v1:

- **Buyer carried:** `OwnerId`, and `Variant` when one exists, travel
  unchanged from rod to tank to river fish attribute.
- **Harpooned fish not despawned:** the river-release despawn timer no
  longer deletes a fish the harpoon has hit.

Until `InstallSales` passes a buyer, it behaves exactly like v1.

### Install / rollback

1. Edit mode → paste `tools/economy/UpgradeAquariumV12.lua`.
2. Edit mode → paste `tools/economy/InstallSales.lua`. It refuses if the
   aquarium isn't v1.2.

Each installer:

- **Checks first:** it changes nothing if any script differs from the
  expected version (the refusal names the first differing line), if a script name isn't unique, if an economy object
  isn't tagged as ours, or in Play mode.
- **Records one undo step.**
- **Backs up what it changes:** `InstallSales` backs up 10 scripts to
  `ServerStorage.EconomySalesBackup`; the aquarium upgrade backs up 4 to
  `EconomyAquariumBackup`.

`InstallSales` changes:

- the six live sale scripts
- RodFishingSystem
- EconomyService, plus its Ledger and PieceTags modules. Studio test clients
  (negative UserIds) can own pieces and be paid in Studio only.

**Rollback:** `RollbackSales.lua`, then `RollbackAquariumV12.lua`. Each one
restores the exact previous sources and refuses while a later milestone is
installed.

### Sale payouts checklist (Studio)

Run Play with the aquarium enabled.

| # | Do | Expect |
|---|---|---|
| S1 | Step on the net pad and catch fish | Nobody paid yet; the meat on the stack has `PieceId`, `OwnerId` = you, and `Value` attributes |
| S2 | Carry meat to a truck (as any player) | The **owner's** Money goes up by each piece's `Value`; the carrier gets nothing unless they own it; truck UI unchanged |
| S3 | Let the Blender Bot sell to a customer | The owner is paid once when the customer takes it |
| S4 | Buy a rod fish, release it from the tank, net it (any player) | That meat pays **the buyer** |
| S5 | Harpoon a fish, with no `OwnerUserId` on `HarpoonGun` | The meat sells; nobody is paid |
| S6 | Set `Workspace.HarpoonGun.OwnerUserId` to your UserId, harpoon | You are paid when it sells |
| S7 | Pick up meat, then reset your character | Your carried pieces come back out of the grinder pipe later (same owner) |
| S8 | Fill the stack to the top | The belt pauses; no meat disappears; it resumes when meat is taken |
| S9 | Leave and rejoin | Money earned from sales is saved |
| S10 | Edit mode: `RollbackSales`, then `RollbackAquariumV12` | Back to the rod-offers install (buying works, no payouts) |

## Paid aquarium upgrades (`InstallUpgrades.lua`)

The aquarium's two upgrade prompts now cost **Money**, at the aquarium's own
prices:

| Upgrade | Levels | Costs |
|---|---|---|
| Tank Capacity | 3 → 6 → 10 → 15 | 50, 150, 400 |
| Release Rate | 1 → 2 → 4 → 6 fish per release | 40, 120, 350 |

(The levels are `Config.Upgrades` in `tools/aquarium-cycle/src/shared/Config.luau`.)

- **Who pays:** the player who triggers the prompt pays. The server checks
  that they're alive and within range before charging.
- **Shared tank:** the level applies to the one shared tank **for this
  server session**. It isn't saved, and it's never per player.
- **⚠ Not production-ready: unresolved design issue.** Upgrade levels reset
  whenever a server starts, but the Money spent on them is saved. A player
  who buys Tank 6 and rejoins a new server has paid 50 and sees Tank 3
  again. Only acceptable for testing. **Nothing here picks a persistence
  policy:** saving tank levels (per server owner? globally?) or selling them
  as a per-session boost is a design decision still open, and whichever it
  is, the prompt must say so.
- **The same gap exists in the live Car Sales upgrades.** CarSalesServer
  charges through `EconomyService.tryDebit` (the one Money, not a second
  currency), but its truck unlock, Max Line, Car Speed and customer levels
  live only in player attributes, so they reset on rejoin while the Money
  stays spent. Same open decision; not changed here.
- **One step:** the charge and the level-up happen in one step with no
  yields in between.
- **Nothing charged:** when the player can't afford it, at max level, or
  while their Money is still loading ("try again in a moment").

**Early game:** the 100 Money grant buys Tank 6 (50) and still leaves 50 for
starter rod fish (1–3 Money each). Tier 1–5 meat sells for 4–11 Money per
fish.

**What it changes:** one module, `ServerScriptService.AquariumEconomy`.
Before, it returned nil, meaning "upgrades unavailable".

**What it requires:** `InstallSales` and aquarium v1.2, checked by source.

**Rollback:** `RollbackUpgrades.lua` puts back the nil module, so the
upgrades show "unavailable" again. `RollbackSales` refuses while this is
installed.

### Paid upgrades checklist (Studio)

| # | Do | Expect |
|---|---|---|
| U1 | Look at the upgrade prompts | They show the price (e.g. `3 → 6 (50)`), not "unavailable" |
| U2 | New player: buy Tank Capacity | Money 100 → 50; count shows `x/6`; toast "Tank Capacity upgraded to 6!" |
| U3 | Try the next level (150) with 50 Money | "You can't afford that upgrade yet."; nothing changes |
| U4 | A second player buys a level | Only they pay; both see the bigger tank |
| U5 | Buy to the max level | Prompt shows "Maxed"; further triggers charge nothing |
| U6 | Stop, Play again | Tank levels are back to the start (session-scoped); Money stays spent. **This is the unresolved issue above**, not a pass |

## Earnings popup (`InstallEarnings.lua`)

When a piece of **your** meat sells (a customer takes it at the sale table,
or it goes in a truck), you see a popup on the right of your screen:

- `+$12` in big green text, with `Salmon sold to a customer` under it
- **Quick sales add up:** further sales within 2.5 s join the same popup,
  e.g. `+$54` / `3 pieces sold`. It hides 2.5 s after the last one.
- **Gold / Silver meat** tints it gold or silver; the tint stays for the rest
  of that run.
- **Whoever carried it:** you see it even if another player carried your
  meat to the truck. The carrier sees nothing (they aren't paid).
- **Unowned meat** (an unbound harpoon catch) shows nothing anywhere.

It's display only. The payment is the same ledger settlement as before:
once per piece, to its owner. **The popup shows what really reached your
Money**, not the piece's price:

- **Money still loading** (or its load failed and is retrying): the sale is
  queued, not spendable. The popup says `+$12 pending` in grey, with `Added
  when your Money loads`. Pending and spendable sales never add up in the
  same popup. The queue is added to the balance once, when it loads.
- **At the balance limit** (`Config.MaxBalance`): the balance is clamped, so
  the popup shows the real increase (`+$3`, or `+$0`) with `Money is at the
  maximum`. Same for a full pending queue (`Pending limit reached`).
- The server measures the increase around the credit itself (no yields in
  between) and sends `(added, route, fish, variant, kind, price)`.

**How:** EconomyService creates `ReplicatedStorage.Economy.Earned` (a
RemoteEvent) when it starts, and fires it to the owner after each paid
sale. EconomyClient shows it and ignores anything malformed. Turn it off
with the `EarningsPopup = false` attribute on `ReplicatedStorage.Economy`.

**Install:** `InstallEarnings.lua` (v2 guarded template). It needs
`EconomySalesBackup` and the exact sales-release EconomyService,
EconomyClient, Sales, Ledger and PieceTags. It backs up the two scripts it
changes to `ServerStorage.EconomyEarningsBackup`, in one undo step.
**Install `InstallUpgrades` first** if you use it. **Rollback:**
`RollbackEarnings.lua`, before `RollbackSales` (which refuses while the
EconomyService differs).

### Earnings checklist (Studio)

| # | Do | Expect |
|---|---|---|
| E1 | Net a fish; let a customer buy one piece | `+$N` on the right, `<Fish> sold to a customer`; Money goes up by N |
| E2 | Carry 3+ of your pieces to a truck at once | One popup adding up, `3 pieces sold`; it hides ~2.5 s later |
| E3 | Second test client carries your meat to a truck | Only you see the popup; the carrier sees nothing |
| E4 | Sell Gold meat (after variants) | The popup is gold |
| E5 | Set `ReplicatedStorage.Economy.EarningsPopup = false` in Play | Sales still pay; no popup |
| E6 | Sell a piece while your Money is still loading (hard to hit by hand: the runtime sim covers it with a locked save) | Grey `+$N pending`, `Added when your Money loads`; the balance gains N once it loads |

## Money HUD (`InstallMoneyHud.lua`)

**The bug (real Studio):** both HUD copies of `MoneyController`
(`StarterGui.Money.MoneyFrame` and `StarterGui.ScreenGui.Buttons.Frames.MoneyFrame`)
wait forever on `ReplicatedStorage.FormatModule`, which doesn't exist. They
also read `LocalPlayer.Money` (the balance is `leaderstats.Money`) and wait
on `Modules.RebirthDefinitions`, `Rebirths`, `FriendsMultiplier`, `VIP` and
`Upgrades.RobuxMultiplier`, none of which exist. So the labels never update.

**The fix** replaces both with one new controller
(`src/client/MoneyController.client.luau`, written fresh):

- **Money:** `leaderstats.Money`, the value EconomyService keeps. It shows
  `Loading...` until the player's Money has loaded (and stays that way if it
  never does), then the balance, following every change. `$1.23K` style,
  truncated so it never rounds up. `FormatModule` is used if it exists and
  works; otherwise it uses its own format.
- **Multiplier labels** (`RebirthMulti`, `RobuxMulti`, `FriendsMulti`,
  `VIPMulti`): the old formulas, **only when their inputs exist**. A label
  whose inputs are missing (all of them today) is hidden, not filled with a
  guess. If the inputs appear later, the label comes back. These are display
  only: **no payout applies any multiplier**, so if those systems are ever
  added, their payouts need their own design.
- It never waits on anything that may not exist.

**Install:** `InstallMoneyHud.lua` (v2 guarded template). It needs
`EconomyRodOffersBackup` and both copies exactly as Astra sent them (by
path). It backs up both to `ServerStorage.EconomyMoneyHudBackup`, in one
undo step. Nothing server side. Independent of every other installer.
**Rollback:** `RollbackMoneyHud.lua` (the old, stuck scripts come back).

### Money HUD checklist (Studio)

| # | Do | Expect |
|---|---|---|
| M1 | Play | Both money labels show `$100` (new player) or your saved balance within a moment, `Loading...` before that; no `FormatModule` / infinite-yield warnings |
| M2 | Buy a rod fish; sell meat | Both labels follow the balance each time |
| M3 | Compare with the leaderboard | Same number as `leaderstats.Money` (abbreviated from 1,000: `$1.23K`) |
| M4 | Look at the multiplier labels | Hidden (their inputs don't exist); nothing claims a bonus |
| M5 | Edit mode: `RollbackMoneyHud` | Both scripts are the old source again |

## Rods, milestone 1 (`InstallRods.lua`)

Rods are **owned for good**, **equipped**, and make **bites come faster**.
They are saved with the player's Money.

| Rod | Model | Price | Bite wait |
|---|---|---|---|
| Basic | `FishingRod1` | free, always owned | ×1 |
| Tiger | `FishingRod4` | 150 | ×0.85 |
| Coral | `FishingRod3` | 600 | ×0.75 |
| Tide | `FishingRod2` | 2000 | ×0.65 |
| Magma | `FishingRod5` | 7500 | ×0.55 |

These numbers are **initial easy-early-game tuning, not measured pacing**
(`Config.Rods`). The legacy `Price` / `Tier` / `Title` attributes on the rod
models are ignored; while the server runs, each model's `Price` attribute is
set to the table's price, and `Benefit` holds text like "Bites 45% faster".
Fish sale and offer prices and rarity odds are unchanged.

**Shop (`RodShopServer`, `BuyRod(rodName)`):**

- **Owned rod:** equipped. Never charged again, and allowed from anywhere.
- **Unowned rod:** bought and equipped. The server checks that:
  - the paid shop is open
  - the player is in this server, alive and their Money has loaded
  - they are within reach of `Workspace["Pet Shop"].ShopPrompt` (the open
    prompt's 14 studs + 16)
  - the rod is in stock: Basic and Tiger always are; the others keep the
    per-player restock roll, and owned rods always show
  - one action at a time, with a 0.5 s cooldown
- **Fail closed:** without a running EconomyService nothing is sold. The
  old fallback that wrote `leaderstats.Money` / a `Money` attribute directly
  is gone.
- **Paid shop stays CLOSED** (`Config.RodShopOpen = false`) until the saved
  path is validated. For a Studio validation **with Studio API access
  enabled** (the in-memory fallback is not proof of persistence), set the
  `RodShopOpen` attribute on `ReplicatedStorage.Economy` to true.
- **Display attributes:** the server publishes `RodOwned_<id> = 1` and
  `EquippedRod` for the UI. It never reads them back.

**Casting (`RodFishingSystem`):**

- Each accepted press reads the **presser's** equipped rod once and uses it
  for every rod that press casts.
- A later equip by anyone, including the presser, never changes a cast in
  progress.
- The wait before a bite is the old random 3–9 s × the rod's bite wait,
  **never below 2 s**, because the aquarium hooks a fish no earlier than
  2.5 s after the press. Measured in the sim, press to bite: Magma averages
  3.8 s (2.2–5.2), Basic 6.0 s (3.3–8.7).
- Immediate cast, aquarium reservations, offers, variants, dwell and the
  grinder fallback are unchanged.

### Saved data (schema v2) and migration risks

The Money record gains an optional
`rods = { owned = { [rodId] = true }, equipped = rodId }`; Basic is never
stored.

- **v1 records** load with their money untouched and Basic equipped.
- **Every save keeps what it doesn't manage:** every other field, rod IDs
  this build doesn't know (and a newer build's equipped rod), unknown
  sub-fields of `rods`, and a newer schema number.
- **A rods field that isn't valid data** is left untouched. The player
  plays with Basic and can't buy rods that session.
- **A record that failed to load is never written** (unchanged).
- **A purchase** debits in memory, then writes the new balance **and** the
  rod in **one** UpdateAsync before reporting success. The new rod is
  **staged**: casts and the shop keep reading the committed rods until that
  write succeeded, so a cast during a slow or failing save never gets an
  unpaid rod (review fix, `rods.test` + `rods_sim`).
- **Re-checked after waiting:** if a save is already running, the purchase
  waits for it. It then checks everything again, with no yield before the
  debit: the player is still here and alive, the shop is open, they are in
  range, the rod is in stock and not already owned. If that write fails
  or the session lock is lost, the money and the rod are both undone
  ("you were not charged"). Credits that arrived meanwhile stay.
- **Equipping** is saved with the next autosave (60 s) or on leave. A
  server crash can lose an equip choice, never a purchase.
- **Risks to know:**
  1. **Ambiguous DataStore error:** if a write errors but actually
     committed, the next save writes the undone state (money back, rod not
     owned). If the server crashes before that save, the player keeps the
     rod they paid for. Either way money and rod always match.
  2. **Old servers:** a server still running the released v1 MoneyStore
     keeps the `rods` field (it copies unknown fields) but writes `v = 1`.
     The new code reads that fine.
  3. **Rollback** (`RollbackRods`) puts the v1 MoneyStore back. Saved rods
     stay in the records (v1 copies them) and come back if this is
     reinstalled.
  4. **Studio test clients** (negative UserIds) always use a memory store.
     Studio's in-memory fallback is **not** persistence proof.

### Not in this milestone (reported)

- **Shop UI:** a separate installer, `InstallRodShopUI.lua` (below).
  Without it, the live controller shows prices captured once, always
  "BUY", "BOUGHT!" on success, and "NO $ YET" for most refusals. It does
  **not** show the server's messages.
- **Rod visuals:** the five dock rods stay the Basic model. Swapping them
  per cast would have to keep `LineTip`, `RestPivot`, the stand position
  and the client's cached models, so it's left out. Each cast carries
  `CastRod = <rod id>` on the dock rod model as a hook for a later visual
  step.

### Rod shop UI (`InstallRodShopUI.lua`)

This patches the **exact live** `RodShopController` (the installer checks
it by source and path). It needs `InstallRods`, and `RollbackRods` refuses
while this is in.

- **Each card shows:** the real price, or **OWNED**; the benefit ("Bites 15%
  faster"); and a button that says what pressing does: **BUY / EQUIP /
  EQUIPPED / SOON** (the paid shop isn't open) **/ SOLD OUT**. All of it
  updates live from the server's attributes (`RodOwned_<id>`,
  `EquippedRod`, `RodStock_<id>`, `Price`, `Benefit`,
  `Economy.RodShopPaidOpen`).
- **Pressing:** the button shows **"..."** while the server answers. Only
  one request per rod at a time, and pressing the equipped rod sends
  nothing. Then it shows the server's real result as short text
  (**BOUGHT! / EQUIPPED / NEED $ / TOO FAR / NOT SAVED / SAVING / LOADING /
  SOON / SOLD OUT**...), with the full message on a status line under the
  cards.
- **Unchanged:** the picture, restock countdown, open / close and
  scrolling. The client decides nothing.
- **Tests:** `shopui_sim` (28 checks) runs the real controller against the
  real server. It also runs the live controller to show the "NO $ YET"
  bug.

### Rods checklist (Studio, API access ON)

| # | Do | Expect |
|---|---|---|
| R1 | Play | `EquippedRod = FishingRod1`, `RodOwned_FishingRod1 = 1` on your player; Money unchanged from before |
| R2 | Shop (closed): press Buy on Tiger | "The rod shop opens soon"; nothing charged |
| R3 | Set `ReplicatedStorage.Economy.RodShopOpen = true`; buy Tiger at the shop | −150, "Bought and equipped Tiger Rod", `EquippedRod = FishingRod4` |
| R4 | Buy Tiger again / buy Basic | Equips it, no charge |
| R5 | Walk far away, buy Coral | "Walk back to the rod shop to buy" |
| R6 | Press the big button | Bites come noticeably sooner than with Basic |
| R7 | Stop, Play again (real DataStore) | Money, owned rods and equipped rod are back |
| R8 | Two clients: A (Tiger) presses, then B equips Basic | A's cast keeps Tiger timing; B's next press uses Basic |
| R9 | (shop UI) Open the shop, shop closed | Cards: price or OWNED, benefit line; Basic EQUIPPED; others SOON; status line "Buying opens soon..." |
| R10 | (shop UI) Shop open: buy Tiger | "..." then BOUGHT! and "Bought and equipped Tiger Rod"; then OWNED / EQUIPPED |
| R11 | (shop UI) Walk away, press Coral; press Magma broke | TOO FAR / NEED $ with the full message; nothing charged |
| R12 | Check the new status line doesn't cover anything | Readable under the cards (layout is untested visually) |

## Upgrade board on the live baseline (`InstallBoardUpgrades.lua`)

**One installer** for the whole upgrade board and the one saved net
capacity (the sections below describe the parts). It is built on what
Studio has now (Astra, 2026-09-30): rods `61a7bd4` plus the
**GrinderUpgrades** system Astra installed.

- The live EconomyService has the blade multiplier in the sale callback.
- GrinderUpgradesServer sold the KG signs and kept a **count** of +5 kg buys
  in its own store, `GrinderUpgrades_v1` (`kg`).
- GrinderUpgradesClient wrote the posts' `PricePlate.PriceGui.Pill` every
  0.25 s.

The exact live sources are in `studio/live/` (`EconomyService.grinder.lua`,
`GrinderUpgrades{Server,Client,Config}.lua`). The installer checks every
script it touches against them and **refuses on anything else**, naming the
first different line.

**What it does to the GrinderUpgrades system** (`build/make_grinder.py`, a
reviewable diff of the live scripts):

- **One seller, one progression.**
  - NetCapacityServer is the **only** KG-sign seller: the board and the
    PricePlate ClickDetectors, at 24 studs as before.
  - It sells the Money record's `netKg`: money + kg in **one** write, which
    the Net Strength card sells too.
  - GrinderUpgradesServer no longer binds the signs, so there's no second
    handler and no second charge.
- **Migration** (idempotent, no compounding):
  - At each join, GrinderUpgradesServer reports its saved `kg` count, and
    EconomyService adopts `netKg = max(netKg, 15 + 5 × kg)`.
  - Reporting again never adds.
  - The base is the fixed 15, **never** the live `NetLift.MaxWeight` (which
    NetCapacityServer raises).
  - The old record is left exactly as it is.
  - A player's net can't be bought, and doesn't count toward the shared
    net, until that count is in (`Config.NetKgLegacy`).
  - `NetMaxWeight` / `NetKgBuys` are now published from `netKg`, so they
    don't move when `MaxWeight` changes.
- **One plate writer.** GrinderUpgradesClient no longer touches the Pill.
  KgSignClient writes Price (`$10`, green / red by your money, SOON, MAX,
  `...`), Info (`NET 15 KG → 20 KG`) and the Border colour, with the same
  look, per player.
- **Conveyor / blades** keep the same prices and effects:
  - **no memory store in a live server**: if its DataStore is unavailable
    outside Studio, nothing is loaded or bought;
  - a record it can't read is **never overwritten** (buying is off for that
    player);
  - the player's **final Money save waits** for the store write
    (`EconomyService.holdSave`, at most `Config.SaveHoldSeconds` = 20 s);
  - a failed write is refunded **even if the player left** meanwhile
    (`refundHeld`), so the saved balance is the one from before the
    purchase;
  - a successful write while leaving keeps both the debit and the upgrade.
- **Blade × Meat Price**, each exactly once:
  - Meat Price is in the piece's value, fixed when the grinder cuts the
    fish.
  - The blade multiplier is applied at each sale by the unchanged live
    code.
  - The "+$" popup shows what was actually credited; each piece still
    pays once.

**The board's cards use the board's own art.**

- Each card is a copy of the board's first card that has the card
  structure: a "Buy" button with its Price, gradient, stroke and corner, an
  "Icons" image, and title / value labels told apart by height.
- The copy is recoloured pink / lime / cyan / amber and relabelled.
- **Icons:** set `Workspace.Board` attributes `IconNetStrength`,
  `IconRodLuck`, `IconMeatPrice` and `IconFasterReels` to `rbxassetid://…`
  images you have. A card without one shows its emoji over a hidden image.

**Install:** the prerequisite is `EconomyRodsBackup`. The installer refuses
if any backup of the superseded per-milestone installers exists.

- Changes: EconomyService, Config, MoneyStore, Pricing, Ledger, Sales,
  RodFishingSystem, GrinderUpgradesServer and GrinderUpgradesClient.
- Checks unchanged: Rods, Offers, PieceTags, GrinderUpgradesConfig and
  RodShopServer.
- Adds: `EconomyService.NetKg`, `EconomyService.BoardUpgrades`,
  NetCapacityServer, UpgradeBoardServer, KgSignClient and
  UpgradeBoardClient.
- Backup: `EconomyBoardUpgradesBackup`. Every earlier backup, including
  `GrinderUpgradesBackup` and `BillboardLockBackup`, is untouched.
- Paid upgrades stay **closed**: `NetKgOpen` for the net, `UpgradesOpen`
  for the other three.

**Rollback:** `RollbackBoardUpgrades.lua` restores exactly the live
baseline: the blade EconomyService, the live GrinderUpgrades scripts, and
the added scripts removed. It refuses over any edited script. What happens
to the data:

- **Old KG buys are safe both ways.** The `kg` count in
  `GrinderUpgrades_v1` is never changed, so after a rollback the old system
  sells from exactly where it was.
- **Steps bought while installed** live only in the Money record (`netKg`,
  `upgrades`). The old system doesn't read them, so after a rollback those
  players are back to their old kg count; the Money they spent stays spent.
  Re-installing brings those steps back: the records are kept, and v2 keeps
  unknown fields.
- While paid upgrades are closed, no real purchases happen, so a rollback
  during validation loses nothing.

### Live-baseline checklist (Studio, API access ON)

| # | Do | Expect |
|---|---|---|
| G1 | Run `InstallBoardUpgrades.lua` (Edit mode) | "Installed"; if it refuses, send the named script's current source |
| G2 | Play with a player whose `GrinderUpgrades_v1` record has `kg = 3` | Their net shows 30 kg (plates `NET 30 KG → 35 KG`, card `30kg > 35kg`); `NetMaxWeight` 30 |
| G3 | Change `Workspace.NetLift.MaxWeight` by hand | That player's `NetMaxWeight` stays 30 |
| G4 | `NetKgOpen = true`; click a post, then its price plate | Two separate purchases (−$100, then −$150); one toast each; `GrinderUpgrades_v1` kg still 3 |
| G5 | Watch the plates for a few seconds | They keep YOUR values (no flicker back to $100 / old text) |
| G6 | Blade pad / conveyor pad | Work as before (same prices, blade shows, sales pay × blade) |
| G7 | Leave and rejoin | Still 40 kg (not 55): the old count isn't added again |
| G8 | Meat Price 2x + an Uncommon blade, sell a fish | Pays 2 × value × 1.25 (each once); the popups add up to it |
| G9 | Board | Four cards in the board's card style; icons from the attributes you set |
| G10 | `RollbackBoardUpgrades.lua` | The live GrinderUpgrades scripts and EconomyService come back exactly |

## +5 KG signs: net capacity (part of `InstallBoardUpgrades.lua`)

Each player **owns** a net capacity, saved with their Money. Everyone starts
at 15 kg.

**The signs:**

- The server binds **every** Workspace child named `KGsign`; the place has
  two with the same name.
- Clicking a sign's `Board Part` ClickDetector buys the clicker's next
  +5 kg.
- A panel above each sign shows **your** capacity → next and the price
  (**SOON** while closed, **MAX** at the cap), plus the shared net's
  current capacity. It uses the same style as the rod Buy panel.
- The result appears as the usual toast, e.g. "Net capacity 15 → 20 kg
  (-$25)" or "Walk up to the sign".

**Pricing (`Config.NetKg`, initial tuning, not measured pacing).** As
released in `187fe39` the steps were 25, 50, 100, ... (3,315 in total).
The upgrade board makes the first step
$10 like every board upgrade:

| From → to (kg) | 15→20 | 20→25 | 25→30 | 30→35 | 35→40 | 40→45 | 45→50 | 50→55 | 55→60 |
|---|---|---|---|---|---|---|---|---|---|
| Cost (row 17) | 10 | 25 | 50 | 100 | 150 | 225 | 340 | 510 | 765 |

After the listed costs (10, 25, 50, 100), each step is the previous cost ×
1.5, rounded to 5, up to **Max 60 kg**: 2,175 in total from 15 kg.
`Config.check` refuses a first step other than `UpgradeFirstCost` (10) or
any step above `UpgradeCostCap` (5,000). To tune:

- `Base`: the start, the place's MaxWeight
- `Step`: kg per purchase
- `Max`: the cap
- `Costs`: the listed first costs
- `Growth`: the multiplier after the list

**The shared net:**

- `Workspace.NetLift.MaxWeight`, which the weight gate, gauge and net
  themes read, is the **highest capacity among players in the server whose
  Money has loaded**. It never goes below the place's own value (15).
- It updates on join (once loaded), on each purchase and on leave. A
  player who leaves stops counting at once, even while their final save is
  still running.
- Only the attribute changes: no fish are touched, and NetLiftScript, the
  dwell, ownership and harpoon code are unchanged.

**Protections:**

- The player must be alive, have their Money loaded, and be near the
  clicked sign (the ClickDetector's 20 studs, + 8, + half the board's
  size).
- One purchase at a time per player (shared with rod purchases), with a
  0.5 s cooldown.
- Every condition is checked again right before the debit, after any wait
  for a running save.
- Money goes only through EconomyService; nothing writes leaderstats
  directly.
- **Fail closed:** without EconomyService the signs do nothing.

**Saving:**

- Record field `netKg` (whole kg). A purchase writes the new balance
  **and** the new capacity in **one** write before it counts.
- The new capacity is staged: `netKg()` keeps the committed one until the
  write succeeded. If the write fails, nothing is charged.
- An invalid `netKg` is never overwritten; that player gets 15 kg and
  can't buy that session.
- A newer build's higher value is kept as it is.
- v1/v2 records without the field load as 15 kg with their money
  untouched.
- The same migration risks as rods apply (see above).

**Paid signs stay CLOSED** (`Config.NetKgOpen = false`) until the saved path
is validated. For a Studio validation **with API access**, set the
`NetKgOpen` attribute on `ReplicatedStorage.Economy`.

**Install:** part of [`InstallBoardUpgrades.lua`](#upgrade-board-on-the-live-baseline-installboardupgradeslua) (the per-milestone installer this section was written for was never installed and is superseded).

### Net capacity checklist (Studio, API access ON)

| # | Do | Expect |
|---|---|---|
| K1 | Play, walk to either +5 KG sign | Panel: "Your net 15 → 20 kg", "SOON", "Net now: 15 kg" (above BOTH signs) |
| K2 | Click a sign (closed) | Toast "Net upgrades open soon"; nothing charged |
| K3 | Set `ReplicatedStorage.Economy.NetKgOpen = true`; click | −25, toast "Net capacity 15 → 20 kg (-$25)"; `NetLift.MaxWeight` 20; panel $50 |
| K4 | Click the OTHER sign | Same thing (+5 kg, −50) |
| K5 | Walk away 40+ studs, click | Toast "Walk up to the sign"; nothing charged |
| K6 | Net a heavy load | The weight gate / gauge use the new MaxWeight |
| K7 | Second client (15 kg) joins, then the first leaves | MaxWeight follows the highest present player, then drops to 15; no fish vanish |
| K8 | Stop, Play again (real DataStore) | Your capacity is back; MaxWeight follows it once your money loads |

(With row 17 installed the prices in K3/K4 are $10 and $25, and the posts'
own plates show them instead of the floating panel.)

## Upgrade board, milestone 1: Net Strength (part of `InstallBoardUpgrades.lua`)

The board at `Workspace.Board` (its `Main` part, `SurfaceGui.bord3`) becomes
four upgrade cards, drawn **for each player**:

| Card | Colour | Shows | Sells (this milestone) |
|---|---|---|---|
| Net Strength | pink | your net, e.g. `15kg > 20kg` | the next +5 kg: **$10** first |
| Rod Luck | lime | `1x > 2x` | milestone 2 |
| Meat Price | cyan | `1x > 2x` (a value multiplier: fish values differ) | milestone 3 |
| Faster Reels | amber | `1x > 1.2x` | milestone 4 |

2 × 2 grid in a wooden frame. Each card is made from the board's own card
art (see [the live-baseline install](#upgrade-board-on-the-live-baseline-installboardupgradeslua)):
its Buy button, gradient and icon frame; icons from Board attributes, the
themed emoji only where none is supplied.

**The board in the place is never changed.** `UpgradeBoardClient` copies
`Main.SurfaceGui` into the player's PlayerGui (adorned to `Main`), removes
the old cards and the list layout from the copy, builds the four cards and
hides the original **on that client only**.

- Found by exact path: exactly one Workspace child `Board`, one `Main` in
  it, one `SurfaceGui` on it, one `bord3` in that. The two old cards (both
  named `Frame`, each with two labels named `Text`) are never looked up by
  name. If the path is missing or ambiguous (two `Board`s), the server sells
  nothing and warns; the client draws nothing and hides nothing.
- The client looks for the board every second, so streaming in/out works.

**Net Strength is the same saved capacity as the KGsign posts** (one
progression, `netKg` in the Money record). Buying at the board or at either
post moves the same number; the other place shows the new step at once.
The shared `NetLift.MaxWeight` follows board purchases too (NetCapacityServer
already follows each player's `NetKg`).

**Pressing a card** (mouse, touch or gamepad: `Activated`):

- the client asks `ReplicatedStorage.Economy.UpgradeAction` (a
  RemoteFunction made at run time, never saved) with the card's id. One
  request per card at a time; **SAVING...** meanwhile
- the server: known id only (anything else, or a non-string, is refused),
  0.25 s between presses per player, then `EconomyService.netKgAction` with
  "near the board" (20 studs + half the board) as its place check: alive,
  money loaded, one purchase at a time (shared with rods and the posts),
  cooldown, re-checked right before the debit, money + capacity saved in
  one write before it counts
- the answer shows on the button for a moment (BOUGHT! / NEED $ / TOO FAR /
  NOT SAVED / MAX / WAIT / SOON) and as the usual toast with the full
  message
- the button also shows: `$10` (red when you can't afford it), `...` while
  your money loads, **SOON** while paid upgrades are closed, **MAX** at
  60 kg, **OFF** if the server's board isn't running

**The posts' price plates.** Each `KGsign.PricePlate.PriceGui` (a live edit
showing `$100` and `NET15KG->20KG`) now shows **your** values: `$10` /
SOON / MAX / `...`, and `NET15KG->20KG` / `NET60KG MAX`. The labels are
told apart by what they say (exactly one that is only a price, exactly one
that names KG); if that isn't clear-cut the plate is left alone and the
post keeps the floating panel. A post with a bound plate has no floating
panel. Changes are on each client only.

**Paid upgrades stay CLOSED** (`Config.NetKgOpen = false`): SOON on the card
and the plates. For a Studio validation **with API access**, set the
`NetKgOpen` attribute on `ReplicatedStorage.Economy`. Studio's memory
fallback is **not** proof of persistence.

**Install:** part of [`InstallBoardUpgrades.lua`](#upgrade-board-on-the-live-baseline-installboardupgradeslua) (the per-milestone installer this section was written for was never installed and is superseded).

### Upgrade board checklist (Studio, API access ON)

| # | Do | Expect |
|---|---|---|
| N1 | Play, look at the board | Four cards in a 2 × 2 wooden frame: Net Strength (pink) `15kg > 20kg`, Rod Luck (lime) `1x > 2x`, Meat Price (cyan) `1x > 2x`, Faster Reels (amber) `1x > 1.2x`; all SOON. No Axe Speed / Buy Miner cards. No `[UpgradeBoard]` warning in Output |
| N2 | Look at both +5 KG posts | Their plates show `SOON` and `NET15KG->20KG`; no floating panel over them |
| N3 | Press Net Strength (closed) | SOON; toast "Net upgrades open soon"; nothing charged |
| N4 | Set `ReplicatedStorage.Economy.NetKgOpen = true` | Card and both plates: `$10` |
| N5 | Press Net Strength | SAVING..., then BOUGHT!; −10; toast "Net capacity 15 → 20 kg (-$10)"; card `20kg > 25kg` `$25`; plates `$25` `NET20KG->25KG`; `NetLift.MaxWeight` 20 |
| N6 | Click a post | −25, 20 → 25 kg; the board card follows (`25kg > 30kg`, `$50`) |
| N7 | Press the card from 40+ studs away (or from a post) | TOO FAR; toast "Walk up to the board"; nothing charged |
| N8 | Press Rod Luck / Meat Price / Faster Reels | SOON; toast "... coming soon"; nothing charged |
| N9 | On a phone emulator and with a mouse | The buttons press the same way |
| N10 | Second client with little money | Their own values on the card and plates; red price; NEED $ when pressed |
| N11 | Stop, Play again (real DataStore) | Your capacity is back on the card, plates and posts |

## Upgrade board, milestone 2: Rod Luck (part of `InstallBoardUpgrades.lua`)

The Rod Luck card (lime) now sells a saved **level**:

| Level | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Rod Luck | 1x | **2x** | 2.5x | 3x |
| Price of this level | - | **$10** | $75 | $300 |

Initial tuning in `Config.BoardUpgrades.RodLuck`. `Config.check` enforces:
Values start at 1 then the card's `FirstValue` (2), increase, and stay at or
under `MaxValue` (5); the first cost is `UpgradeFirstCost` ($10); costs
increase and stay at or under `UpgradeCostCap`.

**What 2x means.** Rod Luck changes only the **fish species roll on your own
casts**:

- Each fish's rod weight is multiplied by `luck ^ ((tier − lowest tier) /
  (highest tier − lowest tier))`: the commonest tier ×1, the rarest ×luck,
  tiers between scale geometrically.
- The odds are then renormalised over all fish. At 2x the rarest fish's
  weight is **doubled relative to the commonest**. That makes it likelier,
  never certain.
- Example with two fish (spawn weights 50 and 20, which rods flatten to
  weight^0.85): the rare one goes from 31% to 48% at 2x.
- The **Silver / Gold roll is unchanged**.
- The rod-fish offer's chance label uses the same odds, so it shows the
  chance that catch really had.

**Whose luck, and when.** Each accepted press of the fish button fixes the
**presser's committed** luck for every rod that press casts, next to their
equipped rod.

- Buying more luck during a cast changes nothing for that cast.
- A purchase that is still being saved doesn't count yet.
- Another player's luck never affects your cast.
- Without the money service, on any error, or for a value outside 1..5: 1x
  (the old odds).

**Saving:**

- Record field `upgrades` (`{ RodLuck = level }`, whole numbers).
- A purchase writes the new balance **and** the new level in one write
  before it counts. The level is staged until then. If the write fails,
  nothing is charged.
- An unreadable `upgrades` field is never overwritten: that player has 1x
  and can't buy this session.
- Entries a newer build added are kept. A level above this build's last one
  is kept; its effect is this build's last value.

**The board.** Pressing the card goes through
`EconomyService.upgradeAction`. It has the same checks as Net Strength:
alive, loaded, near the board, one purchase at a time (shared with rods and
the net), a 0.5 s cooldown, and everything re-checked right before the
debit. Toasts read like "Rod Luck 1x → 2x (-$10)". The card shows **your**
`2x > 2.5x` and the price, `3x MAX`, SOON while closed, and so on.

**Paid board upgrades stay CLOSED** (`Config.BoardUpgradesOpen = false`),
separately from Net Strength (`NetKgOpen`). For a Studio validation **with
API access**, set the `UpgradesOpen` attribute on
`ReplicatedStorage.Economy`.

**Install:** part of [`InstallBoardUpgrades.lua`](#upgrade-board-on-the-live-baseline-installboardupgradeslua) (the per-milestone installer this section was written for was never installed and is superseded).

### Rod Luck checklist (Studio, API access ON)

| # | Do | Expect |
|---|---|---|
| L1 | Play, look at the board | Rod Luck: `1x > 2x`, SOON |
| L2 | Press Rod Luck (closed) | Toast "Rod Luck upgrades open soon"; nothing charged |
| L3 | Set `ReplicatedStorage.Economy.UpgradesOpen = true`; press | −10; toast "Rod Luck 1x → 2x (-$10)"; card `2x > 2.5x` `$75` |
| L4 | Press the fish button, catch fish | Rod-fish offers show chances with 2x (rarer fish's % higher than before); Silver/Gold as before |
| L5 | A second player without luck fishes | Their offers show the old chances |
| L6 | Buy 2.5x while your rods are out | That catch keeps 2x; the next press uses 2.5x |
| L7 | Buy up to 3x | `3x MAX`, MAX; pressing again: "Rod Luck is at the maximum (3x)" |
| L8 | Stop, Play again (real DataStore) | Your level is back on the card |

## Upgrade board, milestone 3: Meat Price (part of `InstallBoardUpgrades.lua`)

The Meat Price card (cyan) sells a saved **value multiplier** on your own
fish:

| Level | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Meat Price | 1x | **2x** | 2.5x | 3x |
| Price of this level | - | **$10** | $150 | $600 |

Initial tuning in `Config.BoardUpgrades.MeatPrice`, with the same guard
rails as Rod Luck. The card shows `1x > 2x`, not dollars, because fish
values differ.

**How it pays.** When the grinder cuts a fish, `EconomyService.issueFish`
looks up the fish's **owner** (the same owner the sale pays).

- The fish's whole sale value (tier value × Silver/Gold, both unchanged) is
  multiplied **once** by that owner's committed Meat Price and rounded.
- It is then split into the usual number of meat pieces. For example, a
  tier-10 fish worth 42 at 2.5x is worth 105, which splits into 52 + 53
  (not 53 + 53).
- The pieces' values are fixed from then on, and each piece still pays
  once. The duplicate-payment guard (settle removes the record) is
  unchanged.
- Only the owner's multiplier counts. A fish you net for someone else pays
  them at theirs. An unowned fish pays nobody. Carriers are never paid.
- An owner who isn't in the server (or whose money hasn't loaded) gets 1x
  for that cut.
- A fish cut **before** you bought keeps its old value even if it sells
  after.
- Rod-fish offer prices don't change.

**Saving, checks and closing:** the same as Rod Luck
(`upgrades.MeatPrice`, money + level in one write, `upgradeAction`'s
checks, `UpgradesOpen` for a Studio validation).

**Install:** part of [`InstallBoardUpgrades.lua`](#upgrade-board-on-the-live-baseline-installboardupgradeslua) (the per-milestone installer this section was written for was never installed and is superseded).

### Meat Price checklist (Studio, API access ON)

| # | Do | Expect |
|---|---|---|
| P1 | Play, look at the board | Meat Price: `1x > 2x`, SOON |
| P2 | Set `UpgradesOpen = true`; press Meat Price | −10; toast "Meat Price 1x → 2x (-$10)"; card `2x > 2.5x` `$150` |
| P3 | Net a fish, sell its meat (truck or customer) | The "+$" popups add up to 2 × that fish's usual value |
| P4 | A Gold fish | 2 × (its value × 5) |
| P5 | Net a fish another player bought (their fish) | It pays them at their multiplier, not yours |
| P6 | Meat already on the stack when you buy | Sells at the old value |
| P7 | Stop, Play again (real DataStore) | Your level is back |

## Upgrade board, milestone 4: Faster Reels (part of `InstallBoardUpgrades.lua`)

The Faster Reels card (amber) sells a saved **reel speed** for your own
casts:

| Level | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Faster Reels | 1x | **1.2x** | 1.35x | 1.5x |
| Reel-in | 3.4 s | 2.83 s | 2.52 s | 2.27 s |
| Price of this level | - | **$10** | $100 | $400 |

Initial tuning in `Config.BoardUpgrades.FasterReels`, never above 2x
(`MaxValue`).

**What it changes:**

- Each accepted press of the fish button fixes the **presser's committed**
  reel speed for every rod it casts, next to their rod and luck.
- The reel-in (fish rising on the line) takes `3.4 / speed` seconds on the
  server, and the silhouette flicks speed up by the same factor.
- The clients need no change. Their rising-fish animation already runs over
  the server's `Dur` attribute, and the rod bends while the server says
  `Pulling`, so both shorten with the server's timing.
- **The bite wait is not touched.** That stays the equipped rod's benefit
  (`BiteWait`). A purchase during a cast applies from the next press.

**Saving, checks and closing:** the same as Rod Luck
(`upgrades.FasterReels`, `UpgradesOpen`).

**Install:** part of [`InstallBoardUpgrades.lua`](#upgrade-board-on-the-live-baseline-installboardupgradeslua) (the per-milestone installer this section was written for was never installed and is superseded).

### Faster Reels checklist (Studio, API access ON)

| # | Do | Expect |
|---|---|---|
| F1 | Play, look at the board | Faster Reels: `1x > 1.2x`, SOON |
| F2 | Set `UpgradesOpen = true`; press Faster Reels | −10; toast "Faster Reels 1x → 1.2x (-$10)"; card `1.2x > 1.35x` `$100` |
| F3 | Press the fish button | The fish rise on the line in about 2.8 s instead of 3.4 s, smoothly (no jump at the end); the rod bends for the same time |
| F4 | Compare the wait for a bite | Unchanged (only your rod changes that) |
| F5 | A second player without it fishes | Their reel stays 3.4 s |
| F6 | Stop, Play again (real DataStore) | Your level is back |

## Blender Bot recovery (`InstallBotRecovery.lua`)

**The bug:** the Blender Bot's loop had no error handling. If anything
errored mid-trip (a part of the bot removed, a bad table slot attribute),
the whole script stopped: the bot froze for the rest of the server, and the
piece it was carrying floated as `CarriedMeat`, never sold and never paid.

**The fix** (BotSystem only, on the sales version):

- Each trip runs under `pcall`. The bot tracks the piece in its hands from
  the moment it leaves the stack until it lies on the table.
- On an error, the loose clone is removed and the piece is **held** in the
  ledger. The grinder brings it back out of the pipe with the same owner
  and value, the same path a full stack uses. Nothing is lost unpaid.
- The bot tries again after a back-off of 1 s, growing to 5 s while
  something stays broken. It warns once, then once per 20 failures.
- An error with nothing in its hands holds nothing.

**Install:** `InstallBotRecovery.lua` (v2 guarded template) needs
`EconomySalesBackup` and the exact sales BotSystem. Backup:
`ServerStorage.EconomyBotBackup`. **Rollback:** `RollbackBotRecovery.lua`,
before `RollbackSales`.

### Bot recovery checklist (Studio)

| # | Do | Expect |
|---|---|---|
| B1 | Play normally | The bot carries meat to the table exactly as before |
| B2 | In Play, while the bot carries a piece, delete one of the bot's parts from the Explorer (or rename `SaleTable` attribute `Slot1`) | One `[BotSystem] trip failed ... piece kept` warning; the carried piece disappears; within a few seconds a piece with the same `PieceId` comes back out of the grinder pipe |
| B3 | Undo the damage (Stop and Play again) | The bot works normally |

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
python3 tools/economy/tests/run_tests.py path/to/luau          # 461 checks (rods 80, net kg 52, board upgrades 67)
python3 tools/economy/tests/run_runtime_sim.py path/to/luau    # prompt 80, sales 40, upgrades 18, jump 10, rod 23, dwell 17, variants 25, earnings 47, money HUD 41, rods 67 (+67 on the upgrade board's RodFishingSystem), shop UI 28, panel 47, bot 14, meat glow 21, harpoon blend 15, kg 28 + 4, board 49 + 6, luck 30, meat 17, reels 15, grinder 27 + 7 checks
python3 tools/economy/tests/run_installer_sim.py path/to/luau  # 336 checks
python3 tools/aquarium-cycle/tests/run_tests.py path/to/luau   # 869 checks (aquarium v1.2)
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
- **Sales simulation:** the **real patched GrinderProcessor and
  TruckSystem** with the real EconomyService on the fake engine
  (`tests/sim/`). It checks:
  - who is paid on each route: the net player, the buyer, the bound
    harpoon, nobody, never the carrier
  - value split across pieces, and one payment per piece
  - respawn/leave while carrying: pieces held, then re-emitted with the same
    identity
  - a full stack: the pit stays bounded, overflow is held, nothing is lost,
    and everything flows once there is room
  - the customer route
- **Installer dry run:** the real fresh installer and uninstaller, plus
  `UpdateRodPrompt` / `RollbackRodPrompt`, against a place set up by the
  **real 8cb2554 installer** (from git). It checks:
  - every refusal
  - rollback to exactly 8cb2554
  - the original uninstall chain afterwards
- **Build-time guards:** the offer path never fires the grinder event, and
  its only aquarium delivery is the paid `deliver` callback. It also passes
  the rod's stand and real chance.
