-- Rod shop UI: opens from the shop stand prompt, shows each rod with price + stock, restock countdown.
--
-- [Economy rods v1] Changes marked "Rods": each card shows the rod's real
-- price and benefit and whether you OWN it / have it EQUIPPED (the server's
-- RodOwned_<id> / EquippedRod attributes); the button says what pressing
-- does (BUY / EQUIP / EQUIPPED / SOON / SOLD OUT), shows "..." while the
-- server answers, then the server's real result; the full message appears
-- on a status line under the cards. The server checks and charges; nothing
-- here decides anything.
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

-- Rods: the economy root (RodShopPaidOpen) and a status line under the cards
local econ = RS:FindFirstChild("Economy")
local LIME, GREEN, RED = Color3.fromRGB(120, 255, 40), Color3.fromRGB(120, 255, 120), Color3.fromRGB(255, 90, 90)
local status = Instance.new("TextLabel")
status.Name = "RodShopStatus"
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.Position = UDim2.fromScale(0.5, 0.955)
status.Size = UDim2.fromScale(0.9, 0.065)
status.BackgroundTransparency = 1
status.Font = Enum.Font.FredokaOne
status.TextScaled = true
status.TextColor3 = Color3.new(1, 1, 1)
status.Text = ""
status.ZIndex = 5
do
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = Color3.fromRGB(10, 10, 12)
	st.Parent = status
end
status.Parent = frame
-- the server's replies -> short button text (anything else: TRY AGAIN)
local SHORT = {
	["Not enough money"] = "NEED $",
	["Sold out"] = "SOLD OUT",
	["The rod shop opens soon"] = "SOON",
	["Walk back to the rod shop to buy"] = "TOO FAR",
	["Your money is still loading - try again in a moment"] = "LOADING",
	["Couldn't save the purchase - you were not charged. Try again."] = "NOT SAVED",
	["One moment - still saving"] = "SAVING",
	["Slow down a little"] = "WAIT",
	["You already own that rod"] = "OWNED",
	["You can't do that right now"] = "NOT NOW",
	["The rod shop is unavailable right now"] = "CLOSED",
	["Your saved rods couldn't be read, so buying rods is off this session"] = "UNAVAILABLE",
}
local busy, flash = {}, {} -- rod name -> waiting for the server / { text, untilT }
local statusUntil = 0
local refresh -- defined below
local function paidOpen()
	return econ ~= nil and econ:GetAttribute("RodShopPaidOpen") == true
end
local function showStatus(text, seconds)
	status.Text = text
	statusUntil = os.clock() + seconds
	task.delay(seconds, function()
		if os.clock() >= statusUntil then
			refresh()
		end
	end)
end
-- one request per rod at a time; the equipped rod sends nothing
local function buyPressed(name)
	if busy[name] or player:GetAttribute("EquippedRod") == name then
		return
	end
	busy[name] = true
	refresh()
	local reached, ok, msg = pcall(function()
		return buyRemote:InvokeServer(name)
	end)
	busy[name] = nil
	local text
	if not reached then
		text, msg = "TRY AGAIN", "Couldn't reach the server - try again"
	elseif ok == true then
		text = if type(msg) == "string" and string.sub(msg, 1, 6) == "Bought" then "BOUGHT!" else "EQUIPPED"
	else
		text = SHORT[msg] or "TRY AGAIN"
	end
	flash[name] = { text = text, untilT = os.clock() + 1.6 }
	if type(msg) == "string" then
		showStatus(msg, 3)
	end
	refresh()
	task.delay(1.7, function()
		refresh()
	end)
end

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
		buyPressed(rod.Name) -- Rods: the server's real answer, see buyPressed
	end)
	card.Parent = scroll
	cards[rod.Name] = card
end

-- Rods: price or OWNED, benefit, and what the button does, all from the
-- server's attributes (they can change while the shop is open)
function refresh()
	local open = paidOpen()
	local now = os.clock()
	for name, card in pairs(cards) do
		local rod = rods:FindFirstChild(name)
		local owned = player:GetAttribute("RodOwned_" .. name) ~= nil
		local equipped = player:GetAttribute("EquippedRod") == name
		local s = player:GetAttribute("RodStock_" .. name) or 0
		local price = rod and rod:GetAttribute("Price") or 0
		local benefit = rod and rod:GetAttribute("Benefit")
		card.Price.Text = if owned then "OWNED" else money(price)
		local soldOut = not owned and s <= 0
		if type(benefit) == "string" then
			card.Stock.Text = if soldOut then benefit .. " - sold out" else benefit
		else
			card.Stock.Text = s > 0 and ("x" .. s .. " Stock") or "Out of stock"
		end
		card.Stock.TextColor3 = if soldOut then RED else GREEN
		local f = flash[name]
		local label
		if busy[name] then
			label = "..."
		elseif f and now < f.untilT then
			label = f.text
		elseif equipped then
			label = "EQUIPPED"
		elseif owned then
			label = "EQUIP"
		elseif not open then
			label = "SOON"
		elseif soldOut then
			label = "SOLD OUT"
		else
			label = "BUY"
		end
		card.BuyButton.Price.Text = label
		card.BuyButton.Price.TextColor3 = if equipped then LIME else Color3.new(1, 1, 1)
	end
	if now >= statusUntil then
		status.Text = if econ == nil
			then "The rod shop is unavailable right now"
			elseif not open then "Buying opens soon - you can equip rods you own"
			else ""
	end
end
player.AttributeChanged:Connect(function(a)
	if a:sub(1, 9) == "RodStock_" or a:sub(1, 9) == "RodOwned_" or a == "EquippedRod" then refresh() end
end)
for _, rod in ipairs(rods:GetChildren()) do
	rod.AttributeChanged:Connect(function(a)
		if a == "Price" or a == "Benefit" then refresh() end
	end)
end
local function watchEconomy(e)
	econ = e
	e:GetAttributeChangedSignal("RodShopPaidOpen"):Connect(refresh)
	refresh()
end
if econ then
	watchEconomy(econ)
else
	RS.ChildAdded:Connect(function(c)
		if c.Name == "Economy" and not econ then watchEconomy(c) end
	end)
end
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
