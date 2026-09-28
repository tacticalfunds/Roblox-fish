--!strict
-- Sales: issuing a caught fish's pieces and settling one sale. Pure glue
-- between the Ledger and a `pay` callback, so the offline tests run the
-- exact logic EconomyService uses.

local Ledger = require(script.Parent.Ledger)
local PieceTags = require(script.Parent.PieceTags)

local Sales = {}

-- A fish enters the grinder. `playerUserId` is the net-pad player (nil for
-- the harpoon); `meta` the catch payload { OwnerId, Variant, Source }.
function Sales.issue(ledger: Ledger.Ledger, playerUserId: number?, fishName: any, tier: any, meta: any): { string }
	return ledger:issueFish({
		ownerId = PieceTags.ownerFor(playerUserId, meta),
		tier = tier,
		variant = PieceTags.variantFrom(meta),
		fishName = fishName,
		source = PieceTags.sourceFrom(meta, playerUserId ~= nil),
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

return Sales
