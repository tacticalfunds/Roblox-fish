#!/usr/bin/env python3
"""Customers for every player: the CustomerSystem side of the fast start.

Patches the CustomerSystem Studio runs now - the MeatGlow version
(tools/fish-variants/studio/meat-glow/CustomerSystem.patched.from-sales.lua;
the place inventory's SourceLength, 9985, matches it exactly) - into
studio/board/CustomerSystem.lua. Changes, marked "Economy board":

  * the spawn loop asks EconomyService.customers() for the rate and line
    size: Config.Customers.PerPlayer customers a minute for EACH player in
    the server, up to Config.Customers.Max (about what the Blender Bot can
    carry to the table). Live, one customer came every 10-20 s for the whole
    server (~4 a minute, shared by everyone) - the early game's income limit.
  * the Car Sales upgrades' published values (workspace CustomersPerMin /
    CustomersLineCap) are never lowered (see Sales.customers).
  * without a running EconomyService, or if the call errors, the loop is
    exactly the original (published values, else 10-20 s).

Usage:  python3 tools/economy/build/make_customers.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
BASE = ROOT.parent / "fish-variants" / "studio" / "meat-glow" / "CustomerSystem.patched.from-sales.lua"
OUT = ROOT / "studio" / "board" / "CustomerSystem.lua"


class Patch:
    def __init__(self, src: str):
        self.src = src

    def rep(self, old: str, new: str) -> None:
        n = self.src.count(old)
        assert n == 1, f"expected 1 match, got {n}: {old[:70]!r}"
        self.src = self.src.replace(old, new)


def customers() -> str:
    p = Patch(BASE.read_text())
    p.rep(
        "-- [MeatGlow patch] Changes marked \"MeatGlow\"",
        "-- [Economy board patch] Changes marked \"Economy board\": customers come for\n"
        "-- EACH player in the server (EconomyService.customers(): Config.Customers),\n"
        "-- never slower than the Car Sales upgrades publish. Without EconomyService\n"
        "-- the spawn loop is exactly the original.\n"
        "--\n"
        "-- [MeatGlow patch] Changes marked \"MeatGlow\"",
    )
    p.rep(
        """task.wait(4)
while true do
	-- Customers upgrade (CarSalesServer) publishes rate + line cap on workspace
	local cap = workspace:GetAttribute("CustomersLineCap") or MAX_IN_LINE
	if #Players:GetPlayers() > 0 and #line < cap then
		spawnCustomer()
	end
	local perMin = workspace:GetAttribute("CustomersPerMin")
""",
        """task.wait(4)
while true do
	-- Economy board: a rate for each player (never below Car Sales' values)
	local rate, lineCap = nil, nil
	if Economy and Economy.customers then
		local ok, r, c = pcall(Economy.customers)
		if ok and type(r) == "number" and r > 0 and type(c) == "number" then
			rate, lineCap = r, c
		end
	end
	-- Customers upgrade (CarSalesServer) publishes rate + line cap on workspace
	local cap = lineCap or workspace:GetAttribute("CustomersLineCap") or MAX_IN_LINE
	if #Players:GetPlayers() > 0 and #line < cap then
		spawnCustomer()
	end
	local perMin = rate or workspace:GetAttribute("CustomersPerMin")
""",
    )
    out = p.src
    assert out.count("Economy board") == 3
    return out


def main() -> None:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(customers())
    print(f"wrote {OUT.relative_to(ROOT.parent.parent)}")


if __name__ == "__main__":
    main()
