-- CustomerBoardClient (LocalScript in StarterPlayer.StarterPlayerScripts).
-- [Economy customer board v1]
--
-- The old two-panel board (Workspace.Board.Main.SurfaceGui.bord3) becomes the
-- CUSTOMER board for THIS player, in the board's own art: its SurfaceGui is
-- copied into PlayerGui (adorned to Main, so its buttons can be pressed) and
-- the original is hidden on this client only - never changed in the place.
--   card "Axe Speed"  -> Customer Speed   "6/min > 9/min"   $25
--   card "Buy Miner"  -> Customer Line    "6 > 7 in line"   $40
-- (the cards are told apart by their title text, never by name: both are
-- named Frame and both labels Text). Each card keeps its art: the Buy button
-- (gradient, stroke, corner), its Price label and the Icons frame, which
-- shows the board's person icon on both cards.
-- Values are YOUR saved levels (Upg<Id>, Upg<Id>Next, Upg<Id>Cost): current >
-- next and the price, MAX at the last level, SOON while paid upgrades are
-- closed, "..." while your money loads, OFF if the server's board isn't
-- running. Pressing Buy (mouse, touch or gamepad: Activated) bounces it at
-- once (display only) and asks ReplicatedStorage.Economy.CustomerUpgradeAction
-- (one request per card at a time); SAVING... then the server's answer for a
-- moment (BOUGHT! / NEED $ / TOO FAR / NOT SAVED / WAIT / SOON / MAX). The
-- client decides nothing. If the board isn't there (yet) or a card can't be
-- found, nothing is drawn; it is looked for again every second (streaming).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local COPY_NAME = "CustomerBoard"
local PERSON_ICON = "rbxassetid://137299198925368" -- the board's own person icon (the "Buy Miner" card)
local FLASH_SECONDS = 1.6
local BOUNCE_SCALE = 0.92
local BOUNCE_DOWN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BOUNCE_BACK = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local CARDS = {
	{ id = "CustomerSpeed", art = "Axe Speed", title = "Customer Speed" },
	{ id = "CustomerLine", art = "Buy Miner", title = "Customer Line" },
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

-- (Main, its SurfaceGui) or nil
local function findBoard(): (BasePart?, SurfaceGui?)
	local board = only(workspace, "Board", "Model")
	local main = board and only(board, "Main", "BasePart")
	local gui = main and only(main, "SurfaceGui", "SurfaceGui")
	local bord = gui and only(gui, "bord3", "Frame")
	if not bord then
		return nil, nil
	end
	return main :: BasePart, gui :: SurfaceGui
end

-- a card's parts by its art title: (title, stat, buy, price, icon) or nil
local function cardParts(bord: Instance, artTitle: string)
	local match = nil
	for _, card in ipairs(bord:GetChildren()) do
		if card:IsA("Frame") then
			local texts, buys, icons = {}, {}, {}
			for _, c in ipairs(card:GetChildren()) do
				if c.Name == "Text" and c:IsA("TextLabel") then
					table.insert(texts, c)
				elseif c.Name == "Buy" and c:IsA("TextButton") then
					table.insert(buys, c)
				elseif c.Name == "Icons" and c:IsA("ImageLabel") then
					table.insert(icons, c)
				end
			end
			if #texts == 2 and #buys == 1 and #icons == 1 then
				local title = if texts[1].Text == artTitle then texts[1] elseif texts[2].Text == artTitle then texts[2] else nil
				local price = buys[1]:FindFirstChild("Price")
				if title and price and price:IsA("TextLabel") then
					if match then
						return nil -- two cards with that title: nothing guessed
					end
					local stat = if title == texts[1] then texts[2] else texts[1]
					match = { title = title, stat = stat, buy = buys[1], price = price, icon = icons[1] }
				end
			end
		end
	end
	if not match then
		return nil
	end
	return match.title, match.stat, match.buy, match.price, match.icon
end

------------------------------------------------------------ the press bounce (display only)

local function scaledUDim2(u: UDim2, k: number): UDim2
	return UDim2.new(u.X.Scale * k, u.X.Offset * k, u.Y.Scale * k, u.Y.Offset * k)
end
local function centred(pos: UDim2, size: UDim2, small: UDim2, anchor: Vector2): UDim2
	return UDim2.new(
		pos.X.Scale + (size.X.Scale - small.X.Scale) * (0.5 - anchor.X),
		pos.X.Offset + (size.X.Offset - small.X.Offset) * (0.5 - anchor.X),
		pos.Y.Scale + (size.Y.Scale - small.Y.Scale) * (0.5 - anchor.Y),
		pos.Y.Offset + (size.Y.Offset - small.Y.Offset) * (0.5 - anchor.Y)
	)
end
local function settle(c)
	c.bounce += 1
	if c.tween then
		c.tween:Cancel()
		c.tween = nil
	end
	c.buy.Size = c.size
	c.buy.Position = c.pos
end
local function bounce(c)
	c.bounce += 1
	local token = c.bounce
	if c.tween then
		c.tween:Cancel()
	end
	local small = scaledUDim2(c.size, BOUNCE_SCALE)
	local down = TweenService:Create(c.buy, BOUNCE_DOWN, { Size = small, Position = centred(c.pos, c.size, small, c.buy.AnchorPoint) })
	down.Completed:Connect(function(state)
		if c.bounce ~= token or state ~= Enum.PlaybackState.Completed then
			return
		end
		local back = TweenService:Create(c.buy, BOUNCE_BACK, { Size = c.size, Position = c.pos })
		back.Completed:Connect(function(state2)
			if c.bounce == token and state2 == Enum.PlaybackState.Completed then
				c.tween = nil
				c.buy.Size = c.size
				c.buy.Position = c.pos
			end
		end)
		c.tween = back
		back:Play()
	end)
	c.tween = down
	down:Play()
end

------------------------------------------------------------ showing

local cards = {} -- id -> { stat, buy, price, size, pos, bounce, tween, pending, flashUntil }

local function economy(): Instance?
	return ReplicatedStorage:FindFirstChild("Economy")
end

local function amount(v: number, unit: string): string
	return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")) .. unit
end

local function render()
	local econ = economy()
	local remote = econ and econ:FindFirstChild("CustomerUpgradeAction")
	local open = econ ~= nil and econ:GetAttribute("UpgradesPaidOpen") == true
	for _, def in ipairs(CARDS) do
		local c = cards[def.id]
		if c then
			local cur = player:GetAttribute("Upg" .. def.id)
			local nextV = player:GetAttribute("Upg" .. def.id .. "Next")
			local cost = player:GetAttribute("Upg" .. def.id .. "Cost")
			local loaded = type(cur) == "number"
			local maxed = type(nextV) ~= "number" or type(cost) ~= "number"
			local unit = if def.id == "CustomerSpeed" then "/min" else ""
			if not loaded then
				c.stat.Text = if def.id == "CustomerSpeed" then "Buyers / min" else "Line size"
			elseif maxed then
				c.stat.Text = amount(cur, unit) .. (if def.id == "CustomerLine" then " in line" else "") .. " MAX"
			elseif def.id == "CustomerSpeed" then
				c.stat.Text = amount(cur, unit) .. " > " .. amount(nextV, unit)
			else
				c.stat.Text = amount(cur, "") .. " > " .. amount(nextV, "") .. " in line"
			end
			if c.pending then
				c.price.Text = "SAVING..."
			elseif os.clock() < c.flashUntil then
				-- the server's answer stays up for a moment
			elseif not remote then
				c.price.Text = "OFF"
			elseif not loaded then
				c.price.Text = "..."
			elseif maxed then
				c.price.Text = "MAX"
			elseif not open then
				c.price.Text = "SOON"
			else
				c.price.Text = "$" .. tostring(cost)
			end
		end
	end
end

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
	local remote = econ and econ:FindFirstChild("CustomerUpgradeAction")
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
	if cards[id] == c then
		c.flashUntil = os.clock() + FLASH_SECONDS
		c.price.Text = short(ok == true, message)
		task.delay(FLASH_SECONDS + 0.05, render)
	end
end

------------------------------------------------------------ binding

local shown: SurfaceGui? = nil
local shownFor: BasePart? = nil
local hidden: SurfaceGui? = nil
local connections: { RBXScriptConnection } = {}

local function unbind()
	for _, c in pairs(cards) do
		settle(c)
	end
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	connections = {}
	cards = {}
	if hidden and hidden.Parent then
		hidden.Enabled = true -- the place's board shows again on this client
	end
	if shown then
		shown:Destroy()
	end
	shown, shownFor, hidden = nil, nil, nil
end

local warned = false
local function build(main: BasePart, original: SurfaceGui)
	local copy = original:Clone()
	copy.Name = COPY_NAME
	copy.Adornee = main
	copy.ResetOnSpawn = false
	copy.Enabled = true
	for _, d in ipairs(copy:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy() -- nothing from the place runs in the copy
		end
	end
	local bord = only(copy, "bord3", "Frame") :: Frame
	local found = {}
	for _, def in ipairs(CARDS) do
		local title, stat, buy, price, icon = cardParts(bord, def.art)
		if not title then
			if not warned then
				warned = true
				warn("[CustomerBoard] no single card titled \"" .. def.art .. "\" on Workspace.Board: the customer board isn't drawn")
			end
			copy:Destroy()
			return
		end
		found[def.id] = { title = title, stat = stat, buy = buy, price = price, icon = icon }
	end
	for _, def in ipairs(CARDS) do
		local f = found[def.id]
		f.title.Text = def.title
		f.icon.Image = PERSON_ICON
		local c = { stat = f.stat, buy = f.buy, price = f.price, size = f.buy.Size, pos = f.buy.Position, bounce = 0, pending = false, flashUntil = 0 }
		cards[def.id] = c
		local id = def.id
		table.insert(connections, f.buy.Activated:Connect(function()
			bounce(c) -- at once, whatever the server answers
			press(id)
		end))
	end
	original.Enabled = false -- this client only
	copy.Parent = playerGui
	shown, shownFor, hidden = copy, main, original
	render()
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
	if string.sub(name, 1, 11) == "UpgCustomer" then
		render()
	end
end)
local function watchEconomy(econ: Instance)
	econ:GetAttributeChangedSignal("UpgradesPaidOpen"):Connect(render)
	econ.ChildAdded:Connect(render) -- CustomerUpgradeAction appears
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
