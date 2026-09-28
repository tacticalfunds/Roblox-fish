-- Rod shop: every 5 minutes each player's stock re-rolls (rarer rods show up less and in smaller amounts).
-- Stock lives on the player as attributes "RodStock_<RodName>", owned rods as "RodOwned_<RodName>".
--
-- [Economy patch v1] Changes vs. the live script are marked "Economy".
-- With EconomyService running, rods are charged through it (never by writing
-- leaderstats.Money directly, which EconomyService reverts). The shop stays
-- closed (Config.RodShopOpen = false) until owning a rod does something and is
-- saved; stock/restock and the RodOwned attributes are unchanged.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local rods = RS:WaitForChild("Rods")
local shop = RS:WaitForChild("RodShop")
local buyRemote = shop:WaitForChild("BuyRod")
local EVERY = shop:GetAttribute("RestockEvery") or 300

-- Economy: optional money service (missing or not running -> original behaviour)
local Economy = nil
do
	local mod = game:GetService("ServerScriptService"):FindFirstChild("EconomyService")
	if mod and mod:IsA("ModuleScript") then
		local ok, api = pcall(require, mod)
		if ok and type(api) == "table" then
			local ran, running = pcall(api.start)
			if ran and running then
				Economy = api
			else
				warn("[RodShopServer] economy not running, original behaviour: " .. tostring(running))
			end
		else
			warn("[RodShopServer] could not load EconomyService, original behaviour: " .. tostring(api))
		end
	end
end

local function rollStock(player)
	for _, r in ipairs(rods:GetChildren()) do
		local qty = 0
		if math.random() <= (r:GetAttribute("StockChance") or 1) then
			qty = math.random(r:GetAttribute("StockMin") or 1, r:GetAttribute("StockMax") or 1)
		end
		player:SetAttribute("RodStock_" .. r.Name, qty)
	end
end

-- money: uses leaderstats.Money (or a "Money" attribute) when the game has one
local function getMoney(player)
	local ls = player:FindFirstChild("leaderstats")
	local v = ls and (ls:FindFirstChild("Money") or ls:FindFirstChild("Cash"))
	if v then return v.Value, function(n) v.Value = n end end
	local a = player:GetAttribute("Money")
	if a then return a, function(n) player:SetAttribute("Money", n) end end
	return nil
end

buyRemote.OnServerInvoke = function(player, rodName)
	local rod = typeof(rodName) == "string" and rods:FindFirstChild(rodName)
	if not rod then return false, "Unknown rod" end
	local stock = player:GetAttribute("RodStock_" .. rod.Name) or 0
	if stock <= 0 then return false, "Sold out" end
	local price = rod:GetAttribute("Price") or 0
	if Economy then
		-- Economy: charged through EconomyService; closed until rods are linked to stats
		if not Economy.rodShopOpen() then return false, "Rod shop opens soon" end
		if type(price) ~= "number" or price < 0 or price ~= math.floor(price) then return false, "Unknown rod" end
		if price > 0 then
			local paid, why = Economy.tryDebit(player, price, "Rod:" .. rod.Name)
			if not paid then return false, if why == "funds" then "Not enough money" else "Money not loaded yet" end
		end
	else
		local money, setMoney = getMoney(player)
		if money == nil then return false, "No money system yet" end
		if money < price then return false, "Not enough money" end
		setMoney(money - price)
	end
	player:SetAttribute("RodStock_" .. rod.Name, stock - 1)
	player:SetAttribute("RodOwned_" .. rod.Name, (player:GetAttribute("RodOwned_" .. rod.Name) or 0) + 1)
	return true, "Bought " .. (rod:GetAttribute("DisplayName") or rod.Name)
end

Players.PlayerAdded:Connect(rollStock)
for _, p in ipairs(Players:GetPlayers()) do rollStock(p) end

-- global restock clock (everyone restocks at the same time)
while true do
	shop:SetAttribute("NextRestock", workspace:GetServerTimeNow() + EVERY)
	task.wait(EVERY)
	for _, p in ipairs(Players:GetPlayers()) do rollStock(p) end
end
