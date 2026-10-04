#!/usr/bin/env python3
"""Customer queue fix: patches the CustomerSystem Studio runs now (the upgrade
board release's, studio/board/CustomerSystem.lua at fffdaa3) into
studio/queue/CustomerSystem.lua. Changes, marked "Queue fix":

  * "standing at the counter" is a HORIZONTAL distance (<= 3 studs) to the
    slot plus a vertical sanity bound (<= 6): the slots are ground points
    (Y 9.3) and a customer's root part stands ~3 studs above, so the old 3-D
    check (> 3) could stay false forever at the counter and jam the line
    (seen live: 3.126).
  * bounded recovery at the front: walk to the counter again once after
    FRONT_RETRY s; still not there after FRONT_GIVE_UP s -> leave (the
    customer is out of the line at once, so the next one moves up).
  * a customer that is removed, dies or whose script errors is dropped from
    the line (and its model removed), so a stale entry can't hold a place;
    the spawn loop also sweeps such entries.

Usage:  python3 tools/economy/build/make_queue.py
"""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE_COMMIT = "fffdaa3"
BASE_PATH = "tools/economy/studio/board/CustomerSystem.lua"
OUT = ROOT / "studio" / "queue" / "CustomerSystem.lua"


def base() -> str:
    return subprocess.run(
        ["git", "show", f"{BASE_COMMIT}:{BASE_PATH}"], cwd=ROOT, capture_output=True, text=True, check=True
    ).stdout


class Patch:
    def __init__(self, src: str):
        self.src = src

    def rep(self, old: str, new: str) -> None:
        n = self.src.count(old)
        assert n == 1, f"expected 1 match, got {n}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


def customers() -> str:
    p = Patch(base())
    p.rep(
        "-- [Economy board patch] Changes marked \"Economy board\"",
        "-- [Queue fix] Changes marked \"Queue fix\": arriving at the counter is a\n"
        "-- horizontal distance (the slots are ground points, a customer stands ~3\n"
        "-- studs above them), the front customer gives up after a bounded time, and\n"
        "-- removed / dead / errored customers leave the line - it can't jam.\n"
        "--\n"
        "-- [Economy board patch] Changes marked \"Economy board\"",
    )
    p.rep(
        "local WALK_SPEED = 9\n",
        "local WALK_SPEED = 9\n"
        "-- Queue fix: arriving at a slot, and how long the front customer may try\n"
        "local ARRIVE_XZ = 3 -- studs, horizontal, to the slot\n"
        "local ARRIVE_Y = 6 -- studs, vertical sanity (the root part is ~3 above the slot)\n"
        "local FRONT_RETRY = 6 -- s at the front without arriving: walk to the counter again\n"
        "local FRONT_GIVE_UP = 20 -- s at the front without arriving: leave (the next moves up)\n",
    )
    p.rep(
        "local function leave(c)\n",
        "-- Queue fix: at a slot = close horizontally, roughly at its height\n"
        "local function atSlot(c, slot)\n"
        "\tlocal d = c.hrp.Position - slot\n"
        "\treturn Vector3.new(d.X, 0, d.Z).Magnitude <= ARRIVE_XZ and math.abs(d.Y) <= ARRIVE_Y\n"
        "end\n"
        "\n"
        "-- Queue fix: still a customer that can walk and buy\n"
        "local function alive(c)\n"
        "\treturn c.model.Parent ~= nil and c.hum.Parent ~= nil and c.hum.Health > 0 and c.hrp.Parent ~= nil\n"
        "end\n"
        "\n"
        "-- Queue fix: out of the line for good (removed / dead / errored); idempotent\n"
        "local function drop(c)\n"
        "\tfor i, x in ipairs(line) do if x == c then table.remove(line, i) break end end\n"
        "\tc.state = \"gone\"\n"
        "\treposition()\n"
        "\tif c.model.Parent then c.model:Destroy() end\n"
        "end\n"
        "\n"
        "local function leave(c)\n",
    )
    p.rep(
        "\t-- wait until we're at the front and standing at the table\n"
        "\twhile c.model.Parent and (line[1] ~= c or (c.hrp.Position - SLOTS[1]).Magnitude > 3) do task.wait(0.3) end\n"
        "\tif not c.model.Parent then return end\n",
        "\t-- wait until we're at the front and standing at the table\n"
        "\t-- Queue fix: horizontal arrival; bounded at the front; removed / dead -> dropped\n"
        "\tlocal frontFor, retried = 0, false\n"
        "\twhile true do\n"
        "\t\tif not alive(c) then drop(c) return end\n"
        "\t\tif line[1] == c then\n"
        "\t\t\tif atSlot(c, SLOTS[1]) then break end\n"
        "\t\t\tif frontFor >= FRONT_GIVE_UP then leave(c) return end\n"
        "\t\t\tif frontFor >= FRONT_RETRY and not retried then\n"
        "\t\t\t\tretried = true\n"
        "\t\t\t\ttask.spawn(walkTo, c, SLOTS[1])\n"
        "\t\t\tend\n"
        "\t\t\tfrontFor += task.wait(0.3)\n"
        "\t\telse\n"
        "\t\t\ttask.wait(0.3)\n"
        "\t\tend\n"
        "\tend\n",
    )
    p.rep(
        "\ttable.insert(line, c)\n"
        "\ttask.spawn(runCustomer, c)\n",
        "\ttable.insert(line, c)\n"
        "\ttask.spawn(function() -- Queue fix: an error never leaves a stale place in the line\n"
        "\t\tlocal ok, err = pcall(runCustomer, c)\n"
        "\t\tif not ok then\n"
        "\t\t\twarn(\"[CustomerSystem] customer failed, removed from the line: \" .. tostring(err))\n"
        "\t\t\tdrop(c)\n"
        "\t\tend\n"
        "\tend)\n",
    )
    p.rep(
        "\tlocal cap = lineCap or workspace:GetAttribute(\"CustomersLineCap\") or MAX_IN_LINE\n",
        "\tlocal cap = lineCap or workspace:GetAttribute(\"CustomersLineCap\") or MAX_IN_LINE\n"
        "\tfor i = #line, 1, -1 do -- Queue fix: sweep removed / dead customers that still hold a place\n"
        "\t\tlocal c = line[i]\n"
        "\t\tif c.state ~= \"walking\" and not alive(c) then drop(c) end\n"
        "\tend\n",
    )
    out = p.src
    assert "(c.hrp.Position - SLOTS[1]).Magnitude > 3" not in out
    assert out.count("Queue fix") == 9, out.count("Queue fix")
    return out


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(customers())
    print(f"wrote {OUT.relative_to(ROOT.parent.parent)}")


if __name__ == "__main__":
    main()
