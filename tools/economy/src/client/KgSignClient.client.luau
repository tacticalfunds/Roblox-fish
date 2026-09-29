-- KgSignClient (LocalScript in StarterPlayer.StarterPlayerScripts).
-- [Economy net capacity v1]
--
-- A small panel above every +5 KG sign (every Workspace child named KGsign),
-- in the style of the rod Buy panel: dark box, bold FredokaOne white text
-- with dark outlines, the price in lime. It shows YOUR net capacity and what
-- the next +5 kg costs (15 → 20 kg, $25), MAX at the cap, SOON while paid
-- upgrades aren't open, and the shared net's current capacity. Click the
-- sign itself (its ClickDetector) to buy; the server checks and charges and
-- answers with a toast. Display only: values come from the server's
-- attributes (NetKg, NetKgNext, NetKgCost on you; NetKgPaidOpen on
-- ReplicatedStorage.Economy; MaxWeight on Workspace.NetLift).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local WHITE = Color3.new(1, 1, 1)
local LIME = Color3.fromRGB(120, 255, 40)
local GREY = Color3.fromRGB(170, 170, 175)
local OUTLINE = Color3.fromRGB(10, 10, 12)
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

local panels = {} -- sign -> { gui, capacity, price, shared }

local function economy(): Instance?
	return ReplicatedStorage:FindFirstChild("Economy")
end

local function render()
	local kg = player:GetAttribute("NetKg")
	local nextKg = player:GetAttribute("NetKgNext")
	local cost = player:GetAttribute("NetKgCost")
	local econ = economy()
	local open = econ ~= nil and econ:GetAttribute("NetKgPaidOpen") == true
	local netLift = workspace:FindFirstChild("NetLift")
	local shared = netLift and netLift:GetAttribute("MaxWeight")
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
		p.shared.Text = if type(shared) == "number" then string.format("Net now: %d kg", shared) else ""
	end
end

local function addSign(sign: Instance)
	if panels[sign] or sign.Name ~= "KGsign" then
		return
	end
	local board = sign:FindFirstChild("Board Part")
	if not (board and board:IsA("BasePart")) then
		return
	end
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
	local p = {
		gui = gui,
		capacity = label(frame, "Capacity", 4, 26, WHITE),
		price = label(frame, "Price", 30, 30, LIME),
		shared = label(frame, "Shared", 60, 20, WHITE),
	}
	panels[sign] = p
	sign.AncestryChanged:Connect(function()
		if not sign:IsDescendantOf(workspace) and panels[sign] == p then
			panels[sign] = nil
			gui:Destroy()
		end
	end)
	gui.Parent = playerGui
	render()
end

for _, child in ipairs(workspace:GetChildren()) do
	addSign(child)
end
workspace.ChildAdded:Connect(addSign)

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
local function watchNet(netLift: Instance)
	netLift:GetAttributeChangedSignal("MaxWeight"):Connect(render)
	render()
end
local netLift = workspace:FindFirstChild("NetLift")
if netLift then
	watchNet(netLift)
end
render()
