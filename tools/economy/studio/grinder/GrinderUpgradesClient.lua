-- GrinderUpgradesClient: shows the conveyor as a see-through, walk-through ghost
-- until you buy it, shows YOUR blade tier in the blender, and updates the pad labels.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local Cfg = require(RS:WaitForChild("GrinderUpgradesConfig"))
local bladesFolder = RS:WaitForChild("Blades")

------------------------------------------------------------ conveyor ghost
local GHOST_TRANSPARENCY = 0.6
local saved = {} -- [inst] = original props

local function setGhost(model, ghost)
	local hl = model:FindFirstChild("GhostHighlight")
	if ghost and not hl then
		hl = Instance.new("Highlight")
		hl.Name = "GhostHighlight"
		hl.FillColor = Color3.fromRGB(90, 200, 255)
		hl.OutlineColor = Color3.fromRGB(140, 225, 255)
		hl.FillTransparency = 0.55
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = model
	elseif not ghost and hl then
		hl:Destroy()
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			saved[d] = saved[d] or { T = d.Transparency, C = d.CanCollide }
			local o = saved[d]
			d.Transparency = ghost and math.max(o.T, GHOST_TRANSPARENCY) or o.T
			d.CanCollide = (not ghost) and o.C
		elseif d:IsA("Decal") or d:IsA("Texture") then
			saved[d] = saved[d] or { T = d.Transparency }
			d.Transparency = ghost and math.max(saved[d].T, GHOST_TRANSPARENCY) or saved[d].T
		elseif d:IsA("Beam") or d:IsA("ParticleEmitter") or d:IsA("Trail") then
			saved[d] = saved[d] or { E = d.Enabled }
			d.Enabled = (not ghost) and saved[d].E
		end
	end
end

local function refreshConveyor()
	local owned = player:GetAttribute("OwnsConveyor") == true
	for _, m in ipairs(CollectionService:GetTagged("PurchasableConveyor")) do
		setGhost(m, not owned)
	end
end

------------------------------------------------------------ blade
local serverBlade = workspace:WaitForChild("BladeCommon")
local myBlade, myBladeTier = nil, 1

local function showServerBlade(show)
	for _, d in ipairs(serverBlade:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = show and 0 or 1
		elseif d:IsA("Trail") or d:IsA("ParticleEmitter") then
			d.Enabled = show
		end
	end
end

local function refreshBlade()
	local def, tier = Cfg.blade(player:GetAttribute("BladeTier") or 1)
	if tier == myBladeTier and (tier == 1 or myBlade) then return end
	myBladeTier = tier
	if myBlade then myBlade:Destroy() myBlade = nil end
	if tier == 1 then
		showServerBlade(true)
		return
	end
	local template = bladesFolder:FindFirstChild(def.Model)
	if not template then showServerBlade(true) return end
	myBlade = template:Clone()
	myBlade.Name = "MyBlade"
	myBlade:PivotTo(serverBlade:GetPivot())
	myBlade.Parent = workspace
	showServerBlade(false)
end

RunService.RenderStepped:Connect(function()
	if myBlade then myBlade:PivotTo(serverBlade:GetPivot()) end
end)

------------------------------------------------------------ pad labels
local function label(padTag, fn)
	for _, pad in ipairs(CollectionService:GetTagged(padTag)) do
		local gui = pad:FindFirstChild("TouchPart") and pad.TouchPart:FindFirstChildOfClass("BillboardGui")
		if gui then
			local title = gui:FindFirstChild("Name")
			local price = gui:FindFirstChild("Price")
			if title and price then fn(title, price) end
		end
	end
end

local GREEN = Color3.fromRGB(85, 220, 95)
local padRed = {} -- [TouchPart] = original color

local function money()
	local ls = player:FindFirstChild("leaderstats")
	local m = ls and ls:FindFirstChild("Money")
	return m and m.Value or 0
end

local function tintPads(padTag, canBuy)
	for _, pad in ipairs(CollectionService:GetTagged(padTag)) do
		local touch = pad:FindFirstChild("TouchPart")
		if touch then
			padRed[touch] = padRed[touch] or touch.Color
			touch.Color = canBuy and GREEN or padRed[touch]
		end
	end
end

local function refreshLabels()
	local owned = player:GetAttribute("OwnsConveyor") == true
	local cash = money()
	tintPads("ConveyorPad", not owned and cash >= Cfg.ConveyorPrice)
	do
		local _, t = Cfg.blade(player:GetAttribute("BladeTier") or 1)
		local nextDef = Cfg.Blades[t + 1]
		tintPads("BladePad", nextDef ~= nil and cash >= nextDef.Price)
	end
	label("ConveyorPad", function(title, price)
		title.Text = "CONVEYOR"
		price.Text = owned and "OWNED" or Cfg.short(Cfg.ConveyorPrice)
	end)
	-- Economy board: the KG signs' price plates are KgSignClient's (the one saved net capacity)
	local _, tier = Cfg.blade(player:GetAttribute("BladeTier") or 1)
	label("BladePad", function(title, price)
		local nextDef = Cfg.Blades[tier + 1]
		if nextDef then
			title.Text = "UPGRADE BLADE"
			price.Text = nextDef.Name:upper() .. " " .. Cfg.short(nextDef.Price)
		else
			title.Text = "BLADE MAXED"
			price.Text = Cfg.Blades[tier].Name:upper()
		end
	end)
end

------------------------------------------------------------ wiring
local function refreshAll()
	refreshConveyor()
	refreshBlade()
	refreshLabels()
end

player:GetAttributeChangedSignal("OwnsConveyor"):Connect(refreshAll)
player:GetAttributeChangedSignal("BladeTier"):Connect(refreshAll)
CollectionService:GetInstanceAddedSignal("PurchasableConveyor"):Connect(refreshConveyor)
CollectionService:GetInstanceAddedSignal("ConveyorPad"):Connect(refreshLabels)
CollectionService:GetInstanceAddedSignal("BladePad"):Connect(refreshLabels)
refreshAll()
-- pads/models can stream in late: keep labels and ghost in sync
task.spawn(function()
	while true do
		task.wait(0.25)
		refreshLabels()
	end
end)
