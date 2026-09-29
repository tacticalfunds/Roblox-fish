-- MoneyController (LocalScript in a MoneyFrame; the same source runs in
-- StarterGui.Money.MoneyFrame and StarterGui.ScreenGui.Buttons.Frames.MoneyFrame).
--
-- The Money label shows leaderstats.Money: EconomyService's authoritative
-- balance, created once the player's Money has loaded. Until then (and if it
-- never loads) the label says "Loading..." instead of a number.
--
-- The multiplier labels (RebirthMulti, RobuxMulti, FriendsMulti, VIPMulti)
-- work as before WHEN their inputs exist (Rebirths + Modules.RebirthDefinitions,
-- Upgrades.RobuxMultiplier, FriendsMultiplier, VIP on the player). A label
-- whose inputs are missing is hidden: nothing is shown or assumed. These are
-- display only; EconomyService applies no multipliers to any payout.
--
-- Uses ReplicatedStorage.FormatModule for the number if it exists and works,
-- else its own abbreviation. Never waits on anything that may not exist.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local frame = script.Parent
local moneyLabel = frame:WaitForChild("Money")
local CURRENCY = "Money" -- EconomyService Config.CurrencyName
local LOADING = "Loading..."

------------------------------------------------------------ number format

local function optionalModule(inst: Instance?): any
	if inst and inst:IsA("ModuleScript") then
		local ok, mod = pcall(require, inst)
		if ok and type(mod) == "table" then
			return mod
		end
	end
	return nil
end

local FormatModule = optionalModule(ReplicatedStorage:FindFirstChild("FormatModule"))

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }
-- 1234 -> "1.23K"; truncated, never rounded up (999999 -> "999.99K")
local function abbreviate(n: number): string
	n = math.floor(n)
	if n < 1000 then
		return tostring(n)
	end
	local i = 0
	while i < #SUFFIXES and n >= 1000 ^ (i + 1) do
		i += 1
	end
	local hundredths = n // (1000 ^ i / 100)
	local text = string.format("%d.%02d", hundredths // 100, hundredths % 100)
	text = string.gsub(text, "%.?0+$", "")
	return text .. SUFFIXES[i]
end

local function formatMoney(n: number): string
	if FormatModule and type(FormatModule.AbbreviateNumbers) == "function" then
		local ok, text = pcall(FormatModule.AbbreviateNumbers, FormatModule, n)
		if ok and (type(text) == "string" or type(text) == "number") then
			return "$" .. tostring(text)
		end
	end
	return "$" .. abbreviate(n)
end

------------------------------------------------------------ Money (leaderstats.Money)

local moneyValue: Instance? = nil
local moneyConn: RBXScriptConnection? = nil
local statsConns: { RBXScriptConnection } = {}

local function renderMoney()
	local v = moneyValue
	local n = if v and v.Parent then (v :: any).Value else nil
	if type(n) == "number" and n == n and n >= 0 and n ~= math.huge then
		moneyLabel.Text = formatMoney(n)
	else
		moneyLabel.Text = LOADING
	end
end

local function bindMoney()
	local stats = LocalPlayer:FindFirstChild("leaderstats")
	local v = stats and stats:FindFirstChild(CURRENCY)
	if v and not (v:IsA("IntValue") or v:IsA("NumberValue")) then
		v = nil
	end
	if v ~= moneyValue then
		if moneyConn then
			moneyConn:Disconnect()
			moneyConn = nil
		end
		moneyValue = v
		if v then
			moneyConn = v.Changed:Connect(renderMoney)
		end
	end
	renderMoney()
end

local function bindStats()
	for _, c in ipairs(statsConns) do
		c:Disconnect()
	end
	table.clear(statsConns)
	local stats = LocalPlayer:FindFirstChild("leaderstats")
	if stats then
		table.insert(statsConns, stats.ChildAdded:Connect(bindMoney))
		table.insert(statsConns, stats.ChildRemoved:Connect(bindMoney))
	end
	bindMoney()
end

------------------------------------------------------------ multipliers (only when their inputs exist)

local rebirthLabels, robuxLabels = {}, {}
for _, child in ipairs(frame:GetChildren()) do
	if child:IsA("TextLabel") and child.Name == "RebirthMulti" then
		table.insert(rebirthLabels, child)
	elseif child:IsA("TextLabel") and child.Name == "RobuxMulti" then
		table.insert(robuxLabels, child)
	end
end
local friendsLabel = frame:FindFirstChild("FriendsMulti")
local vipLabel = frame:FindFirstChild("VIPMulti")
local shownAtStart = {}
for _, label in ipairs(frame:GetChildren()) do
	shownAtStart[label] = label:IsA("GuiObject") and label.Visible
end

local RebirthDefinitions = nil
do
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	RebirthDefinitions = optionalModule(modules and modules:FindFirstChild("RebirthDefinitions"))
end

local function formatMultiplier(p: any): string
	local n = tonumber(p) or 1
	if n == math.floor(n) then
		return tostring(math.floor(n))
	end
	local text = string.format("%.2f", n)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

local function numberIn(parent: Instance?, name: string): number?
	local v = parent and parent:FindFirstChild(name)
	local value = v and (v:IsA("IntValue") or v:IsA("NumberValue")) and (v :: any).Value
	return if type(value) == "number" and value == value then value else nil
end

-- text = nil hides the label (its input is missing)
local function setLabel(label: Instance?, text: string?)
	if label and label:IsA("TextLabel") then
		if text then
			label.Text = text
			label.Visible = shownAtStart[label] ~= false
		else
			label.Visible = false
		end
	end
end

local function updateMultipliers()
	local rebirth = nil
	local rebirths = numberIn(LocalPlayer, "Rebirths")
	if rebirths and RebirthDefinitions and type(RebirthDefinitions.GetMultiplier) == "function" then
		local ok, m = pcall(RebirthDefinitions.GetMultiplier, RebirthDefinitions, rebirths)
		if ok and type(m) == "number" then
			rebirth = "x" .. formatMultiplier(m)
		end
	end
	for _, label in ipairs(rebirthLabels) do
		setLabel(label, rebirth)
	end

	local robuxLevel = numberIn(LocalPlayer:FindFirstChild("Upgrades"), "RobuxMultiplier")
	local robux = if robuxLevel then "x" .. formatMultiplier(2 ^ math.clamp(math.floor(robuxLevel), 0, 15)) else nil
	for _, label in ipairs(robuxLabels) do
		setLabel(label, robux)
	end

	local friends = numberIn(LocalPlayer, "FriendsMultiplier")
	setLabel(friendsLabel, if friends then "x" .. formatMultiplier(friends) else nil)

	local vipValue = LocalPlayer:FindFirstChild("VIP")
	local vip = if vipValue and vipValue:IsA("BoolValue") then (vipValue :: any).Value else nil
	setLabel(vipLabel, if type(vip) == "boolean" then "x" .. formatMultiplier(if vip then 1.25 else 1) else nil)
end

-- inputs may appear later; each one's changes redraw the labels
local watched = {}
local watchInputs: () -> ()
local function watch(v: Instance?, onChildren: boolean?)
	if v and not watched[v] then
		watched[v] = true
		v.Changed:Connect(updateMultipliers)
		if onChildren then
			v.ChildAdded:Connect(watchInputs)
			v.ChildRemoved:Connect(updateMultipliers)
		end
	end
end
watchInputs = function()
	for _, name in ipairs({ "Rebirths", "FriendsMultiplier", "VIP" }) do
		watch(LocalPlayer:FindFirstChild(name))
	end
	local upgrades = LocalPlayer:FindFirstChild("Upgrades")
	watch(upgrades, true)
	watch(upgrades and upgrades:FindFirstChild("RobuxMultiplier"))
	updateMultipliers()
end

------------------------------------------------------------ start

LocalPlayer.ChildAdded:Connect(function(child)
	if child.Name == "leaderstats" then
		bindStats()
	else
		watchInputs()
	end
end)
LocalPlayer.ChildRemoved:Connect(function(child)
	if child.Name == "leaderstats" then
		bindStats()
	else
		updateMultipliers()
	end
end)
bindStats()
watchInputs()
