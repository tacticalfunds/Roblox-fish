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
python3 tools/economy/tests/run_tests.py path/to/luau          # 262 checks
python3 tools/economy/tests/run_runtime_sim.py path/to/luau    # prompt 80, sales 40, upgrades 18, jump 10, rod 23, dwell 17, variants 21, earnings 47, money HUD 41, bot 14, meat glow 21, harpoon blend 15 checks
python3 tools/economy/tests/run_installer_sim.py path/to/luau  # 255 checks
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
