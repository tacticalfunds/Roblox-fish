-- EconomyBoot (Script in ServerScriptService). Starts EconomyService at
-- server start so every player's Money loads (and shows in leaderstats)
-- before anything is bought or sold. Removing this script does not break
-- the patched scripts: they start the service themselves when they need it.
local ServerScriptService = game:GetService("ServerScriptService")

local mod = ServerScriptService:FindFirstChild("EconomyService")
if mod and mod:IsA("ModuleScript") then
	local ok, api = pcall(require, mod)
	if ok and type(api) == "table" then
		local ran, err = pcall(api.start)
		if not ran then
			warn("[EconomyBoot] EconomyService failed to start: " .. tostring(err))
		end
	else
		warn("[EconomyBoot] could not load EconomyService: " .. tostring(api))
	end
end
