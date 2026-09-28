-- EconomyClient (LocalScript in StarterPlayerScripts).
--   * toast for EconomyService notices (money loading, purchase results)
--   * the buy prompt for the local player's OWN rod catches: a ProximityPrompt
--     (Style = Custom) on the rod stand, with a small world-anchored panel
--     ([E] + fish name + "Buy"). Keyboard E, the gamepad button and tapping
--     the panel all go through the prompt's own activation.
-- Display only: prices, ownership, range, expiry, funds and tank space are
-- all decided and checked on the server; a trigger just sends (offerId, "buy").
-- Other players' catches get no prompt (the server refuses them anyway).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

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

------------------------------------------------------------ buy prompt

local offerAction = root:WaitForChild("OfferAction")
local playerGui = player:WaitForChild("PlayerGui")

local LIME = Color3.fromRGB(120, 255, 40)
local OUTLINE = Color3.fromRGB(10, 10, 12)
local PANEL_W, PANEL_H = 140, 75 -- reference size at a 720 px tall screen

local function outlined(inst: Instance, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = thickness
	stroke.Parent = inst
end

local function text(
	parent: Instance,
	name: string,
	value: string,
	color: Color3,
	x: number,
	y: number,
	w: number,
	h: number
): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextColor3 = color
	t.Text = value
	outlined(t, 2)
	t.Parent = parent
	return t
end

local function keyLabel(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): (string?, string?)
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		local ok, image = pcall(function()
			return UserInputService:GetImageForKeyCode(prompt.GamepadKeyCode)
		end)
		if ok and type(image) == "string" and image ~= "" then
			return nil, image
		end
		local okName, name = pcall(function()
			return UserInputService:GetStringForKeyCode(prompt.GamepadKeyCode)
		end)
		return (if okName and type(name) == "string" and name ~= "" then name else "X"), nil
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP", nil
	end
	local ok, name = pcall(function()
		return UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
	end)
	return (if ok and type(name) == "string" and name ~= "" then name else "E"), nil
end

-- The reference panel: dark translucent box with a thin black border; a lime
-- outlined keycap on the left; fish name (white) over "Buy" (lime) on the right.
local function buildPanel(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): BillboardGui
	local camera = workspace.CurrentCamera
	local scale = math.clamp((camera and camera.ViewportSize.Y or 720) / 720, 0.8, 1.4)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BuyPromptPanel"
	gui.Adornee = prompt.Parent
	gui.Size = UDim2.fromOffset(PANEL_W * scale, PANEL_H * scale)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Active = true -- the panel is tappable / clickable
	local frame = Instance.new("TextButton")
	frame.Name = "Panel"
	frame.Text = ""
	frame.AutoButtonColor = false
	frame.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	frame.BackgroundColor3 = Color3.fromRGB(14, 14, 16)
	frame.BackgroundTransparency = 0.3
	frame.Parent = gui
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = scale
	uiScale.Parent = frame
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)
	local border = Instance.new("UIStroke")
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Color = Color3.new(0, 0, 0)
	border.Thickness = 1.5
	border.Parent = frame

	local key = Instance.new("Frame")
	key.Name = "Key"
	key.Position = UDim2.fromOffset(10, 16)
	key.Size = UDim2.fromOffset(43, 43)
	key.BackgroundColor3 = Color3.fromRGB(22, 30, 20)
	key.Parent = frame
	Instance.new("UICorner", key).CornerRadius = UDim.new(0, 9)
	local keyStroke = Instance.new("UIStroke")
	keyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	keyStroke.Color = LIME
	keyStroke.Thickness = 2.5
	keyStroke.Parent = key
	local keyText, keyImage = keyLabel(prompt, inputType)
	if keyImage then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Position = UDim2.fromScale(0.15, 0.15)
		img.Size = UDim2.fromScale(0.7, 0.7)
		img.Image = keyImage
		img.Parent = key
	else
		local k = Instance.new("TextLabel")
		k.Name = "Glyph"
		k.BackgroundTransparency = 1
		k.Position = UDim2.fromScale(0.1, 0.1)
		k.Size = UDim2.fromScale(0.8, 0.8)
		k.Font = Enum.Font.FredokaOne
		k.TextScaled = true
		k.TextColor3 = LIME
		k.Text = keyText or "E"
		k.Parent = key
	end

	text(frame, "FishName", prompt.ObjectText, Color3.new(1, 1, 1), 62, 12, 72, 26)
	text(frame, "Action", prompt.ActionText, LIME, 62, 38, 72, 26)

	-- mouse / touch: the prompt's own activation (fires its Triggered)
	frame.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end)
	frame.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end)
	gui.Parent = playerGui
	return gui
end

local stands = {} -- stand part -> { prompt, panel? }

local function hidePanel(entry)
	if entry.panel then
		entry.panel:Destroy()
		entry.panel = nil
	end
end

local function dropStand(part: Instance)
	local entry = stands[part]
	stands[part] = nil
	if entry then
		hidePanel(entry)
		if entry.prompt.Parent then
			entry.prompt:Destroy()
		end
	end
end

local function addStand(part: Instance)
	if stands[part] or not part:IsA("BasePart") then
		return
	end
	if part:GetAttribute("CasterUserId") ~= player.UserId then
		return -- someone else's catch: no prompt
	end
	local id = part:GetAttribute("OfferId")
	if type(id) ~= "number" or not part.Parent then
		return
	end
	local variant = part:GetAttribute("Variant")
	local prefix = if variant == "Gold" then "Gold " elseif variant == "Silver" then "Silver " else ""
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ObjectText = prefix .. tostring(part:GetAttribute("FishName") or "Fish")
	prompt.ActionText = "Buy"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = tonumber(part:GetAttribute("PromptDistance")) or 10
	prompt.RequiresLineOfSight = false
	-- one Buy panel at a time: only the nearest of your catches shows
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	local entry = { prompt = prompt, panel = nil, busy = false }
	stands[part] = entry
	prompt.PromptShown:Connect(function(inputType)
		hidePanel(entry)
		if stands[part] == entry then
			entry.panel = buildPanel(prompt, inputType)
		end
	end)
	prompt.PromptHidden:Connect(function()
		hidePanel(entry)
	end)
	prompt.Triggered:Connect(function()
		if entry.busy then
			return -- one request in flight; the server charges once anyway
		end
		entry.busy = true
		prompt.Enabled = false
		-- the server answers with a toast (bought / not enough Money / too far)
		local ok, bought = pcall(function()
			return offerAction:InvokeServer(id, "buy")
		end)
		if not ok then
			show("Couldn't reach the server - try again", "warn")
		end
		entry.busy = false
		-- bought: the prompt stays off and the server removes the stand. Not
		-- bought (funds, too far): the offer is still open, the prompt comes back.
		if not (ok and bought == true) and stands[part] == entry and part.Parent then
			prompt.Enabled = true
		end
	end)
	prompt.Destroying:Connect(function()
		hidePanel(entry)
	end)
	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			dropStand(part)
		end
	end)
	prompt.Parent = part
end

local function watch(folder: Instance)
	for _, part in ipairs(folder:GetChildren()) do
		addStand(part)
	end
	folder.ChildAdded:Connect(function(part)
		-- attributes replicate with the instance; wait a frame to be safe
		task.defer(addStand, part)
	end)
	folder.ChildRemoved:Connect(dropStand)
end

local STANDS = "EconomyBuyStands" -- created by EconomyService at server start
local existing = workspace:FindFirstChild(STANDS)
if existing then
	watch(existing)
end
workspace.ChildAdded:Connect(function(child)
	if child.Name == STANDS and child:IsA("Folder") then
		watch(child)
	end
end)
