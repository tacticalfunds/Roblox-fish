-- Rod shop UI: opens from the shop stand prompt, shows each rod with price + stock, restock countdown.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local player = Players.LocalPlayer

local frame = script.Parent
local scroll = frame:WaitForChild("ScrollingFrame")
local template = scroll:WaitForChild("CarTemplate")
local timerLabel = frame:WaitForChild("RestockTimer"):WaitForChild("TextLabel")
local closeButton = frame:WaitForChild("CloseButton")
local rods = RS:WaitForChild("Rods")
local shop = RS:WaitForChild("RodShop")
local buyRemote = shop:WaitForChild("BuyRod")

local RARITY_COLORS = {
	Common = Color3.fromRGB(210, 210, 210), Uncommon = Color3.fromRGB(90, 230, 90), Rare = Color3.fromRGB(60, 150, 255),
	Epic = Color3.fromRGB(180, 80, 255), Legendary = Color3.fromRGB(255, 190, 40),
}

local function click() local s = SoundService:FindFirstChild("Click") if s then s:Play() end end
local function money(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "$" .. out:gsub("^,", "")
end

-- bright outlined rod picture, laid diagonally so it fills the square
local function fillViewport(vp, rodModel)
	vp.Ambient = Color3.new(1, 1, 1) vp.LightColor = Color3.new(1, 1, 1) vp.LightDirection = Vector3.new(-0.3, -1, -0.6)
	vp.BackgroundTransparency = 1
	local m = rodModel:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true if d.MaterialVariant ~= "" then d.MaterialVariant = "" d.Material = Enum.Material.SmoothPlastic end
		elseif d:IsA("LuaSourceContainer") then d:Destroy() end
	end
	m:PivotTo(CFrame.Angles(0, 0, math.rad(-42)) * CFrame.Angles(0, math.rad(90), 0))
	m.Parent = vp
	local cf = m:GetBoundingBox()
	local dir = Vector3.new(0, 0.1, 1).Unit
	local look = CFrame.lookAt(Vector3.zero, -dir)
	local R, U = look.RightVector, look.UpVector
	local t = math.tan(math.rad(15)) * 0.95
	local center, need = cf.Position, 0
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local h = p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do for _, sy in ipairs({ -1, 1 }) do for _, sz in ipairs({ -1, 1 }) do
				local q = p.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z) - center
				local along = q:Dot(dir)
				need = math.max(need, math.abs(q:Dot(R)) / t + along, math.abs(q:Dot(U)) / t + along)
			end end end
		end
	end
	local cam = Instance.new("Camera") cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(center + dir * need, center)
	cam.Parent = vp vp.CurrentCamera = cam
	local z = vp.ZIndex vp.ZIndex = z + 1
	for _, d in ipairs({ { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }) do
		local cp = vp:Clone() cp.Name = "Outline" cp.ImageColor3 = Color3.new(0, 0, 0) cp.ZIndex = z
		cp.Position = vp.Position + UDim2.fromOffset(d[1] * 3, d[2] * 3)
		cp.CurrentCamera = cp:FindFirstChildOfClass("Camera") cp.Parent = vp.Parent
	end
end

-- build cards (cheapest first)
local list = rods:GetChildren()
table.sort(list, function(a, b) return (a:GetAttribute("Order") or 0) < (b:GetAttribute("Order") or 0) end)
local cards = {}
for _, rod in ipairs(list) do
	local card = template:Clone()
	card.Name = rod.Name
	card.Visible = true
	card.LayoutOrder = rod:GetAttribute("Order") or 0
	local rarity = rod:GetAttribute("Rarity") or "Common"
	card.Rarity.Text = rarity
	card.Rarity.TextColor3 = RARITY_COLORS[rarity] or Color3.new(1, 1, 1)
	card.Mutation.Text = rod:GetAttribute("DisplayName") or rod.Name
	card.Price.Text = money(rod:GetAttribute("Price") or 0)
	local stock = card.Mutation:Clone()
	stock.Name = "Stock"
	stock.Position = UDim2.new(0.5, 0, 0.745, 0)
	stock.Parent = card
	fillViewport(card.ViewportFrame, rod)
	local buy = card.BuyButton
	buy.Activated:Connect(function()
		click()
		local ok, msg = buyRemote:InvokeServer(rod.Name)
		local label = buy.Price
		local before = label.Text
		label.Text = ok and "BOUGHT!" or (msg == "Not enough money" and "NEED $" or (msg == "Sold out" and "SOLD OUT" or "NO $ YET"))
		task.delay(1.2, function() if label.Parent then label.Text = before end end)
	end)
	card.Parent = scroll
	cards[rod.Name] = card
end

local function refresh()
	for name, card in pairs(cards) do
		local s = player:GetAttribute("RodStock_" .. name) or 0
		card.Stock.Text = s > 0 and ("x" .. s .. " Stock") or "Out of stock"
		card.Stock.TextColor3 = s > 0 and Color3.fromRGB(120, 255, 120) or Color3.fromRGB(255, 90, 90)
		card.BuyButton.Price.Text = s > 0 and "BUY" or "SOLD OUT"
	end
end
player.AttributeChanged:Connect(function(a) if a:sub(1, 9) == "RodStock_" then refresh() end end)
refresh()

-- restock countdown
task.spawn(function()
	while true do
		local nextAt = shop:GetAttribute("NextRestock")
		if nextAt then
			local left = math.max(0, math.floor(nextAt - workspace:GetServerTimeNow()))
			timerLabel.Text = string.format("Restock: %d:%02d", left // 60, left % 60)
		end
		task.wait(0.25)
	end
end)

-- open from the shop stand, close with X
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt.Name == "OpenShopPrompt" then frame.Visible = true end
end)
closeButton.MouseButton1Click:Connect(function() frame.Visible = false end)

-- make sure the whole list can be scrolled (auto canvas size misses wrapped rows)
do
	local layout = scroll:FindFirstChildOfClass("UIListLayout") or scroll:FindFirstChildOfClass("UIGridLayout")
	local pad = scroll:FindFirstChildOfClass("UIPadding")
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	local function fit()
		local extra = 30
		if pad then extra += pad.PaddingTop.Offset + pad.PaddingBottom.Offset end
		scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + extra)
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
end
