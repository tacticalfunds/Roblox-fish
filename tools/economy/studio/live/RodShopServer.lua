-- Rod shop: every 5 minutes each player's stock re-rolls (rarer rods show up less and in smaller amounts).
-- Stock lives on the player as attributes "RodStock_<RodName>", owned rods as "RodOwned_<RodName>".
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local rods = RS:WaitForChild("Rods")
local shop = RS:WaitForChild("RodShop")
local buyRemote = shop:WaitForChild("BuyRod")
local EVERY = shop:GetAttribute("RestockEvery") or 300

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
	local money, setMoney = getMoney(player)
	if money == nil then return false, "No money system yet" end
	if money < price then return false, "Not enough money" end
	setMoney(money - price)
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
