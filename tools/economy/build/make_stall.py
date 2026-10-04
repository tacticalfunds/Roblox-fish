#!/usr/bin/env python3
"""Sell stall: patches the TruckSystem Studio runs now (the MeatGlow version,
tools/fish-variants/studio/meat-glow/TruckSystem.patched.from-sales.lua; the
place inventory's SourceLength, 15071, matches it exactly) into
studio/stall/TruckSystem.lua. Changes, marked "Sell stall":

  * the red-and-white Sell stall's red ring sells carried meat: standing in
    it sells the pieces you carry, one per transfer tick (like a truck),
    each through the SAME ledger sale as a truck drop -
    Economy.settle(pieceId, "Stall"): paid once to the piece's OWNER (the
    Earned popup shows what really arrived), never per count, never twice.
    An untracked piece (no ledger id) sells for nothing, as at a truck.
  * the ring is found by shape, never by a name that could match the Sell NPC
    (Workspace.Sell): exactly one Workspace child Model with direct BasePart
    children Circle and Touch and a descendant TextLabel / TextBox saying
    "Sell". Not exactly one -> no stall (a warning), trucks unchanged. Looked
    for again every few seconds while missing.
  * "in the ring" is checked on the server: horizontal distance to the
    Circle's centre <= half its width + RING_SLACK, vertically within
    RING_Y. Alive players only (the transfer loop's own check).
  * without a running EconomyService the stall sells nothing (original
    behaviour: there was no stall).

Usage:  python3 tools/economy/build/make_stall.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = ROOT.parent / "fish-variants" / "studio" / "meat-glow" / "TruckSystem.patched.from-sales.lua"
OUT = ROOT / "studio" / "stall" / "TruckSystem.lua"


class Patch:
    def __init__(self, src: str):
        self.src = src

    def rep(self, old: str, new: str) -> None:
        n = self.src.count(old)
        assert n == 1, f"expected 1 match, got {n}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


def truck() -> str:
    p = Patch(BASE.read_text())
    p.rep(
        "-- [MeatGlow patch] Changes marked \"MeatGlow\"",
        "-- [Sell stall patch] Changes marked \"Sell stall\": standing in the Sell stall's\n"
        "-- red ring sells the meat you carry, one piece per tick, each the same ledger\n"
        "-- sale as a truck drop (Economy.settle(id, \"Stall\"): paid once to its owner).\n"
        "-- The ring is found by shape (a Workspace Model with Circle + Touch parts and a\n"
        "-- \"Sell\" label), never confused with the Sell NPC. No EconomyService -> no stall.\n"
        "--\n"
        "-- [MeatGlow patch] Changes marked \"MeatGlow\"",
    )
    p.rep(
        "local DELIVER_RANGE = 9\n",
        "local DELIVER_RANGE = 9\n"
        "-- Sell stall: the red ring (see findStall)\n"
        "local RING_SLACK = 1.5 -- studs beyond the ring's radius that still count\n"
        "local RING_Y = 8 -- studs above / below the ring's centre that still count\n"
        "local STALL_RESCAN = 5 -- seconds between looks for the stall while it's missing\n",
    )
    p.rep(
        "local timers = {}\n",
        "-- Sell stall: the ring's Circle part, found by shape (never by the name \"Sell\":\n"
        "-- Workspace.Sell is an NPC). Exactly one Workspace child Model with direct\n"
        "-- BasePart children Circle and Touch and a descendant label saying \"Sell\".\n"
        "local function saysSell(model)\n"
        "\tfor _, d in ipairs(model:GetDescendants()) do\n"
        "\t\tif (d:IsA(\"TextLabel\") or d:IsA(\"TextBox\")) and string.lower(d.Text) == \"sell\" then return true end\n"
        "\tend\n"
        "\treturn false\n"
        "end\n"
        "local function findStall()\n"
        "\tlocal found, count = nil, 0\n"
        "\tfor _, m in ipairs(workspace:GetChildren()) do\n"
        "\t\tif m:IsA(\"Model\") then\n"
        "\t\t\tlocal circle, touch = m:FindFirstChild(\"Circle\"), m:FindFirstChild(\"Touch\")\n"
        "\t\t\tif circle and circle:IsA(\"BasePart\") and touch and touch:IsA(\"BasePart\") and saysSell(m) then\n"
        "\t\t\t\tfound, count = circle, count + 1\n"
        "\t\t\tend\n"
        "\t\tend\n"
        "\tend\n"
        "\tif count ~= 1 then return nil, count end\n"
        "\treturn found, 1\n"
        "end\n"
        "local stallRing, nextStallLook, stallWarned = nil, 0, false\n"
        "local function currentStall()\n"
        "\tif stallRing and stallRing:IsDescendantOf(workspace) then return stallRing end\n"
        "\tstallRing = nil\n"
        "\tif os.clock() < nextStallLook then return nil end\n"
        "\tnextStallLook = os.clock() + STALL_RESCAN\n"
        "\tlocal ring, count = findStall()\n"
        "\tstallRing = ring\n"
        "\tif not ring and not stallWarned then\n"
        "\t\tstallWarned = true\n"
        "\t\twarn(\"[TruckSystem] Sell stall: expected exactly one ring (a Model with Circle + Touch and a Sell label), found \" .. count .. \" - the stall doesn't sell\")\n"
        "\tend\n"
        "\treturn ring\n"
        "end\n"
        "local function inRing(ring, pos)\n"
        "\tlocal c = ring.Position\n"
        "\tlocal radius = math.max(ring.Size.X, ring.Size.Z) / 2 + RING_SLACK\n"
        "\treturn Vector3.new(pos.X - c.X, 0, pos.Z - c.Z).Magnitude <= radius and math.abs(pos.Y - c.Y) <= RING_Y\n"
        "end\n"
        "\n"
        "local timers = {}\n",
    )
    p.rep(
        "\t\tlocal bucketPos = front and (Path.truckCF(Path.LOAD_S) * CFrame.new(front.bucketOffset)).Position\n",
        "\t\tlocal bucketPos = front and (Path.truckCF(Path.LOAD_S) * CFrame.new(front.bucketOffset)).Position\n"
        "\t\tlocal stall = Economy and currentStall() -- Sell stall: only with the money service\n",
    )
    p.rep(
        "\t\t\t-- drop into the front truck\n"
        "\t\t\telseif loading and c.count > 0 then\n",
        "\t\t\t-- Sell stall: standing in the red ring sells the top piece (the same ledger sale)\n"
        "\t\t\telseif stall and c.count > 0 and inRing(stall, pos) then\n"
        "\t\t\t\tc.count -= 1\n"
        "\t\t\t\tlocal variant = c.glow and c.glow[c.count + 1] -- MeatGlow: the top piece\n"
        "\t\t\t\tEconomy.settle(table.remove(c.ids), \"Stall\") -- the one sale: paid to the piece's owner\n"
        "\t\t\t\tcarryVisual(player)\n"
        "\t\t\t\tflyPart(pos + Vector3.new(0, 1.5, 0), stall.Position + Vector3.new(0, 1, 0), 3, 0.3, variant)\n"
        "\t\t\t-- drop into the front truck\n"
        "\t\t\telseif loading and c.count > 0 then\n",
    )
    out = p.src
    assert out.count("Sell stall") == 8, out.count("Sell stall")
    return out


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(truck())
    print(f"wrote {OUT.relative_to(ROOT.parent.parent)}")


if __name__ == "__main__":
    main()
