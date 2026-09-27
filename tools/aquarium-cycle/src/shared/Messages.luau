--!strict
-- Player-facing feedback for every refusal code the system can return.

local Messages = {}

Messages.Reasons = {
	tankFull = "The aquarium is full. Release some fish back into the river first.",
	empty = "The aquarium is empty.",
	cooldown = "Release is still recharging.",
	economyAdapterOff = "Aquarium upgrades aren't available yet: no currency is connected to this game.",
	max = "That aquarium upgrade is already maxed.",
	funds = "You can't afford that upgrade yet.",
	tooFar = "Move closer to the aquarium.",
	stopped = "The aquarium is offline right now.",
	badUpgrade = "Unknown aquarium upgrade.",
}

Messages.Fallback = "Couldn't do that right now."

function Messages.forReason(reason: string?): string
	return reason and Messages.Reasons[reason] or Messages.Fallback
end

function Messages.released(n: number): string
	if n == 1 then
		return "Released 1 fish back into the river."
	end
	return string.format("Released %d fish back into the river.", n)
end

function Messages.upgraded(displayName: string, value: number): string
	return string.format("%s upgraded to %d!", displayName, value)
end

return Messages
