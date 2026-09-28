-- EconomyClient (LocalScript in StarterPlayerScripts).
--   * toast for EconomyService notices (money loading, purchase results)
--   * the Buy/Pass panel for the local player's own rod-fish offers
-- Display only: prices, ownership, range, funds and tank space are all
-- decided and checked on the server; the buttons just send (offerId, action).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local root = ReplicatedStorage:WaitForChild("Economy")

local gui = Instance.new("ScreenGui")
gui.Name = "EconomyNotices"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 120)
label.Size = UDim2.fromOffset(460, 44)
label.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
label.BackgroundTransparency = 0.2
label.Font = Enum.Font.FredokaOne
label.TextScaled = true
label.TextColor3 = Color3.new(1, 1, 1)
label.Visible = false
label.Parent = gui
Instance.new("UICorner", label).CornerRadius = UDim.new(0, 10)
local padding = Instance.new("UIPadding", label)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)

local COLORS = {
	info = Color3.fromRGB(20, 30, 45),
	success = Color3.fromRGB(30, 110, 60),
	warn = Color3.fromRGB(140, 60, 30),
}
local token = 0
local function show(text: any, kind: any)
	if type(text) ~= "string" then
		return
	end
	token += 1
	local mine = token
	label.Text = text
	label.BackgroundColor3 = COLORS[kind] or COLORS.info
	label.Visible = true
	task.delay(3, function()
		if mine == token then
			label.Visible = false
		end
	end)
end

local notice = root:WaitForChild("Notice")
if notice:IsA("RemoteEvent") then
	notice.OnClientEvent:Connect(show)
end

------------------------------------------------------------ Buy/Pass panel

local offersFolder = root:WaitForChild("Offers")
local offerAction = root:WaitForChild("OfferAction")

local panel = Instance.new("Frame")
panel.Name = "RodOffers"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -24)
panel.Size = UDim2.fromOffset(460, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundTransparency = 1
panel.Parent = gui
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.VerticalAlignment = Enum.VerticalAlignment.Bottom
list.Parent = panel

local VARIANT_COLOR = {
	Gold = Color3.fromRGB(255, 205, 60),
	Silver = Color3.fromRGB(215, 230, 245),
}

local rows = {} -- offer Configuration -> row Frame

local function button(parent: Instance, text: string, color: Color3, x: number): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, x, 0.5, 0)
	b.Size = UDim2.fromOffset(78, 38)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.FredokaOne
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	return b
end

local function addRow(cfg: Instance)
	if rows[cfg] or not cfg:IsA("Configuration") then
		return
	end
	if cfg:GetAttribute("CasterUserId") ~= player.UserId then
		return -- someone else's catch: no controls
	end
	local id = cfg:GetAttribute("OfferId")
	local variant = cfg:GetAttribute("Variant")
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 50)
	row.BackgroundColor3 = Color3.fromRGB(20, 30, 45)
	row.BackgroundTransparency = 0.15
	row.LayoutOrder = if type(id) == "number" then id else 0
	row.Parent = panel
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(12, 0)
	label.Size = UDim2.new(1, -200, 1, 0)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextColor3 = VARIANT_COLOR[variant] or Color3.new(1, 1, 1)
	label.Parent = row
	local buy = button(row, "Buy", Color3.fromRGB(40, 160, 70), -92)
	local pass = button(row, "Pass", Color3.fromRGB(150, 60, 50), -8)
	local busy = false
	local function send(action: string)
		if busy then
			return
		end
		busy = true
		buy.Active, pass.Active = false, false
		local ok, _, text = pcall(function()
			return offerAction:InvokeServer(id, action)
		end)
		if not ok then
			show("Couldn't reach the server - try again", "warn")
		elseif type(text) == "string" and action == "pass" then
			show(text, "info")
		end
		busy = false
		if row.Parent then
			buy.Active, pass.Active = true, true
		end
	end
	buy.Activated:Connect(function()
		send("buy")
	end)
	pass.Activated:Connect(function()
		send("pass")
	end)
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not row.Parent then
			conn:Disconnect()
			return
		end
		local left = math.max(0, (cfg:GetAttribute("ExpiresAt") or 0) - workspace:GetServerTimeNow())
		local prefix = if variant == "Gold" then "GOLD " elseif variant == "Silver" then "SILVER " else ""
		label.Text = string.format(
			"%s%s - %d Money  (%ds)",
			prefix,
			tostring(cfg:GetAttribute("FishName")),
			tonumber(cfg:GetAttribute("Price")) or 0,
			math.ceil(left)
		)
	end)
	rows[cfg] = row
end

local function removeRow(cfg: Instance)
	local row = rows[cfg]
	rows[cfg] = nil
	if row then
		row:Destroy()
	end
end

for _, cfg in ipairs(offersFolder:GetChildren()) do
	addRow(cfg)
end
offersFolder.ChildAdded:Connect(function(cfg)
	-- attributes replicate with the instance; wait a frame to be safe
	task.defer(addRow, cfg)
end)
offersFolder.ChildRemoved:Connect(removeRow)
