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

-- The customers' rate (a minute) and line size. `players` is either a count
-- (each player at the base rate) or the list of each present player's own
-- Customer Speed value; `lines` (optional) the list of their Customer Line
-- values. `cfg` is Config.Customers ({ PerPlayer, Max, LineCap, LineMax }).
--   rate = the SUM of the players' rates (each at least the base), at most
--          Max; line = the LARGEST player's line (at least LineCap), at most
--          LineMax.
-- The Car Sales upgrades' published values (`publishedRate` = workspace
-- CustomersPerMin, used per player; `publishedCap` = CustomersLineCap;
-- anything not a positive number is ignored) are never lowered.
function Sales.customers(players: any, publishedRate: any, publishedCap: any, cfg: any, lines: any): (number, number)
	local function positive(v: any): number
		return if type(v) == "number" and v == v and v > 0 and v < math.huge then v else 0
	end
	local published = positive(publishedRate)
	local perPlayer = math.max(cfg.PerPlayer, published)
	local sum, n = 0, 0
	if type(players) == "table" then
		for _, own in ipairs(players) do
			n += 1
			sum += math.max(perPlayer, math.min(positive(own), cfg.Max))
		end
	else
		n = math.floor(positive(players))
		sum = perPlayer * n
	end
	if n == 0 then
		sum = perPlayer -- counted as one player
	end
	local perMin = math.min(sum, math.max(cfg.Max, published))
	local line = cfg.LineCap
	if type(lines) == "table" then
		for _, own in ipairs(lines) do
			line = math.max(line, math.floor(positive(own)))
		end
	end
	line = math.min(line, cfg.LineMax or 8)
	local cap = math.max(line, math.floor(positive(publishedCap)))
	return perMin, cap
end

return Sales
