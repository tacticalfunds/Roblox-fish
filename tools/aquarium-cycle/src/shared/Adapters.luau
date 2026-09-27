--!strict
-- Integration contracts between the pure cycle core and whatever already
-- exists in the Studio place (RodFishingClient, FishSwimClient, TruckClient,
-- FishTank, SwimmingFish, the economy, ...). NOTHING here is wired yet: every
-- adapter defaults to OFF (nil), and the core refuses the actions that would
-- need one. Real implementations are written only after the existing server
-- source has been read, and must extend that code rather than replace it.
--
-- Deliberate non-defaults:
--   * No currency is ever granted by this system on its own. Releasing fish
--     pays nothing unless a Payout adapter is installed and decides to.
--   * No leaderboard/currency objects are created. Economy is whatever the
--     place already uses, reached only through the Economy adapter.
--   * Upgrades cannot be bought while no Economy adapter is installed.

export type Economy = {
	-- Attempts to charge `amount` from the owner. Must be atomic: returns true
	-- only if the full amount was taken.
	tryCharge: (owner: any, amount: number, reason: string) -> boolean,
}

export type Payout = {
	-- Called after the core confirms a state change. The adapter alone decides
	-- whether anything is paid; the trigger (release, return, truck, ...) is
	-- not confirmed by design yet.
	onEvent: (event: { kind: string, fishId: number?, owner: any? }) -> (),
}

export type FishSource = {
	-- Picks a river fish id for a waiting rod (e.g. nearest to the hook),
	-- or nil if none is suitable. Must only return ids the core knows about.
	pickFishForRod: (rodId: any) -> number?,
}

export type Adapters = {
	Economy: Economy?,
	Payout: Payout?,
	FishSource: FishSource?,
}

local Upgrades = require(script.Parent.Upgrades)

local Adapters = {}

-- `warn` exists in Roblox; fall back to print in the offline test runner.
local report: (...any) -> () = (warn :: any) or print

function Adapters.defaults(): Adapters
	return { Economy = nil, Payout = nil, FishSource = nil }
end

-- Buys one upgrade level through the economy adapter, then applies it. The
-- price comes from the owner's current level in the core state, never from
-- the caller. Refuses without charging when no adapter is installed, at max
-- level, or when the charge fails. Returns (ok, reason, newLevel).
function Adapters.buyUpgrade(adapters: Adapters, state: any, owner: any, upgradeId: string)
	if not adapters.Economy then
		return false, "economyAdapterOff", nil
	end
	local info = state:tankInfo(owner)
	if not info or type(upgradeId) ~= "string" or info.levels[upgradeId] == nil then
		return false, "badUpgrade", nil
	end
	local cost = Upgrades.nextCost(state.config, upgradeId, info.levels[upgradeId])
	if cost == nil then
		return false, "max", info.levels[upgradeId]
	end
	if not adapters.Economy.tryCharge(owner, cost, "AquariumUpgrade:" .. upgradeId) then
		return false, "funds", nil
	end
	return state:applyUpgrade(owner, upgradeId)
end

-- Forwards core events to the payout adapter, if any. Errors in the adapter
-- are contained so they can't corrupt the cycle state.
function Adapters.emit(adapters: Adapters, events: { any })
	local payout = adapters.Payout
	if not payout then
		return
	end
	for _, event in ipairs(events) do
		local ok, err = pcall(function()
			payout.onEvent(event)
		end)
		if not ok then
			report("[AquariumCycle] payout adapter error: " .. tostring(err))
		end
	end
end

return Adapters
