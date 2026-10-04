-- EconomyClient (LocalScript in StarterPlayerScripts).
--   * toast for EconomyService notices (money loading, purchase results)
--   * a big "+$" popup when a piece of YOUR meat sells (Economy.Earned),
--     wherever it sold and whoever carried it; quick sales add up into one
--     popup. It shows what really reached your Money: grey "pending" while
--     your Money is still loading, and the real amount at the balance limit.
--     Centred in the upper middle of the screen (above the crosshair, below
--     the notice toast), sized to the screen within limits; it bounces in,
--     holds, then floats up and fades. Display only.
--   * the buy prompt for the local player's OWN rod catches: a ProximityPrompt
--     (Style = Custom) on the rod stand, with a small world-anchored panel
--     ([E] + fish name + "Buy"). Keyboard E, the gamepad button and tapping
--     the panel all go through the prompt's own activation.
-- Display only: prices, ownership, range, expiry, funds and tank space are
-- all decided and checked on the server; a trigger just sends (offerId, "buy").
-- Other players' catches get no prompt (the server refuses them anyway).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
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

------------------------------------------------------------ earnings popup

local GREEN = Color3.fromRGB(120, 255, 50) -- lime
local PENDING = Color3.fromRGB(160, 175, 190) -- not spendable yet
local VARIANT_COLORS = { Gold = Color3.fromRGB(255, 205, 40), Silver = Color3.fromRGB(205, 220, 235) }
local VARIANT_RANK = { Silver = 1, Gold = 2 }
local ROUTES = { Customer = "to a customer", Truck = "to a truck" }
local EARN_HOLD = 2.5 -- seconds the popup stays after the last sale
local EARN_POS = UDim2.fromScale(0.5, 0.3) -- upper middle: above the crosshair, below the notice toast
local EARN_RISE = UDim2.fromScale(0, -0.06) -- how far it floats while fading
local EARN_POP = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local EARN_FADE = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local OUTLINE_DARK = Color3.fromRGB(10, 10, 12)

local earnFrame = Instance.new("Frame")
earnFrame.Name = "Earnings"
earnFrame.AnchorPoint = Vector2.new(0.5, 0.5)
earnFrame.Position = EARN_POS
earnFrame.Size = UDim2.fromScale(0.42, 0.16) -- of the screen, kept in shape and within limits:
earnFrame.BackgroundTransparency = 1
earnFrame.Visible = false
earnFrame.Parent = gui
local earnAspect = Instance.new("UIAspectRatioConstraint")
earnAspect.AspectRatio = 3.4
earnAspect.Parent = earnFrame
local earnLimits = Instance.new("UISizeConstraint")
earnLimits.MinSize = Vector2.new(220, 65) -- still readable on a phone
earnLimits.MaxSize = Vector2.new(500, 147) -- never a wall of text on a big screen
earnLimits.Parent = earnFrame
local earnScale = Instance.new("UIScale")
earnScale.Parent = earnFrame

local earnFaders = {} -- every label / stroke that fades out
local function earnText(name: string, pos: UDim2, size: UDim2, stroke: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = pos
	t.Size = size
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextColor3 = Color3.new(1, 1, 1)
	local s = Instance.new("UIStroke")
	s.Color = OUTLINE_DARK
	s.Thickness = stroke
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = t
	t.Parent = earnFrame
	table.insert(earnFaders, { label = t, stroke = s })
	return t
end
local earnSold = earnText("Sold", UDim2.fromScale(0.5, 0), UDim2.fromScale(0.34, 0.2), 2.5)
earnSold.Text = "SOLD!"
earnSold.Rotation = -6
local earnAmount = earnText("Amount", UDim2.fromScale(0.5, 0.16), UDim2.fromScale(1, 0.6), 4)
local earnDetail = earnText("Detail", UDim2.fromScale(0.5, 0.78), UDim2.fromScale(0.9, 0.22), 2.5)
-- a few UI sparkles around the amount (display only)
local earnSparkles = {}
for i, spot in ipairs({ { 0.08, 0.2 }, { 0.92, 0.25 }, { 0.14, 0.72 }, { 0.86, 0.7 } }) do
	local sp = earnText("Sparkle" .. i, UDim2.fromScale(spot[1], spot[2]), UDim2.fromScale(0.09, 0.26), 1.5)
	sp.AnchorPoint = Vector2.new(0.5, 0.5)
	sp.Text = "✦"
	sp.TextColor3 = Color3.fromRGB(255, 245, 160)
	earnSparkles[i] = sp
end

-- the running tweens of the popup (cancelled and reset on every new sale)
local earnTweens = {}
local function earnPlay(inst: Instance, info: TweenInfo, goal, onDone: ((Enum.PlaybackState) -> ())?)
	local tw = TweenService:Create(inst, info, goal)
	table.insert(earnTweens, tw)
	if onDone then
		tw.Completed:Connect(onDone) -- before Play
	end
	tw:Play()
end
local function earnReset()
	for _, tw in ipairs(earnTweens) do
		tw:Cancel()
	end
	earnTweens = {}
	earnFrame.Position = EARN_POS
	for _, f in ipairs(earnFaders) do
		f.label.TextTransparency = 0
		f.stroke.Transparency = 0
	end
end

local earnRun = { total = 0, count = 0, rank = 0, token = 0, pending = false, short = false }

-- (added, route, fishName, variant, kind, value) from EconomyService:
-- `added` is what really reached your Money (kind "paid") or the queue that
-- waits for your Money to load (kind "pending"); `value` is the piece's
-- price, more than `added` only at the balance / pending-queue limit.
-- Spendable and pending sales never add up in the same popup.
local function onEarned(added: any, route: any, fishName: any, variant: any, kind: any, value: any)
	if type(added) ~= "number" or added ~= added or added < 0 or added == math.huge then
		return
	end
	added = math.floor(added)
	local short = type(value) == "number" and value == value and value > added
	if added == 0 and not short then
		return
	end
	local pending = kind == "pending"
	local run = earnRun
	if not earnFrame.Visible or run.pending ~= pending then
		run.total, run.count, run.rank, run.pending, run.short = 0, 0, 0, pending, false
	end
	run.total += added
	run.count += 1
	run.short = run.short or short
	local v = if type(variant) == "string" and VARIANT_COLORS[variant] then variant else nil
	local rank = if v then VARIANT_RANK[v] else 0
	if pending then
		earnAmount.TextColor3 = PENDING
	elseif rank >= run.rank then
		run.rank = rank
		earnAmount.TextColor3 = if v then VARIANT_COLORS[v] else GREEN
	end
	earnAmount.Text = "+$" .. tostring(run.total) .. (if pending then " pending" else "")
	if run.short then
		earnDetail.Text = if pending then "Pending limit reached" else "Money is at the maximum"
	elseif pending then
		earnDetail.Text = "Added when your Money loads"
	elseif run.count == 1 then
		local fish = if type(fishName) == "string" and fishName ~= "" then fishName else "Meat"
		local where = if type(route) == "string" and ROUTES[route] then " " .. ROUTES[route] else ""
		earnDetail.Text = (if v then v .. " " else "") .. fish .. " sold" .. where
	else
		earnDetail.Text = run.count .. " pieces sold"
	end
	-- SOLD! and the sparkles only for money that really arrived
	local celebrate = not pending and run.total > 0
	earnSold.Visible = celebrate
	for _, sp in ipairs(earnSparkles) do
		sp.Visible = celebrate
	end
	-- bounce in (a sale during the hold or the fade starts it over cleanly)
	earnReset()
	earnFrame.Visible = true
	earnScale.Scale = 0.55
	earnPlay(earnScale, EARN_POP, { Scale = 1 })
	run.token += 1
	local mine = run.token
	task.delay(EARN_HOLD, function()
		if mine ~= run.token then
			return
		end
		-- float up and fade out
		for _, f in ipairs(earnFaders) do
			earnPlay(f.label, EARN_FADE, { TextTransparency = 1 })
			earnPlay(f.stroke, EARN_FADE, { Transparency = 1 })
		end
		earnPlay(earnFrame, EARN_FADE, { Position = EARN_POS + EARN_RISE }, function(state)
			if mine == run.token and state == Enum.PlaybackState.Completed then
				earnFrame.Visible = false
				earnReset()
			end
		end)
	end)
end

-- Economy.Earned appears when EconomyService starts (older services have none)
local function hookEarned(child: Instance)
	if child.Name == "Earned" and child:IsA("RemoteEvent") then
		child.OnClientEvent:Connect(onEarned)
		return true
	end
	return false
end
local earnedRemote = root:FindFirstChild("Earned")
if not (earnedRemote and hookEarned(earnedRemote)) then
	local conn
	conn = root.ChildAdded:Connect(function(child)
		if hookEarned(child) then
			conn:Disconnect()
		end
	end)
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
