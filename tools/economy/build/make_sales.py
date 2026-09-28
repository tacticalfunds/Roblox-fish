#!/usr/bin/env python3
"""Generates the sale-payout milestone patches -> tools/economy/studio/sales/.

  GrinderProcessor, BotSystem, CustomerSystem, TruckSystem, NetLiftScript,
  HarpoonSystem: base = the live sources Astra supplied (studio/live/);
  edits in make_patches.py.
  RodFishingSystem: base = the rod-offers version installed in Studio
  (commit a826d73, read from git); a bought rod fish carries its buyer
  (OwnerId) into the aquarium (needs aquarium v1.2 to keep it).

Every edit is asserted to match exactly once.

Usage:  python3 tools/economy/build/make_sales.py
"""
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import make_patches as mp  # noqa: E402

ROOT = mp.ROOT
LIVE = mp.LIVE
OUT = ROOT / "studio" / "sales"
ROD_BASE_COMMIT = "a826d73"
LIVE_SCRIPTS = ["GrinderProcessor", "BotSystem", "CustomerSystem", "TruckSystem", "NetLiftScript", "HarpoonSystem"]


def rod_base() -> str:
    return subprocess.run(
        ["git", "show", f"{ROD_BASE_COMMIT}:tools/economy/studio/rod-offers/RodFishingSystem.lua"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout


def rod_fishing(src: str) -> str:
    p = mp.Patch(src)
    p.rep(
        "-- aquarium v1 behaviour above.\n",
        "-- aquarium v1 behaviour above.\n"
        "--\n"
        "-- [Economy sales patch] A fish hooked in offer mode carries its caster as\n"
        "-- OwnerId into the aquarium (only the caster can buy it; an unbought fish is\n"
        "-- aborted with its data). Aquarium v1.2 keeps it through tank -> river, so the\n"
        "-- meat of a bought fish pays its buyer whoever nets or harpoons it.\n",
    )
    p.rep(
        "\t\ttoTank = Aquarium.hook(rod.key, finalName)\n",
        "\t\t-- Economy: the buyer rides with the fish (offer mode only: nobody bought a free fish)\n"
        "\t\ttoTank = Aquarium.hook(rod.key, finalName, if rod.offerMode and player then { OwnerId = player.UserId } else nil)\n",
    )
    return p.src


def check_sales(outputs: dict) -> None:
    """Guards on the generated call sites (what the route tests rely on)."""
    g = outputs["GrinderProcessor"]
    assert "Economy.issueFish(info.player, info.fishName, info.tier, info.meta)" in g
    assert "if Economy then Economy.hold(meat:GetAttribute(\"PieceId\")) end" in g, "a full stack holds, never loses, unpaid meat"
    assert "caught.Event:Connect(function(player, fishName, tier, meta)" in g
    b = outputs["BotSystem"]
    assert b.index("Economy.readPiece(meat)") < b.index("meat:Destroy()") < b.index("Economy.writePiece(c, tags)")
    c = outputs["CustomerSystem"]
    assert c.index('Economy.settle(meat:GetAttribute("PieceId"), "Customer")') < c.index("giveMeat(c, meat)\n\t\t\tbought:Fire")
    t = outputs["TruckSystem"]
    assert t.count("Economy.settle(") == 1 and t.count("dropCarried(") == 3
    assert "for _, p in ipairs(Players:GetPlayers()) do bindPlayer(p) end" in t, "players already present are bound"
    cs = outputs["CustomerSystem"]
    assert 'workspace:GetAttribute("CustomersLineCap")' in cs and 'workspace:GetAttribute("CustomersPerMin")' in cs, \
        "CarSalesServer customer-upgrade hooks kept"
    for attr in ("CarsMaxQueue", "CarsUnlocked", "CarsGapSeconds"):
        assert f'workspace:GetAttribute("{attr}")' in t, "Car Sales unlock / max line / speed hooks kept: " + attr
    n = outputs["NetLiftScript"]
    assert 'OwnerId = m:GetAttribute("OwnerId")' in n and 'Source = "Net"' in n
    h = outputs["HarpoonSystem"]
    assert "fishCaught:Fire(nil, fish.Name, fish:GetAttribute(\"Tier\") or 1, harpoonMeta(fish))" in h
    assert 'gunModel:GetAttribute("OwnerUserId")' in h
    r = outputs["RodFishingSystem"]
    assert "{ OwnerId = player.UserId } else nil)" in r and r.count("Aquarium.hook(") == 1
    # nothing in the payout path writes Money directly
    for name, src in outputs.items():
        assert "leaderstats" not in src or name == "RodFishingSystem", name


def build() -> dict:
    outputs = {}
    for name in LIVE_SCRIPTS:
        base = (LIVE / f"{name}.lua").read_text()
        outputs[name] = mp.BUILDERS[name](base)
        assert outputs[name] != base
    outputs["RodFishingSystem"] = rod_fishing(rod_base())
    check_sales(outputs)
    return outputs


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, src in build().items():
        (OUT / f"{name}.lua").write_text(src)
        print(f"wrote studio/sales/{name}.lua")


if __name__ == "__main__":
    main()
