#!/usr/bin/env python3
"""Aquarium panel: the server side.

Patches the INSTALLED aquarium v1.2 AquariumCycleServer (read from git at the
sales release 91121de, which UpgradeAquariumV12 installed) so its prompts
draw no default UI; tools/aquarium-panel/src/AquariumPanelClient draws one
compact panel instead. Changes, all marked "AquariumPanel":

  * every aquarium ProximityPrompt is Style = Custom (no stacked default
    panels) and is published to clients as ReplicatedStorage.AquariumCycle
    .<Id>Prompt (ObjectValue, removed on stop). Triggers still go through
    the prompt's own Triggered, with the same server checks (alive, in
    range, cooldown); the client never decides a charge.
  * Release Fish: E / ButtonX. The two upgrade prompts (F / ButtonY; the
    client enables the one its card shows) exist ONLY when a currency
    binding exists (ServerScriptService.AquariumEconomy returns one). Without
    it (today: paid upgrades not installed) there is nothing to trigger.
  * attributes for the panel: UpgradesAvailable, CapacityLevel,
    ReleaseRateLevel (next to TankCount / TankCapacity / TankFull)
  * the placeholder prompt bound as CountPrompt, and any BillboardGui next
    to it, stay hidden while the aquarium runs (restored on stop) even when
    the count UI isn't bound to it. The binding itself is untouched.

Usage:  python3 tools/aquarium-panel/build/make_panel.py
"""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = ROOT.parent.parent
OUT = ROOT / "studio" / "AquariumCycleServer.patched.from-v12.lua"
SALES_RELEASE = "91121de"


def v12_server() -> str:
    return subprocess.run(
        ["git", "show", f"{SALES_RELEASE}:tools/aquarium-cycle/src/server/AquariumCycleServer.luau"],
        cwd=REPO, capture_output=True, text=True, check=True,
    ).stdout


class Patch:
    def __init__(self, base: str):
        self.src = base

    def rep(self, old: str, new: str) -> None:
        n = self.src.count(old)
        assert n == 1, f"expected 1 match, got {n}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


def build() -> str:
    p = Patch(v12_server())
    p.rep(
        "-- place. It never grants currency.\n",
        "-- place. It never grants currency.\n"
        "--\n"
        "-- [AquariumPanel patch v1] Changes marked \"AquariumPanel\": the prompts are\n"
        "-- Style = Custom and published as ReplicatedStorage.AquariumCycle.<Id>Prompt\n"
        "-- for StarterPlayerScripts.AquariumPanelClient, which draws one compact\n"
        "-- panel (Release Fish + one upgrade card at a time). Upgrade prompts exist\n"
        "-- only while a currency binding exists. Server checks are unchanged.\n",
    )
    # hide the placeholder prompt (and its sibling billboard) even when the
    # count UI can't bind to it
    p.rep(
        "-- Own billboard when the placeholder UI isn't bound.\n",
        "-- AquariumPanel: the placeholder prompt bound as CountPrompt (\"E / NEW CAR\")\n"
        "-- and any BillboardGui beside it stay hidden while the aquarium runs, even\n"
        "-- when the count UI couldn't bind to it. Restored on stop.\n"
        "local function hidePlaceholder(prompt: Instance?)\n"
        "\tif not (scene.HidePlaceholderPrompt and prompt and prompt:IsA(\"ProximityPrompt\")) then\n"
        "\t\treturn\n"
        "\tend\n"
        "\tlocal hidden = { prompt }\n"
        "\tfor _, sibling in ipairs(prompt.Parent and prompt.Parent:GetChildren() or {}) do\n"
        "\t\tif sibling:IsA(\"BillboardGui\") then\n"
        "\t\t\ttable.insert(hidden, sibling)\n"
        "\t\tend\n"
        "\tend\n"
        "\tfor _, inst in ipairs(hidden) do\n"
        "\t\tlocal target: any = inst\n"
        "\t\tlocal was = target.Enabled\n"
        "\t\ttable.insert(restore, function()\n"
        "\t\t\ttarget.Enabled = was\n"
        "\t\tend)\n"
        "\t\ttarget.Enabled = false\n"
        "\tend\n"
        "end\n"
        "\n"
        "-- Own billboard when the placeholder UI isn't bound.\n",
    )
    p.rep(
        '\troot:SetAttribute("TankFull", info.full)\nend\n',
        '\troot:SetAttribute("TankFull", info.full)\n'
        "\t-- AquariumPanel: the panel's upgrade card reads these\n"
        '\troot:SetAttribute("CapacityLevel", info.levels.Capacity)\n'
        '\troot:SetAttribute("ReleaseRateLevel", info.levels.ReleaseRate)\n'
        "end\n",
    )
    p.rep(
        "local function makePrompt(parent: Instance, id: string, key: Enum.KeyCode, pad: Enum.KeyCode, offsetY: number)\n"
        "\tlocal prompt = own(Instance.new(\"ProximityPrompt\"))\n"
        "\tprompt.Name = \"Aquarium\" .. id\n",
        "local function makePrompt(parent: Instance, id: string, key: Enum.KeyCode, pad: Enum.KeyCode)\n"
        "\tlocal prompt = own(Instance.new(\"ProximityPrompt\"))\n"
        "\tprompt.Name = \"Aquarium\" .. id\n"
        "\t-- AquariumPanel: no default prompt UI; AquariumPanelClient draws the panel\n"
        "\tprompt.Style = Enum.ProximityPromptStyle.Custom\n",
    )
    p.rep(
        "\tprompt.UIOffset = Vector2.new(0, offsetY)\n",
        "",
    )
    p.rep(
        "\tprompt.Parent = parent\n\tprompts[id] = prompt\n",
        "\tprompt.Parent = parent\n"
        "\tprompts[id] = prompt\n"
        "\t-- AquariumPanel: where the client finds it (removed on stop)\n"
        "\tlocal ref = own(Instance.new(\"ObjectValue\"))\n"
        "\tref.Name = id .. \"Prompt\"\n"
        "\tref.Value = prompt\n"
        "\tref.Parent = root\n",
    )
    p.rep(
        "\tcountUi = bindCountUi(countPrompt)\n"
        "\tif not countUi then\n"
        "\t\tcountUi = makeCountUi()\n"
        "\tend\n",
        "\tcountUi = bindCountUi(countPrompt)\n"
        "\tif not countUi then\n"
        "\t\tcountUi = makeCountUi()\n"
        "\t\thidePlaceholder(countPrompt) -- AquariumPanel\n"
        "\tend\n",
    )
    p.rep(
        '\tmakePrompt(promptParent, "Release", Enum.KeyCode.E, Enum.KeyCode.ButtonX, 0)\n'
        '\tmakePrompt(promptParent, "Capacity", Enum.KeyCode.F, Enum.KeyCode.ButtonY, 80)\n'
        '\tmakePrompt(promptParent, "ReleaseRate", Enum.KeyCode.G, Enum.KeyCode.ButtonB, 160)\n',
        '\tmakePrompt(promptParent, "Release", Enum.KeyCode.E, Enum.KeyCode.ButtonX)\n'
        "\t-- AquariumPanel: upgrades can only be bought through a currency binding.\n"
        "\t-- Without one there is no upgrade prompt at all (the panel says so); with\n"
        "\t-- one, both share F / ButtonY and the client enables the card it shows.\n"
        "\tif economy then\n"
        '\t\tmakePrompt(promptParent, "Capacity", Enum.KeyCode.F, Enum.KeyCode.ButtonY)\n'
        '\t\tmakePrompt(promptParent, "ReleaseRate", Enum.KeyCode.F, Enum.KeyCode.ButtonY)\n'
        "\tend\n"
        '\troot:SetAttribute("UpgradesAvailable", economy ~= nil)\n',
    )
    p.rep(
        '\troot:SetAttribute("TankFull", nil)\n\tprint("[AquariumCycle] stopped; catches go to the grinder")\n',
        '\troot:SetAttribute("TankFull", nil)\n'
        "\t-- AquariumPanel\n"
        '\troot:SetAttribute("UpgradesAvailable", nil)\n'
        '\troot:SetAttribute("CapacityLevel", nil)\n'
        '\troot:SetAttribute("ReleaseRateLevel", nil)\n'
        '\tprint("[AquariumCycle] stopped; catches go to the grinder")\n',
    )
    out = p.src
    # guards: what must (not) be in the patched server
    assert "UIOffset" not in out and "Enum.KeyCode.G" not in out and "ButtonB" not in out
    assert out.count("Enum.ProximityPromptStyle.Custom") == 1  # in makePrompt: every prompt
    assert "tryCharge" in out and "validPlayer(player, prompts[upgradeId])" in out  # server checks unchanged
    # v1.2's harpoon-safe river despawn and metadata passthrough are untouched
    assert 'not model:GetAttribute("HarpoonT")' in out and "setMeta(model, meta)" in out
    return out


def main() -> None:
    OUT.write_text(build())
    print(f"wrote {OUT.relative_to(REPO)}")


if __name__ == "__main__":
    main()
