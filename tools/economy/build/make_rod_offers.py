#!/usr/bin/env python3
"""Generates the rod-fish buying slice patches (installable milestone).

  RodFishingSystem: rod-fish offers, bought at the rod stand (base = live, aquarium v1 + Astra's tweaks)
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
                "Rod-fish offers. While offers are configured (ReplicatedStorage.Economy exists",
                "and its RodOffersEnabled attribute is not false), each cast needs the money",
                "service AND the aquarium, and the revealed fish WAITS on the line for its",
                "caster (the player who pressed the button) to walk up to that rod's stand and",
                "Buy it with the proximity prompt (price shown; charged once, then it goes to",
                "the aquarium). Otherwise it slips back into the water and is gone: timeout,",
                "the caster dying or leaving, or the aquarium closing end the offer with no",
                "charge. An unpaid rod fish NEVER goes to the aquarium or the grinder.",
                "Configured but EconomyService not running = FAIL CLOSED (no cast, notice).",
                "Only RodOffersEnabled = false or uninstalling (no Economy folder) restores the",
                "aquarium v1 behaviour above.",
            ]
        ),
    )
    p.rep(
        """local function pickFish()
	local r = math.random() * total
	for _, e in ipairs(pool) do r -= e.w if r <= 0 then return e.name end end
	return pool[1].name
end
""",
        """local function pickFish()
	local r = math.random() * total
	for _, e in ipairs(pool) do r -= e.w if r <= 0 then return e.name end end
	return pool[1].name
end
-- Economy: a fish's real roll chance on the rods (the same weights pickFish uses)
local function rodChance(name)
	if total <= 0 then return nil end
	local w = 0
	for _, e in ipairs(pool) do if e.name == name then w += e.w end end
	return w / total
end
""",
    )
    p.rep(
        "\t\tlocal best, bp, bpart = -math.huge, nil, nil\n",
        "\t\tlocal best, bp, bpart = -math.huge, nil, nil\n"
        "\t\tlocal low, stand = math.huge, nil -- Economy: rod stand = lowest corner (buy prompt)\n",
    )
    p.rep(
        "\t\t\t\t\tif c.Y > best then best, bp, bpart = c.Y, c, p end\n",
        "\t\t\t\t\tif c.Y > best then best, bp, bpart = c.Y, c, p end\n"
        "\t\t\t\t\tif c.Y < low then low, stand = c.Y, c end\n",
    )
    p.rep(
        '\t\ttable.insert(rods, { model = m, tip = bp, tipAtt = att, state = "idle" })\n',
        '\t\ttable.insert(rods, { model = m, tip = bp, tipAtt = att, state = "idle", stand = stand })\n',
    )
    p.rep(
        "------------------------------------------------------------ button look / lock\n",
        mp.loader("RodFishingSystem").lstrip("\n")
        + """-- Economy: offers are CONFIGURED while ReplicatedStorage.Economy exists and
-- its RodOffersEnabled attribute is not false (checked at every press).
local function offersConfigured()
	local root = RS:FindFirstChild("Economy")
	return root ~= nil and root:GetAttribute("RodOffersEnabled") ~= false
end
-- works even when EconomyService itself failed to start
local function economyNotice(player, text)
	local root = RS:FindFirstChild("Economy")
	local n = root and root:FindFirstChild("Notice")
	if n and n:IsA("RemoteEvent") and player and player.Parent then n:FireClient(player, text, "warn") end
end

------------------------------------------------------------ button look / lock
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
				chance = rodChance(finalName),
				fish = shown,
				stand = rod.stand,
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
        """	-- Economy: in offer mode every cast needs the money service and the
	-- aquarium (a bought fish goes there). Fail closed: no cast without them.
	local offerMode = offersConfigured()
	if offerMode and not (Economy and Economy.running()) then
		economyNotice(player, "Fish buying is unavailable right now - rod fishing is paused")
		return
	end
	if offerMode and not (Aquarium and Aquarium.active()) then
		economyNotice(player, "The aquarium is closed - rod fishing is paused")
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
    assert "Aquarium.hook(rod.key, finalName)\n" in src, "live v1 hook call left unchanged (v1 would discard metadata)"
    press = src[src.index("local function press(player)"):]
    assert press.index("offersConfigured()") < press.index("Economy.running()") < press.index("Aquarium.reserve("), \
        "fail closed before any reservation when offers are configured but the service is down"
    assert "chance = rodChance(finalName)," in block and "stand = rod.stand," in block
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
