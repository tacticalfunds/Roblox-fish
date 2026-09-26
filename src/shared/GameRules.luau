--!strict
-- Pure gameplay rules shared by the server services and the offline tests.
-- Nothing here touches Instances; callers own the state tables.

local GameRules = {}

export type Carry = { fish: number, food: number }
export type Grinder = { input: number, output: number, progress: number }
export type Customer = { size: number, delivered: number }

function GameRules.carrySpace(carry: Carry, capacity: number): number
	return math.max(0, capacity - carry.fish - carry.food)
end

-- How many items can move given what is available and the free space.
function GameRules.transferAmount(available: number, space: number, maxPerStep: number?): number
	local amount = math.min(available, space)
	if maxPerStep then
		amount = math.min(amount, maxPerStep)
	end
	return math.max(0, math.floor(amount))
end

-- Moves netted fish onto the carry stack. Returns (moved, leftInNet).
-- Fish that do not fit stay in the net: nothing is discarded.
function GameRules.haul(netted: number, carry: Carry, capacity: number): (number, number)
	local moved = GameRules.transferAmount(netted, GameRules.carrySpace(carry, capacity))
	carry.fish += moved
	return moved, netted - moved
end

-- Advances the grinder by dt seconds. Mutates the grinder table and returns
-- (fishProcessed, status) where status is "Processing", "Idle" or "OutputFull".
-- The grinder never consumes a fish unless the output tray has room for all of
-- its portions, so stock is never silently lost.
function GameRules.grinderStep(
	grinder: Grinder,
	dt: number,
	processSeconds: number,
	outputCapacity: number,
	portionsPerFish: number
): (number, string)
	local processed = 0
	if grinder.input <= 0 then
		grinder.progress = 0
		return 0, "Idle"
	end
	if grinder.output + portionsPerFish > outputCapacity then
		return 0, "OutputFull"
	end
	grinder.progress += dt
	while grinder.progress >= processSeconds and grinder.input > 0 do
		if grinder.output + portionsPerFish > outputCapacity then
			grinder.progress = math.min(grinder.progress, processSeconds)
			return processed, "OutputFull"
		end
		grinder.progress -= processSeconds
		grinder.input -= 1
		grinder.output += portionsPerFish
		processed += 1
	end
	if grinder.input <= 0 then
		grinder.progress = 0
		return processed, "Idle"
	end
	return processed, "Processing"
end

-- Index of the first customer in the queue still waiting for food, or nil.
function GameRules.nextCustomerIndex(queue: { Customer }): number?
	for i, customer in ipairs(queue) do
		if customer.delivered < customer.size then
			return i
		end
	end
	return nil
end

-- Coins paid by a customer who received `delivered` of `size` portions.
function GameRules.payout(delivered: number, size: number, pricePerPortion: number, completionBonus: number): number
	local coins = delivered * pricePerPortion
	if delivered >= size and size > 0 then
		coins += completionBonus
	end
	return coins
end

return GameRules
