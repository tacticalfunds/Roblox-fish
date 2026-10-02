--!strict
-- Sales: issuing a caught fish's pieces and settling one sale. Pure glue
-- between the Ledger and a `pay` callback, so the offline tests run the
-- exact logic EconomyService uses.

local Ledger = require(script.Parent.Ledger)
local PieceTags = require(script.Parent.PieceTags)

local Sales = {}

-- A fish enters the grinder. `playerUserId` is the net-pad player (nil for
-- the harpoon); `meta` the catch payload { OwnerId, Variant, Source }.
-- `multiplierFor(ownerId)` (optional) is the owner's Meat Price right now:
-- the whole fish's value is multiplied by it once, before the split.
function Sales.issue(
	ledger: Ledger.Ledger,
	playerUserId: number?,
	fishName: any,
	tier: any,
	meta: any,
	multiplierFor: ((ownerId: number) -> number)?
): { string }
	local ownerId = PieceTags.ownerFor(playerUserId, meta)
	local multiplier = nil
	if ownerId and multiplierFor then
		local ok, m = pcall(multiplierFor, ownerId)
		multiplier = if ok then m else nil
	end
	return ledger:issueFish({
		ownerId = ownerId,
		tier = tier,
		variant = PieceTags.variantFrom(meta),
		fishName = fishName,
		source = PieceTags.sourceFrom(meta, playerUserId ~= nil),
		multiplier = multiplier,
	})
end

-- The one sale of a piece. `pay(ownerId, amount)` returns the credit result
-- ("paid" | "pending" | "absent" | "dropped"). Returns (paid, amount, piece).
-- Unknown, already-settled or held ids pay nothing and call nothing.
function Sales.settle(
	ledger: Ledger.Ledger,
	pieceId: any,
	pay: (ownerId: number, amount: number) -> string
): (boolean, number, Ledger.Piece?)
	local piece = ledger:settle(pieceId)
	if not piece then
		return false, 0, nil
	end
	local paid = false
	if piece.ownerId then
		local r = pay(piece.ownerId, piece.value)
		paid = r == "paid" or r == "pending"
	end
	ledger:notePaid(paid)
	return paid, if paid then piece.value else 0, piece
end

-- The customers' rate (a minute) and line size for `players` players in the
-- server. `cfg` is Config.Customers ({ PerPlayer, Max, LineCap }); the Car
-- Sales upgrades' published values (`publishedRate` = workspace
-- CustomersPerMin, `publishedCap` = CustomersLineCap; anything not a positive
-- number is ignored) are never lowered.
function Sales.customers(players: any, publishedRate: any, publishedCap: any, cfg: any): (number, number)
	local function positive(v: any): number
		return if type(v) == "number" and v == v and v > 0 and v < math.huge then v else 0
	end
	local n = math.max(1, math.floor(positive(players)))
	local rate = positive(publishedRate)
	local perPlayer = math.max(cfg.PerPlayer, rate)
	local perMin = math.min(perPlayer * n, math.max(cfg.Max, rate))
	local cap = math.max(cfg.LineCap, math.floor(positive(publishedCap)))
	return perMin, cap
end

return Sales
