-- Sends short feedback toasts to a player, with optional per-key throttling so
-- continuous checks (e.g. "grinder full" while standing on a pad) do not spam.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.FishTycoonShared.Remotes)

local Notifier = {}

local THROTTLE_SECONDS = 2
local lastSent: { [Player]: { [string]: number } } = {}

-- kind: "info" | "success" | "warn"
function Notifier.send(player: Player, kind: string, text: string, throttleKey: string?)
	if not player.Parent then
		return
	end
	if throttleKey then
		local now = os.clock()
		local perPlayer = lastSent[player]
		if not perPlayer then
			perPlayer = {}
			lastSent[player] = perPlayer
		end
		local last = perPlayer[throttleKey]
		if last and now - last < THROTTLE_SECONDS then
			return
		end
		perPlayer[throttleKey] = now
	end
	Remotes.get("Notify"):FireClient(player, kind, text)
end

function Notifier.forget(player: Player)
	lastSent[player] = nil
end

return Notifier
