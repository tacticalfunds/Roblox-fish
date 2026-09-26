-- Polls each owner's position against their plot's pads and performs the
-- server-authoritative transfer/purchase for whichever pad they are standing
-- on. No remotes: standing on a pad is the whole interaction, matching "buy
-- upgrades by standing on purchase pads" in the design brief. Continuous
-- transfer pads (deposit/output/counter) move one item every
-- Config.Stations.TransferInterval seconds; cash and upgrade pads are
-- edge-triggered (once per step-on) so lingering doesn't drain/buy repeatedly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.FishTycoonShared
local Config = require(Shared.Config)
local Scene = require(Shared.Scene)
local Economy = require(Shared.Economy)

local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)
local Grinder = require(script.Parent.Grinder)
local Customers = require(script.Parent.Customers)
local Notifier = require(script.Parent.Notifier)

local Stations = {}

local function onPad(plot, name: string, position: Vector3): boolean
	return Plots.isOnPad(plot.parts[name], position)
end

-- Continuous transfer pads: returns true if an item moved.
local function stepDeposit(plot, state): boolean
	local result = Grinder.depositOne(plot, state)
	if result == "full" then
		Notifier.send(state.player, "warn", "Hopper is full - wait for it to grind some down.", "hopperfull")
	elseif result == "empty" then
		Notifier.send(state.player, "info", "No fish to deposit. Go net some!", "nofish")
	end
	return result == "ok"
end

local function stepOutput(plot, state): boolean
	local result = Grinder.collectOne(plot, state)
	if result == "full" then
		Notifier.send(state.player, "warn", "Your carry stack is full!", "carryfull")
	elseif result == "empty" then
		Notifier.send(state.player, "info", "No food ready yet - wait for the grinder.", "nofood")
	end
	return result == "ok"
end

local function stepCounter(plot, state): boolean
	return Customers.serveOne(plot, state)
end

-- Edge-triggered pads: called once when the character steps onto the pad.
local function enterCash(plot, state)
	if plot.cash <= 0 then
		Notifier.send(state.player, "info", "No earnings waiting yet.", "nocash")
		return
	end
	state.money += plot.cash
	Notifier.send(state.player, "success", string.format("Collected %d coins!", plot.cash))
	plot.cash = 0
	Plots.refreshCashLabel(plot)
	PlayerData.commit(state)
end

local function enterUpgrade(plot, state, upgradeId: string)
	local def = Config.Upgrades[upgradeId]
	local level = state.levels[upgradeId] or 1
	local result, cost = Economy.tryPurchase(def, level, state.money)
	if result == "max" then
		Notifier.send(state.player, "info", def.DisplayName .. " is already at max level.")
	elseif result == "funds" then
		Notifier.send(state.player, "warn", string.format("Need %d coins for the next %s upgrade.", cost, def.DisplayName))
	else
		state.money -= cost
		state.levels[upgradeId] = level + 1
		Notifier.send(state.player, "success", string.format("%s upgraded to level %d!", def.DisplayName, level + 1))
		PlayerData.commit(state)
	end
end

function Stations.step(dt: number)
	for _, state in pairs(PlayerData.all()) do
		local plot = state.plot
		if not plot then
			continue
		end
		local root = PlayerData.aliveRoot(state)
		if not root then
			continue
		end
		local position = root.Position

		local onDeposit = onPad(plot, Scene.Parts.DepositPad, position)
		local onOutput = onPad(plot, Scene.Parts.OutputPad, position)
		local onCounter = onPad(plot, Scene.Parts.CounterPad, position)
		local onCash = onPad(plot, Scene.Parts.CashPad, position)

		state.nextTransfer -= dt
		if state.nextTransfer <= 0 then
			local moved = false
			if onDeposit then
				moved = stepDeposit(plot, state)
			elseif onOutput then
				moved = stepOutput(plot, state)
			elseif onCounter then
				moved = stepCounter(plot, state)
			end
			if moved then
				state.nextTransfer = Config.Stations.TransferInterval
			else
				state.nextTransfer = 0
			end
		end

		if onCash and not state.pads.Cash then
			enterCash(plot, state)
		end
		state.pads.Cash = onCash

		for upgradeId, pad in pairs(plot.upgradePads) do
			local onPadNow = Plots.isOnPad(pad, position)
			if onPadNow and not state.pads[upgradeId] then
				enterUpgrade(plot, state, upgradeId)
			end
			state.pads[upgradeId] = onPadNow
		end
	end
end

return Stations
