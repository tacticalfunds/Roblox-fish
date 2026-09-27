#!/usr/bin/env python3
"""Runs the REAL patched press() + PressFishButton handler code under the Luau
CLI against small stubs, to check rapid presses can't double-cast.

The two functions are sliced verbatim out of the generated patched
RodFishingSystem (both supported bases) and dropped into a harness that
stubs only what they touch: rods, ready/setReady, the aquarium reservation,
safeRunRod (a coroutine that stays "casting" until the test finishes it),
task.spawn, os.clock, the button and the remote.

Usage:  python3 tools/rod-cast/tests/run_press_sim.py [path/to/luau]
Pure-logic simulation only; not a Roblox runtime test.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def slice_between(text: str, start: str, end: str) -> str:
    i = text.index(start)
    j = text.index(end, i)
    return text[i : j + len(end)]


HARNESS = r"""
local failures, passes = 0, 0
local function check(name, cond)
	if cond then passes += 1 else failures += 1 print("FAIL: " .. name) end
end

-- scheduler: task.spawn runs a coroutine until its first yield
local task = { spawn = function(fn, ...) local co = coroutine.create(fn) assert(coroutine.resume(co, ...)) end }
local clockNow = 0
local os = { clock = function() return clockNow end }
local workspace = { GetServerTimeNow = function() return 1.7e9 + clockNow end }
local Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z, sub = true } end }

-- world
local rods, active, casts, maxActive = {}, {}, 0, 0
for i = 1, 5 do rods[i] = { key = i, state = "idle", model = {} } end
local ready = true
local function setReady(v) ready = v end
local function anyIdle()
	for _, r in ipairs(rods) do if r.state == "idle" then return true end end
	return false
end

-- safeRunRod stub: stays casting until finish(rod)
local waiting = {}
local function safeRunRod(rod, player)
	active[rod] = (active[rod] or 0) + 1
	casts += 1
	if active[rod] > maxActive then maxActive = active[rod] end
	waiting[rod] = coroutine.running()
	coroutine.yield()
	active[rod] -= 1
	rod.state = "idle"
end
local function finish(rod)
	local co = waiting[rod]
	waiting[rod] = nil
	assert(coroutine.resume(co))
end

-- aquarium stub with a shared capacity
local capacity, reservedCount = 5, 0
local notified = 0
local Aquarium = {
	active = function() return true end,
	hasFreeSpot = function(p) if reservedCount < capacity then return true end notified += 1 return false end,
	reserve = function(list, p)
		local out = {}
		for _, rod in ipairs(list) do
			if reservedCount < capacity then reservedCount += 1 table.insert(out, rod) end
		end
		if #out == 0 then notified += 1 end
		return out
	end,
}

-- button + remote
local pressedAt = 0
local button = { SetAttribute = function(_, k, v) if k == "PressedAt" then pressedAt += 1 end end }
local btnModel = { GetPivot = function() return { Position = { X = 0, Y = 0, Z = 0 } } end }
local handler
local RS = { WaitForChild = function(_, name)
	return { OnServerEvent = { Connect = function(_, fn) handler = fn end } }
end }
local Players = { PlayerRemoving = { Connect = function() end } }

local function newPlayer()
	local hrp = { Position = { X = 1, Y = 0, Z = 0 } }
	setmetatable(hrp.Position, { __sub = function(a, b) return { Magnitude = math.abs(a.X - b.X) } end })
	return { Character = { FindFirstChild = function(_, n) return if n == "HumanoidRootPart" then hrp else nil end } }
end

----------------------------------------------------------------- code under test
--[[PRESS]]
--[[HANDLER]]
----------------------------------------------------------------- scenarios

local function busyCount() local n = 0 for _, r in ipairs(rods) do if r.state ~= "idle" then n += 1 end end return n end
local function releaseAll()
	for _, r in ipairs(rods) do if waiting[r] then finish(r) reservedCount -= 1 end end
	clockNow += 5
end

local a, b = newPlayer(), newPlayer()

-- 1) one press casts every eligible rod at once, button animates once
handler(a)
check("all 5 rods cast immediately", casts == 5 and busyCount() == 5)
check("button animated once", pressedAt == 1)
check("button locked", ready == false)

-- 2) rapid presses from two players in the same instant: no duplicates
handler(a) handler(b) handler(b)
check("no duplicate casts from rapid presses", casts == 5 and maxActive == 1)
check("rejected presses don't animate", pressedAt == 1)
releaseAll()

-- 3) same player spamming inside the 0.6 s cooldown is ignored
local before = casts
handler(a)
clockNow += 0.1
handler(a)
check("cooldown spam ignored", casts == before + 5 and maxActive == 1)
releaseAll()

-- 4) full tank: no cast, no animation, player told
capacity = 0
local c0, p0, n0 = casts, pressedAt, notified
clockNow += 1
handler(a)
check("full tank starts nothing", casts == c0 and pressedAt == p0 and notified == n0 + 1)
check("button stays ready when rejected", ready == true)

-- 5) partial capacity: only reserved rods cast, the rest stay idle
capacity = 3
clockNow += 1
handler(b)
check("only 3 rods cast", casts == c0 + 3 and busyCount() == 3)

-- 6) a rod coming back unlocks the button; the next press casts only idle rods
for _, r in ipairs(rods) do if waiting[r] then finish(r) reservedCount -= 1 ready = true break end end
capacity = 5
clockNow += 1
handler(a)
check("second press casts only idle rods", busyCount() == 5 and maxActive == 1)
releaseAll()

-- 7) reservation race (spot taken between check and press): nothing starts
capacity = 5
local realReserve = Aquarium.reserve
Aquarium.reserve = function(list, p) notified += 1 return {} end
local c7, p7 = casts, pressedAt
clockNow += 1
handler(b)
check("race-lost press starts nothing", casts == c7 and pressedAt == p7 and ready == true)
Aquarium.reserve = realReserve

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then error("press simulation failed") end
"""


def main() -> int:
    luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
    failed = 0
    for base in ("variants", "aquarium"):
        src = (ROOT / "studio" / f"RodFishingSystem.patched.from-{base}.lua").read_text()
        press = slice_between(src, "local function press(player)", "\n\treturn true\nend\n")
        handler = slice_between(src, "local COOLDOWN = 0.6", "\nend)\n")
        assert "task.wait" not in press and "task.delay" not in press, "press() must not yield"
        assert "task.wait" not in handler and "task.delay" not in handler, "handler must not yield"
        text = HARNESS.replace("--[[PRESS]]", press).replace("--[[HANDLER]]", handler)
        with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as f:
            f.write(text)
            path = f.name
        print(f"== press simulation, base: {base}")
        if subprocess.run([luau, path]).returncode != 0:
            failed += 1
        pathlib.Path(path).unlink()
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
