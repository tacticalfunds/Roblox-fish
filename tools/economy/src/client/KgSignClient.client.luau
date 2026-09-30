-- KgSignClient (LocalScript in StarterPlayer.StarterPlayerScripts).
-- [Economy net capacity v2]
--
-- The +5 KG posts (tagged KgSign, as the place has them, or named KGsign;
-- the same two posts, each once). Each shows YOUR saved net capacity - the
-- one EconomyService keeps, sold by these posts and by the upgrade board's
-- Net Strength card alike:
--   * on the post's own price plate, PricePlate.PriceGui.Pill (found by that
--     exact path): Price "$10" (green when you can afford it, red when not),
--     SOON while paid net upgrades aren't open, MAX at the cap, "..." while
--     your money loads; Info "NET 15 KG → 20 KG" / "NET 60 KG MAX"; the Border
--     green / amber - the look GrinderUpgradesClient gave it (it no longer
--     writes the plate: this is the plate's only writer). On this client only.
--   * a post without that plate gets a small floating panel instead (dark
--     box, white outlined text): your net → next and the price.
-- Click the post (or its plate) to buy; the server checks, charges and
-- answers with a toast. Display only: values come from the server's
-- attributes (NetKg, NetKgNext, NetKgCost on you; NetKgPaidOpen on
-- ReplicatedStorage.Economy). The net is per player: the pad uses YOUR capacity.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local WHITE = Color3.new(1, 1, 1)
local LIME = Color3.fromRGB(120, 255, 40)
local GREY = Color3.fromRGB(170, 170, 175)
local OUTLINE = Color3.fromRGB(10, 10, 12)
local CAN_BUY = Color3.fromRGB(120, 255, 60) -- the plate's own colours (as GrinderUpgradesClient drew it)
local SHORT = Color3.fromRGB(255, 80, 70)
local AMBER = Color3.fromRGB(255, 205, 60)
local PANEL_W, PANEL_H = 170, 84
local MAX_DISTANCE = 45

local function label(parent: Instance, name: string, y: number, h: number, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(6, y)
	t.Size = UDim2.fromOffset(PANEL_W - 12, h)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = ""
	local s = Instance.new("UIStroke")
	s.Color = OUTLINE
	s.Thickness = 2.5
	s.Parent = t
	t.Parent = parent
	return t
end

local panels = {} -- sign -> { gui, capacity, price }
local plates = {} -- sign -> { price, info, border } (the post's own PricePlate.PriceGui.Pill)
local PLATE_WAIT = 10 -- seconds to wait for a post's PricePlate to appear

local function economy(): Instance?
	return ReplicatedStorage:FindFirstChild("Economy")
end

local function money(): number?
	local stats = player:FindFirstChild("leaderstats")
	local m = stats and stats:FindFirstChild("Money")
	local v = m and (m :: any).Value
	return if type(v) == "number" then v else nil
end

-- as GrinderUpgradesConfig.short: $950, $1.4K, $2.5M
local function short(n: number): string
	if n >= 1e9 then
		return string.format("$%gB", math.floor(n / 1e7) / 100)
	elseif n >= 1e6 then
		return string.format("$%gM", math.floor(n / 1e4) / 100)
	elseif n >= 1e3 then
		return string.format("$%gK", math.floor(n / 10) / 100)
	end
	return "$" .. tostring(n)
end

local function render()
	local kg = player:GetAttribute("NetKg")
	local nextKg = player:GetAttribute("NetKgNext")
	local cost = player:GetAttribute("NetKgCost")
	local econ = economy()
	local open = econ ~= nil and econ:GetAttribute("NetKgPaidOpen") == true
	local have = money()
	for _, p in pairs(plates) do
		local canBuy = false
		if type(kg) ~= "number" then
			p.info.Text = "NET ... KG"
			p.price.Text = "..."
		elseif type(nextKg) ~= "number" or type(cost) ~= "number" then
			p.info.Text = string.format("NET %d KG MAX", kg)
			p.price.Text = "MAX"
		else
			p.info.Text = string.format("NET %d KG → %d KG", kg, nextKg)
			p.price.Text = if open then short(cost) else "SOON"
			canBuy = open and have ~= nil and have >= cost
		end
		p.price.TextColor3 = if canBuy then CAN_BUY elseif p.price.Text == "SOON" or p.price.Text == "MAX" or p.price.Text == "..." then GREY else SHORT
		if p.border then
			p.border.Color = if canBuy then CAN_BUY else AMBER
		end
	end
	for _, p in pairs(panels) do
		if type(kg) ~= "number" then
			p.capacity.Text = "Your net"
			p.price.Text = "Loading..."
			p.price.TextColor3 = GREY
		elseif type(nextKg) ~= "number" or type(cost) ~= "number" then
			p.capacity.Text = string.format("Your net %d kg", kg)
			p.price.Text = "MAX"
			p.price.TextColor3 = GREY
		else
			p.capacity.Text = string.format("Your net %d → %d kg", kg, nextKg)
			p.price.Text = if open then "$" .. tostring(cost) else "SOON"
			p.price.TextColor3 = if open then LIME else GREY
		end
	end
end

-- The post's own plate: PricePlate.PriceGui.Pill with its Price and Info
-- labels (and Border stroke), or nil.
local function pill(sign: Instance)
	local plate = sign:FindFirstChild("PricePlate")
	local gui = plate and plate:FindFirstChild("PriceGui")
	local pillFrame = gui and gui:FindFirstChild("Pill")
	local price = pillFrame and pillFrame:FindFirstChild("Price")
	local info = pillFrame and pillFrame:FindFirstChild("Info")
	if not (price and price:IsA("GuiObject") and info and info:IsA("GuiObject")) then
		return nil
	end
	local border = pillFrame:FindFirstChild("Border")
	return { price = price, info = info, border = if border and border:IsA("UIStroke") then border else nil }
end

local function removePanel(sign: Instance)
	local p = panels[sign]
	if p then
		panels[sign] = nil
		p.gui:Destroy()
	end
end

-- waits a while for the post's plate (it may stream in after the post)
local function bindPlate(sign: Instance)
	local plate = sign:WaitForChild("PricePlate", PLATE_WAIT)
	local gui = plate and plate:WaitForChild("PriceGui", PLATE_WAIT)
	local pillFrame = gui and gui:WaitForChild("Pill", PLATE_WAIT)
	if not pillFrame or not sign:IsDescendantOf(workspace) then
		return
	end
	local found = pill(sign)
	if found then
		plates[sign] = found
		removePanel(sign)
		render()
	else
		warn("[KgSign] " .. sign:GetFullName() .. ".PricePlate.PriceGui.Pill has no Price / Info labels; using the panel")
	end
end

local signs = {}
local function addSign(sign: Instance)
	if signs[sign] then
		return
	end
	signs[sign] = true
	sign.AncestryChanged:Connect(function()
		if not sign:IsDescendantOf(workspace) then
			signs[sign] = nil
			plates[sign] = nil
			removePanel(sign)
		end
	end)
	local board = sign:FindFirstChild("Board Part")
	if board and board:IsA("BasePart") then
		local gui = Instance.new("BillboardGui")
		gui.Name = "KgSignPanel"
		gui.Adornee = board
		gui.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
		gui.StudsOffsetWorldSpace = Vector3.new(0, board.Size.Y / 2 + 2.5, 0)
		gui.MaxDistance = MAX_DISTANCE
		gui.LightInfluence = 0
		gui.ResetOnSpawn = false
		local frame = Instance.new("Frame")
		frame.Name = "Panel"
		frame.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
		frame.BackgroundColor3 = Color3.fromRGB(14, 14, 16)
		frame.BackgroundTransparency = 0.3
		frame.Parent = gui
		Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
		local border = Instance.new("UIStroke")
		border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		border.Color = Color3.new(0, 0, 0)
		border.Thickness = 1.5
		border.Parent = frame
		panels[sign] = {
			gui = gui,
			capacity = label(frame, "Capacity", 4, 26, WHITE),
			price = label(frame, "Price", 30, 30, LIME),
		}
		gui.Parent = playerGui
	end
	render()
	task.spawn(bindPlate, sign)
end

for _, sign in ipairs(CollectionService:GetTagged("KgSign")) do
	addSign(sign)
end
CollectionService:GetInstanceAddedSignal("KgSign"):Connect(addSign)
for _, child in ipairs(workspace:GetChildren()) do
	if child.Name == "KGsign" then
		addSign(child)
	end
end
workspace.ChildAdded:Connect(function(child)
	if child.Name == "KGsign" then
		addSign(child)
	end
end)

-- the price turns green / red with your money
local watchedMoney: Instance? = nil
local function watchMoney()
	local stats = player:FindFirstChild("leaderstats")
	local m = stats and stats:FindFirstChild("Money")
	if m and m ~= watchedMoney and m:IsA("ValueBase") then
		watchedMoney = m
		local value: any = m
		value.Changed:Connect(render)
		render()
	end
end
player.ChildAdded:Connect(function(c)
	if c.Name == "leaderstats" then
		c.ChildAdded:Connect(watchMoney)
		watchMoney()
	end
end)
local stats = player:FindFirstChild("leaderstats")
if stats then
	stats.ChildAdded:Connect(watchMoney)
	watchMoney()
end

player.AttributeChanged:Connect(function(name)
	if name == "NetKg" or name == "NetKgNext" or name == "NetKgCost" then
		render()
	end
end)
local function watchEconomy(econ: Instance)
	econ:GetAttributeChangedSignal("NetKgPaidOpen"):Connect(render)
	render()
end
local econ = economy()
if econ then
	watchEconomy(econ)
else
	local conn
	conn = ReplicatedStorage.ChildAdded:Connect(function(c)
		if c.Name == "Economy" then
			conn:Disconnect()
			watchEconomy(c)
		end
	end)
end
render()
