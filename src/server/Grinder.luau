-- Per-plot fish grinder: fish dropped into the hopper are processed one at a
-- time into food portions on the output tray. Hopper and tray each hold
-- GrinderStorage items; processing pauses (never discards) when the tray is full.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.FishTycoonShared
local Config = require(Shared.Config)
local Scene = require(Shared.Scene)
local GameRules = require(Shared.GameRules)

local PlayerData = require(script.Parent.PlayerData)
local Billboard = require(script.Parent.Billboard)
local Notifier = require(script.Parent.Notifier)

local Grinder = {}

local STATUS_TEXT = {
	Idle = "Idle",
	Processing = "Grinding...",
	OutputFull = "Tray full!",
}

function Grinder.initPlot(plot)
	plot.grinder = {
		input = 0,
		output = 0,
		progress = 0,
		status = "Idle",
		hopperLabel = Billboard.create(plot.parts[Scene.Parts.DepositPad], plot.runtime, 4, 170),
		trayLabel = Billboard.create(plot.parts[Scene.Parts.OutputPad], plot.runtime, 4, 170),
	}
	Grinder.refresh(plot)
end

-- Storage size for hopper and tray, from the owner's Processing level.
function Grinder.storage(plot): number
	local state = plot.owner and PlayerData.get(plot.owner)
	if state then
		return PlayerData.intStat(state, "GrinderStorage")
	end
	return math.floor(Config.Stats.GrinderStorage.Base)
end

function Grinder.refresh(plot)
	local g = plot.grinder
	local storage = Grinder.storage(plot)
	g.hopperLabel.Text = string.format("HOPPER  fish %d/%d  (%s)", g.input, storage, STATUS_TEXT[g.status] or g.status)
	g.trayLabel.Text = string.format("FOOD TRAY  %d/%d", g.output, storage)
	plot.model:SetAttribute("GrinderActive", g.status == "Processing")
end

function Grinder.step(plot, dt: number)
	local state = plot.owner and PlayerData.get(plot.owner)
	if not state then
		return
	end
	local g = plot.grinder
	local before = g.status
	local processed, status = GameRules.grinderStep(
		g,
		dt,
		PlayerData.stat(state, "ProcessSeconds"),
		Grinder.storage(plot),
		Config.Grinder.PortionsPerFish
	)
	g.status = status
	if status == "OutputFull" and before ~= "OutputFull" then
		Notifier.send(state.player, "warn", "Food tray is full! Pick up food so the grinder can keep going.", "trayfull")
	end
	if processed > 0 or status ~= before then
		Grinder.refresh(plot)
	end
end

-- Moves up to one fish from the carry stack into the hopper.
-- Returns "ok", "empty" (nothing to deposit) or "full".
function Grinder.depositOne(plot, state): string
	if state.carry.fish <= 0 then
		return "empty"
	end
	local g = plot.grinder
	if GameRules.transferAmount(state.carry.fish, Grinder.storage(plot) - g.input, 1) <= 0 then
		return "full"
	end
	state.carry.fish -= 1
	g.input += 1
	Grinder.refresh(plot)
	return "ok"
end

-- Moves up to one food portion from the tray onto the carry stack.
-- Returns "ok", "empty" or "full" (hands full).
function Grinder.collectOne(plot, state): string
	local g = plot.grinder
	if g.output <= 0 then
		return "empty"
	end
	local space = GameRules.carrySpace(state.carry, PlayerData.intStat(state, "CarryCapacity"))
	if GameRules.transferAmount(g.output, space, 1) <= 0 then
		return "full"
	end
	g.output -= 1
	state.carry.food += 1
	Grinder.refresh(plot)
	return "ok"
end

-- Plot released: empty hopper and tray (see README reset behaviour).
function Grinder.reset(plot)
	local g = plot.grinder
	g.input, g.output, g.progress, g.status = 0, 0, 0, "Idle"
	Grinder.refresh(plot)
end

return Grinder
