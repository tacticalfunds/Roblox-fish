#!/usr/bin/env python3
"""Regenerates the grinder-dwell patches for every base that can be live.

  FishSwimClient:   fish-jump patched (latest) | original
  NetLiftScript:    fish-variants patched (latest) | original
  RodFishingSystem: rod-cast (from variants) (latest) | rod-cast (from aquarium)
                    | fish-variants patched | aquarium patched
All edits are asserted to match exactly once in each base.

Usage:  python3 tools/grinder-dwell/build/make_patches.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
TOOLS = ROOT.parent
OUT = ROOT / "studio"

BASES = {
    "FishSwimClient": {
        "jump": TOOLS / "fish-jump" / "studio" / "FishSwimClient.patched.lua",
        "original": TOOLS / "fish-jump" / "studio" / "FishSwimClient.original.lua",
    },
    "NetLiftScript": {
        "variants": TOOLS / "fish-variants" / "studio" / "NetLiftScript.patched.lua",
        "original": TOOLS / "fish-variants" / "studio" / "NetLiftScript.original.lua",
    },
    "RodFishingSystem": {
        "rodcast-variants": TOOLS / "rod-cast" / "studio" / "RodFishingSystem.patched.from-variants.lua",
        "rodcast-aquarium": TOOLS / "rod-cast" / "studio" / "RodFishingSystem.patched.from-aquarium.lua",
        "variants": TOOLS / "fish-variants" / "studio" / "RodFishingSystem.patched.lua",
        "aquarium": TOOLS / "aquarium-cycle" / "studio" / "RodFishingSystem.patched.lua",
    },
}

LOAD = """
-- GrinderDwell: optional ~1 s tumble on the rollers before the pull-in
-- (missing module -> original timing)
local Dwell = nil
do
	local mod = game:GetService("ReplicatedStorage"):FindFirstChild("GrinderDwell")
	if mod and mod:IsA("ModuleScript") then
		local ok, m = pcall(require, mod)
		if ok and type(m) == "table" then
			Dwell = m
		else
			warn("[GrinderDwell] failed to load, using original timing: " .. tostring(m))
		end
	end
end
"""


class Patch:
    def __init__(self, base: str):
        self.src = base

    def rep(self, old: str, new: str) -> None:
        count = self.src.count(old)
        assert count == 1, f"expected 1 match, got {count}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


def swim_client(base: str) -> str:
    p = Patch(base)
    p.rep(
        "-- Fish that get a CaughtT attribute (set by the net) are launched in an arc into the grinder.\n",
        "-- Fish that get a CaughtT attribute (set by the net) are launched in an arc into the grinder.\n"
        "--\n"
        "-- [GrinderDwell patch v1] Changes marked \"GrinderDwell\": with\n"
        "-- ReplicatedStorage.GrinderDwell installed, a launched fish lands on the\n"
        "-- rollers, tumbles/shudders there for about a second, then spirals in and\n"
        "-- shrinks. The timeline comes from that module (NetLiftScript uses the same\n"
        "-- numbers). Without it the launch is exactly the original.\n",
    )
    p.rep(
        "local LAUNCH_RISE, LAUNCH_FLY, LAUNCH_DROP = 0.12, 0.95, 0.55\n",
        "local LAUNCH_RISE, LAUNCH_FLY, LAUNCH_DROP = 0.12, 0.95, 0.55\n"
        + LOAD
        + "if Dwell then LAUNCH_RISE, LAUNCH_FLY, LAUNCH_DROP = Dwell.Rise, Dwell.Fly, Dwell.Drop end\n"
        "local DWELL = if Dwell then Dwell.Dwell else 0\n"
        "local TUMBLE = if Dwell then Dwell.TumbleSpeed else 0\n",
    )
    p.rep(
        "\t\t\telse\n"
        "\t\t\t\t-- SUCKED IN: spiral down into the rollers while spinning and shrinking\n"
        "\t\t\t\tlocal u = math.clamp((lt - LAUNCH_RISE - LAUNCH_FLY) / LAUNCH_DROP, 0, 1)\n"
        "\t\t\t\tlocal e = u * u\n"
        "\t\t\t\tlocal r = 1.2 * (1 - u)\n"
        "\t\t\t\tlocal a = u * math.pi * 5\n"
        "\t\t\t\tpos = grinder + Vector3.new(math.cos(a) * r, -3.2 * e, math.sin(a) * r)\n"
        "\t\t\t\tf.suck = 1 - 0.92 * e\n"
        "\t\t\tend\n",
        "\t\t\telseif lt < LAUNCH_RISE + LAUNCH_FLY + DWELL then\n"
        "\t\t\t\t-- GrinderDwell: settle onto the rollers, tumble and shudder there\n"
        "\t\t\t\tlocal ox, oy, oz = Dwell.dwellOffset(lt - LAUNCH_RISE - LAUNCH_FLY, f.phase)\n"
        "\t\t\t\tpos = grinder + Vector3.new(ox, oy, oz)\n"
        "\t\t\telseif Dwell then\n"
        "\t\t\t\t-- GrinderDwell: spiral in from the rollers while shrinking\n"
        "\t\t\t\tlocal ox, oy, oz, scale = Dwell.dropOffset((lt - LAUNCH_RISE - LAUNCH_FLY - DWELL) / LAUNCH_DROP)\n"
        "\t\t\t\tpos = grinder + Vector3.new(ox, oy, oz)\n"
        "\t\t\t\tf.suck = scale\n"
        "\t\t\telse\n"
        "\t\t\t\t-- SUCKED IN: spiral down into the rollers while spinning and shrinking\n"
        "\t\t\t\tlocal u = math.clamp((lt - LAUNCH_RISE - LAUNCH_FLY) / LAUNCH_DROP, 0, 1)\n"
        "\t\t\t\tlocal e = u * u\n"
        "\t\t\t\tlocal r = 1.2 * (1 - u)\n"
        "\t\t\t\tlocal a = u * math.pi * 5\n"
        "\t\t\t\tpos = grinder + Vector3.new(math.cos(a) * r, -3.2 * e, math.sin(a) * r)\n"
        "\t\t\t\tf.suck = 1 - 0.92 * e\n"
        "\t\t\tend\n",
    )
    p.rep(
        "\t\t\t\tlocal u = math.clamp((lt - LAUNCH_RISE - LAUNCH_FLY) / LAUNCH_DROP, 0, 1)\n"
        "\t\t\t\tlocal flightEnd = startRot * CFrame.fromAxisAngle(f.spinAxis, LAUNCH_FLY * 11)\n",
        "\t\t\t\tlocal u = math.clamp((lt - LAUNCH_RISE - LAUNCH_FLY - DWELL) / LAUNCH_DROP, 0, 1) -- GrinderDwell\n"
        "\t\t\t\tlocal flightEnd = startRot * CFrame.fromAxisAngle(f.spinAxis, LAUNCH_FLY * 11 + DWELL * TUMBLE)\n",
    )
    p.rep(
        "\t\t\t\trot = startRot * CFrame.fromAxisAngle(f.spinAxis, math.max(0, lt - LAUNCH_RISE) * 11)\n",
        "\t\t\t\t-- GrinderDwell: fast spin in flight, slower tumble on the rollers\n"
        "\t\t\t\tlocal flight = math.min(math.max(0, lt - LAUNCH_RISE), LAUNCH_FLY)\n"
        "\t\t\t\tlocal tumble = math.max(0, lt - LAUNCH_RISE - LAUNCH_FLY)\n"
        "\t\t\t\trot = startRot * CFrame.fromAxisAngle(f.spinAxis, flight * 11 + tumble * TUMBLE)\n",
    )
    return p.src


def net_lift(base: str) -> str:
    p = Patch(base)
    p.rep(
        "-- Server: handles the step pad. The net animation + splash runs on each client (NetLiftClient).\n",
        "-- Server: handles the step pad. The net animation + splash runs on each client (NetLiftClient).\n"
        "--\n"
        "-- [GrinderDwell patch v1] Each caught fish is destroyed and FishCaught fires\n"
        "-- once, when the client launch (now with ~1 s on the rollers) has finished:\n"
        "-- GrinderDwell.serverDelay() instead of 1.65 s. Payload and rewards unchanged.\n",
    )
    p.rep(
        "local caughtEvent = model:FindFirstChild(\"FishCaught\") or Instance.new(\"BindableEvent\")\n",
        LOAD.lstrip("\n")
        + "local CATCH_DELAY = if Dwell then Dwell.serverDelay() else 1.65 -- GrinderDwell\n"
        "local caughtEvent = model:FindFirstChild(\"FishCaught\") or Instance.new(\"BindableEvent\")\n",
    )
    p.rep("\t\t\t\ttask.delay(1.65, function()\n", "\t\t\t\ttask.delay(CATCH_DELAY, function() -- GrinderDwell\n")
    return p.src


def rod_system(base: str) -> str:
    p = Patch(base)
    p.rep(
        "-- ServerStorage.AquariumCycleBackup by the installer.\n",
        "-- ServerStorage.AquariumCycleBackup by the installer.\n"
        "--\n"
        "-- [GrinderDwell patch v1] When a rod catch goes to the grinder (aquarium off\n"
        "-- or refusing), the fish also rests on the rollers ~1 s, then spirals in and\n"
        "-- shrinks, before FishCaught fires once. Aquarium routing is unchanged.\n",
    )
    p.rep(
        "------------------------------------------------------------ aquarium (AquariumCycle)\n",
        LOAD.lstrip("\n") + "\n------------------------------------------------------------ aquarium (AquariumCycle)\n",
    )
    old = (
        "\t\tarc(start.Position, grinderPos, 1.1, 10, function(p, u)\n"
        "\t\t\tfish:PivotTo(CFrame.new(p) * start.Rotation * CFrame.Angles(u * 12, u * 8, 0))\n"
        "\t\tend)\n"
        "\t\tfish:Destroy()\n"
    )
    p.rep(
        old,
        "\t\tarc(start.Position, grinderPos, 1.1, 10, function(p, u)\n"
        "\t\t\tfish:PivotTo(CFrame.new(p) * start.Rotation * CFrame.Angles(u * 12, u * 8, 0))\n"
        "\t\tend)\n"
        "\t\t-- GrinderDwell: rest and tumble on the rollers, then spiral in and shrink\n"
        "\t\tif Dwell and fish.Parent then\n"
        "\t\t\tlocal rot0 = start.Rotation * CFrame.Angles(12, 8, 0)\n"
        "\t\t\tlocal baseScale = fish:GetScale()\n"
        "\t\t\tlocal t = 0\n"
        "\t\t\twhile t < Dwell.Dwell + Dwell.Drop and fish.Parent do\n"
        "\t\t\t\tt += RunService.Heartbeat:Wait()\n"
        "\t\t\t\tif t < Dwell.Dwell then\n"
        "\t\t\t\t\tlocal ox, oy, oz = Dwell.dwellOffset(t, rod.key)\n"
        "\t\t\t\t\tfish:PivotTo(CFrame.new(grinderPos + Vector3.new(ox, oy, oz)) * rot0 * CFrame.Angles(t * Dwell.TumbleSpeed, 0, 0))\n"
        "\t\t\t\telse\n"
        "\t\t\t\t\tlocal u = math.min(1, (t - Dwell.Dwell) / Dwell.Drop)\n"
        "\t\t\t\t\tlocal ox, oy, oz, scale = Dwell.dropOffset(u)\n"
        "\t\t\t\t\tfish:PivotTo(CFrame.new(grinderPos + Vector3.new(ox, oy, oz)) * rot0\n"
        "\t\t\t\t\t\t* CFrame.Angles(Dwell.Dwell * Dwell.TumbleSpeed, u * math.pi * 6, 0))\n"
        "\t\t\t\t\tfish:ScaleTo(baseScale * scale)\n"
        "\t\t\t\tend\n"
        "\t\t\tend\n"
        "\t\tend\n"
        "\t\tfish:Destroy()\n",
    )
    return p.src


BUILDERS = {"FishSwimClient": swim_client, "NetLiftScript": net_lift, "RodFishingSystem": rod_system}


def main() -> None:
    OUT.mkdir(exist_ok=True)
    for name, bases in BASES.items():
        for label, path in bases.items():
            out = OUT / f"{name}.patched.from-{label}.lua"
            out.write_text(BUILDERS[name](path.read_text()))
            print(f"wrote {out.relative_to(TOOLS.parent)}")


if __name__ == "__main__":
    main()
