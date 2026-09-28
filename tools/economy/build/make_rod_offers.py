#!/usr/bin/env python3
"""Generates the rod Buy/Pass slice patches (installable milestone).

  RodFishingSystem: rod-fish offers (base = live, aquarium v1 + Astra's tweaks)
  RodShopServer:    compatibility - charge through EconomyService (base = live)

Every edit is asserted to match exactly once. Output:
tools/economy/studio/rod-offers/.

Usage:  python3 tools/economy/build/make_rod_offers.py
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import make_patches as mp  # noqa: E402

ROOT = mp.ROOT
LIVE = mp.LIVE
OUT = ROOT / "studio" / "rod-offers"


def rod_fishing(src: str) -> str:
    p = mp.Patch(src)
    p.rep(
        "-- ServerStorage.AquariumCycleBackup by the installer.\n",
        "-- ServerStorage.AquariumCycleBackup by the installer.\n"
        + mp.header(
            [
                "Rod-fish offers. While ServerScriptService.EconomyService runs and offers are",
                "on (ReplicatedStorage.Economy.RodOffersEnabled ~= false), each cast needs the",
                "aquarium, and the revealed fish WAITS on the line for its caster (the player",
                "who pressed the button) to Buy it (price shown; charged once, then it goes to",
                "the aquarium) or Pass (it slips back into the water and is gone). Timeout,",
                "the caster leaving, or the aquarium closing also end the offer with no charge.",
                "An unpaid rod fish NEVER goes to the aquarium or the grinder. Offers switched",
                "off (or EconomyService missing) = exactly the aquarium v1 behaviour above.",
            ]
        ),
    )
    p.rep(
        "------------------------------------------------------------ button look / lock\n",
        mp.loader("RodFishingSystem").lstrip("\n")
        + """local function offersOn()
	return Economy ~= nil and Economy.rodOffersEnabled()
end

------------------------------------------------------------ button look / lock
""",
    )
    p.rep(
        """	if Aquarium then
		toTank = Aquarium.hook(rod.key, finalName)
		if not toTank then Aquarium.abort(rod.key) end
	end
""",
        """	if Aquarium then
		-- Economy: the caster's id rides along as fish metadata (kept by aquarium v1.1+ when whitelisted)
		toTank = Aquarium.hook(rod.key, finalName, if rod.offerMode and player then { OwnerId = player.UserId } else nil)
		if not toTank then Aquarium.abort(rod.key) end
	end
""",
    )
    p.rep(
        """	shown:ScaleTo(base)
	task.wait(SHOW_TIME)
""",
        """	shown:ScaleTo(base)

	-- Economy: offer mode - the caster must Buy (-> aquarium) or Pass (-> gone).
	-- The fish is only delivered by a successful purchase; otherwise it drops
	-- back into the water. Never the grinder, never an unpaid aquarium fish.
	if rod.offerMode then
		local bought = false
		if toTank then
			local tpl = swimTemplates:FindFirstChild(finalName)
			bought = Economy.runRodOffer({
				rodKey = rod.key,
				caster = player,
				fishName = finalName,
				tier = tpl and tpl:GetAttribute("Tier") or 1,
				variant = nil,
				fish = shown,
				stillValid = function() return Aquarium ~= nil and Aquarium.active() end,
				reservationOk = function() return Aquarium ~= nil and Aquarium.active() end,
				deliver = function() return Aquarium ~= nil and Aquarium.land(rod.key) end,
			})
		end
		shown:SetAttribute("Spin", false)
		beam:Destroy()
		local fish = shown
		local start = fish:GetPivot()
		if bought then
			-- paid and already counted in the tank: fly it in
			arc(start.Position, Aquarium.entryPoint(), Aquarium.toTankSeconds, Aquarium.toTankHeight, function(p, u)
				fish:PivotTo(CFrame.new(p) * start.Rotation * CFrame.Angles(u * 12, u * 8, 0))
			end)
		else
			if Aquarium then Aquarium.abort(rod.key) end -- frees the reserved tank spot
			-- passed / timed out / cancelled: it slips off the hook into the water and is gone
			arc(start.Position, landing - Vector3.new(0, 1.5, 0), 0.45, 1.5, function(p, u)
				fish:PivotTo(CFrame.new(p) * start.Rotation * CFrame.Angles(u * 6, 0, 0))
			end)
		end
		fish:Destroy()
		bob:Destroy()
		rod.state = "idle"
		return
	end

	task.wait(SHOW_TIME)
""",
    )
    p.rep(
        """		warn("[RodFishingSystem] rod catch failed: " .. tostring(err))
""",
        """		warn("[RodFishingSystem] rod catch failed: " .. tostring(err))
		if Economy then Economy.cancelRodOffer(rod.key) end -- Economy: no charge for a failed catch
""",
    )
    p.rep(
        """	-- AquariumCycle: reserve a tank spot for each rod BEFORE any rod starts;
	-- rods beyond the free spots stay idle
""",
        """	-- Economy: in offer mode every cast needs the aquarium (a bought fish goes there)
	local offerMode = offersOn()
	if offerMode and not (Aquarium and Aquarium.active()) then
		Economy.notify(player, "The aquarium is closed - rod fishing is paused", "warn")
		return
	end
	-- AquariumCycle: reserve a tank spot for each rod BEFORE any rod starts;
	-- rods beyond the free spots stay idle
""",
    )
    p.rep(
        '	for _, rod in ipairs(toCast) do rod.state = "busy" end\n',
        '	for _, rod in ipairs(toCast) do rod.state = "busy" rod.offerMode = offerMode end -- Economy: mode fixed per cast\n',
    )
    return p.src


def check_offer_block(src: str) -> None:
    """Safety guards on the generated offer path."""
    i = src.index("\tif rod.offerMode then\n")
    j = src.index("\ttask.wait(SHOW_TIME)\n", i)
    block = src[i:j]
    assert "fishCaught" not in block, "offer path must never send a fish to the grinder"
    assert block.count("Aquarium.land(") == 1 and "deliver = function() return Aquarium ~= nil and Aquarium.land(rod.key) end" in block, \
        "the only aquarium delivery in offer mode is the paid deliver callback"
    assert "Aquarium.abort(rod.key)" in block, "an unbought fish must free its tank spot"
    assert block.rstrip().endswith("return\n\tend") or "\t\trod.state = \"idle\"\n\t\treturn\n\tend" in block, "offer path must end the task"
    # the free-delivery code below stays reachable only when not in offer mode
    assert src.index("if not Aquarium.land(rod.key) then") > j


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in (("RodFishingSystem", rod_fishing), ("RodShopServer", mp.rodshop)):
        base = (LIVE / f"{name}.lua").read_text()
        out = fn(base)
        assert out != base
        if name == "RodFishingSystem":
            check_offer_block(out)
        (OUT / f"{name}.lua").write_text(out)
        print(f"wrote studio/rod-offers/{name}.lua")


if __name__ == "__main__":
    main()
