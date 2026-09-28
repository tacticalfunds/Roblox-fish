# Economy (work in progress)

A single soft currency, `leaderstats.Money`, paid only when a meat piece sells.
Also rod-fish Buy/Pass offers and aquarium upgrade charging. Nothing here is
installed in Studio. Astra reviews the code against the live mechanics before
anything is installed.

Status of this directory:

| Part | State |
|---|---|
| `src/core`: Config, Pricing, Ledger, MoneyStore, Offers | done, 168 offline checks |
| EconomyService (Roblox binding), live-script patches, installer/uninstaller | next commit |
| Rod-fish Buy/Pass + aquarium v1.2 (buyer id through tank/river) | after that |

`studio/live/` holds the latest live sources Astra supplied (2026-09-28). The
patches and installer guards are built against these copies.

## Rules the core enforces

- **One payment per meat piece.** The grinder issues a ledger record per piece
  with its owner and value fixed. Settling removes the record, so a second
  settle of the same `PieceId` (a clone, a second route, a repeated event)
  pays nothing.
- **Value is split, not multiplied.** A fish is worth
  `round(4 × 1.3^(tier−1)) × variant`, where Silver is ×2 and Gold ×5. That
  value is split across the existing 1/2/3/5 meat pieces, with the remainder
  on the last piece, so the pieces add up to exactly the fish value.
- **No full stack destroys unpaid meat.** When the pipeline is full, a piece
  is *held* as a ledger record with no object and re-emitted later, oldest
  first. The same happens to meat a truck carrier was holding when they left
  or respawned.
- **Money safety:**
  - The starting grant (100) is given only when the store positively reports
    no record.
  - A load error or corrupt record never grants and never writes defaults,
    and that player is never saved.
  - Saves use a session lock. A save reports success only if this server's
    value was actually written.
  - Credits earned while a player's money is loading are applied once the
    load succeeds, or dropped if they leave first.
- **Offers:**
  - Only the caster can buy or pass.
  - Buy is one step with no yields: range → tank reservation → debit →
    delivery, with a refund if the delivery fails.
  - A full or unavailable tank cancels the offer without charging.
  - Too little money keeps the offer open.
  - Repeated clicks never charge or deliver twice.
  - Pass, timeout, disconnect and switching the feature off all cancel with
    no charge.

All prices are tentative targets, not measured income.

## Tests

```
python3 tools/economy/tests/run_tests.py path/to/luau
```

These are pure-logic tests; the DataStore is a fake that fails on purpose.
They are not Roblox runtime tests.
