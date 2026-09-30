-- UpgradeBoardClient (LocalScript in StarterPlayer.StarterPlayerScripts).
-- [Economy upgrade board v2: Rod Luck]
--
-- Draws the four-upgrade board for THIS player on Workspace.Board.Main
-- (a copy of its SurfaceGui in PlayerGui, adorned to Main; the original is
-- only hidden on this client, never changed in the place):
--   2 x 2 cards in a wooden frame, white outlined text, a themed icon and a
--   green Buy button on each:
--     Net Strength (pink)   15kg > 20kg    $10
--     Rod Luck (lime)       1x > 2x        $10
--     Meat Price (cyan)     1x > 2x        SOON
--     Faster Reels (amber)  1x > 1.2x      SOON
-- Net Strength shows YOUR saved net (the same one the KGsign posts sell);
-- Rod Luck YOUR saved luck level. Each: current > next and its price, MAX
-- at the last level, SOON while those paid upgrades aren't open, "..."
-- while your money loads, the price in red when you can't afford it. Pressing (mouse, touch or gamepad) shows SAVING... while
-- the server checks, charges and saves, then its real answer for a moment
-- (BOUGHT! / NEED $ / TOO FAR / NOT SAVED / ...); the full message is the
-- server's toast. The client decides nothing.
--
-- The board is found by its exact path: exactly one Workspace child named
-- Board, one Main part in it, one SurfaceGui on Main, one bord3 in that.
-- The old cards (two Frames both named "Frame") are never looked up by
-- name: every Frame and the list layout are removed from the copy and the
-- four cards are built new. If the board isn't there (yet), nothing is
-- drawn; it is looked for again every second (the board can stream in/out).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local WHITE = Color3.new(1, 1, 1)
local OUTLINE = Color3.fromRGB(10, 10, 12)
local GREY = Color3.fromRGB(200, 200, 205)
local SHORT = Color3.fromRGB(255, 95, 95)
local WOOD = Color3.fromRGB(122, 78, 42)
local WOOD_DARK = Color3.fromRGB(70, 42, 20)
local BUY_TOP = Color3.fromRGB(208, 231, 0) -- the board's own Buy gradient
local BUY_BOTTOM = Color3.fromRGB(0, 202, 0)
local BUY_EDGE = Color3.fromRGB(0, 74, 0)
local FLASH_SECONDS = 1.6

local CARDS = {
	{ id = "NetStrength", title = "Net Strength", icon = "🥅", color = Color3.fromRGB(255, 120, 190) },
	{ id = "RodLuck", title = "Rod Luck", icon = "🍀", color = Color3.fromRGB(150, 225, 45), value = "1x > 2x", upgrade = true },
	{ id = "MeatPrice", title = "Meat Price", icon = "🥩", color = Color3.fromRGB(45, 205, 235), value = "1x > 2x" },
	{ id = "FasterReels", title = "Faster Reels", icon = "⚡", color = Color3.fromRGB(255, 180, 35), value = "1x > 1.2x" },
}

------------------------------------------------------------ finding the board

local function only(parent: Instance, name: string, class: string): Instance?
	local found = nil
	local count = 0
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == name then
			count += 1
			found = child
		end
	end
	if count == 1 and (found :: Instance):IsA(class) then
		return found
	end
	return nil
end

-- (Main, its SurfaceGui, bord3) or nil
local function findBoard(): (BasePart?, SurfaceGui?, Frame?)
	local board = only(workspace, "Board", "Model")
	local main = board and only(board, "Main", "BasePart")
	local gui = main and only(main, "SurfaceGui", "SurfaceGui")
	local bord = gui and only(gui, "bord3", "Frame")
	if not bord then
		return nil, nil, nil
	end
	return main :: BasePart, gui :: SurfaceGui, bord :: Frame
end

------------------------------------------------------------ building

local function outlined(t: TextLabel | TextButton, thickness: number)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = WHITE
	t.BackgroundTransparency = 1
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Color = OUTLINE
	s.Thickness = thickness
	s.Parent = t
end

local function label(parent: Instance, name: string, text: string, pos: UDim2, size: UDim2): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Position = pos
	t.Size = size
	t.Text = text
	outlined(t, 3)
	t.Parent = parent
	return t
end

local cards = {} -- id -> { value, button, price, pending, flashUntil }

local function buildCard(parent: Instance, def, order: number)
	local card = Instance.new("Frame")
	card.Name = def.id
	card.LayoutOrder = order
	card.BackgroundColor3 = def.color
	card.BackgroundTransparency = 0
	Instance.new("UICorner", card).CornerRadius = UDim.new(0.08, 0)
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = WOOD_DARK
	edge.Thickness = 5
	edge.Parent = card
	local icon = label(card, "Icon", def.icon, UDim2.fromScale(0.03, 0.12), UDim2.fromScale(0.25, 0.76))
	icon.TextColor3 = WHITE
	label(card, "Title", def.title, UDim2.fromScale(0.3, 0.06), UDim2.fromScale(0.67, 0.28))
	local value = label(card, "Value", def.value or "", UDim2.fromScale(0.3, 0.36), UDim2.fromScale(0.67, 0.24))

	local button = Instance.new("TextButton")
	button.Name = "Buy"
	button.Position = UDim2.fromScale(0.3, 0.64)
	button.Size = UDim2.fromScale(0.67, 0.3)
	button.BackgroundColor3 = WHITE
	button.AutoButtonColor = true
	button.Text = ""
	Instance.new("UICorner", button).CornerRadius = UDim.new(0.25, 0)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(BUY_TOP, BUY_BOTTOM)
	grad.Rotation = 90
	grad.Parent = button
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = BUY_EDGE
	rim.Thickness = 3
	rim.Parent = button
	local price = Instance.new("TextLabel")
	price.Name = "Price"
	price.Position = UDim2.fromScale(0.05, 0.08)
	price.Size = UDim2.fromScale(0.9, 0.84)
	price.Text = "..."
	outlined(price, 2.5)
	price.Parent = button
	button.Parent = card

	cards[def.id] = { value = value, button = button, price = price, grad = grad, pending = false, flashUntil = 0 }
	card.Parent = parent
end

------------------------------------------------------------ showing

local function economy(): Instance?
	return ReplicatedStorage:FindFirstChild("Economy")
end

local function money(): number?
	local stats = player:FindFirstChild("leaderstats")
	local m = stats and stats:FindFirstChild("Money")
	if m and m:IsA("ValueBase") and type((m :: any).Value) == "number" then
		return (m :: any).Value
	end
	return nil
end

local function setButton(c, text: string, color: Color3, live: boolean)
	c.price.Text = text
	c.price.TextColor3 = color
	c.grad.Enabled = live
	c.button.BackgroundColor3 = if live then WHITE else Color3.fromRGB(120, 120, 125)
end

-- one card's button (the server's answer stays up while it flashes)
local function showState(c, remote: Instance?, loaded: boolean, maxed: boolean, open: boolean, cost: number?)
	if c.pending then
		setButton(c, "SAVING...", WHITE, true)
	elseif os.clock() < c.flashUntil then
		-- the server's answer stays up for a moment
	elseif not remote then
		setButton(c, "OFF", GREY, false)
	elseif not loaded then
		setButton(c, "...", GREY, false)
	elseif maxed or not cost then
		setButton(c, "MAX", GREY, false)
	elseif not open then
		setButton(c, "SOON", GREY, false)
	else
		local have = money()
		setButton(c, "$" .. tostring(cost), if have and have < cost then SHORT else WHITE, true)
	end
end

local function times(v: number): string
	return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")) .. "x"
end

local function render()
	local econ = economy()
	local remote = econ and econ:FindFirstChild("UpgradeAction")
	-- Net Strength: the saved net capacity
	local net = cards.NetStrength
	if net then
		local kg = player:GetAttribute("NetKg")
		local nextKg = player:GetAttribute("NetKgNext")
		local cost = player:GetAttribute("NetKgCost")
		local maxed = type(nextKg) ~= "number" or type(cost) ~= "number"
		if type(kg) ~= "number" then
			net.value.Text = "Net"
		elseif maxed then
			net.value.Text = string.format("%dkg MAX", kg)
		else
			net.value.Text = string.format("%dkg > %dkg", kg, nextKg)
		end
		showState(net, remote, type(kg) == "number", maxed, econ ~= nil and econ:GetAttribute("NetKgPaidOpen") == true,
			if type(cost) == "number" then cost else nil)
	end
	local upgradesOpen = econ ~= nil and econ:GetAttribute("UpgradesPaidOpen") == true
	for _, def in ipairs(CARDS) do
		local c = cards[def.id]
		if c and def.upgrade then
			-- a board upgrade: the saved level's value (Upg<Id>, Upg<Id>Next, Upg<Id>Cost)
			local v = player:GetAttribute("Upg" .. def.id)
			local nextV = player:GetAttribute("Upg" .. def.id .. "Next")
			local cost = player:GetAttribute("Upg" .. def.id .. "Cost")
			local maxed = type(nextV) ~= "number" or type(cost) ~= "number"
			if type(v) ~= "number" then
				c.value.Text = def.value
			elseif maxed then
				c.value.Text = times(v) .. " MAX"
			else
				c.value.Text = times(v) .. " > " .. times(nextV)
			end
			showState(c, remote, type(v) == "number", maxed, upgradesOpen, if type(cost) == "number" then cost else nil)
		elseif c and def.id ~= "NetStrength" and not c.pending and os.clock() >= c.flashUntil then
			setButton(c, "SOON", GREY, false) -- not sold yet
		end
	end
end

-- a short word for the server's answer (the toast has the whole message)
local function short(ok: boolean, message: string?): string
	if ok then
		return "BOUGHT!"
	end
	local m = string.lower(message or "")
	if string.find(m, "not enough money", 1, true) then
		return "NEED $"
	elseif string.find(m, "walk up", 1, true) then
		return "TOO FAR"
	elseif string.find(m, "maximum", 1, true) then
		return "MAX"
	elseif string.find(m, "not charged", 1, true) then
		return "NOT SAVED"
	elseif string.find(m, "loading", 1, true) or string.find(m, "saving", 1, true) or string.find(m, "slow down", 1, true) then
		return "WAIT"
	elseif string.find(m, "soon", 1, true) then
		return "SOON"
	end
	return "NO"
end

local function press(id: string)
	local c = cards[id]
	if not c or c.pending then
		return -- one request per card at a time
	end
	local econ = economy()
	local remote = econ and econ:FindFirstChild("UpgradeAction")
	if not (remote and remote:IsA("RemoteFunction")) then
		render()
		return
	end
	c.pending = true
	render()
	local ran, ok, message = pcall(function()
		return (remote :: RemoteFunction):InvokeServer(id)
	end)
	c.pending = false
	if not ran then
		ok, message = false, "Couldn't reach the server"
	end
	c.flashUntil = os.clock() + FLASH_SECONDS
	setButton(c, short(ok == true, message), if ok == true then WHITE else SHORT, ok == true)
	task.delay(FLASH_SECONDS + 0.05, render)
end

------------------------------------------------------------ binding

local shown: SurfaceGui? = nil
local shownFor: BasePart? = nil

local function build(main: BasePart, original: SurfaceGui)
	local copy = original:Clone()
	copy.Name = "UpgradeBoard"
	copy.Adornee = main
	copy.ResetOnSpawn = false
	copy.Enabled = true
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy() -- nothing from the place runs in the copy
		end
	end
	local frame = only(copy, "bord3", "Frame") :: Frame
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("UIListLayout") then
			child:Destroy() -- the old cards and their list layout
		end
	end
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = WOOD
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = WOOD_DARK
	rim.Thickness = 8
	rim.Parent = frame
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.VerticalAlignment = Enum.VerticalAlignment.Center
	grid.CellPadding = UDim2.fromScale(0.02, 0.04)
	grid.CellSize = UDim2.fromScale(0.48, 0.46)
	grid.Parent = frame
	cards = {}
	for i, def in ipairs(CARDS) do
		buildCard(frame, def, i)
		local id = def.id
		cards[id].button.Activated:Connect(function()
			press(id)
		end)
	end
	original.Enabled = false -- this client only
	copy.Parent = playerGui
	shown, shownFor = copy, main
	render()
end

local function unbind()
	if shown then
		shown:Destroy()
	end
	shown, shownFor = nil, nil
	cards = {}
end

task.spawn(function()
	while true do
		if shownFor and not shownFor:IsDescendantOf(workspace) then
			unbind() -- streamed out or removed; look for it again
		end
		if not shown then
			local main, original = findBoard()
			if main and original then
				build(main, original)
			end
		end
		task.wait(1)
	end
end)

------------------------------------------------------------ updates

player.AttributeChanged:Connect(function(name)
	if name == "NetKg" or name == "NetKgNext" or name == "NetKgCost" or string.sub(name, 1, 3) == "Upg" then
		render()
	end
end)
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
local function watchEconomy(econ: Instance)
	econ:GetAttributeChangedSignal("NetKgPaidOpen"):Connect(render)
	econ:GetAttributeChangedSignal("UpgradesPaidOpen"):Connect(render)
	econ.ChildAdded:Connect(render) -- UpgradeAction appears
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
