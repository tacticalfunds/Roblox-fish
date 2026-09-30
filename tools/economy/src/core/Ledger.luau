--!strict
-- Meat ledger: the single record of every meat piece's identity and value,
-- from the grinder to its one sale. Pure; the service binds it to objects.
--
-- A piece is issued when the grinder cuts a fish. Its owner and value are
-- fixed then and never recomputed. Objects that stand for the piece (the
-- pit/belt/stack part, the Blender Bot's carried clone, the sale-table
-- part) carry only its PieceId attribute; copies with the same PieceId are
-- harmless because a piece can be SETTLED ONLY ONCE: settling removes the
-- record, so any later settle of that id finds nothing and pays nothing.
--
-- States:
--   Live     an object in the world stands for it (pit, belt, stack, bot, table)
--   Carried  a player carries it toward a truck (no object of its own)
--   Held     no object: kept as data because the pipeline was full, or its
--            carrier left / respawned. Re-emitted by the grinder, oldest first.
-- A settled or voided piece is removed.

local Pricing = require(script.Parent.Pricing)

export type Piece = {
	id: string,
	ownerId: number?, -- UserId paid on sale; nil = unowned (sells, pays nobody)
	value: number,
	variant: string?,
	tier: number,
	fishName: string,
	source: string,
	state: "Live" | "Carried" | "Held",
}

export type FishInfo = {
	ownerId: number?,
	tier: any,
	variant: any,
	fishName: any,
	source: any,
	multiplier: any, -- the owner's Meat Price (whole-fish value x this, once); only for an owned fish
}

local Ledger = {}
Ledger.__index = Ledger

export type Ledger = typeof(setmetatable(
	{} :: {
		allowTestIds: boolean,
		pieces: { [string]: Piece },
		held: { string }, -- FIFO of held ids (may contain stale ids; skipped)
		heldCount: number,
		nextId: number,
		prefix: string,
		totals: { issued: number, settled: number, paid: number, unpaid: number, voided: number },
	},
	Ledger
))

-- allowTestIds: Studio test clients have negative UserIds (-1, -2, ...);
-- the service passes RunService:IsStudio() so they can own pieces there.
-- Live servers only ever see positive UserIds.
function Ledger.new(prefix: string?, allowTestIds: boolean?): Ledger
	return setmetatable({
		allowTestIds = allowTestIds == true,
		pieces = {},
		held = {},
		heldCount = 0,
		nextId = 0,
		prefix = prefix or "P",
		totals = { issued = 0, settled = 0, paid = 0, unpaid = 0, voided = 0 },
	}, Ledger)
end

local function validOwner(v: any, allowTestIds: boolean?): number?
	if type(v) == "number" and v == v and v == math.floor(v) and (v > 0 or (allowTestIds == true and v < 0)) then
		return v
	end
	return nil
end
Ledger.validOwner = validOwner

-- Cuts one fish into pieces. Returns the new piece ids (all Live).
function Ledger.issueFish(self: Ledger, info: FishInfo): { string }
	local variant = Pricing.variant(info.variant)
	local tier = if type(info.tier) == "number" and info.tier == info.tier then info.tier else 1
	local ownerId = validOwner(info.ownerId, self.allowTestIds)
	-- an unowned fish pays nobody: no owner, no multiplier
	local values = Pricing.pieceValues(tier, variant, if ownerId then info.multiplier else nil)
	local ids = {}
	for _, value in ipairs(values) do
		self.nextId += 1
		local id = self.prefix .. tostring(self.nextId)
		self.pieces[id] = {
			id = id,
			ownerId = ownerId,
			value = value,
			variant = variant,
			tier = tier,
			fishName = if type(info.fishName) == "string" then info.fishName else "Fish",
			source = if type(info.source) == "string" then info.source else "Unknown",
			state = "Live",
		}
		self.totals.issued += 1
		table.insert(ids, id)
	end
	return ids
end

function Ledger.get(self: Ledger, id: any): Piece?
	if type(id) ~= "string" then
		return nil
	end
	return self.pieces[id]
end

-- Marks a Live piece as carried by a player (picked up for a truck).
function Ledger.carry(self: Ledger, id: any): boolean
	local p = self:get(id)
	if not p or p.state ~= "Live" then
		return false
	end
	p.state = "Carried"
	return true
end

-- The ONE sale of a piece. Returns the piece the first time; nil for an
-- unknown, already-settled or held id (held pieces have no object to sell).
function Ledger.settle(self: Ledger, id: any): Piece?
	local p = self:get(id)
	if not p or p.state == "Held" then
		return nil
	end
	self.pieces[p.id] = nil
	self.totals.settled += 1
	return p
end

-- Records the payout outcome of a settled piece (for diagnostics only).
function Ledger.notePaid(self: Ledger, paid: boolean)
	if paid then
		self.totals.paid += 1
	else
		self.totals.unpaid += 1
	end
end

-- The piece's object is gone without a sale: keep it as data to re-emit.
function Ledger.hold(self: Ledger, id: any): boolean
	local p = self:get(id)
	if not p or p.state == "Held" then
		return false
	end
	p.state = "Held"
	table.insert(self.held, p.id)
	self.heldCount += 1
	return true
end

-- Oldest held piece back to Live (the caller makes its object). nil if none.
function Ledger.takeHeld(self: Ledger): Piece?
	while #self.held > 0 do
		local id = table.remove(self.held, 1)
		local p = self.pieces[id :: string]
		if p and p.state == "Held" then
			p.state = "Live"
			self.heldCount -= 1
			return p
		end
	end
	return nil
end

-- Removes a piece that can never be sold (logged by the caller).
function Ledger.void(self: Ledger, id: any): Piece?
	local p = self:get(id)
	if not p then
		return nil
	end
	if p.state == "Held" then
		self.heldCount -= 1 -- its stale FIFO entry is skipped by takeHeld
	end
	self.pieces[p.id] = nil
	self.totals.voided += 1
	return p
end

function Ledger.counts(self: Ledger): { live: number, carried: number, held: number }
	local c = { live = 0, carried = 0, held = 0 }
	for _, p in pairs(self.pieces) do
		if p.state == "Live" then
			c.live += 1
		elseif p.state == "Carried" then
			c.carried += 1
		else
			c.held += 1
		end
	end
	return c
end

-- Invariant check for tests: heldCount matches, FIFO covers every held piece.
function Ledger.check(self: Ledger): (boolean, string?)
	local c = self:counts()
	if c.held ~= self.heldCount then
		return false, "heldCount " .. self.heldCount .. " but " .. c.held .. " held pieces"
	end
	local inFifo = {}
	for _, id in ipairs(self.held) do
		inFifo[id] = true
	end
	for id, p in pairs(self.pieces) do
		if p.state == "Held" and not inFifo[id] then
			return false, "held piece " .. id .. " missing from queue"
		end
	end
	return true, nil
end

return Ledger
