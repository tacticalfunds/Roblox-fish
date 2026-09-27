# Immediate rod cast

Pressing the big button now casts every eligible rod together, right away,
and the rods visibly dip toward the water. After that everything is as
before: the bite wait, silhouettes, reveal, reel, and tank (or grinder)
delivery.

## What changes

**RodFishingSystem** (patched on top of the aquarium version, with or
without fish-variants):
- **No delays:** the 0.45 s `PRESS_DELAY` and the 0.12 s per-rod stagger
  are removed.
- **One synchronous press:** `press()` no longer yields and returns whether
  the press was accepted. It claims the button lock and every rod's busy
  state before anything else can run, so rapid presses can't double-cast.
- **Button animation:** it animates for other players (`PressedAt`) only
  when the press was accepted. A full tank, busy rods, or a lost reservation
  start nothing and don't animate.
- **Rod dip:** each rod gets `CastT0` when its cast starts; this is cleared
  when the reel starts and on the error-cleanup path.
- **Unchanged:** the per-player 0.6 s cooldown, the 80-stud distance check,
  busy checks and the aquarium reservation.

**RodFishingClient:** while `CastT0` is set, the rod dips `CAST_DIP_DEG`
(−14°) over 0.18 s through the existing rod smoothing, and rests low with a
gentle sway. The existing reel tug takes over when `Pulling` starts. **If
rods tilt up instead of down in Studio, flip the sign of `CAST_DIP_DEG`.**

## Install and uninstall (Studio, Edit mode, Command Bar)

- **Install:** `tools/rod-cast/InstallRodCast.lua` (generated). One undo step.
  It matches RodFishingSystem against either the variants+aquarium or the
  aquarium-only reviewed version, and RodFishingClient against the supplied
  original. It backs both up to `ServerStorage.RodCastBackup`.
- **Order:** install fish-variants **before** this. The variants installer
  refuses a RodFishingSystem it doesn't recognize.
- **Uninstall:** `tools/rod-cast/UninstallRodCast.lua`. Run it before
  uninstalling variants or the aquarium. It restores both scripts and
  refuses if they were edited after install.

## Checks run

`python3 tools/rod-cast/tests/run_press_sim.py <luau>` slices the real
patched `press()` and button handler out of both generated server scripts.
It runs them under the Luau CLI with small stubs: rods, the aquarium
reservation, a coroutine scheduler, and a `safeRunRod` that stays casting
until released. **11/11 pass on both bases:**
- one press casts all five rods at once
- same-instant presses from two players and spam produce no duplicate
  casts: never more than one active cast per rod
- the cooldown still ignores spam
- a full tank starts nothing, doesn't animate, and leaves the button ready
- with partial capacity, only the reserved rods cast
- after a rod returns, a re-press casts only the idle rods
- a lost reservation race starts nothing

The patches compile and type-check. The only findings are lints on
unchanged base lines.

**Not Roblox runtime tested.** Check in Studio:
- the rods dip down (not up) the instant you press
- all eligible rods cast together
- the reel, reveal and tank delivery still work
- pressing with a full tank does nothing except show the notice
