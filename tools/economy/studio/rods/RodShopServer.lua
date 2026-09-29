-- Rod shop: every 5 minutes each player's stock re-rolls (rarer rods show up less and in smaller amounts).
-- Stock lives on the player as attributes "RodStock_<RodName>", owned rods as "RodOwned_<RodName>".
--
-- [Economy rods v1] Rewritten buy path, marked "Rods":
--   * Rods are OWNED for good (one each), saved with the player's Money by
--     EconomyService, and EQUIPPED; the equipped rod makes bites come faster
--     (RodFishingSystem reads it per cast). Basic (FishingRod1) is free and
--     always owned.
--   * BuyRod(rodName): an owned rod is equipped (never charged again); an
--     unowned one is bought and equipped through EconomyService.rodAction,
--     which saves the money and the rod in one write before it counts.
--   * Fail closed: without a running EconomyService nothing is sold (the old
--     fallback that wrote leaderstats.Money / a Money attribute is gone).
--   * Buying needs the player near the shop (Workspace["Pet Shop"].ShopPrompt,
--     the part whose OpenShopPrompt opens the shop UI).
--   * Stock: Basic and Tiger are always in stock; the others keep the
--     per-player restock roll below (StockChance / StockMin / StockMax).
--     Owned rods always show (to equip them).
--   * Prices / benefits shown by the shop come from EconomyService's rod
--     table: the Price attribute on each ReplicatedStorage.Rods model is set
--     to it while the server runs (legacy Price / Tier / Title are ignored).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local rods = RS:WaitForChild("Rods")
local shop = RS:WaitForChild("RodShop")
local buyRemote = shop:WaitForChild("BuyRod")
local EVERY = shop:GetAttribute("RestockEvery") or 300

-- Rods: the money service is required; missing or not running -> the shop sells nothing
local Economy = nil
do
	local mod = game:GetService("ServerScriptService"):FindFirstChild("EconomyService")
	if mod and mod:IsA("ModuleScript") then
		local ok, api = pcall(require, mod)
		if ok and type(api) == "table" then
			local ran, running = pcall(api.start)
			if ran and running and type(api.rodAction) == "function" then
				Economy = api
			else
				warn("[RodShopServer] economy not running: the rod shop sells nothing (" .. tostring(running) .. ")")
			end
		else
			warn("[RodShopServer] could not load EconomyService: the rod shop sells nothing (" .. tostring(api) .. ")")
		end
	else
		warn("[RodShopServer] no EconomyService: the rod shop sells nothing")
	end
end
local RodTable = Economy and Economy.Rods

-- Rods: the shop shows the real price and benefit of each rod
if RodTable then
	for _, def in ipairs(RodTable.list()) do
		local model = rods:FindFirstChild(def.Id)
		if model then
			model:SetAttribute("Price", def.Price)
			model:SetAttribute("BiteWait", def.BiteWait)
			model:SetAttribute("Benefit", if def.BiteWait < 1
				then string.format("Bites %d%% faster", math.floor((1 - def.BiteWait) * 100 + 0.5))
				else "Standard bites")
		end
	end
end

local function owns(player, name)
	return player:GetAttribute("RodOwned_" .. name) ~= nil
end

local function rollStock(player)
	for _, r in ipairs(rods:GetChildren()) do
		local qty = 0
		if RodTable and RodTable.alwaysStocked(r.Name) then
			qty = 1 -- Rods: early progression never waits on a random roll
		elseif math.random() <= (r:GetAttribute("StockChance") or 1) then
			qty = math.random(r:GetAttribute("StockMin") or 1, r:GetAttribute("StockMax") or 1)
		end
		if owns(player, r.Name) then
			qty = math.max(qty, 1) -- Rods: an owned rod always shows, to equip it
		end
		player:SetAttribute("RodStock_" .. r.Name, qty)
	end
end

-- Rods: buying needs the player at the shop
local BUY_SLACK = 16 -- studs beyond the open-shop prompt's own distance
local function nearShop(player)
	local building = workspace:FindFirstChild("Pet Shop")
	local part = building and building:FindFirstChild("ShopPrompt")
	if not (part and part:IsA("BasePart")) then
		return false, "The rod shop isn't set up here"
	end
	local prompt = part:FindFirstChildWhichIsA("ProximityPrompt")
	local reach = (prompt and prompt.MaxActivationDistance or 14) + BUY_SLACK
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) or (hrp.Position - part.Position).Magnitude > reach then
		return false, "Walk back to the rod shop to buy"
	end
	return true, nil
end

buyRemote.OnServerInvoke = function(player, rodName)
	if not Economy then
		return false, "The rod shop is unavailable right now"
	end
	-- Rods: owned -> equip (free); else buy, saved before it counts
	local ok, message = Economy.rodAction(player, rodName, function(def)
		if not RodTable.alwaysStocked(def.Id) and (player:GetAttribute("RodStock_" .. def.Id) or 0) <= 0 then
			return false, "Sold out"
		end
		return nearShop(player)
	end)
	if ok and typeof(rodName) == "string" and rods:FindFirstChild(rodName) then
		player:SetAttribute("RodStock_" .. rodName, math.max(player:GetAttribute("RodStock_" .. rodName) or 0, 1))
	end
	return ok, message
end

-- Rods: owned rods are known once the player's money has loaded (after the
-- first roll): keep them visible then
local function showOwned(player)
	for _, r in ipairs(rods:GetChildren()) do
		if owns(player, r.Name) and (player:GetAttribute("RodStock_" .. r.Name) or 0) < 1 then
			player:SetAttribute("RodStock_" .. r.Name, 1)
		end
	end
end
local function onPlayer(player)
	rollStock(player)
	player:GetAttributeChangedSignal("EquippedRod"):Connect(function()
		showOwned(player)
	end)
	showOwned(player)
end

Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end

-- global restock clock (everyone restocks at the same time)
while true do
	shop:SetAttribute("NextRestock", workspace:GetServerTimeNow() + EVERY)
	task.wait(EVERY)
	for _, p in ipairs(Players:GetPlayers()) do rollStock(p) end
end
