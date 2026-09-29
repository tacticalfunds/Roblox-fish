-- AquariumPanelClient (LocalScript in StarterPlayer.StarterPlayerScripts).
--
-- The aquarium's one panel at the loader pad, in the style of the rod Buy
-- panel: a dark box, bold FredokaOne white text with thick dark outlines,
-- lime outlined keycaps and buttons.
--   * top: Release Fish ([E] / gamepad X / tap) and how full the tank is
--   * below: ONE upgrade card at a time (Tank Capacity or Release Amount),
--     switched with the < > buttons, the Left / Right arrow keys or the
--     D-pad. Its button is [F] / gamepad Y / tap.
-- The server's prompts (Style = Custom, published as
-- ReplicatedStorage.AquariumCycle.<Id>Prompt) do the work: every action is
-- the prompt's own trigger, checked on the server (alive, in range,
-- cooldown); this script only draws and chooses which card's prompt is on.
-- Upgrades are shown as "Not available yet" while the server offers no
-- upgrade prompt (no currency binding): nothing can be bought from here.
-- The panel exists only while the Release prompt is shown (in range, alive)
-- and is removed when it hides or the aquarium stops.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local root = ReplicatedStorage:WaitForChild("AquariumCycle")
local Config = require(root:WaitForChild("Config"))
local Upgrades = require(root:WaitForChild("Upgrades"))

local WHITE = Color3.new(1, 1, 1)
local LIME = Color3.fromRGB(120, 255, 40)
local GREY = Color3.fromRGB(150, 150, 155)
local RED = Color3.fromRGB(235, 70, 60)
local OUTLINE = Color3.fromRGB(10, 10, 12)
local PANEL_W, PANEL_H = 250, 176 -- reference size at a 720 px tall screen
local STUDS_UP = 2.5 -- panel height above the pad
local SWITCH_ACTION = "AquariumPanelSwitch"

local CARDS = {
	{ id = "Capacity", title = "Tank Capacity", unit = "fish" },
	{ id = "ReleaseRate", title = "Release Amount", unit = "per release" },
}
local selected = 1

------------------------------------------------------------ prompts

local function promptFor(id: string): ProximityPrompt?
	local ref = root:FindFirstChild(id .. "Prompt")
	local prompt = ref and ref:IsA("ObjectValue") and ref.Value
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

-- Only the shown card's upgrade prompt is on (on this client), so [F] /
-- gamepad Y buys exactly what the card says. The server charges only through
-- the prompt it receives.
local function applySelection()
	for i, card in ipairs(CARDS) do
		local prompt = promptFor(card.id)
		if prompt then
			prompt.Enabled = i == selected
		end
	end
end

local function fire(prompt: ProximityPrompt?)
	if prompt and prompt.Parent and prompt.Enabled then
		prompt:InputHoldBegin()
		prompt:InputHoldEnd()
	end
end

------------------------------------------------------------ building blocks

local function stroke(inst: Instance, color: Color3, thickness: number, border: boolean)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	if border then
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	s.Parent = inst
	return s
end

local function label(parent: Instance, name: string, x: number, y: number, w: number, h: number, align: Enum.TextXAlignment?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextColor3 = WHITE
	t.Text = ""
	stroke(t, OUTLINE, 2.5, false)
	t.Parent = parent
	return t
end

local function button(parent: Instance, name: string, x: number, y: number, w: number, h: number): (TextButton, UIStroke)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.Position = UDim2.fromOffset(x, y)
	b.Size = UDim2.fromOffset(w, h)
	b.BackgroundColor3 = Color3.fromRGB(22, 30, 20)
	b.BackgroundTransparency = 0.1
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	local s = stroke(b, LIME, 2.5, true)
	b.Parent = parent
	return b, s
end

-- the key to show for a prompt: its keyboard key, gamepad button, or TAP
local function keyGlyph(prompt: ProximityPrompt?, inputType: any): (string, string?)
	if not prompt then
		return "", nil
	end
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		local ok, image = pcall(function()
			return UserInputService:GetImageForKeyCode(prompt.GamepadKeyCode)
		end)
		if ok and type(image) == "string" and image ~= "" then
			return "", image
		end
		local okName, name = pcall(function()
			return UserInputService:GetStringForKeyCode(prompt.GamepadKeyCode)
		end)
		return (if okName and type(name) == "string" and name ~= "" then name else prompt.GamepadKeyCode.Name), nil
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP", nil
	end
	local ok, name = pcall(function()
		return UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
	end)
	return (if ok and type(name) == "string" and name ~= "" then name else prompt.KeyboardKeyCode.Name), nil
end

local function keycap(parent: Instance, name: string, x: number, y: number, size: number)
	local key = Instance.new("Frame")
	key.Name = name
	key.Position = UDim2.fromOffset(x, y)
	key.Size = UDim2.fromOffset(size, size)
	key.BackgroundColor3 = Color3.fromRGB(22, 30, 20)
	Instance.new("UICorner", key).CornerRadius = UDim.new(0, 9)
	local s = stroke(key, LIME, 2.5, true)
	local glyph = label(key, "Glyph", 0, 0, size, size, Enum.TextXAlignment.Center)
	glyph.TextColor3 = LIME
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromScale(0.15, 0.15)
	icon.Size = UDim2.fromScale(0.7, 0.7)
	icon.Visible = false
	icon.Parent = key
	key.Parent = parent
	return { frame = key, stroke = s, glyph = glyph, icon = icon }
end

local function setKey(cap, prompt: ProximityPrompt?, inputType: any)
	local text, image = keyGlyph(prompt, inputType)
	cap.glyph.Text = text
	cap.icon.Image = image or ""
	cap.icon.Visible = image ~= nil
	cap.glyph.Visible = image == nil
end

------------------------------------------------------------ the panel

local panel = nil -- the open panel's parts, or nil

local function render()
	if not panel then
		return
	end
	local count, capacity = root:GetAttribute("TankCount"), root:GetAttribute("TankCapacity")
	if type(count) == "number" and type(capacity) == "number" then
		panel.tank.Text = string.format("%d/%d fish in tank", count, capacity)
	else
		panel.tank.Text = ""
	end
	panel.tank.TextColor3 = if root:GetAttribute("TankFull") == true then RED else WHITE
	setKey(panel.releaseKey, panel.release, panel.inputType)

	local card = CARDS[selected]
	local level = root:GetAttribute(card.id .. "Level")
	local now = Upgrades.value(Config, card.id, level)
	local cost = Upgrades.nextCost(Config, card.id, level)
	local prompt = promptFor(card.id)
	local available = root:GetAttribute("UpgradesAvailable") == true and prompt ~= nil
	panel.title.Text = card.title
	local canBuy = false
	if not available then
		panel.value.Text = string.format("Now %d %s", now, card.unit)
		panel.action.Text = "Not available yet"
	elseif cost == nil then
		panel.value.Text = string.format("%d %s (max)", now, card.unit)
		panel.action.Text = "Maxed"
	else
		panel.value.Text = string.format("%d → %d %s", now, Upgrades.value(Config, card.id, level + 1), card.unit)
		panel.action.Text = "Upgrade  $" .. tostring(cost)
		canBuy = true
	end
	panel.canBuy = canBuy
	panel.action.TextColor3 = if canBuy then LIME else GREY
	panel.actionStroke.Color = if canBuy then LIME else GREY
	panel.upgradeKey.frame.Visible = canBuy
	if canBuy then
		setKey(panel.upgradeKey, prompt, panel.inputType)
	end
end

local function switch(step: number)
	selected = (selected - 1 + step) % #CARDS + 1
	applySelection()
	render()
end

local function hidePanel()
	if panel then
		ContextActionService:UnbindAction(SWITCH_ACTION)
		local gui = panel.gui
		panel = nil
		gui:Destroy()
	end
end

local function showPanel(release: ProximityPrompt, inputType: any)
	hidePanel()
	local camera = workspace.CurrentCamera
	local scale = math.clamp((camera and camera.ViewportSize.Y or 720) / 720, 0.8, 1.4)
	local gui = Instance.new("BillboardGui")
	gui.Name = "AquariumPanel"
	gui.Adornee = release.Parent
	gui.Size = UDim2.fromOffset(PANEL_W * scale, PANEL_H * scale)
	gui.StudsOffsetWorldSpace = Vector3.new(0, STUDS_UP, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Active = true -- buttons are tappable / clickable
	local frame = Instance.new("Frame")
	frame.Name = "Panel"
	frame.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	frame.BackgroundColor3 = Color3.fromRGB(14, 14, 16)
	frame.BackgroundTransparency = 0.3
	frame.Parent = gui
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = scale
	uiScale.Parent = frame
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
	stroke(frame, Color3.new(0, 0, 0), 1.5, true)

	-- Release Fish (always usable; the server says when the tank is empty or recharging)
	local releaseButton = button(frame, "Release", 8, 8, PANEL_W - 16, 58)
	local releaseKey = keycap(releaseButton, "Key", 7, 7, 44)
	label(releaseButton, "Action", 60, 5, PANEL_W - 84, 28).Text = "Release Fish"
	local tank = label(releaseButton, "Tank", 60, 33, PANEL_W - 84, 20)

	-- one upgrade card
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundTransparency = 1
	card.Position = UDim2.fromOffset(8, 72)
	card.Size = UDim2.fromOffset(PANEL_W - 16, PANEL_H - 80)
	card.Parent = frame
	local prev = button(card, "Prev", 0, 4, 30, 40)
	label(prev, "Arrow", 0, 4, 30, 32, Enum.TextXAlignment.Center).Text = "<"
	local nextB = button(card, "Next", PANEL_W - 46, 4, 30, 40)
	label(nextB, "Arrow", 0, 4, 30, 32, Enum.TextXAlignment.Center).Text = ">"
	local title = label(card, "Title", 36, 0, PANEL_W - 88, 26, Enum.TextXAlignment.Center)
	local value = label(card, "Value", 36, 26, PANEL_W - 88, 20, Enum.TextXAlignment.Center)
	local actionButton, actionStroke = button(card, "Upgrade", 0, 50, PANEL_W - 16, 42)
	local upgradeKey = keycap(actionButton, "Key", 5, 4, 34)
	local action = label(actionButton, "Action", 46, 7, PANEL_W - 70, 28)

	panel = {
		gui = gui,
		release = release,
		inputType = inputType,
		tank = tank,
		releaseKey = releaseKey,
		title = title,
		value = value,
		action = action,
		actionStroke = actionStroke,
		upgradeKey = upgradeKey,
		canBuy = false,
	}
	releaseButton.Activated:Connect(function()
		fire(release)
	end)
	prev.Activated:Connect(function()
		switch(-1)
	end)
	nextB.Activated:Connect(function()
		switch(1)
	end)
	actionButton.Activated:Connect(function()
		if panel and panel.canBuy then
			fire(promptFor(CARDS[selected].id))
		end
	end)
	ContextActionService:BindAction(SWITCH_ACTION, function(_, state, input)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		local key = input.KeyCode
		switch(if key == Enum.KeyCode.Left or key == Enum.KeyCode.DPadLeft then -1 else 1)
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight)
	gui.Parent = playerGui
	render()
end

------------------------------------------------------------ follow the server's prompts

local hooked = nil -- { prompt, conns }

local function unhook()
	if hooked then
		for _, c in ipairs(hooked.conns) do
			c:Disconnect()
		end
		hooked = nil
	end
	hidePanel()
end

local function hook()
	local release = promptFor("Release")
	applySelection()
	if hooked and hooked.prompt == release then
		render()
		return
	end
	unhook()
	if not release then
		return
	end
	local conns = {}
	hooked = { prompt = release, conns = conns }
	table.insert(conns, release.PromptShown:Connect(function(inputType)
		showPanel(release, inputType)
	end))
	table.insert(conns, release.PromptHidden:Connect(hidePanel))
	table.insert(conns, release.Destroying:Connect(unhook))
end

local function watchRef(child: Instance)
	if child:IsA("ObjectValue") and string.sub(child.Name, -6) == "Prompt" then
		child.Changed:Connect(hook) -- a reference can replicate after its object
		hook()
	end
end

root.ChildAdded:Connect(watchRef)
root.ChildRemoved:Connect(function(child)
	if child.Name == "ReleasePrompt" then
		unhook()
	else
		render()
	end
end)
root.AttributeChanged:Connect(render)
for _, child in ipairs(root:GetChildren()) do
	watchRef(child)
end
hook()
