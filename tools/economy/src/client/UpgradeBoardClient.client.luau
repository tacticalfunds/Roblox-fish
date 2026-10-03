-- UpgradeBoardClient (LocalScript in StarterPlayer.StarterPlayerScripts).
-- [Economy upgrade board v6: the place's four-card board art]
--
-- Wires the place's own board art for THIS player: PlayerGui.UpgradeBoardGui
-- (Roblox copies it from StarterGui.UpgradeBoardGui, a SurfaceGui adorned to
-- Workspace["Upgrade board"].Screen). Nothing is created and no art is
-- changed: only each card's Desc text and its Btn.Price text are written.
--   Frame "Net Strength"  Desc: YOUR saved net, "15 > 20kg" / "60kg MAX"
--   Frame "Rod Luck"      Desc: YOUR level, "1x > 1.5x" / "3x MAX"
--   Frame "Meat Price"    Desc: "1x > 1.25x" (a value multiplier on your own fish)
--   Frame "Faster Reels"  Desc: "1x > 1.1x"
--   Btn.Price: "$10"; "..." while your money loads; SOON while those paid
--   upgrades aren't open; MAX at the last level; OFF if the server's board
--   isn't running; SAVING... while a press is answered, then the server's
--   real answer for a moment (BOUGHT! / NEED $ / TOO FAR / NOT SAVED / WAIT /
--   SOON / MAX). The full message is the server's toast.
-- Pressing Btn (mouse, touch or gamepad: Activated) asks the server through
-- ReplicatedStorage.Economy.UpgradeAction; one request per card at a time.
-- The client decides nothing.
--
-- Found by exact names, never guessed: exactly one PlayerGui child named
-- UpgradeBoardGui (a SurfaceGui); in it exactly one Frame per card name; in
-- each exactly one TextLabel Desc and one button Btn holding one TextLabel
-- Price. A card without that shape is left alone (a warning names it); the
-- others still work. The gui is copied again on respawn (ResetOnSpawn), so a
-- new copy is bound when it appears. The icon art (viewports, models), the
-- titles, gradients and layout are never touched. The old Workspace.Board is
-- not used.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GUI_NAME = "UpgradeBoardGui"
local FLASH_SECONDS = 1.6

local CARDS = {
	{ id = "NetStrength", frame = "Net Strength" },
	{ id = "RodLuck", frame = "Rod Luck", upgrade = true },
	{ id = "MeatPrice", frame = "Meat Price", upgrade = true },
	{ id = "FasterReels", frame = "Faster Reels", upgrade = true },
}

------------------------------------------------------------ finding the art

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

-- one card's (desc, button, price), or nil + why
local function cardParts(gui: Instance, frameName: string): (TextLabel?, GuiButton?, TextLabel?, string?)
	local frame = only(gui, frameName, "Frame")
	if not frame then
		return nil, nil, nil, "no single Frame \"" .. frameName .. "\""
	end
	local desc = only(frame, "Desc", "TextLabel")
	local btn = only(frame, "Btn", "GuiButton")
	local price = btn and only(btn, "Price", "TextLabel")
	if not (desc and btn and price) then
		return nil, nil, nil, "\"" .. frameName .. "\" needs one TextLabel Desc and one Btn with one TextLabel Price"
	end
	return desc :: TextLabel, btn :: GuiButton, price :: TextLabel, nil
end

------------------------------------------------------------ showing

local cards = {} -- id -> { desc, price, artDesc, pending, flashUntil }
local bound: Instance? = nil
local connections: { RBXScriptConnection } = {}

local function economy(): Instance?
	return ReplicatedStorage:FindFirstChild("Economy")
end

local function times(v: number): string
	return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")) .. "x"
end

-- one card's price label (the server's answer stays up while it flashes)
local function showPrice(c, remote: Instance?, loaded: boolean, maxed: boolean, open: boolean, cost: number?)
	if c.pending then
		c.price.Text = "SAVING..."
	elseif os.clock() < c.flashUntil then
		-- the server's answer stays up for a moment
	elseif not remote then
		c.price.Text = "OFF"
	elseif not loaded then
		c.price.Text = "..."
	elseif maxed or not cost then
		c.price.Text = "MAX"
	elseif not open then
		c.price.Text = "SOON"
	else
		c.price.Text = "$" .. tostring(cost)
	end
end

local function render()
	local econ = economy()
	local remote = econ and econ:FindFirstChild("UpgradeAction")
	local netOpen = econ ~= nil and econ:GetAttribute("NetKgPaidOpen") == true
	local upgradesOpen = econ ~= nil and econ:GetAttribute("UpgradesPaidOpen") == true
	for _, def in ipairs(CARDS) do
		local c = cards[def.id]
		if c then
			local cur, nextV, cost
			if def.upgrade then
				-- a board upgrade: the saved level's value (Upg<Id>, Upg<Id>Next, Upg<Id>Cost)
				cur = player:GetAttribute("Upg" .. def.id)
				nextV = player:GetAttribute("Upg" .. def.id .. "Next")
				cost = player:GetAttribute("Upg" .. def.id .. "Cost")
			else
				-- Net Strength: the saved net capacity (the same one the KG posts sell)
				cur = player:GetAttribute("NetKg")
				nextV = player:GetAttribute("NetKgNext")
				cost = player:GetAttribute("NetKgCost")
			end
			local loaded = type(cur) == "number"
			local maxed = type(nextV) ~= "number" or type(cost) ~= "number"
			if not loaded then
				c.desc.Text = c.artDesc -- the art's own text until your values load
			elseif def.upgrade then
				c.desc.Text = if maxed then times(cur) .. " MAX" else times(cur) .. " > " .. times(nextV)
			else
				c.desc.Text = if maxed then string.format("%dkg MAX", cur) else string.format("%d > %dkg", cur, nextV)
			end
			showPrice(c, remote, loaded, maxed, if def.upgrade then upgradesOpen else netOpen, if type(cost) == "number" then cost else nil)
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
	if cards[id] == c then -- still the bound copy
		c.flashUntil = os.clock() + FLASH_SECONDS
		c.price.Text = short(ok == true, message)
		task.delay(FLASH_SECONDS + 0.05, render)
	end
end

------------------------------------------------------------ binding

local function unbind()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	connections = {}
	cards = {}
	bound = nil
end

local warned: { [Instance]: boolean } = {}
local function bind(gui: Instance)
	unbind()
	bound = gui
	for _, def in ipairs(CARDS) do
		local desc, btn, price, why = cardParts(gui, def.frame)
		if desc and btn and price then
			cards[def.id] = { desc = desc, price = price, artDesc = desc.Text, pending = false, flashUntil = 0 }
			local id = def.id
			table.insert(connections, btn.Activated:Connect(function()
				press(id)
			end))
		elseif not warned[gui] then
			warn("[UpgradeBoard] " .. tostring(why) .. ": that card is left as it is")
		end
	end
	warned[gui] = true
	render()
end

-- (re)bind whenever the PlayerGui copy appears, is replaced or goes away
local function refresh()
	local gui = only(playerGui, GUI_NAME, "SurfaceGui")
	if gui ~= bound then
		if gui then
			bind(gui)
		else
			unbind()
		end
	end
end
playerGui.ChildAdded:Connect(function(c)
	if c.Name == GUI_NAME then
		task.defer(refresh)
	end
end)
playerGui.ChildRemoved:Connect(function(c)
	if c.Name == GUI_NAME then
		task.defer(refresh)
	end
end)
refresh()

------------------------------------------------------------ updates

player.AttributeChanged:Connect(function(name)
	if name == "NetKg" or name == "NetKgNext" or name == "NetKgCost" or string.sub(name, 1, 3) == "Upg" then
		render()
	end
end)
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
