-- Discovers the prototype scene built by the setup script, validates it and
-- hands out one plot per player. Plot records hold all per-plot runtime state;
-- other services attach their own sub-tables (fish, grinder, customers, net).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.FishTycoonShared
local Config = require(Shared.Config)
local Scene = require(Shared.Scene)
local Billboard = require(script.Parent.Billboard)

local Plots = {}

export type Plot = {
	index: number,
	model: Model,
	parts: { [string]: BasePart },
	customerSpots: { BasePart },
	upgradePads: { [string]: BasePart },
	runtime: Folder,
	owner: Player?,
	signLabel: TextLabel,
	-- Filled in by other services:
	fish: any,
	grinder: any,
	customers: any,
	net: any,
	cash: number,
	cashLabel: TextLabel?,
	upgradeLabels: { [string]: TextLabel },
}

local plots: { Plot } = {}

local function sortedParts(folder: Instance): { BasePart }
	local list = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

local function loadPlot(model: Model): (Plot?, string?)
	local index = model:GetAttribute("PlotIndex")
	if type(index) ~= "number" then
		return nil, "missing number attribute PlotIndex"
	end

	local parts = {}
	for _, name in pairs(Scene.Parts) do
		local part = model:FindFirstChild(name)
		if not (part and part:IsA("BasePart")) then
			return nil, "missing part " .. name
		end
		parts[name] = part
	end

	local spotsFolder = model:FindFirstChild(Scene.CustomerSpots)
	local spots = spotsFolder and sortedParts(spotsFolder) or {}
	if #spots == 0 then
		return nil, "missing " .. Scene.CustomerSpots .. " parts"
	end

	local padsFolder = model:FindFirstChild(Scene.UpgradePads)
	local pads = {}
	if padsFolder then
		for _, pad in ipairs(sortedParts(padsFolder)) do
			local id = pad:GetAttribute("UpgradeId")
			if type(id) == "string" and Config.Upgrades[id] then
				pads[id] = pad
			end
		end
	end
	for _, id in ipairs(Scene.UpgradeIds) do
		if not pads[id] then
			return nil, "missing upgrade pad for " .. id
		end
	end

	-- Runtime objects live in their own folder so edit-time content is never
	-- modified. A leftover folder (e.g. from a saved play session) is replaced.
	local old = model:FindFirstChild(Scene.RuntimeFolder)
	if old then
		old:Destroy()
	end
	local runtime = Instance.new("Folder")
	runtime.Name = Scene.RuntimeFolder
	runtime.Parent = model

	local plot: Plot = {
		index = index,
		model = model,
		parts = parts,
		customerSpots = spots,
		upgradePads = pads,
		runtime = runtime,
		owner = nil,
		signLabel = Billboard.create(parts[Scene.Parts.Sign], runtime, 3, 240),
		fish = nil,
		grinder = nil,
		customers = nil,
		net = nil,
		cash = 0,
		cashLabel = nil,
		upgradeLabels = {},
	}
	plot.signLabel.Text = string.format("Plot %d - free", index)
	return plot, nil
end

-- Returns true when at least one valid plot was found.
function Plots.load(): boolean
	local scene = Workspace:FindFirstChild(Config.SceneFolderName)
	if not scene then
		warn(
			string.format(
				"[FishTycoon] Workspace.%s not found. Run the opt-in setup builder first (see README).",
				Config.SceneFolderName
			)
		)
		return false
	end
	local folder = scene:FindFirstChild(Scene.PlotsFolder)
	if not folder then
		warn("[FishTycoon] Scene has no " .. Scene.PlotsFolder .. " folder")
		return false
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			local plot, problem = loadPlot(child)
			if plot then
				table.insert(plots, plot)
			else
				warn(string.format("[FishTycoon] Skipping %s: %s", child:GetFullName(), problem or "?"))
			end
		end
	end
	table.sort(plots, function(a, b)
		return a.index < b.index
	end)
	return #plots > 0
end

function Plots.all(): { Plot }
	return plots
end

function Plots.assign(player: Player): Plot?
	for _, plot in ipairs(plots) do
		if plot.owner == nil then
			plot.owner = player
			plot.model:SetAttribute("OwnerUserId", player.UserId)
			plot.signLabel.Text = string.format("%s's Fish Dock", player.DisplayName)
			return plot
		end
	end
	return nil
end

function Plots.release(plot: Plot)
	plot.owner = nil
	plot.model:SetAttribute("OwnerUserId", nil)
	plot.signLabel.Text = string.format("Plot %d - free", plot.index)
end

-- True when a world position is standing on top of the given pad part.
function Plots.isOnPad(pad: BasePart, position: Vector3, margin: number?): boolean
	local localPos = pad.CFrame:PointToObjectSpace(position)
	local m = margin or Config.Stations.PadMargin
	local size = pad.Size
	return math.abs(localPos.X) <= size.X / 2 + m
		and math.abs(localPos.Z) <= size.Z / 2 + m
		and localPos.Y >= -1
		and localPos.Y <= Config.Stations.PadHeight
end

return Plots
