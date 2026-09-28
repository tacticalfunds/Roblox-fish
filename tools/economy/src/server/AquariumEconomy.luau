-- AquariumEconomy (ModuleScript in ServerScriptService) - Economy version.
--
-- The aquarium's currency binding. Upgrades are charged to the player who
-- triggers the upgrade prompt, through EconomyService (leaderstats.Money).
-- Returns nil (upgrades "unavailable", never free) if EconomyService is
-- missing or not running.
--
-- Shared tank upgrades are SESSION-SCOPED: the one physical tank's levels
-- live only in this server and reset when the server closes. They are not
-- saved to anyone's data, and capacity is never per player. Whoever buys a
-- level pays for it; everyone in the server shares the tank.
--
-- tryCharge is synchronous (no yields), so the aquarium's charge-then-apply
-- can't interleave with another purchase.

local ServerScriptService = game:GetService("ServerScriptService")

local mod = ServerScriptService:FindFirstChild("EconomyService")
if not (mod and mod:IsA("ModuleScript")) then
	return nil
end
local ok, Economy = pcall(require, mod)
if not ok or type(Economy) ~= "table" then
	warn("[AquariumEconomy] EconomyService failed to load: " .. tostring(Economy))
	return nil
end
local started, running = pcall(Economy.start)
if not (started and running) then
	return nil
end

return {
	tryCharge = function(player: Player, amount: number, reason: string): boolean
		local paid, why = Economy.tryDebit(player, amount, reason)
		if not paid and why == "notLoaded" then
			Economy.notify(player, "Money is still loading - try again in a moment", "warn")
		end
		return paid == true
	end,
}
