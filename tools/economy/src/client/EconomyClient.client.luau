-- EconomyClient (LocalScript in StarterPlayerScripts). Shows EconomyService
-- notices (money loading problems, grinder backed up, purchase results) as
-- a small toast. Display only; the server decides everything.
local Players = game:GetService("Players")
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
