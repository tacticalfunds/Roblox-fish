--!strict
-- Rod-fish offers: a revealed rod fish waits on the line until its CASTER
-- buys it (-> aquarium) or passes / lets it time out (-> gone). Pure state
-- machine; the service supplies the side effects as callbacks.
--
-- States: Open -> Delivering -> Bought
--         Open -> Passed | Expired | Cancelled
--         Delivering -> Cancelled (delivery failed; the charge is refunded)
--
-- Buy is one synchronous sequence (no yields between the checks, the debit
-- and the delivery), so repeated clicks, a Buy racing a Pass, or two players
-- can never charge or deliver twice:
--   offer still Open -> buyer is the caster -> not expired -> buyer in range
--   -> tank reservation still valid (else the offer is cancelled, NO charge)
--   -> debit (insufficient funds leaves the offer Open) -> deliver
--   -> delivery failed? refund + Cancelled.

export type Status = "Open" | "Delivering" | "Bought" | "Passed" | "Expired" | "Cancelled"

export type Offer = {
	id: number,
	rodKey: any,
	casterId: number,
	fishName: string,
	tier: number,
	variant: string?,
	price: number,
	expiresAt: number,
	status: Status,
	reason: string?,
}

export type BuyDeps = {
	inRange: () -> boolean,
	reservationOk: () -> boolean,
	debit: (amount: number) -> (boolean, string?),
	deliver: () -> boolean,
	refund: (amount: number) -> (),
}

local Offers = {}
Offers.__index = Offers

export type Offers = typeof(setmetatable(
	{} :: {
		offers: { [number]: Offer },
		byRod: { [any]: number },
		nextId: number,
		timeout: number,
		allowTestIds: boolean,
	},
	Offers
))

-- allowTestIds: accept Studio test clients' negative UserIds (-1, -2, ...).
-- The service passes RunService:IsStudio(); live servers only accept real
-- (positive) UserIds.
function Offers.new(timeoutSeconds: number, allowTestIds: boolean?): Offers
	return setmetatable(
		{ offers = {}, byRod = {}, nextId = 0, timeout = timeoutSeconds, allowTestIds = allowTestIds == true },
		Offers
	)
end

function Offers.validCaster(self: Offers, id: any): boolean
	if type(id) ~= "number" or id ~= id or id ~= math.floor(id) or id == 0 then
		return false
	end
	return id > 0 or self.allowTestIds
end

local function closed(self: Offers, offer: Offer, status: Status, reason: string?)
	offer.status = status
	offer.reason = reason
	if self.byRod[offer.rodKey] == offer.id then
		self.byRod[offer.rodKey] = nil
	end
end

-- Opens an offer for a rod. One open offer per rod. Returns the offer or
-- (nil, reason).
function Offers.open(
	self: Offers,
	rodKey: any,
	casterId: number,
	fishName: string,
	tier: number,
	variant: string?,
	price: number,
	now: number
): (Offer?, string?)
	if rodKey == nil then
		return nil, "noRod"
	end
	if self.byRod[rodKey] then
		return nil, "rodBusy"
	end
	if not self:validCaster(casterId) then
		return nil, "noCaster"
	end
	if type(price) ~= "number" or price < 1 or price ~= math.floor(price) then
		return nil, "badPrice"
	end
	self.nextId += 1
	local offer: Offer = {
		id = self.nextId,
		rodKey = rodKey,
		casterId = casterId,
		fishName = fishName,
		tier = tier,
		variant = variant,
		price = price,
		expiresAt = now + self.timeout,
		status = "Open",
		reason = nil,
	}
	self.offers[offer.id] = offer
	self.byRod[rodKey] = offer.id
	return offer, nil
end

function Offers.get(self: Offers, id: any): Offer?
	if type(id) ~= "number" then
		return nil
	end
	return self.offers[id]
end

-- Returns (result, offer?). Results: "bought", "alreadyBought", "closed",
-- "unknown", "notYours", "expired", "tooFar", "tankUnavailable", "funds",
-- "notLoaded", "deliveryFailed".
function Offers.buy(self: Offers, id: any, userId: number, now: number, deps: BuyDeps): (string, Offer?)
	local offer = self:get(id)
	if not offer then
		return "unknown", nil
	end
	if offer.status ~= "Open" then
		if offer.status == "Bought" and offer.casterId == userId then
			return "alreadyBought", offer
		end
		return "closed", offer
	end
	if offer.casterId ~= userId then
		return "notYours", offer
	end
	if now >= offer.expiresAt then
		closed(self, offer, "Expired", "timeout")
		return "expired", offer
	end
	if not deps.inRange() then
		return "tooFar", offer
	end
	if not deps.reservationOk() then
		closed(self, offer, "Cancelled", "tankUnavailable")
		return "tankUnavailable", offer
	end
	local paid, why = deps.debit(offer.price)
	if not paid then
		-- the offer stays open: the player can still buy before it expires
		return if why == "notLoaded" then "notLoaded" else "funds", offer
	end
	offer.status = "Delivering"
	local delivered = false
	local ok = pcall(function()
		delivered = deps.deliver() == true
	end)
	if ok and delivered then
		closed(self, offer, "Bought", nil)
		return "bought", offer
	end
	deps.refund(offer.price)
	closed(self, offer, "Cancelled", "deliveryFailed")
	return "deliveryFailed", offer
end

-- Caster declines. Returns "passed" | "notYours" | "closed" | "unknown".
function Offers.pass(self: Offers, id: any, userId: number): string
	local offer = self:get(id)
	if not offer then
		return "unknown"
	end
	if offer.status ~= "Open" then
		return "closed"
	end
	if offer.casterId ~= userId then
		return "notYours"
	end
	closed(self, offer, "Passed", nil)
	return "passed"
end

-- Times out open offers. Returns those that just expired.
function Offers.expire(self: Offers, now: number): { Offer }
	local out = {}
	for _, offer in pairs(self.offers) do
		if offer.status == "Open" and now >= offer.expiresAt then
			closed(self, offer, "Expired", "timeout")
			table.insert(out, offer)
		end
	end
	return out
end

-- Cancels one open offer (rod task error, tank switched off). No charge.
function Offers.cancel(self: Offers, id: any, reason: string): boolean
	local offer = self:get(id)
	if not offer or offer.status ~= "Open" then
		return false
	end
	closed(self, offer, "Cancelled", reason)
	return true
end

-- Caster left: cancel their open offers. No charge.
function Offers.cancelForUser(self: Offers, userId: number, reason: string): { Offer }
	local out = {}
	for _, offer in pairs(self.offers) do
		if offer.status == "Open" and offer.casterId == userId then
			closed(self, offer, "Cancelled", reason)
			table.insert(out, offer)
		end
	end
	return out
end

-- Feature switched off: cancel every open offer. No charge, no delivery.
function Offers.cancelAll(self: Offers, reason: string): { Offer }
	local out = {}
	for _, offer in pairs(self.offers) do
		if offer.status == "Open" then
			closed(self, offer, "Cancelled", reason)
			table.insert(out, offer)
		end
	end
	return out
end

-- Drops a resolved offer's record (after the rod has cleaned up).
function Offers.forget(self: Offers, id: any)
	local offer = self:get(id)
	if offer and offer.status ~= "Open" and offer.status ~= "Delivering" then
		self.offers[offer.id] = nil
	end
end

-- Buy reach, measured from the rod stand: the prompt shows within
-- promptDistance; the server accepts up to promptDistance + slack.
function Offers.inReach(distance: any, promptDistance: number, slack: number): boolean
	return type(distance) == "number" and distance == distance and distance >= 0 and distance <= promptDistance + slack
end

-- A catch's real roll chance (0..1] as display text, e.g. "12%", "3.4%",
-- "0.45%". nil for anything that isn't a valid probability (nothing shown;
-- never an invented number).
function Offers.chanceText(chance: any): string?
	if type(chance) ~= "number" or chance ~= chance or chance <= 0 or chance > 1 then
		return nil
	end
	local pct = chance * 100
	if pct >= 10 then
		return string.format("%d%%", math.floor(pct + 0.5))
	elseif pct >= 1 then
		return string.format("%.1f%%", pct)
	elseif pct >= 0.01 then
		return string.format("%.2f%%", pct)
	end
	return "<0.01%"
end

function Offers.openCount(self: Offers): number
	local n = 0
	for _, offer in pairs(self.offers) do
		if offer.status == "Open" then
			n += 1
		end
	end
	return n
end

return Offers
